-- Draws a plot's fixed pieces (ports, rocks, pads, power node) at either
-- tile size: the preview of land on offer, on the board and on the contract
-- screen.

local P = require 'src.gfx.palette'
local Sprites = require 'src.gfx.sprites'
local UI = require 'src.ui.ui'
local Map = require 'src.map'
local Terrain = require 'src.gfx.terrain'

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
  -- Fresh concrete in slabs of 2x2 tiles, with a kerb round it.
  local w, h = Map.PW * T, Map.PH * T
  UI.rect(ox, oy, w, h, P.concrete, alpha)
  for k = 2, Map.PW - 1, 2 do UI.rect(ox + k * T - 1, oy, 1, h, P.seam, alpha) end
  for k = 2, Map.PH - 1, 2 do UI.rect(ox, oy + k * T - 1, w, 1, P.seam, alpha) end
  UI.frame(ox, oy, w, h, P.kerb, alpha)
  UI.frame(ox + 1, oy + 1, w - 2, h - 2, P.kerb, (alpha or 1) * 0.5)
  for _, p in ipairs(plot.pads or {}) do UI.sprite(S.pad, ox + p.x * T, oy + p.y * T, 0, alpha) end
  for _, r in ipairs(plot.rocks) do UI.sprite(S.machine.rock, ox + r.x * T, oy + r.y * T, 0, alpha) end
  if plot.node then UI.sprite(S.machine.node, ox + plot.node.x * T, oy + plot.node.y * T, 0, alpha) end
  if plot.depot then
    UI.sprite(Terrain.depot(T), ox + Map.DEPOT[1][1] * T, oy + Map.DEPOT[1][2] * T, 0, alpha)
  end
  for _, p in ipairs(plot.ports) do
    local x, y = ox + p.x * T, oy + p.y * T
    UI.sprite(S.machine.port, x, y, 0, alpha)
    UI.sprite(S.item[p.item], x + T / 4, y + T / 4, 0, alpha)
    Land.nub(x, y, p.dir, p.rich and P.money or P.amber, alpha, T)
  end
end

return Land
