-- Minimal ECS.
--   entity    = plain table; each key is a component (e.pos, e.belt, e.machine ...)
--   world     = owns entities, hands out ids, answers component queries
--   system    = function(world, ...) registered under a phase name ('tick', ...)
-- Queries return entities sorted by id, so iteration order is deterministic.

local ECS = {}
local World = {}
World.__index = World

function ECS.world()
  return setmetatable({ ents = {}, nextId = 1, cache = {}, systems = {} }, World)
end

function World:spawn(e)
  e = e or {}
  e.id = self.nextId
  self.nextId = self.nextId + 1
  self.ents[e.id] = e
  self.cache = {}
  return e
end

function World:despawn(e)
  if self.ents[e.id] ~= e then return end
  self.ents[e.id] = nil
  e.dead = true
  self.cache = {}
end

-- Add / replace / remove (v = nil) a component after spawn.
function World:set(e, name, v)
  e[name] = v
  self.cache = {}
end

local function byId(a, b) return a.id < b.id end

-- All live entities that have every listed component (up to three).
function World:query(a, b, c)
  local key = a .. (b and ('|' .. b) or '') .. (c and ('|' .. c) or '')
  local list = self.cache[key]
  if list then return list end
  list = {}
  for _, e in pairs(self.ents) do
    if e[a] ~= nil and (not b or e[b] ~= nil) and (not c or e[c] ~= nil) then
      list[#list + 1] = e
    end
  end
  table.sort(list, byId)
  self.cache[key] = list
  return list
end

function World:addSystem(phase, fn)
  local list = self.systems[phase]
  if not list then list = {}; self.systems[phase] = list end
  list[#list + 1] = fn
end

function World:run(phase, ...)
  local list = self.systems[phase]
  if not list then return end
  for i = 1, #list do list[i](self, ...) end
end

return ECS
