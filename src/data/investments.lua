-- Investments: the incremental upgrades. Unlimited in number, bought a level
-- at a time, each level a little dearer than the last. Four families:
--
--   power             +10W per level
--   rate:<item>       a raw resource's ports supply 25% more per level,
--                     up to a full belt (60/min)
--   speed:<kind>      machines of that kind run 20% faster per level
--   value:<material>  items containing that raw material sell for 20% more
--                     per level; an item gets the bonus of every material
--                     in it, multiplied together
--
-- An investment works through the same hooks as a module (see
-- src/data/upgrades.lua) but is `quiet`: it has no card, the board does not
-- mark the machines it changes, and the ledger shows all of them as one row.

local Items = require 'src.data.items'
local Machines = require 'src.data.machines'

local Investments = {}

Investments.POWER = 10          -- watts per level
Investments.RATE = 0.25         -- port rate per level
Investments.SPEED = 0.2         -- machine speed per level
Investments.VALUE = 0.2         -- item value per level
Investments.MAX_RATE = 4        -- levels: 30/min -> 60/min
Investments.MAX_SPEED = 5

local RAW = { 'iron_ore', 'copper_ore', 'coal', 'quartz', 'gold_ore', 'crude' }
local RAW_OF = { iron = 'iron_ore', copper = 'copper_ore', coal = 'coal', quartz = 'quartz', gold = 'gold_ore', oil = 'crude' }
local MAKERS = {
  'smelter', 'crusher', 'press', 'wiremill', 'foundry', 'refinery',
  'assembler', 'manufacturer', 'polisher', 'packer',
}

local function pct(x) return math.floor(x * 100 + 0.5) .. '%' end

local list = {}
Investments.list = list
Investments.byId = {}

local function add(def)
  list[#list + 1] = def
  Investments.byId[def.id] = def
end

add({
  id = 'power', family = 'power', name = 'Grid Upgrade', icon = { machine = 'node' },
  cost = 3, step = 1,
  effect = function(level) return '+' .. level * Investments.POWER .. 'W' end,
  desc = 'The site supplies 10W more per level.',
})

for _, item in ipairs(RAW) do
  add({
    id = 'rate:' .. item, family = 'rate', item = item, name = Items[item].name .. ' Rate',
    icon = { machine = 'port', item = item },
    cost = 4, step = 2, max = Investments.MAX_RATE,
    effect = function(level) return math.floor(30 * (1 + Investments.RATE * level) + 0.5) .. '/MIN' end,
    desc = 'Every ' .. Items[item].name .. ' port supplies 25% more per level, up to a full belt. Rich ports are already there.',
  })
end

for _, kind in ipairs(MAKERS) do
  add({
    id = 'speed:' .. kind, family = 'speed', kind = kind, name = Machines[kind].name .. ' Speed',
    icon = { machine = kind },
    cost = 4, step = 2, max = Investments.MAX_SPEED,
    effect = function(level) return 'X' .. (1 + Investments.SPEED * level) end,
    desc = 'Every ' .. Machines[kind].name .. ' runs 20% faster per level. It draws the same watts, so each item costs less power.',
  })
end

for _, mat in ipairs(Items.materials) do
  add({
    id = 'value:' .. mat, family = 'value', mat = mat, name = Items.materialName[mat] .. ' Value',
    icon = { item = RAW_OF[mat], money = true },
    cost = 4, step = 2,
    effect = function(level) return '+' .. pct(Investments.VALUE * level) end,
    desc = 'Items containing ' .. Items.materialName[mat] .. ' sell for 20% more per level. An item made of several materials gets every bonus, multiplied.',
  })
end

-- Price of the next level, given the level already held.
function Investments.cost(def, level)
  return def.cost + def.step * level
end

-- Is this investment worth offering? `resources` is the set of raw items on
-- the site, `kinds` the set of machine kinds the run can build.
function Investments.eligible(def, level, resources, kinds)
  if def.max and level >= def.max then return false end
  if def.family == 'rate' then return resources[def.item] == true end
  if def.family == 'speed' then return kinds[def.kind] == true end
  if def.family == 'value' then return resources[RAW_OF[def.mat]] == true end
  return true
end

-- The hooks of an investment at a level, as a quiet mod. Power and port
-- rates are plain numbers and have none (see Investments.watts / .rates).
local cache = {}
function Investments.mod(def, level)
  local key = def.id .. '@' .. level
  if cache[key] then return cache[key] end
  local mod = { id = def.id, name = def.name, color = 'green', quiet = true, investment = def, level = level }
  if def.family == 'speed' then
    local kind, factor = def.kind, 1 + Investments.SPEED * level
    mod.speed = function(F, e)
      return e.building.kind == kind and factor or 1
    end
  elseif def.family == 'value' then
    local mat, factor = def.mat, 1 + Investments.VALUE * level
    mod.value = function(s, ctx)
      if ctx.mats[mat] then ctx.value = ctx.value * factor end
    end
  else
    return nil
  end
  cache[key] = mod
  return mod
end

-- The quiet mods for a table of levels { id = level }, in list order.
function Investments.mods(levels)
  local mods = {}
  for _, def in ipairs(list) do
    local level = levels[def.id] or 0
    if level > 0 then
      local mod = Investments.mod(def, level)
      if mod then mods[#mods + 1] = mod end
    end
  end
  return mods
end

function Investments.watts(levels)
  return (levels.power or 0) * Investments.POWER
end

-- Port rate multipliers by item: { iron_ore = 1.5, ... }.
function Investments.rates(levels)
  local rates = {}
  for _, item in ipairs(RAW) do
    local level = levels['rate:' .. item] or 0
    if level > 0 then rates[item] = 1 + Investments.RATE * level end
  end
  return rates
end

return Investments
