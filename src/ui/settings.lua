-- Settings panel: drawn on top of whichever screen is showing (F10, the
-- title screen button, or the pause menu). Kept narrow so the picture stays
-- visible around it while the CRT sliders move.
--
-- The CRT filter has two modes: SIMPLE is one strength slider for the whole
-- filter, CUSTOM is one slider per part.

local P = require 'src.gfx.palette'
local UI = require 'src.ui.ui'
local Settings = require 'src.settings'
local Crt = require 'src.gfx.crt'

local Panel = {}

local X, W = 80, 160
local ROWH = 13
local TRACK, STEP = X + 78, 6          -- slider: 11 stops, 6 px apart
local LABEL = {
  crt = 'STRENGTH', scanlines = 'SCANLINES', glow = 'GLOW',
  vignette = 'DARK CORNERS', fringe = 'COLOUR FRINGE', bulge = 'BULGE',
}

local dragging = nil         -- key of the slider being dragged
local focus = 'crt'          -- key of the slider the arrow keys move

-- The rows for the current mode, each with the y of its text, plus the
-- panel's top and height (it grows with the number of rows).
local function layout()
  local rows = { { kind = 'mode' } }
  if Settings.custom then
    for _, part in ipairs(Settings.PARTS) do rows[#rows + 1] = { kind = 'slider', key = part } end
  else
    rows[#rows + 1] = { kind = 'slider', key = 'crt' }
  end
  rows[#rows + 1] = { kind = 'fullscreen' }
  rows[#rows + 1] = { kind = 'integer' }
  local h = 22 + #rows * ROWH + 20
  local y = math.floor((180 - h) / 2)
  for i, row in ipairs(rows) do row.y = y + 22 + (i - 1) * ROWH end
  return rows, y, h
end

local function sliders()
  local list = {}
  for _, row in ipairs(layout()) do
    if row.kind == 'slider' then list[#list + 1] = row end
  end
  return list
end

local function onTrack(row, x, y)
  return x >= TRACK - 4 and x <= TRACK + 10 * STEP + 4 and y >= row.y - 3 and y < row.y + 8
end

local function sliderAt(x, y)
  for _, row in ipairs(sliders()) do
    if onTrack(row, x, y) then return row end
  end
end

local function setFromX(key, x)
  local i = math.floor((x - TRACK) / STEP + 0.5)
  Settings.set(key, math.max(0, math.min(10, i)) * 10)
end

-- Canvas positions for the screenshot script: a stop (0..100) of a slider,
-- and the middle of a control ('mode', 'fullscreen', 'integer', 'close').
function Panel.stop(value, key)
  for _, row in ipairs(sliders()) do
    if row.key == (key or 'crt') then return TRACK + value / 10 * STEP, row.y + 2 end
  end
end

function Panel.at(name)
  local rows, y, h = layout()
  if name == 'close' then return X + W / 2, y + h - 11 end
  for _, row in ipairs(rows) do
    if row.kind == name then return X + W - 20, row.y + 2 end
  end
end

local function switch(label, y, on, w, opts)
  opts = opts or {}
  opts.active, opts.color = on, opts.color or P.green
  return UI.button(label, X + W - 8 - w, y - 3, w, 11, opts)
end

local function drawSlider(row)
  local y, live = row.y, Crt.ok
  local value = Settings[row.key]
  UI.text(LABEL[row.key], X + 8, y, live and P.text or P.faint)
  UI.rect(TRACK, y + 2, 10 * STEP + 1, 1, live and P.line or P.faint)
  if not live then
    UI.textRight('N/A', X + W - 6, y, P.faint)
    return
  end
  local kx = TRACK + value / 10 * STEP
  local hot = dragging == row.key or (not dragging and onTrack(row, UI.mx, UI.my))
  if hot then focus = row.key end
  UI.rect(TRACK, y + 2, kx - TRACK, 1, P.gold)
  UI.rect(kx - 2, y - 2, 5, 9, focus == row.key and P.white or P.dim)
  UI.frame(kx - 2, y - 2, 5, 9, P.dark)
  UI.textRight(value == 0 and 'OFF' or value, X + W - 6, y, P.gold)
end

function Panel.draw(app)
  local rows, y, h = layout()
  UI.rect(X + 2, y + 2, W, h, P.dark, 0.6)
  UI.panel(X, y, W, h, P.panel, P.line)
  UI.textCenter('SETTINGS', X + W / 2, y + 6, P.gold)
  UI.rect(X + 6, y + 15, W - 12, 1, P.line)

  for _, row in ipairs(rows) do
    if row.kind == 'mode' then
      UI.text('CRT FILTER', X + 8, row.y, Crt.ok and P.text or P.faint)
      if switch(Settings.custom and 'CUSTOM' or 'SIMPLE', row.y, Settings.custom, 40,
          { disabled = not Crt.ok, color = P.blue }) then
        Settings.setCustom(not Settings.custom)
        dragging = nil
        focus = Settings.custom and Settings.PARTS[1] or 'crt'
      end
    elseif row.kind == 'slider' then
      drawSlider(row)
    elseif row.kind == 'fullscreen' then
      UI.text('FULLSCREEN', X + 8, row.y, P.text)
      local on = love.window.getFullscreen()
      if switch(on and 'ON' or 'OFF', row.y, on, 26) then app.setFullscreen(not on) end
    else
      UI.text('INTEGER SCALING', X + 8, row.y, P.text)
      if switch(Settings.integer and 'ON' or 'OFF', row.y, Settings.integer, 26) then
        Settings.set('integer', not Settings.integer)
      end
    end
  end

  if UI.button('CLOSE', X + W / 2 - 25, y + h - 17, 50, 11) then app.closeSettings() end
end

function Panel.press(app, x, y, b)
  local row = b == 1 and Crt.ok and sliderAt(x, y)
  if row then
    dragging, focus = row.key, row.key
    setFromX(row.key, x)
    return
  end
  UI.click = { x = x, y = y, b = b }
end

function Panel.release()
  dragging = nil
end

function Panel.moved(app, x)
  if dragging then setFromX(dragging, x) end
end

-- Left / Right move the highlighted slider; Up / Down pick another one.
function Panel.key(app, key)
  if key == 'escape' then
    app.closeSettings()
    return
  end
  if not Crt.ok then return end
  local list = sliders()
  local at = 1
  for i, row in ipairs(list) do
    if row.key == focus then at = i end
  end
  focus = list[at].key
  if key == 'left' or key == 'right' then
    local step = key == 'left' and -10 or 10
    Settings.set(focus, math.max(0, math.min(100, Settings[focus] + step)))
  elseif key == 'up' or key == 'down' then
    at = math.max(1, math.min(#list, at + (key == 'up' and -1 or 1)))
    focus = list[at].key
  end
end

return Panel
