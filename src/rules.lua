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
-- (A sale zeroed by one mod and then changed by another is the exception:
-- value never goes below $0.)

local Rules = {}
Rules.__index = Rules

local function isScalar(v)
  local t = type(v)
  return t ~= 'table' and t ~= 'function'
end

-- base: the run's own numbers, before any mod touches them:
--   { basePower = watts, portRate = { item = multiplier } }
function Rules.new(mods, base)
  local r = setmetatable({
    mods = mods or {}, state = {}, extra = {}, owner = {}, recipeOwner = {},
  }, Rules)
  r.shiftLen = Contracts.shiftLen
  r.shifts = Contracts.shifts
  r.basePower = base and base.basePower or Contracts.basePower
  r.portRate = base and base.portRate or {}
  r.maxPolish = 1
  r.exportPeriod = 1
  r.leakEvery = nil
  r.oven = false
  r.demandBonus = 0            -- added to the multiplier of products in demand
  r.demandUnlimited = false    -- demand pays on every unit
  r.slumpMult = nil            -- replaces the multiplier of the slumped product
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

-- Added recipes come first: where one shares its input with a standard
-- recipe, it is the one the machine uses.
function Rules:recipesFor(kind)
  local out = {}
  for _, r in ipairs(self.extra[kind] or {}) do out[#out + 1] = r end
  for _, r in ipairs(Recipes[kind] or {}) do out[#out + 1] = r end
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
-- info.premium: the price multiplier of the depot face it came in through.
function Rules:sale(it, tick, len, info)
  local def = Items[it.type]
  -- A crate sells as its `units` items at once, for a little more.
  local units = it.pack or 1
  local scale = 2 ^ it.polished * units * (it.pack and Items.CRATE_BONUS or 1)
  local ctx = {
    type = it.type, polished = it.polished, dist = it.dist,
    tick = tick, len = len, mats = {}, units = units,
    premium = info and info.premium or nil,
    rules = self,
  }
  for _, m in ipairs(def.mats) do ctx.mats[m] = true end
  ctx.plain = def.value * scale

  local mods, s = self.mods, self.state
  local fired
  for i = 1, #mods do
    local m = mods[i]
    if m.sellAs then
      local type0, mats0 = ctx.type, countKeys(ctx.mats)
      m.sellAs(s, ctx)
      if ctx.type ~= type0 or countKeys(ctx.mats) ~= mats0 then
        fired = credit(fired, m, (Items[ctx.type].value - Items[type0].value) * scale)
      end
    end
  end
  local sold = Items[ctx.type]
  ctx.form, ctx.tier = sold.form, sold.tier
  ctx.value = sold.value * scale
  for i = 1, #mods do
    local m = mods[i]
    if m.value then
      local v0 = ctx.value
      m.value(s, ctx)
      if ctx.value ~= v0 then fired = credit(fired, m, ctx.value - v0) end
    end
  end
  -- Sales keep their cents: a percentage on a $1 item still counts. Only
  -- the shift total is rounded.
  ctx.value = math.max(0, ctx.value)
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
    -- Investments and mods that change every machine are not marked one by one.
    if hit and not m.quiet and not m.noPips then
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
