-- Pause menu: opens over a run (Esc, or the MENU button). The run waits
-- underneath. Abandoning takes two clicks, since a run cannot be resumed.

local P = require 'src.gfx.palette'
local UI = require 'src.ui.ui'

local Pause = {}

local X, Y, W, H = 110, 46, 100, 88
local BX, BW, BH = X + 12, W - 24, 13
local ROW = { resume = Y + 22, settings = Y + 38, abandon = Y + 54 }
local armed = false          -- ABANDON RUN was clicked once

function Pause.open()
  armed = false
end

-- Canvas position of a button's centre (for the screenshot script).
function Pause.at(name)
  return X + W / 2, ROW[name] + 6
end

function Pause.draw(app)
  UI.rect(X + 2, Y + 2, W, H, P.dark, 0.6)
  UI.panel(X, Y, W, H, P.panel, P.line)
  UI.textCenter('PAUSED', X + W / 2, Y + 6, P.gold)
  UI.rect(X + 6, Y + 15, W - 12, 1, P.line)

  if UI.button('RESUME', BX, ROW.resume, BW, BH, { color = P.green }) then app.closePause() end
  if UI.button('SETTINGS', BX, ROW.settings, BW, BH) then app.openSettings() end

  -- Moving off the button takes the question back.
  if armed and not UI.inside(BX, ROW.abandon, BW, BH) then armed = false end
  if UI.button(armed and 'REALLY ABANDON?' or 'ABANDON RUN', BX, ROW.abandon, BW, BH,
      { color = P.red, active = armed }) then
    if armed then app.abandonRun() else armed = true end
  end

  UI.textCenter('SEED ' .. app.run.seed, X + W / 2, Y + H - 13, P.faint)
end

function Pause.press(app, x, y, b)
  UI.click = { x = x, y = y, b = b }
end

function Pause.key(app, key)
  if key == 'escape' then app.closePause() end
end

return Pause
