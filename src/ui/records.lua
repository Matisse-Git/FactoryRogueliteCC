-- Records panel, opened from the title screen.

local P = require 'src.gfx.palette'
local UI = require 'src.ui.ui'
local Fmt = require 'src.fmt'
local Records = require 'src.records'

local Panel = {}

local X, Y, W, H = 85, 40, 150, 100

function Panel.draw(app)
  UI.rect(X + 2, Y + 2, W, H, P.dark, 0.6)
  UI.panel(X, Y, W, H, P.panel, P.line)
  UI.textCenter('RECORDS', X + W / 2, Y + 6, P.gold)
  UI.rect(X + 6, Y + 15, W - 12, 1, P.line)
  local rows = {
    { 'RUNS STARTED', tostring(Records.runs) },
    { 'RUNS WON', tostring(Records.wins) },
    { 'MOST CONTRACTS CLEARED', Records.contract > 0 and tostring(Records.contract) or '-' },
    { 'ON SEED', Records.contract > 0 and tostring(Records.seed) or '-' },
    { 'BEST SHIFT', Records.shift > 0 and Fmt.money(Records.shift) or '-' },
  }
  for i, row in ipairs(rows) do
    local y = Y + 12 + i * 11
    UI.text(row[1], X + 10, y, P.dim)
    UI.textRight(row[2], X + W - 10, y, P.text)
  end
  if UI.button('CLOSE', X + W / 2 - 25, Y + H - 17, 50, 11) then app.closeRecords() end
end

function Panel.press(app, x, y, b)
  UI.click = { x = x, y = y, b = b }
end

function Panel.key(app, key)
  if key == 'escape' or key == 'return' then app.closeRecords() end
end

return Panel
