-- Bosses: the twist on every third contract. A boss attacks the factory
-- that is standing, and it is announced at the start of its sector, three
-- contracts ahead, so it can be prepared for with the shop and the layout.
--
-- A boss definition:
--   pick(run, rng)   choose its target when it is revealed: a material, a
--                    resource, a machine kind, a plot. Returns a params table,
--                    or nil when the boss makes no sense on this site yet.
--   desc(p)          one sentence, naming the target
--   hooks(p)         the same hooks an upgrade has (see src/data/upgrades.lua)
--   prepare(run, p)  changes to the board when its contract starts
--   final            only for the last contract of a run
--
-- Bosses.make turns a definition and its params into the mod that joins the
-- rules of its contract.

local Items = require 'src.data.items'
local Machines = require 'src.data.machines'
local Map = require 'src.map'

local Bosses = {}

local function sortedKeys(set)
  local list = {}
  for k in pairs(set) do list[#list + 1] = k end
  table.sort(list)
  return list
end

-- The raw materials the site's ports supply, sorted.
local MATERIAL_OF = { iron_ore = 'iron', copper_ore = 'copper', coal = 'coal', quartz = 'quartz', gold_ore = 'gold', crude = 'oil' }
local function materials(run)
  local set = {}
  for item in pairs(run:resources()) do set[MATERIAL_OF[item]] = true end
  return sortedKeys(set)
end

local function ownedPlots(run)
  local list = {}
  for sy = 0, Map.ROWS - 1 do
    for sx = 0, Map.COLS - 1 do
      if run.map:has(sx, sy) then list[#list + 1] = { sx, sy } end
    end
  end
  return list
end

-- A speed hook that stops every machine standing on one of `plots`.
local function unpowered(plots)
  return function(F, e)
    local sx, sy = Map.slotOf(e.pos.x, e.pos.y)
    for _, p in ipairs(plots) do
      if p[1] == sx and p[2] == sy then return 0 end
    end
    return 1
  end
end

Bosses.list = {
  {
    id = 'tariff', name = 'Tariff',
    pick = function(run, rng) return { mat = rng:pick(materials(run)) } end,
    desc = function(p) return 'Items containing ' .. Items.materialName[p.mat] .. ' sell for half.' end,
    hooks = function(p)
      return { value = function(s, ctx)
        if ctx.mats[p.mat] then ctx.value = ctx.value * 0.5 end
      end }
    end,
  },
  {
    id = 'brownout', name = 'Brownout',
    desc = function() return 'The site supplies half its power. Generators still give all of theirs.' end,
    hooks = function()
      return { setup = function(r) r.basePower = math.floor(r.basePower / 2) end }
    end,
  },
  {
    id = 'rockfall', name = 'Rockfall',
    desc = function() return '10 tiles of your land are buried under rubble. Whatever stood there is gone.' end,
    prepare = function(run) run:placeRubble(10) end,
  },
  {
    id = 'narrow_dock', name = 'Narrow Dock',
    desc = function() return 'Every other face of the depot is closed: 4 ways in instead of 8.' end,
    prepare = function(run) run:closeFaces() end,
  },
  {
    id = 'rush', name = 'Rush Order',
    desc = function() return 'Shifts are 20 seconds shorter.' end,
    hooks = function()
      return { setup = function(r) r.shiftLen = r.shiftLen - 20 end }
    end,
  },
  {
    id = 'inspection', name = 'Inspection',
    desc = function() return 'Items below tier 3 sell for $0: nothing raw, nothing merely smelted.' end,
    hooks = function()
      return { value = function(s, ctx)
        if ctx.tier < 3 then ctx.value = 0 end
      end }
    end,
  },
  {
    id = 'blackout', name = 'Blackout',
    -- Needs somewhere else to build: not on a one-plot site.
    pick = function(run, rng)
      local plots = ownedPlots(run)
      if #plots < 2 then return nil end
      return { plots = { rng:pick(plots) } }
    end,
    desc = function() return 'The marked plot has no power: machines on it do not run.' end,
    hooks = function(p) return { speed = unpowered(p.plots) } end,
  },
  {
    id = 'drought', name = 'Drought',
    -- Only where it leaves at least two resources flowing.
    pick = function(run, rng)
      local list = sortedKeys(run:resources())
      if #list < 3 then return nil end
      return { item = rng:pick(list) }
    end,
    desc = function(p) return 'Every ' .. Items[p.item].name .. ' port has run dry.' end,
    hooks = function(p)
      return { setup = function(r)
        local rates = {}
        for item, rate in pairs(r.portRate) do rates[item] = rate end
        rates[p.item] = 0
        r.portRate = rates
      end }
    end,
  },
  {
    id = 'strike', name = 'Strike',
    pick = function(run, rng)
      local kinds = {}
      for _, kind in ipairs(Machines.list) do
        if run.blueprints[kind] then kinds[#kinds + 1] = kind end
      end
      return { kind = rng:pick(kinds) }
    end,
    desc = function(p) return 'Every ' .. Machines[p.kind].name .. ' runs at half speed.' end,
    hooks = function(p)
      return { speed = function(F, e) return e.building.kind == p.kind and 0.5 or 1 end }
    end,
  },
  {
    id = 'glut', name = 'Glut',
    desc = function() return 'Nothing is in demand: no product pays a bonus.' end,
    hooks = function()
      return { setup = function(r) r.noDemand = true end }
    end,
  },
  {
    id = 'surge', name = 'Surge Pricing', noPips = true,
    desc = function() return 'Every machine draws 50% more power.' end,
    hooks = function()
      return { draw = function(F, e, watts) return watts * 1.5 end }
    end,
  },
  {
    id = 'long_haul', name = 'Long Haul',
    desc = function() return 'Items lose 3% of their value per belt tile travelled since their last machine, up to 60%.' end,
    hooks = function()
      return { value = function(s, ctx)
        ctx.value = ctx.value * (1 - math.min(0.6, 0.03 * ctx.dist))
      end }
    end,
  },

  -- The last contract of a run draws from these.
  {
    id = 'gridlock', name = 'Gridlock', final = true, noPips = true,
    desc = function() return 'The site supplies half its power, and every machine draws 25% more.' end,
    hooks = function()
      return {
        setup = function(r) r.basePower = math.floor(r.basePower / 2) end,
        draw = function(F, e, watts) return watts * 1.25 end,
      }
    end,
  },
  {
    id = 'saturation', name = 'Saturation', final = true,
    desc = function() return 'Every unit sold makes the next of its type worth 1% less this shift, down to 30%.' end,
    hooks = function()
      return {
        value = function(s, ctx)
          local n = s.saturation and s.saturation[ctx.type] or 0
          if n > 0 then ctx.value = ctx.value * math.max(0.3, 1 - 0.01 * n) end
        end,
        sold = function(s, ctx)
          s.saturation = s.saturation or {}
          s.saturation[ctx.type] = (s.saturation[ctx.type] or 0) + ctx.units
        end,
      }
    end,
  },
  {
    id = 'foreclosure', name = 'Foreclosure', final = true,
    pick = function(run, rng)
      local plots = ownedPlots(run)
      if #plots < 3 then return nil end
      rng:shuffle(plots)
      return { plots = { plots[1], plots[2] } }
    end,
    desc = function() return 'The two marked plots have no power: machines on them do not run.' end,
    hooks = function(p) return { speed = unpowered(p.plots) } end,
  },
}

Bosses.byId = {}
for _, def in ipairs(Bosses.list) do Bosses.byId[def.id] = def end

-- The mod of a boss with its target chosen. `params` may come from a save.
function Bosses.make(def, params)
  params = params or {}
  local mod = {
    id = def.id, name = def.name, color = 'red', boss = true, noPips = def.noPips,
    def = def, params = params, desc = def.desc(params),
  }
  for name, hook in pairs(def.hooks and def.hooks(params) or {}) do mod[name] = hook end
  return mod
end

-- Regular and final definitions, in list order.
function Bosses.pool(final)
  local list = {}
  for _, def in ipairs(Bosses.list) do
    if (def.final or false) == final then list[#list + 1] = def end
  end
  return list
end

return Bosses
