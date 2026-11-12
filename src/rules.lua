-- Rules = the active upgrades (in slot order) plus the boss twist, exposed to
-- the simulation as a handful of hook calls. See src/data/upgrades.lua.

local Items = require 'src.data.items'
local Recipes = require 'src.data.recipes'
local Contracts = require 'src.data.contracts'

--
-- Rules also works out when a mod "triggers", so the UI can show it. No mod
-- declares this itself; it is read off what its hooks actually did:
--   sellAs / value   the hook changed the sale       -> `fired` from Rules:sale
--   shiftEnd         the hook changed sc.mult        -> results of Rules:shiftEnd
--   speed / draw     the hook changes a machine      -> Rules:affecting
--   setup            the mod set a rule field or added a recipe; r.owner[field]
--                    and r.recipeOwner[recipe] name it, and the simulation
--                    reports the moment that field or recipe does something.
-- Each mod is credited with its marginal change in slot order, so the credits
-- of one sale add up to exactly what the sale paid over its plain value.

local Rules = {}
Rules.__index = Rules

local function isScalar(v)
  local t = type(v)
  return t ~= 'table' and t ~= 'function'
end

function Rules.new(mods)
  local r = setmetatable({
    mods = mods or {}, state = {}, extra = {}, owner = {}, recipeOwner = {},
  }, Rules)
  r.shiftLen = Contracts.shiftLen
  r.shifts = Contracts.shifts
  r.basePower = Contracts.basePower
  r.maxPolish = 1
  r.exportPeriod = 1
  r.leakEvery = nil
  r.oven = false
  for _, m in ipairs(r.mods) do
    if m.setup then
      local before = {}
      for k, v in pairs(r) do
        if isScalar(v) then before[k] = v end
      end
      r.setting = m
      m.setup(r)
      r.setting = nil
      for k, v in pairs(r) do
        if isScalar(v) and before[k] ~= v then r.owner[k] = m end
      end
    end
  end
  return r
end

function Rules:addRecipe(kind, recipe)
  self.extra[kind] = self.extra[kind] or {}
  table.insert(self.extra[kind], recipe)
  if self.setting then self.recipeOwner[recipe] = self.setting end
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

local function credit(fired, mod, delta)
  fired = fired or {}
  for i = 1, #fired do
    if fired[i].mod == mod then
      fired[i].delta = fired[i].delta + delta
      return fired
    end
  end
  fired[#fired + 1] = { mod = mod, delta = delta }
  return fired
end

local function countKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- Price one item. Returns the $ value, the sale context, and the mods that
-- changed this sale as a list of { mod, delta } in slot order (nil if none).
-- ctx.plain is what the item would have paid with no mods at all.
function Rules:sale(it, tick, len)
  local def = Items[it.type]
  local ctx = {
    type = it.type, polished = it.polished, dist = it.dist,
    tick = tick, len = len, mats = {},
  }
  for _, m in ipairs(def.mats) do ctx.mats[m] = true end
  ctx.plain = def.value * 2 ^ ctx.polished

  local mods, s = self.mods, self.state
  local fired
  for i = 1, #mods do
    local m = mods[i]
    if m.sellAs then
      local type0, mats0 = ctx.type, countKeys(ctx.mats)
      m.sellAs(s, ctx)
      if ctx.type ~= type0 or countKeys(ctx.mats) ~= mats0 then
        fired = credit(fired, m, (Items[ctx.type].value - Items[type0].value) * 2 ^ ctx.polished)
      end
    end
  end
  local sold = Items[ctx.type]
  ctx.form = sold.form
  ctx.value = sold.value * 2 ^ ctx.polished
  for i = 1, #mods do
    local m = mods[i]
    if m.value then
      local v0 = ctx.value
      m.value(s, ctx)
      if ctx.value ~= v0 then fired = credit(fired, m, ctx.value - v0) end
    end
  end
  -- Rounding goes to the last mod that fired, so the credits stay exact.
  local exact = ctx.value
  ctx.value = math.max(0, math.floor(exact + 0.5))
  if fired then
    fired[#fired].delta = fired[#fired].delta + (ctx.value - exact)
  end
  for i = 1, #mods do
    if mods[i].sold then mods[i].sold(s, ctx) end
  end
  return ctx.value, ctx, fired
end

-- Runs the end-of-shift hooks. Returns one entry per mod that has such a
-- hook, in slot order: { mod, fired, delta, label }. `delta` is the revenue
-- its multiplier added on top of the mods before it.
function Rules:shiftEnd(sc)
  local results = {}
  for _, m in ipairs(self.mods) do
    if m.shiftEnd then
      local mult0, notes0 = sc.mult, #sc.notes
      m.shiftEnd(self.state, sc)
      local res = { mod = m, fired = sc.mult ~= mult0, delta = sc.revenue * (sc.mult - mult0) }
      if #sc.notes > notes0 then res.label = sc.notes[#sc.notes][2] end
      results[#results + 1] = res
    end
  end
  return results
end

-- The mods whose speed or draw hook changes machine entity e where it
-- stands, in slot order (nil if none).
function Rules:affecting(F, e)
  if e.machine.def.generator then return nil end
  local out
  local watts = e.machine.def.draw or 0
  for _, m in ipairs(self.mods) do
    local hit = m.speed ~= nil and m.speed(F, e) ~= 1
    if m.draw then
      local w = m.draw(F, e, watts)
      if w ~= watts then hit = true end
      watts = w
    end
    if hit then
      out = out or {}
      out[#out + 1] = m
    end
  end
  return out
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
