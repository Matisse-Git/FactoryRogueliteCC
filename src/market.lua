-- The market of a contract: which products are in demand, and which one has
-- slumped. It is what makes yesterday's factory the wrong factory today.
--
--   market = {
--     demand = { { item, mult, units }, ... }   pays x mult on the first `units` sold per shift
--     slump  = { item, mult } or nil            pays x mult (below 1) on every unit
--   }
--
-- Demand has volume, so the best plan is rarely a single product: split the
-- factory so that every demand is filled.

local Items = require 'src.data.items'
local Recipes = require 'src.data.recipes'
local Machines = require 'src.data.machines'

local Market = {}
Market.MULT = 3                          -- price multiplier of a product in demand
Market.SLUMP = 0.5                       -- and of the one that slumped
Market.UNITS = { 60, 30, 24, 12, 6 }     -- demand per shift by tier, in sector 1
Market.SCALE = { 1, 1.5, 2, 3 }          -- by sector; x1.5 per sector after that
Market.NEVER = { tar = true, diamond = true }   -- never in demand

-- Everything that can be made from a set of raw items with a set of machine
-- kinds. Returns have[item] = true and how[item] = the kind that makes it.
function Market.closure(resources, kinds)
  local have, how = {}, {}
  for item in pairs(resources) do have[item] = true end
  local grew = true
  while grew do
    grew = false
    for _, kind in ipairs(Machines.list) do
      if kinds[kind] then
        for _, r in ipairs(Recipes[kind] or {}) do
          local ok = true
          for _, input in ipairs(r.inputs) do
            if not have[input[1]] then ok = false; break end
          end
          if ok then
            for _, out in ipairs(r.outputs) do
              if not have[out[1]] then
                have[out[1]] = true
                how[out[1]] = { kind = kind, recipe = r }
                grew = true
              end
            end
          end
        end
      end
    end
  end
  return have, how
end

local ALL
local function allKinds()
  if not ALL then
    ALL = {}
    for _, kind in ipairs(Machines.list) do ALL[kind] = true end
  end
  return ALL
end

-- The machine kinds needed to make `item` from `resources` that are not in
-- `owned`, as a list in palette order. Nil if the resources cannot make it
-- at all.
function Market.missing(item, resources, owned)
  local have, how = Market.closure(resources, allKinds())
  if not have[item] then return nil end
  local need, seen = {}, {}
  local function walk(it)
    if seen[it] then return end
    seen[it] = true
    local h = how[it]
    if not h then return end
    need[h.kind] = true
    for _, input in ipairs(h.recipe.inputs) do walk(input[1]) end
  end
  walk(item)
  local list = {}
  for _, kind in ipairs(Machines.list) do
    if need[kind] and not owned[kind] then list[#list + 1] = kind end
  end
  return list
end

-- Units of demand per shift for an item in a sector.
function Market.units(item, sector)
  local scale = Market.SCALE[sector] or (Market.SCALE[#Market.SCALE] * 1.5 ^ (sector - #Market.SCALE))
  local n = Market.UNITS[Items[item].tier] * scale
  -- Wires come two to a craft.
  for _, r in ipairs(Recipes.wiremill) do
    if r.outputs[1][1] == item then n = n * 2 end
  end
  return math.floor(n + 0.5)
end

local function pickWeighted(rng, list, weight)
  if #list == 0 then return nil end
  local entries = {}
  for i, item in ipairs(list) do entries[i] = { item, weight(item) } end
  return rng:weighted(entries)
end

-- opts = {
--   resources  set of raw items on the site
--   owned      set of machine kinds the run can build
--   sector     1.. (sets the volume and how many products are in demand)
--   easy       both demands must be reachable (the first contract)
--   slump      item to slump, 'random' for any reachable one, or nil for none
-- }
function Market.roll(rng, opts)
  local reach = Market.closure(opts.resources, opts.owned)
  local stretch = Market.closure(opts.resources, allKinds())
  local taken = {}
  local function candidates(set, minTier, exclude)
    local list = {}
    for _, id in ipairs(Items.list) do
      if set[id] and not taken[id] and not Market.NEVER[id] and Items[id].tier >= minTier
          and Items[id].form ~= 'dust' and not (exclude and exclude[id]) then
        list[#list + 1] = id
      end
    end
    return list
  end
  local function add(market, item)
    if not item then return end
    taken[item] = true
    market.demand[#market.demand + 1] = { item = item, mult = Market.MULT, units = Market.units(item, opts.sector) }
  end

  local market = { demand = {} }
  -- One you can make today: the deeper, the likelier.
  add(market, pickWeighted(rng, candidates(reach, 2), function(id) return Items[id].tier ^ 2 end))
  -- One to stretch for: needs a machine you do not have (or, failing that,
  -- anything else within reach).
  local second = candidates(stretch, 3, reach)
  if opts.easy or #second == 0 then second = candidates(reach, 2) end
  add(market, pickWeighted(rng, second, function(id) return Items[id].tier end))
  if opts.sector >= 3 then
    add(market, pickWeighted(rng, candidates(stretch, 3), function(id) return Items[id].tier end))
  end

  if opts.slump then
    local item = opts.slump
    if item == 'random' or taken[item] or not reach[item] then
      item = pickWeighted(rng, candidates(reach, 2), function() return 1 end)
    end
    if item then market.slump = { item = item, mult = Market.SLUMP } end
  end
  return market
end

-- The market as a mod: it takes part in a sale like an upgrade does, so the
-- ledger shows what it earned or cost. Shift state: s.market[item] = units sold.
function Market.mod(market)
  if market.mod then return market.mod end
  local mod = { id = 'market', name = 'Market', color = 'green', market = market }
  function mod.value(s, ctx)
    for _, d in ipairs(market.demand) do
      if d.item == ctx.type then
        s.market = s.market or {}
        local used = s.market[d.item] or 0
        local bonus = math.min(ctx.units, math.max(0, d.units - used))
        s.market[d.item] = used + ctx.units
        if bonus > 0 then
          ctx.value = ctx.value * (bonus * d.mult + (ctx.units - bonus)) / ctx.units
        end
      end
    end
    if market.slump and market.slump.item == ctx.type then
      ctx.value = ctx.value * market.slump.mult
    end
  end
  market.mod = mod
  return mod
end

-- Units of `item` sold so far this shift under these rules.
function Market.filled(rules, item)
  local st = rules.state.market
  return st and st[item] or 0
end

return Market
