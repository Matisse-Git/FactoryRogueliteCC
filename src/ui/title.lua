-- Title screen: continue a saved run, or pick a seed and start a new one.

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

  UI.textCenter('SEED ' .. app.seed, 160, 106, P.text)
  UI.textCenter('TYPE DIGITS TO CHANGE IT', 160, 114, P.faint)
  local saved = app.hasSave()
  if saved and UI.button('CONTINUE', 122, 123, 76, 13, { color = P.gold }) then app.continueRun() end
  if UI.button(saved and 'NEW RUN' or 'START RUN', 122, 139, 76, 13, { color = P.green }) then app.newRun() end
  if UI.button('RECORDS', 102, 155, 56, 11) then app.openRecords() end
  if UI.button('SETTINGS', 162, 155, 56, 11) then app.openSettings() end
  UI.textCenter('F10 SETTINGS   F11 FULLSCREEN   ESC QUIT', 160, 171, P.faint)
end

-- Canvas positions of the buttons (for the screenshot script).
Title.at = { continue = { 160, 129 }, start = { 160, 145 }, records = { 130, 160 }, settings = { 190, 160 } }

function Title.press(app, x, y, b)
  UI.click = { x = x, y = y, b = b }
end

function Title.key(app, key)
  if key == 'return' or key == 'space' then
    -- Enter picks up where you left off, if there is anything to pick up.
    if not (app.hasSave() and app.continueRun()) then app.newRun() end
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
