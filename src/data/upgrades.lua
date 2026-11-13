-- Modules: the upgrades that bend rules. A run holds 5, in slot order.
-- Each one is a table of optional hooks that src/rules.lua calls in that
-- order (left to right):
--
--   setup(r)            once when rules are built; tweak r.shiftLen, r.shifts,
--                       r.basePower, r.maxPolish, r.exportPeriod, r.leakEvery,
--                       r.oven, r.demandBonus, r.demandUnlimited, r.slumpMult,
--                       or add recipes with r:addRecipe(kind, recipe)
--   sellAs(s, ctx)      change what an item counts as when sold
--                       (ctx.type, ctx.mats[material] = true)
--   value(s, ctx)       change ctx.value of one sale
--   sold(s, ctx)        after a sale; keep counters in s (reset every shift)
--   shiftEnd(s, sc)     end of shift; multiply sc.mult, add sc.notes
--   speed(F, e)         return a speed multiplier for machine entity e
--   draw(F, e, watts)   return the watts machine entity e draws
--
-- ctx = { type, form, tier, mats, polished, units, dist, tick, len, value, premium, rules }
--       units: 1, or 4 for a crate (whose value is already that of the four)
-- sc  = { revenue, mult, notes, sold, kinds, perfect, spare, shiftNo, busy, machines }
--       perfect: every machine worked at least 90% of the shift
--       busy:    how many machines did; machines: how many there are
--       spare:   watts of supply left unused, on average
--       shiftNo: 1 for the first shift of a contract
--
-- A module never says when it "triggers": src/rules.lua sees what each hook
-- changed and the game shows it (card pop, ledger, board markers). Write the
-- hook and the feedback follows.
--
-- Everything scales with the numbers of the run: bonuses are percentages
-- and multipliers, never flat dollars.
--
-- rarity: 'common' | 'uncommon' | 'rare' sets the price and how often the
-- shop offers it. noPips: it changes every machine, so the board does not
-- mark them one by one.

local D = require 'src.sim.dirs'
local Links = require 'src.sim.links'

local GOLD_EQUIVALENT = {
  iron_ore = 'gold_ore', iron_dust = 'gold_dust', iron_ingot = 'gold_ingot', gear = 'foil',
}
local INGOT_OF = {
  iron_ore = 'iron_ingot', iron_dust = 'iron_ingot',
  copper_ore = 'copper_ingot', copper_dust = 'copper_ingot',
  gold_ore = 'gold_ingot', gold_dust = 'gold_ingot',
  quartz = 'glass', sand = 'glass',
}

local function countNeighbors(F, e, test)
  local n = 0
  for d = 0, 3 do
    local o = F:at(e.pos.x + D.DX[d], e.pos.y + D.DY[d])
    if o and test(o) then n = n + 1 end
  end
  return n
end

local function countKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- A module that multiplies the value of every item passing `test(ctx)`.
local function times(factor, test)
  return function(s, ctx)
    if test(ctx) then ctx.value = ctx.value * factor end
  end
end

