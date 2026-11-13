-- Upgrades change rules, not stats. Each one is a table of optional hooks
-- that src/rules.lua calls in slot order (left to right):
--
--   setup(r)            once when rules are built; tweak r.shiftLen, r.shifts,
--                       r.basePower, r.maxPolish, r.exportPeriod, r.leakEvery,
--                       r.oven, or add recipes with r:addRecipe(kind, recipe)
--   sellAs(s, ctx)      change what an item counts as when sold
--                       (ctx.type, ctx.mats[material] = true)
--   value(s, ctx)       change ctx.value of one sale
--   sold(s, ctx)        after a sale; keep counters in s (reset every shift)
--   shiftEnd(s, sc)     end of shift; multiply sc.mult, add sc.notes
--   speed(F, e)         return a speed multiplier for machine entity e
--   draw(F, e, watts)   return the watts machine entity e draws
--
-- ctx = { type, form, mats, polished, dist, tick, len, value }
-- sc  = { revenue, mult, notes, sold, kinds, perfect, spare }
--       perfect: every machine worked at least 90% of the shift
--       spare:   watts of supply left unused, on average
--
-- An upgrade never says when it "triggers": src/rules.lua sees what each hook
-- changed and the game shows it (card pop, ledger, board markers). Write the
-- hook and the feedback follows.

local Recipes = require 'src.data.recipes'
local D = require 'src.sim.dirs'

local GOLD_EQUIVALENT = {
  iron_ore = 'gold_ore', iron_dust = 'gold_dust', iron_ingot = 'gold_ingot', gear = 'foil',
}
local INGOT_OF = {
  iron_ore = 'iron_ingot', iron_dust = 'iron_ingot',
  copper_ore = 'copper_ingot', copper_dust = 'copper_ingot',
  gold_ore = 'gold_ingot', gold_dust = 'gold_ingot',
}

local function countNeighbors(F, e, test)
  local n = 0
  for d = 0, 3 do
    local o = F:at(e.pos.x + D.DX[d], e.pos.y + D.DY[d])
    if o and test(o) then n = n + 1 end
  end
  return n
end

