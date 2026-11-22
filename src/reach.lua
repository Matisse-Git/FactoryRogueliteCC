-- What a site can make: from its raw items and the machine kinds the run
-- can build, every product within reach, and what is missing for the rest.
-- The contract board uses it to show what new land opens up.

local Items = require 'src.data.items'
local Recipes = require 'src.data.recipes'
local Machines = require 'src.data.machines'

local Reach = {}

-- Everything that can be made from a set of raw items with a set of machine
-- kinds. Returns have[item] = true and how[item] = the kind that makes it.
function Reach.closure(resources, kinds)
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
function Reach.missing(item, resources, owned)
  local have, how = Reach.closure(resources, allKinds())
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

-- The products that `plot` would put within reach of the run, best paying
-- first: things the site cannot make today and could with that land and
-- the machines the run owns. `later`: those it would open up with
-- blueprints the run does not have yet.
function Reach.opens(run, plot)
  local owned = run:kinds()
  local before = Reach.closure(run:resources(), owned)
  local after = Reach.closure(run:resources(plot), owned)
  local beforeAll = Reach.closure(run:resources(), allKinds())
  local afterAll = Reach.closure(run:resources(plot), allKinds())
  local now, later = {}, {}
  for _, id in ipairs(Items.list) do
    if Items[id].tier >= 2 and id ~= 'tar' then           -- tar: a by-product, worth $1
      if after[id] and not before[id] then
        now[#now + 1] = id
      elseif afterAll[id] and not beforeAll[id] then
        later[#later + 1] = id
      end
    end
  end
  local function dearest(a, b) return Items[a].value > Items[b].value end
  table.sort(now, dearest)
  table.sort(later, dearest)
  return now, later
end

return Reach