local function note(sc, name, label)
  sc.notes[#sc.notes + 1] = { name, label }
end

local list = {
  ---------------------------------------------------------------- common
  {
    id = 'market_fever', name = 'Market Fever', code = 'MF', color = 'gold', rarity = 'common',
    desc = 'Every 3 iron items sold this shift add 1% to the value of gold items.',
    value = function(s, ctx)
      if ctx.mats.gold then ctx.value = ctx.value * (1 + 0.01 * math.floor((s.fever or 0) / 3)) end
    end,
    sold = function(s, ctx)
      if ctx.mats.iron then s.fever = (s.fever or 0) + ctx.units end
    end,
  },
  {
    id = 'scenic_route', name = 'Scenic Route', code = 'SR', color = 'blue', rarity = 'common',
    desc = 'Items gain 2% value per belt tile travelled since their last machine, up to +100%.',
    value = function(s, ctx) ctx.value = ctx.value * (1 + math.min(1, 0.02 * ctx.dist)) end,
  },
  {
    id = 'short_haul', name = 'Short Haul', code = 'SH', color = 'blue', rarity = 'common',
    desc = 'Items that travelled 3 belt tiles or fewer since their last machine sell for +40%.',
    value = times(1.4, function(ctx) return ctx.dist <= 3 end),
  },
  {
    id = 'alternator', name = 'Alternator', code = 'AL', color = 'blue', rarity = 'common',
    desc = 'A sale of a different type than the previous sale pays +50%.',
    value = function(s, ctx)
      if s.lastType and s.lastType ~= ctx.type then ctx.value = ctx.value * 1.5 end
    end,
    sold = function(s, ctx) s.lastType = ctx.type end,
  },
  {
    id = 'last_call', name = 'Last Call', code = 'LC', color = 'red', rarity = 'common',
    desc = 'Items sold in the final 10 seconds of a shift pay triple.',
    value = times(3, function(ctx) return ctx.tick > ctx.len - 10 end),
  },
  {
    id = 'scrap_dealer', name = 'Scrap Dealer', code = 'SD', color = 'green', rarity = 'common',
    desc = 'Ore, dust, quartz and sand sell for the value of what a smelter makes of them.',
    sellAs = function(s, ctx) ctx.type = INGOT_OF[ctx.type] or ctx.type end,
  },
  {
    id = 'bulk_order', name = 'Bulk Order', code = 'BO', color = 'green', rarity = 'common',
    desc = 'Every 8th sale of a shift pays x4.',
    value = function(s, ctx)
      s.bulk = (s.bulk or 0) + 1
      if s.bulk % 8 == 0 then ctx.value = ctx.value * 4 end
    end,
  },
  {
    id = 'variety_pack', name = 'Variety Pack', code = 'VP', color = 'green', rarity = 'common',
    desc = 'Every sale pays +8% per different item type already sold this shift.',
    value = function(s, ctx) ctx.value = ctx.value * (1 + 0.08 * (s.varietyN or 0)) end,
    sold = function(s, ctx)
      s.variety = s.variety or {}
      if not s.variety[ctx.type] then
        s.variety[ctx.type] = true
        s.varietyN = (s.varietyN or 0) + 1
      end
    end,
  },
  {
    id = 'bullion', name = 'Bullion', code = 'BU', color = 'gold', rarity = 'common',
    desc = 'Tier 2 items (ingots, glass, plastic) sell for triple.',
    value = times(3, function(ctx) return ctx.tier == 2 end),
  },
  {
    id = 'middleman', name = 'Middleman', code = 'MM', color = 'green', rarity = 'common',
    desc = 'Tier 3 items (parts and alloys) sell for double.',
    value = times(2, function(ctx) return ctx.tier == 3 end),
  },
  {
    id = 'premium_brand', name = 'Premium Brand', code = 'PB', color = 'purple', rarity = 'common',
    desc = 'Polished items sell for a further +50%.',
    value = times(1.5, function(ctx) return ctx.polished > 0 end),
  },
  {
    id = 'bulk_freight', name = 'Bulk Freight', code = 'BF', color = 'green', rarity = 'common',
    desc = 'Crates sell for +30%.',
    value = times(1.3, function(ctx) return ctx.units > 1 end),
  },
  {
    id = 'black_gold', name = 'Black Gold', code = 'BG', color = 'gold', rarity = 'common',
    desc = 'Items containing oil sell for double.',
    value = times(2, function(ctx) return ctx.mats.oil end),
  },
  {
    id = 'glassworks', name = 'Glassworks', code = 'GW', color = 'cyan', rarity = 'common',
    desc = 'Items containing quartz sell for double.',
    value = times(2, function(ctx) return ctx.mats.quartz end),
  },
  {
    id = 'night_shift', name = 'Night Shift', code = 'NS', color = 'purple', rarity = 'common',
    desc = 'The first shift of every contract earns double.',
    shiftEnd = function(s, sc)
      if sc.shiftNo == 1 then
        sc.mult = sc.mult * 2
        note(sc, 'Night Shift', 'x2')
      end
    end,
  },
  {
    id = 'assembly_line', name = 'Assembly Line', code = 'AS', color = 'blue', rarity = 'common',
    desc = 'A machine runs 25% faster per adjacent machine of the same type.',
    speed = function(F, e)
      local kind = e.building.kind
      return 1 + 0.25 * countNeighbors(F, e, function(o) return o.building.kind == kind end)
    end,
  },
  {
    id = 'direct_drive', name = 'Direct Drive', code = 'DD', color = 'blue', rarity = 'common',
    desc = 'A machine that outputs straight into another machine runs 50% faster.',
    speed = function(F, e)
      local d = e.building.dir
      local o = F:at(e.pos.x + D.DX[d], e.pos.y + D.DY[d])
      if o and o.machine then return 1.5 end
      return 1
    end,
  },
  {
    id = 'depot_district', name = 'Depot District', code = 'DP', color = 'blue', rarity = 'common',
    desc = 'A machine within 2 tiles of the depot runs 30% faster.',
    speed = function(F, e)
      local depot = F.world:query('export')
      for i = 1, #depot do
        local p = depot[i].pos
        if math.max(math.abs(p.x - e.pos.x), math.abs(p.y - e.pos.y)) <= 2 then return 1.3 end
      end
      return 1
    end,
  },
  {
    id = 'isolation', name = 'Hand Crank', code = 'HC', color = 'cyan', rarity = 'common',
    desc = 'A machine with no machine next to it draws no power.',
    draw = function(F, e, watts)
      if countNeighbors(F, e, function(o) return o.machine ~= nil end) == 0 then return 0 end
      return watts
    end,
  },

  ---------------------------------------------------------------- uncommon
  {
    id = 'fools_gold', name = "Fool's Gold", code = 'FG', color = 'gold', rarity = 'uncommon',
    desc = 'Iron ore, dust, ingots and gears sell as their gold counterparts, and every iron item counts as gold.',
    sellAs = function(s, ctx)
      if ctx.mats.iron then
        ctx.mats.gold = true
        ctx.type = GOLD_EQUIVALENT[ctx.type] or ctx.type
      end
    end,
  },
  {
    id = 'monopoly', name = 'Monopoly', code = 'MO', color = 'purple', rarity = 'uncommon',
    desc = 'If you sell only one item type in a shift, shift revenue x2.',
    shiftEnd = function(s, sc)
      if sc.kinds == 1 then
        sc.mult = sc.mult * 2
        note(sc, 'Monopoly', 'x2')
      end
    end,
  },
  {
    id = 'specialist', name = 'Specialist', code = 'SP', color = 'purple', rarity = 'uncommon',
    desc = 'If one item type made at least 80% of a shift\'s revenue, shift revenue x1.5.',
    shiftEnd = function(s, sc)
      for _, rec in pairs(sc.sold) do
        if sc.revenue > 0 and rec.total >= 0.8 * sc.revenue then
          sc.mult = sc.mult * 1.5
          note(sc, 'Specialist', 'x1.5')
          return
        end
      end
    end,
  },
  {
    id = 'embargo', name = 'Embargo', code = 'EM', color = 'red', rarity = 'uncommon',
    desc = 'Items containing copper are worthless. Iron items sell for triple.',
    value = function(s, ctx)
      if ctx.mats.copper then ctx.value = 0
      elseif ctx.mats.iron then ctx.value = ctx.value * 3 end
    end,
  },
  {
    id = 'gold_standard', name = 'Gold Standard', code = 'GS', color = 'gold', rarity = 'uncommon',
    desc = 'Each gold item sold makes every later sale this shift worth 2% more.',
    value = function(s, ctx) ctx.value = ctx.value * (1 + 0.02 * (s.goldSold or 0)) end,
    sold = function(s, ctx)
      if ctx.mats.gold then s.goldSold = (s.goldSold or 0) + ctx.units end
    end,
  },
  {
    id = 'top_shelf', name = 'Top Shelf', code = 'TS', color = 'gold', rarity = 'uncommon',
    desc = 'Tier 5 products sell for +50%.',
    value = times(1.5, function(ctx) return ctx.tier == 5 end),
  },
  {
    id = 'deep_pockets', name = 'Deep Pockets', code = 'DK', color = 'green', rarity = 'uncommon',
    desc = 'Every tier above the first adds 15% to an item\'s value.',
    value = function(s, ctx) ctx.value = ctx.value * (1 + 0.15 * (ctx.tier - 1)) end,
  },
  {
    id = 'heavy_industry', name = 'Heavy Industry', code = 'HI', color = 'green', rarity = 'uncommon',
    desc = 'Items containing 3 or more raw materials sell for +60%.',
    value = times(1.6, function(ctx) return countKeys(ctx.mats) >= 3 end),
  },
  {
    id = 'bull_run', name = 'Bull Run', code = 'BR', color = 'cyan', rarity = 'uncommon',
    desc = 'Products in demand pay x4 instead of x3.',
    setup = function(r) r.demandBonus = r.demandBonus + 1 end,
  },
  {
    id = 'contrarian', name = 'Contrarian', code = 'CN', color = 'cyan', rarity = 'uncommon',
    desc = 'The product that slumped sells for double instead of half.',
    setup = function(r) r.slumpMult = 2 end,
  },
  {
    id = 'leaky_splitter', name = 'Leaky Splitter', code = 'LS', color = 'blue', rarity = 'uncommon',
    desc = 'Splitters duplicate every 4th item that passes through.',
    setup = function(r) r.leakEvery = 4 end,
  },
  {
    id = 'twin_feed', name = 'Twin Feed', code = 'TF', color = 'blue', rarity = 'uncommon',
    desc = 'A machine fed from two or more sides runs 30% faster.',
    speed = function(F, e)
      local n = 0
      for d = 0, 3 do
        if Links.feeds(F, e.pos.x - D.DX[d], e.pos.y - D.DY[d], d) then n = n + 1 end
      end
      return n >= 2 and 1.3 or 1
    end,
  },
  {
    id = 'overclock', name = 'Overclock', code = 'OC', color = 'red', rarity = 'uncommon', noPips = true,
    desc = 'Every machine runs 25% faster and draws 50% more power.',
    speed = function() return 1.25 end,
    draw = function(F, e, watts) return watts * 1.5 end,
  },
  {
    id = 'overtime', name = 'Overtime', code = 'OT', color = 'red', rarity = 'uncommon',
    desc = 'Shifts last 15 seconds longer, but every contract has one shift fewer.',
    setup = function(r)
      r.shiftLen = r.shiftLen + 15
      r.shifts = math.max(1, r.shifts - 1)
    end,
  },
  {
    id = 'double_polish', name = 'Mirror Finish', code = 'MR', color = 'purple', rarity = 'uncommon',
    desc = 'Items can be polished twice, doubling their value again.',
    setup = function(r) r.maxPolish = 2 end,
  },
  {
    id = 'minimalist', name = 'Minimalist', code = 'MI', color = 'purple', rarity = 'uncommon',
    desc = 'Shift revenue +3% for every watt of power left unused, up to +60%.',
    shiftEnd = function(s, sc)
      local pct = math.min(60, math.floor(sc.spare) * 3)
      if pct > 0 then
        sc.mult = sc.mult * (1 + pct / 100)
        note(sc, 'Minimalist', '+' .. pct .. '%')
      end
    end,
  },
  {
    id = 'efficiency', name = 'Efficiency Bonus', code = 'EF', color = 'purple', rarity = 'uncommon',
    desc = 'Shift revenue +2% for each machine that worked at least 90% of the shift, up to +100%.',
    shiftEnd = function(s, sc)
      local pct = math.min(100, sc.busy * 2)
      if pct > 0 then
        sc.mult = sc.mult * (1 + pct / 100)
        note(sc, 'Efficiency Bonus', '+' .. pct .. '%')
      end
    end,
  },
  {
    id = 'conveyor_oven', name = 'Conveyor Oven', code = 'CO', color = 'red', rarity = 'uncommon',
    desc = 'Ore on a belt next to a burning generator smelts itself.',
    setup = function(r) r.oven = true end,
  },

  ---------------------------------------------------------------- rare
  {
    id = 'perfect_ratio', name = 'Perfect Ratio', code = 'PR', color = 'purple', rarity = 'rare',
    desc = 'If every machine worked at least 90% of the shift, shift revenue x2.',
    shiftEnd = function(s, sc)
      if sc.perfect then
        sc.mult = sc.mult * 2
        note(sc, 'Perfect Ratio', 'x2')
      end
    end,
  },
  {
    id = 'full_house', name = 'Full House', code = 'FH', color = 'purple', rarity = 'rare',
    desc = 'If you sold at least 5 different item types in a shift, shift revenue x2.',
    shiftEnd = function(s, sc)
      if sc.kinds >= 5 then
        sc.mult = sc.mult * 2
        note(sc, 'Full House', 'x2')
      end
    end,
  },
  {
    id = 'cornered_market', name = 'Cornered Market', code = 'CM', color = 'cyan', rarity = 'rare',
    desc = 'Demand never runs out: products in demand pay their bonus on every unit.',
    setup = function(r) r.demandUnlimited = true end,
  },
}

local Upgrades = { list = list, byId = {}, INGOT_OF = INGOT_OF }

Upgrades.slots = 5
Upgrades.COST = { common = 5, uncommon = 7, rare = 10 }
Upgrades.WEIGHT = { common = 60, uncommon = 32, rare = 8 }     -- how often the shop offers each
Upgrades.RARITY_COLOR = { common = 'dim', uncommon = 'blue', rare = 'gold' }

for _, u in ipairs(list) do
  Upgrades.byId[u.id] = u
  u.cost = Upgrades.COST[u.rarity]
end

-- What selling a module pays back.
function Upgrades.refund(def)
  return math.floor(def.cost / 2)
end

return Upgrades