local list = {
  {
    id = 'fools_gold', name = "Fool's Gold", code = 'FG', color = 'gold', cost = 7,
    desc = 'Iron items count as gold when sold.',
    sellAs = function(s, ctx)
      if ctx.mats.iron then
        ctx.mats.gold = true
        ctx.type = GOLD_EQUIVALENT[ctx.type] or ctx.type
      end
    end,
  },
  {
    id = 'market_fever', name = 'Market Fever', code = 'MF', color = 'gold', cost = 6,
    desc = 'Every 3 iron items sold this shift add $1 to the value of gold items.',
    value = function(s, ctx)
      if ctx.mats.gold then ctx.value = ctx.value + math.floor((s.fever or 0) / 3) end
    end,
    sold = function(s, ctx)
      if ctx.mats.iron then s.fever = (s.fever or 0) + 1 end
    end,
  },
  {
    id = 'scenic_route', name = 'Scenic Route', code = 'SR', color = 'blue', cost = 5,
    desc = 'Items gain $1 for every 4 belt tiles they travelled.',
    value = function(s, ctx) ctx.value = ctx.value + math.floor(ctx.dist / 4) end,
  },
  {
    id = 'perfect_ratio', name = 'Perfect Ratio', code = 'PR', color = 'purple', cost = 7,
    desc = 'If every machine worked at least 90% of the shift, shift revenue x2.',
    shiftEnd = function(s, sc)
      if sc.perfect then
        sc.mult = sc.mult * 2
        sc.notes[#sc.notes + 1] = { 'Perfect Ratio', 'x2' }
      end
    end,
  },
  {
    id = 'monopoly', name = 'Monopoly', code = 'MO', color = 'purple', cost = 6,
    desc = 'If you sell only one item type in a shift, shift revenue x2.',
    shiftEnd = function(s, sc)
      if sc.kinds == 1 then
        sc.mult = sc.mult * 2
        sc.notes[#sc.notes + 1] = { 'Monopoly', 'x2' }
      end
    end,
  },
  {
    id = 'alternator', name = 'Alternator', code = 'AL', color = 'blue', cost = 5,
    desc = 'A sale of a different type than the previous sale pays $3 extra.',
    value = function(s, ctx)
      if s.lastType and s.lastType ~= ctx.type then ctx.value = ctx.value + 3 end
    end,
    sold = function(s, ctx) s.lastType = ctx.type end,
  },
  {
    id = 'last_call', name = 'Last Call', code = 'LC', color = 'red', cost = 5,
    desc = 'Items sold in the final 10 seconds of a shift pay triple.',
    value = function(s, ctx)
      if ctx.tick > ctx.len - 10 then ctx.value = ctx.value * 3 end
    end,
  },
  {
    id = 'pressure', name = 'Pressure', code = 'PD', color = 'cyan', cost = 6,
    desc = 'A press turns coal into a diamond worth $15.',
    setup = function(r)
      r:addRecipe('press', Recipes.make({ { 'coal', 1 } }, { { 'diamond', 1 } }))
    end,
  },
  {
    id = 'scrap_dealer', name = 'Scrap Dealer', code = 'SD', color = 'green', cost = 5,
    desc = 'Raw ore and dust sell for the value of their ingot.',
    sellAs = function(s, ctx) ctx.type = INGOT_OF[ctx.type] or ctx.type end,
  },
  {
    id = 'embargo', name = 'Embargo', code = 'EM', color = 'red', cost = 6,
    desc = 'Items containing copper are worthless. Iron items sell for triple.',
    value = function(s, ctx)
      if ctx.mats.copper then ctx.value = 0
      elseif ctx.mats.iron then ctx.value = ctx.value * 3 end
    end,
  },
  {
    id = 'leaky_splitter', name = 'Leaky Splitter', code = 'LS', color = 'blue', cost = 6,
    desc = 'Splitters duplicate every 4th item that passes through.',
    setup = function(r) r.leakEvery = 4 end,
  },
  {
    id = 'assembly_line', name = 'Assembly Line', code = 'AS', color = 'blue', cost = 6,
    desc = 'A machine runs 25% faster per adjacent machine of the same type.',
    speed = function(F, e)
      local kind = e.building.kind
      return 1 + 0.25 * countNeighbors(F, e, function(o) return o.building.kind == kind end)
    end,
  },
  {
    id = 'bulk_order', name = 'Bulk Order', code = 'BO', color = 'green', cost = 5,
    desc = 'Every 8th item sold in a shift pays x4.',
    value = function(s, ctx)
      s.bulk = (s.bulk or 0) + 1
      if s.bulk % 8 == 0 then ctx.value = ctx.value * 4 end
    end,
  },
  {
    id = 'gold_standard', name = 'Gold Standard', code = 'GS', color = 'gold', cost = 7,
    desc = 'Each gold item sold makes every later sale this shift worth 5% more.',
    value = function(s, ctx) ctx.value = ctx.value * (1 + 0.05 * (s.goldSold or 0)) end,
    sold = function(s, ctx)
      if ctx.mats.gold then s.goldSold = (s.goldSold or 0) + 1 end
    end,
  },
  {
    id = 'variety_pack', name = 'Variety Pack', code = 'VP', color = 'green', cost = 5,
    desc = 'Every sale pays $1 extra per different item type already sold this shift.',
    value = function(s, ctx) ctx.value = ctx.value + (s.varietyN or 0) end,
    sold = function(s, ctx)
      s.variety = s.variety or {}
      if not s.variety[ctx.type] then
        s.variety[ctx.type] = true
        s.varietyN = (s.varietyN or 0) + 1
      end
    end,
  },
  {
    id = 'overtime', name = 'Overtime', code = 'OT', color = 'red', cost = 5,
    desc = 'Shifts last 15 seconds longer, but every contract has one shift fewer.',
    setup = function(r)
      r.shiftLen = r.shiftLen + 15
      r.shifts = math.max(1, r.shifts - 1)
    end,
  },
  {
    id = 'direct_drive', name = 'Direct Drive', code = 'DD', color = 'blue', cost = 6,
    desc = 'A machine that outputs straight into another machine runs 50% faster.',
    speed = function(F, e)
      local d = e.building.dir
      local o = F:at(e.pos.x + D.DX[d], e.pos.y + D.DY[d])
      if o and o.machine then return 1.5 end
      return 1
    end,
  },
  {
    id = 'isolation', name = 'Hand Crank', code = 'HC', color = 'cyan', cost = 5,
    desc = 'A machine with no machine next to it draws no power.',
    draw = function(F, e, watts)
      if countNeighbors(F, e, function(o) return o.machine ~= nil end) == 0 then return 0 end
      return watts
    end,
  },
  {
    id = 'double_polish', name = 'Mirror Finish', code = 'MR', color = 'purple', cost = 6,
    desc = 'Items can be polished twice, doubling their value again.',
    setup = function(r) r.maxPolish = 2 end,
  },
  {
    id = 'minimalist', name = 'Minimalist', code = 'MI', color = 'purple', cost = 6,
    desc = 'Shift revenue +3% for every watt of power left unused, up to +60%.',
    shiftEnd = function(s, sc)
      local pct = math.min(60, math.floor(sc.spare) * 3)
      if pct > 0 then
        sc.mult = sc.mult * (1 + pct / 100)
        sc.notes[#sc.notes + 1] = { 'Minimalist', '+' .. pct .. '%' }
      end
    end,
  },
  {
    id = 'conveyor_oven', name = 'Conveyor Oven', code = 'CO', color = 'red', cost = 6,
    desc = 'Ore on a belt next to a burning generator smelts itself.',
    setup = function(r) r.oven = true end,
  },
}

local Upgrades = { list = list, byId = {}, INGOT_OF = INGOT_OF }
for _, u in ipairs(list) do Upgrades.byId[u.id] = u end

return Upgrades
