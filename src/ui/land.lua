-- Draws a plot's fixed pieces (ports, rocks, pads, power node) at either
-- tile size: the preview of land on offer, on the board and on the contract
-- screen.

local P = require 'src.gfx.palette'
local Sprites = require 'src.gfx.sprites'
local UI = require 'src.ui.ui'
local Map = require 'src.map'

local Land = {}

-- The mark on the edge of a tile where a port or machine puts its items out.
function Land.nub(x, y, dir, c, a, T)
  UI.color(c, a)
  if T == 16 then
    if dir == 0 then love.graphics.rectangle('fill', x + 14, y + 6, 2, 4)
    elseif dir == 1 then love.graphics.rectangle('fill', x + 6, y + 14, 4, 2)
    elseif dir == 2 then love.graphics.rectangle('fill', x, y + 6, 2, 4)
    else love.graphics.rectangle('fill', x + 6, y, 4, 2) end
  else
    if dir == 0 then love.graphics.rectangle('fill', x + 7, y + 3, 1, 2)
    elseif dir == 1 then love.graphics.rectangle('fill', x + 3, y + 7, 2, 1)
    elseif dir == 2 then love.graphics.rectangle('fill', x, y + 3, 1, 2)
    else love.graphics.rectangle('fill', x + 3, y, 2, 1) end
  end
end

-- plot at pixel (ox, oy), tile size T (16 or 8).
function Land.draw(plot, ox, oy, T, alpha)
  local S = Sprites.set[T]
  for y = 0, Map.PH - 1 do
    for x = 0, Map.PW - 1 do UI.sprite(S.floor, ox + x * T, oy + y * T, 0, alpha) end
  end
  for _, p in ipairs(plot.pads or {}) do UI.sprite(S.pad, ox + p.x * T, oy + p.y * T, 0, alpha) end
  for _, r in ipairs(plot.rocks) do UI.sprite(S.machine.rock, ox + r.x * T, oy + r.y * T, 0, alpha) end
  if plot.node then UI.sprite(S.machine.node, ox + plot.node.x * T, oy + plot.node.y * T, 0, alpha) end
  if plot.depot then
    for _, t in ipairs(Map.DEPOT) do UI.sprite(S.machine.export, ox + t[1] * T, oy + t[2] * T, 0, alpha) end
  end
  for _, p in ipairs(plot.ports) do
    local x, y = ox + p.x * T, oy + p.y * T
    UI.sprite(S.machine.port, x, y, 0, alpha)
    UI.sprite(S.item[p.item], x + T / 4, y + T / 4, 0, alpha)
    Land.nub(x, y, p.dir, p.rich and P.gold or P.yellow, alpha, T)
  end
end

return Land
