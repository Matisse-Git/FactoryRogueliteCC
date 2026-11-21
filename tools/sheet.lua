-- lovec . --sheet: draws every machine sprite, each frame at both sizes, on
-- concrete and on grass, and saves sheet.png to the save directory.

local P = require 'src.gfx.palette'
local Art = require 'src.gfx.art'

return function()
  local kinds = Art.kinds
  local S = 4
  local cw, ch = 16 * 4 + 8 * 4 + 24, 24
  local canvas = love.graphics.newCanvas(cw * 2 * S, (#kinds * ch + 8) * S)
  canvas:setFilter('nearest', 'nearest')
  love.graphics.setCanvas(canvas)
  love.graphics.clear(P.panel)
  love.graphics.push()
  love.graphics.scale(S)
  for col, ground in ipairs({ P.concrete, P.grass }) do
    local ox = (col - 1) * cw
    love.graphics.setColor(ground)
    love.graphics.rectangle('fill', ox, 0, cw, #kinds * ch + 8)
    for i, kind in ipairs(kinds) do
      local fr = Art.frames(kind)
      local y = 4 + (i - 1) * ch
      love.graphics.setColor(1, 1, 1)
      for f, img in ipairs(fr[16]) do love.graphics.draw(img, ox + 4 + (f - 1) * 17, y) end
      for f, img in ipairs(fr[8]) do love.graphics.draw(img, ox + 4 + 4 * 17 + (f - 1) * 9, y + 4) end
    end
  end
  love.graphics.pop()
  love.graphics.setCanvas()
  canvas:newImageData():encode('png', 'sheet.png')
  print('saved ' .. love.filesystem.getSaveDirectory() .. '/sheet.png')
  for i, kind in ipairs(kinds) do io.write(i, ' ', kind, '  ') end
  print('')
  return true
end
