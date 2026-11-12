-- Rules = the active upgrades (in slot order) plus the boss twist, exposed to
-- the simulation as a handful of hook calls. See src/data/upgrades.lua.

local Items = require 'src.data.items'
local Recipes = require 'src.data.recipes'
local Contracts = require 'src.data.contracts'

local Rules = {}
Rules.__index = Rules

function Rules.new(mods)
  local r = setmetatable({ mods = mods or {}, state = {}, extra = {} }, Rules)
  r.shiftLen = Contracts.shiftLen
  r.shifts = Contracts.shifts
  r.basePower = Contracts.basePower
  r.maxPolish = 1
  r.exportPeriod = 1
  r.leakEvery = nil
  r.oven = false
  for _, m in ipairs(r.mods) do
    if m.setup then m.setup(r) end
  end
  return r
end

function Rules:addRecipe(kind, recipe)
  self.extra[kind] = self.extra[kind] or {}
  table.insert(self.extra[kind], recipe)
end

function Rules:recipesFor(kind)
  local out = {}
  for _, r in ipairs(Recipes[kind] or {}) do out[#out + 1] = r end
  for _, r in ipairs(self.extra[kind] or {}) do out[#out + 1] = r end
  return out
end

function Rules:resetShift()
  self.state = {}
end

-- Price one item. Returns the $ value and the sale context.
function Rules:sale(it, tick, len)
  local def = Items[it.type]
  local ctx = {
    type = it.type, polished = it.polished, dist = it.dist,
    tick = tick, len = len, mats = {},
  }
  for _, m in ipairs(def.mats) do ctx.mats[m] = true end

  local mods, s = self.mods, self.state
  for i = 1, #mods do
    if mods[i].sellAs then mods[i].sellAs(s, ctx) end
  end
  local sold = Items[ctx.type]
  ctx.form = sold.form
  ctx.value = sold.value * 2 ^ ctx.polished
  for i = 1, #mods do
    if mods[i].value then mods[i].value(s, ctx) end
  end
  ctx.value = math.max(0, math.floor(ctx.value + 0.5))
  for i = 1, #mods do
    if mods[i].sold then mods[i].sold(s, ctx) end
  end
  return ctx.value, ctx
end

function Rules:shiftEnd(sc)
  for _, m in ipairs(self.mods) do
    if m.shiftEnd then m.shiftEnd(self.state, sc) end
  end
end

function Rules:speed(F, e)
  local sp = 1
  for _, m in ipairs(self.mods) do
    if m.speed then sp = sp * m.speed(F, e) end
  end
  return sp
end

function Rules:draw(F, e, watts)
  for _, m in ipairs(self.mods) do
    if m.draw then watts = m.draw(F, e, watts) end
  end
  return watts
end

return Rules
