-- A production calculator for the balance benchmark: what a perfectly
-- balanced factory needs to make an item, and the best mix of products a
-- site can run. It is the arithmetic a player does by hand, automated.
--
-- It leans on two facts the simulation tests pin down: a machine makes
-- exactly its stated rate, and it draws power only while it is crafting. So
-- a balanced line costs (draw x share of time crafting) per machine, and
-- tests/bench.lua checks the calculator against real simulated lines.

local Items = require 'src.data.items'
local Recipes = require 'src.data.recipes'
local Machines = require 'src.data.machines'

local Plan = {}

Plan.RAW = { 'iron_ore', 'copper_ore', 'coal', 'quartz', 'gold_ore', 'crude' }
local IS_RAW = {}
for _, item in ipairs(Plan.RAW) do IS_RAW[item] = true end

local MAKERS = { 'smelter', 'press', 'wiremill', 'foundry', 'refinery', 'assembler', 'manufacturer' }

-- The standard recipe that makes each item (the crusher's dust route is left
-- out: it changes how far ore goes, not what can be made).
local MADE_BY = {}
for _, kind in ipairs(MAKERS) do
  for _, r in ipairs(Recipes[kind]) do
    if Items[r.inputs[1][1]].form ~= 'dust' then
      for _, out in ipairs(r.outputs) do
        if not MADE_BY[out[1]] then MADE_BY[out[1]] = { kind = kind, recipe = r, n = out[2] } end
      end
    end
  end
end

-- What one unit per minute of `item` costs a balanced factory:
--   { watts, raw = { item = units per minute }, machines = { kind = count } }
-- or nil if a machine it needs is not in `kinds`. speed[kind] is the speed
-- multiplier of that kind (default 1).
function Plan.cost(item, kinds, speed)
  speed = speed or {}
  local total = { watts = 0, raw = {}, machines = {} }
  local function add(it, units)
    if IS_RAW[it] then
      total.raw[it] = (total.raw[it] or 0) + units
      return true
    end
    local how = MADE_BY[it]
    if not how or not kinds[how.kind] then return false end
    local def = Machines[how.kind]
    local crafts = units / how.n                               -- crafts per minute
    local machines = crafts / (60 / def.time * (speed[how.kind] or 1))
    total.machines[how.kind] = (total.machines[how.kind] or 0) + machines
    total.watts = total.watts + machines * def.draw
    for _, input in ipairs(how.recipe.inputs) do
      if not add(input[1], crafts * input[2]) then return false end
    end
    return true
  end
  if not add(item, 1) then return nil end
  return total
end

-- The best mix a site can run for one shift.
--   site = {
--     kinds    set of machine kinds          speed  { kind = multiplier }
--     watts    power available               ports  { raw item = items per minute }
--     value    function(item) -> $ per unit, with every bonus that always applies
--     polish   true if the site has the polisher
--     demand   { { item, mult, units }, ... }    slump = { item, mult } or nil
--   }
-- Returns revenue for a 60 s shift and the lines it runs, as
-- { { item, rate (per minute), polished, revenue }, ... }.
--
-- Greedy on revenue per unit of whatever is scarcest: not an exact optimum,
-- but within a few percent of one on sites like these, and never above it.
function Plan.best(site)
  local options = {}
  for _, item in ipairs(Items.list) do
    local def = Items[item]
    if def.form ~= 'dust' and item ~= 'tar' and item ~= 'diamond' then
      local cost = Plan.cost(item, site.kinds, site.speed)
      if cost then
        local base = site.value(item)
        if site.slump and site.slump.item == item then base = base * site.slump.mult end
        for _, polished in ipairs(site.polish and { false, true } or { false }) do
          local v = base * (polished and 2 or 1)
          local w = cost.watts + (polished and Machines.polisher.draw * Machines.polisher.time / 60 or 0)
          local bonus, cap = 0, math.huge
          for _, d in ipairs(site.demand or {}) do
            if d.item == item then bonus, cap = v * (d.mult - 1), d.units end
          end
          if bonus > 0 then
            options[#options + 1] = { item = item, polished = polished, v = v + bonus, w = w, raw = cost.raw, cap = cap, demand = true }
          end
          options[#options + 1] = { item = item, polished = polished, v = v, w = w, raw = cost.raw, cap = math.huge }
        end
      end
    end
  end

  local watts = site.watts
  local ports, sold = {}, {}
  for item, rate in pairs(site.ports) do ports[item] = rate end
  local lines, revenue = {}, 0

  -- How many units per minute of an option still fit.
  local function room(o)
    local r = o.cap
    -- Demand is counted per item, polished or not.
    if o.demand then r = r - (sold[o.item] or 0) end
    if o.w > 0 then r = math.min(r, watts / o.w) end
    for item, per in pairs(o.raw) do r = math.min(r, (ports[item] or 0) / per) end
    return math.max(0, r)
  end
  -- Revenue per share of the remaining capacity it uses up.
  local function score(o)
    local use = o.w > 0 and o.w / math.max(watts, 1e-9) or 0
    for item, per in pairs(o.raw) do use = math.max(use, per / math.max(ports[item] or 0, 1e-9)) end
    return o.v / math.max(use, 1e-9)
  end

  for _ = 1, 60 do
    local best, bestScore
    for _, o in ipairs(options) do
      if room(o) > 1e-6 then
        local s = score(o)
        if not bestScore or s > bestScore then best, bestScore = o, s end
      end
    end
    if not best then break end
    -- Take it in slices, so a cheap line cannot eat a resource a dearer one needs later.
    local rate = math.min(room(best), math.max(1, room(best) / 2))
    watts = watts - rate * best.w
    for item, per in pairs(best.raw) do ports[item] = ports[item] - rate * per end
    if best.demand then sold[best.item] = (sold[best.item] or 0) + rate end
    revenue = revenue + rate * best.v
    local merged
    for _, line in ipairs(lines) do
      if line.item == best.item and line.polished == best.polished then merged = line end
    end
    if not merged then
      merged = { item = best.item, polished = best.polished, rate = 0, revenue = 0 }
      lines[#lines + 1] = merged
    end
    merged.rate, merged.revenue = merged.rate + rate, merged.revenue + rate * best.v
  end
  table.sort(lines, function(a, b) return a.revenue > b.revenue end)
  return revenue, lines, watts
end

return Plan
