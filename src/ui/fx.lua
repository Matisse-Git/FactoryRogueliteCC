-- Feedback for mods (upgrades and boss twists) that trigger: the pop of a
-- card, the flash on a tile, and the wording of the shift ledger.
-- The simulation says what happened (trigger events, the ledger); this
-- module only keeps the short-lived animation state. Ages run on real time,
-- so effects look the same at every speed and keep fading while paused.

local P = require 'src.gfx.palette'
local Font = require 'src.gfx.font'
local UI = require 'src.ui.ui'
local Fmt = require 'src.fmt'

local Fx = {
  POP = 0.25,     -- seconds a card stays popped after a trigger
  FLASH = 0.35,   -- seconds a tile ring lasts
}

function Fx.new()
  return { pops = {}, flashes = {} }
end

-- Bosses have no colour of their own.
function Fx.color(mod)
  return P[mod.color] or P.red
end

-- Pop the card (or boss label) of `mod`. A re-trigger simply restarts it, so
-- a mod that fires constantly reads as steadily lit.
function Fx.pop(fx, mod, bad)
  local p = fx.pops[mod]
  if p then
    p.age, p.bad = 0, bad
  else
    fx.pops[mod] = { age = 0, bad = bad }
  end
end

-- A trigger event from the simulation.
function Fx.trigger(fx, ev)
  Fx.pop(fx, ev.mod, ev.delta < 0)
  if ev.what ~= 'sale' then
    fx.flashes[#fx.flashes + 1] = { x = ev.x, y = ev.y, color = Fx.color(ev.mod), age = 0 }
  end
end

function Fx.update(fx, dt)
  for mod, p in pairs(fx.pops) do
    p.age = p.age + dt
    if p.age >= Fx.POP then fx.pops[mod] = nil end
  end
  for i = #fx.flashes, 1, -1 do
    local f = fx.flashes[i]
    f.age = f.age + dt
    if f.age >= Fx.FLASH then table.remove(fx.flashes, i) end
  end
end

-- How popped `mod` is: 1 just triggered, 0 at rest. Also whether it was harmful.
function Fx.popOf(fx, mod)
  local p = fx.pops[mod]
  if not p then return 0, false end
  return 1 - p.age / Fx.POP, p.bad
end

-- One pixel left or right, alternating, for harmful pops.
function Fx.shake(pop)
  return (math.floor(pop * 8) % 2 == 0) and 1 or -1
end

-- Rings spreading from the tiles where something just happened.
function Fx.drawFlashes(fx, bx, by, tile)
  for _, f in ipairs(fx.flashes) do
    local p = f.age / Fx.FLASH
    local k = math.floor(p * 4) - 1          -- -1 .. 2 px outside the tile
    local x, y = bx + f.x * tile - k, by + f.y * tile - k
    UI.frame(x, y, tile + 2 * k, tile + 2 * k, p < 0.25 and P.white or f.color, 1 - p * 0.7)
  end
end

function Fx.money(delta)
  local n = math.floor(math.abs(delta) + 0.5)
  return (delta < 0 and '-$' or '+$') .. Fmt.num(n)
end

-- Ledger wording for { delta, n }: money if the mod moved any, else how often
-- it triggered, else a dash.
function Fx.amount(rec)
  if math.abs(rec.delta) >= 0.5 then
    return Fx.money(rec.delta), rec.delta < 0 and P.red or P.text
  elseif rec.n > 0 then
    return 'X' .. rec.n, P.text
  end
  return '-', P.faint
end

-- `s` cut down to fit `px` pixels.
function Fx.fit(s, px)
  while #s > 1 and Font.width(s) > px do s = s:sub(1, -2) end
  return s
end

return Fx
