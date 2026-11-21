-- Little bits of life on the board: dust, leaves, smoke, sparks.
-- Positions and speeds are in tiles, so particles stay put across zoom
-- levels; sizes are in close-view pixels and halve in the overview.
--
-- A particle: { x, y, vx, vy, life, color, size, grav, drag, grow, alpha,
-- shape, fade }. `shape` 'coin' spins, 'note' (a banknote) flutters; others
-- are squares. `fade` false keeps it solid, 'late' fades only at the end.

local UI = require 'src.ui.ui'
local P = require 'src.gfx.palette'

local Particles = {}

local MAX = 600

function Particles.new()
  return { list = {} }
end

function Particles.add(ps, p)
  if #ps.list >= MAX then table.remove(ps.list, 1) end
  p.age = 0
  p.vx, p.vy = p.vx or 0, p.vy or 0
  p.size = p.size or 1
  p.alpha = p.alpha or 1
  ps.list[#ps.list + 1] = p
end

function Particles.update(ps, dt)
  local list = ps.list
  for i = #list, 1, -1 do
    local p = list[i]
    p.age = p.age + dt
    if p.age >= p.life then
      table.remove(list, i)
    else
      p.vy = p.vy + (p.grav or 0) * dt
      local drag = p.drag and (1 - p.drag * dt) or 1
      p.vx, p.vy = p.vx * drag, p.vy * drag
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    end
  end
end

-- A coin turning over: its width through one spin.
local SPIN = { 3, 2, 1, 2 }

local function coin(p, x, y, a, big)
  local w = big and SPIN[math.floor(p.age * 18) % 4 + 1] or (math.floor(p.age * 18) % 2 == 0 and 2 or 1)
  local h = big and 3 or 2
  x = x - math.floor(w / 2)
  UI.rect(x, y + h, w, 1, P.dark, 0.35 * a)
  UI.rect(x, y, w, h, P.money, a)
  if w == 3 then UI.rect(x, y, 1, 1, P.paperL, a) end
end

local function note(p, x, y, a, big)
  local flap = math.floor(p.age * 12) % 2
  local w, h = big and 5 - flap or 3, big and 3 or 2
  x = x - math.floor(w / 2) + math.floor(math.sin(p.age * 14) + 0.5)
  UI.rect(x, y + h, w, 1, P.dark, 0.35 * a)
  UI.rect(x, y, w, h, P.green, a)
  if big then UI.rect(x + math.floor(w / 2), y + 1, 1, 1, P.paperL, a) end
end

-- (ox, oy): the screen position of tile (0, 0); T: the tile size.
function Particles.draw(ps, ox, oy, T)
  local k = T / 16
  for _, p in ipairs(ps.list) do
    local t = p.age / p.life
    local fade = 1 - t
    if p.fade == false then fade = 1 elseif p.fade == 'late' then fade = math.min(1, (1 - t) / 0.3) end
    local a = p.alpha * fade
    if p.shape == 'coin' or p.shape == 'note' then
      local x, y = math.floor(ox + p.x * T + 0.5), math.floor(oy + p.y * T + 0.5)
      if p.shape == 'coin' then coin(p, x, y, a, T == 16) else note(p, x, y, a, T == 16) end
    else
      local size = math.max(1, math.floor((p.size + (p.grow or 0) * t) * k + 0.5))
      local x = math.floor(ox + p.x * T - size / 2 + 0.5)
      local y = math.floor(oy + p.y * T - size / 2 + 0.5)
      UI.rect(x, y, size, size, p.color, a)
    end
  end
end

function Particles.clear(ps)
  ps.list = {}
end

return Particles
