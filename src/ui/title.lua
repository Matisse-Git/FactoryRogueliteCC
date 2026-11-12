-- Title screen: pick a seed and start.

local P = require 'src.gfx.palette'
local Sprites = require 'src.gfx.sprites'
local UI = require 'src.ui.ui'
local Items = require 'src.data.items'

local Title = {}

function Title.draw(app)
  UI.rect(0, 0, 320, 180, P.bg)
  UI.textCenter('QUOTA', 160, 30, P.gold, 6)
  UI.textCenter('A FACTORY ROGUELITE', 160, 68, P.dim)

  -- A belt of everything the factory can make.
  local frame = math.floor(app.time * 16) % 4 + 1
  for x = 0, 19 do UI.sprite(Sprites.belt[frame], x * 16, 86) end
  local n = #Items.list
  local spacing = 24
  local scroll = (app.time * 32) % (n * spacing)
  for i, id in ipairs(Items.list) do
    local x = ((i - 1) * spacing + scroll) % (n * spacing) - 12
    UI.sprite(Sprites.item[id], math.floor(x), 90)
  end

  UI.textCenter('SEED ' .. app.seed, 160, 116, P.text)
  UI.textCenter('TYPE DIGITS TO CHANGE IT', 160, 125, P.faint)
  if UI.button('START RUN', 122, 138, 76, 15, { color = P.green }) then app.newRun() end
  UI.textCenter('F11 FULLSCREEN   ESC QUIT', 160, 166, P.faint)
end

function Title.press(app, x, y, b)
  UI.click = { x = x, y = y, b = b }
end

function Title.key(app, key)
  if key == 'return' or key == 'space' then
    app.newRun()
  elseif key == 'backspace' then
    app.seed = math.floor(app.seed / 10)
  elseif key == 'escape' then
    love.event.quit()
  else
    local d = tonumber(key:match('^kp(%d)$') or key)
    if d and d >= 0 and d <= 9 and app.seed < 100000 then
      app.seed = app.seed * 10 + d
    end
  end
end

return Title
