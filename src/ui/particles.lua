-- Little bits of life on the board: dust, leaves, smoke, sparks.
-- Positions and speeds are in tiles, so particles stay put across zoom
-- levels; sizes are in close-view pixels and halve in the overview.
--
-- A particle: { x, y, vx, vy, life, color, size, grav, drag, grow, alpha }

local UI = require 'src.ui.ui'

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

-- (ox, oy): the screen position of tile (0, 0); T: the tile size.
function Particles.draw(ps, ox, oy, T)
  local k = T / 16
  for _, p in ipairs(ps.list) do
    local t = p.age / p.life
    local size = math.max(1, math.floor((p.size + (p.grow or 0) * t) * k + 0.5))
    local a = p.alpha * (p.fade == false and 1 or (1 - t))
    local x = math.floor(ox + p.x * T - size / 2 + 0.5)
    local y = math.floor(oy + p.y * T - size / 2 + 0.5)
    UI.rect(x, y, size, size, p.color, a)
  end
end

function Particles.clear(ps)
  ps.list = {}
end

return Particles
