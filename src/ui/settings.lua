-- Settings panel: drawn on top of whichever screen is showing (F10, or the
-- button on the title screen). Kept small so the picture stays visible
-- around it while the CRT slider moves.

local P = require 'src.gfx.palette'
local UI = require 'src.ui.ui'
local Settings = require 'src.settings'
local Crt = require 'src.gfx.crt'

local Panel = {}

local X, Y, W, H = 80, 48, 160, 84
local ROW = { crt = Y + 22, fullscreen = Y + 38, integer = Y + 54 }
local TRACK, STEP = X + 78, 6          -- slider: 11 stops, 6 px apart
local dragging = false

-- Canvas position of a slider stop (0..100).
function Panel.stop(value)
  return TRACK + value / 10 * STEP, ROW.crt + 2
end

local function onTrack(x, y)
  return x >= TRACK - 4 and x <= TRACK + 10 * STEP + 4 and y >= ROW.crt - 3 and y < ROW.crt + 8
end

local function setFromX(x)
  local i = math.floor((x - TRACK) / STEP + 0.5)
  Settings.set('crt', math.max(0, math.min(10, i)) * 10)
end

local function switch(value, y)
  return UI.button(value and 'ON' or 'OFF', X + W - 34, y - 3, 26, 11, { active = value, color = P.green })
end

function Panel.draw(app)
  UI.rect(X + 2, Y + 2, W, H, P.dark, 0.6)
  UI.panel(X, Y, W, H, P.panel, P.line)
  UI.textCenter('SETTINGS', X + W / 2, Y + 6, P.gold)
  UI.rect(X + 6, Y + 15, W - 12, 1, P.line)

  -- CRT strength.
  local y = ROW.crt
  local live = Crt.ok
  UI.text('CRT FILTER', X + 8, y, live and P.text or P.faint)
  local kx = TRACK + Settings.crt / 10 * STEP
  UI.rect(TRACK, y + 2, 10 * STEP + 1, 1, live and P.line or P.faint)
  if live then
    UI.rect(TRACK, y + 2, kx - TRACK, 1, P.gold)
    local hot = dragging or onTrack(UI.mx, UI.my)
    UI.rect(kx - 2, y - 2, 5, 9, hot and P.white or P.text)
    UI.frame(kx - 2, y - 2, 5, 9, P.dark)
    UI.textRight(Settings.crt == 0 and 'OFF' or Settings.crt, X + W - 6, y, P.gold)
  else
    UI.textRight('N/A', X + W - 6, y, P.faint)
  end

  y = ROW.fullscreen
  UI.text('FULLSCREEN', X + 8, y, P.text)
  if switch(love.window.getFullscreen(), y) then app.setFullscreen(not love.window.getFullscreen()) end

  y = ROW.integer
  UI.text('INTEGER SCALING', X + 8, y, P.text)
  if switch(Settings.integer, y) then Settings.set('integer', not Settings.integer) end

  if UI.button('CLOSE', X + W / 2 - 25, Y + H - 17, 50, 11) then app.closeSettings() end
end

function Panel.press(app, x, y, b)
  if b == 1 and Crt.ok and onTrack(x, y) then
    dragging = true
    setFromX(x)
    return
  end
  UI.click = { x = x, y = y, b = b }
end

function Panel.release()
  dragging = false
end

function Panel.moved(app, x)
  if dragging then setFromX(x) end
end

function Panel.key(app, key)
  if key == 'escape' then
    app.closeSettings()
  elseif Crt.ok and (key == 'left' or key == 'right') then
    local step = key == 'left' and -10 or 10
    Settings.set('crt', math.max(0, math.min(100, Settings.crt + step)))
  end
end

return Panel
