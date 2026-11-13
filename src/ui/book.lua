-- Recipe book overlay (Tab): recipes on the left, sell values on the right.

local P = require 'src.gfx.palette'
local Sprites = require 'src.gfx.sprites'
local UI = require 'src.ui.ui'
local Items = require 'src.data.items'
local Machines = require 'src.data.machines'

local Book = {}

local function recipeRow(r, x, y)
  local ix = x
  for _, input in ipairs(r.inputs) do
    UI.sprite(Sprites.item[input[1]], ix, y)
    ix = ix + 9
  end
  UI.text('>', x + 19, y + 2, P.faint)
  local out = r.outputs[1]
  UI.sprite(Sprites.item[out[1]], x + 25, y)
  local label = Items[out[1]].name
  if out[2] > 1 then label = label .. ' X' .. out[2] end
  UI.text(label, x + 36, y + 2, P.text)
end

local function section(app, kind, x, y)
  local def = Machines[kind]
  UI.sprite(Sprites.machine[kind], x, y)
  UI.text(def.name, x + 19, y + 2, P.gold)
  UI.text((math.floor(600 / def.time + 0.5) / 10) .. '/MIN, ' .. def.draw .. 'W', x + 19, y + 9, P.dim)
  y = y + 18
  for _, r in ipairs(app.run.rules:recipesFor(kind)) do
    if Items[r.inputs[1][1]].form ~= 'dust' then
      recipeRow(r, x, y)
      y = y + 9
    end
  end
  return y + 4
end

function Book.draw(app)
  UI.rect(0, 0, 320, 180, P.dark, 0.85)
  UI.panel(3, 3, 314, 174, P.panel, P.line)
  UI.text('RECIPES', 9, 8, P.text)
  UI.textRight('TAB OR CLICK TO CLOSE', 311, 8, P.faint)

  local y = section(app, 'smelter', 9, 18)
  y = section(app, 'press', 9, y)
  UI.text('DUST SMELTS LIKE ORE.', 9, y, P.dim)

  y = section(app, 'assembler', 112, 18)
  y = section(app, 'crusher', 112, y)
  local rules = app.run.rules
  UI.text('POLISHER: X2 VALUE' .. (rules.maxPolish > 1 and ', TWICE' or ''), 112, y, P.dim)
  UI.text('GENERATOR: 10 COAL/MIN, +8W', 112, y + 7, P.dim)
  UI.text('PORT: 30/MIN', 112, y + 14, P.dim)
  UI.text('BELT: 60/MIN', 112, y + 21, P.dim)

  UI.text('SELL VALUES', 226, 18, P.gold)
  local vy = 27
  for _, id in ipairs(Items.list) do
    local iy = math.floor(vy)
    UI.sprite(Sprites.item[id], 226, iy)
    UI.textRight('$' .. Items[id].value, 250, iy + 2, P.gold)
    UI.text(Items[id].name, 254, iy + 2, P.dim)
    vy = vy + 8.5
  end
end

return Book
