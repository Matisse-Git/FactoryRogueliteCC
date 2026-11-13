-- Recipe book overlay (Tab): every machine with its rate, watts and recipes,
-- and what every item sells for. Four pages; machines you have no blueprint
-- for are listed too, greyed, so a chain can be planned before it is bought.

local P = require 'src.gfx.palette'
local Font = require 'src.gfx.font'
local Sprites = require 'src.gfx.sprites'
local UI = require 'src.ui.ui'
local Items = require 'src.data.items'
local Machines = require 'src.data.machines'

local Book = {}

local PAGES = {
  { title = 'REFINE',  cols = { { 'smelter', 'crusher' }, { 'press', 'wiremill' } } },
  { title = 'COMBINE', cols = { { 'foundry', 'refinery' }, { 'assembler' } } },
  { title = 'BUILD',   cols = { { 'manufacturer', 'polisher', 'packer' }, { 'generator', 'logistics' } } },
  { title = 'VALUES' },
}
local COLW = 152
local TABW = 56

local function rate(seconds)
  return (math.floor(600 / seconds + 0.5) / 10) .. '/MIN'
end

-- inputs > output NAME [xN] $value
local function recipeRow(r, x, y, owner)
  local ix = x
  for _, input in ipairs(r.inputs) do
    UI.sprite(Sprites.item[input[1]], ix, y)
    ix = ix + 9
  end
  UI.text('>', x + 28, y + 2, P.faint)
  local ox = x + 34
  for i, out in ipairs(r.outputs) do
    if i > 1 then
      UI.text('+', ox, y + 2, P.faint)
      ox = ox + 6
    end
    UI.sprite(Sprites.item[out[1]], ox, y)
    local label = Items[out[1]].name
    if out[2] > 1 then label = label .. ' X' .. out[2] end
    UI.text(label, ox + 10, y + 2, owner and P[owner.color] or P.text)
    ox = ox + 10 + Font.width(label) + 3
    UI.text('$' .. Items[out[1]].value, ox, y + 2, P.gold)
    ox = ox + Font.width('$' .. Items[out[1]].value) + 4
  end
end

local function header(app, kind, x, y)
  local def = Machines[kind]
  local have = app.run:unlocked(kind)
  UI.sprite(Sprites.machine[kind], x, y, 0, have and 1 or 0.4)
  UI.text(def.name, x + 19, y + 2, have and P.gold or P.faint)
  local sub = def.time and (rate(def.time) .. ', ' .. def.draw .. 'W') or ''
  if not have then sub = sub .. (sub ~= '' and '  ' or '') .. 'NO BLUEPRINT' end
  UI.text(sub, x + 19, y + 9, P.dim)
  return y + 18
end

local TEXT = {
  polisher = { 'ANY ITEM: SELLS FOR DOUBLE.', 'ONCE PER ITEM.' },
  packer = { '4 IDENTICAL ITEMS > 1 CRATE,', 'WORTH 10% MORE THAN THE FOUR.', 'A CRATE TAKES ONE BELT SLOT.' },
  generator = { 'COAL 10/MIN OR TAR 15/MIN: +10W', 'WHILE IT BURNS.' },
}

local function section(app, kind, x, y)
  if kind == 'logistics' then
    UI.text('LOGISTICS', x, y + 2, P.gold)
    y = y + 11
    for _, line in ipairs({
      'BELT: 60/MIN.', 'PORT: 30/MIN, RICH PORT 60/MIN.',
      'DEPOT FACE: 60/MIN EACH, 8 FACES.',
      'SPLITTER: FRONT, LEFT, RIGHT IN TURN.',
      'FILTER: ITS ITEM STRAIGHT ON, THE', 'REST OUT OF THE SIDES. F SETS IT.',
      'BRIDGE: TWO BELTS CROSS.',
      'BOOSTER PAD: MACHINE ON IT X1.5.',
    }) do
      UI.text(line, x, y, P.dim)
      y = y + 7
    end
    return y + 4
  end
  y = header(app, kind, x, y)
  if TEXT[kind] then
    local lines = TEXT[kind]
    if kind == 'polisher' and app.run.rules.maxPolish > 1 then
      lines = { 'ANY ITEM: SELLS FOR DOUBLE.', 'UP TO ' .. app.run.rules.maxPolish .. ' TIMES PER ITEM.' }
    end
    for _, line in ipairs(lines) do
      UI.text(line, x, y, P.dim)
      y = y + 7
    end
    return y + 5
  end
  local rules = app.run.rules
  for _, r in ipairs(rules:recipesFor(kind)) do
    if Items[r.inputs[1][1]].form ~= 'dust' then
      recipeRow(r, x, y, rules.recipeOwner[r])
      y = y + 9
    end
  end
  if kind == 'smelter' then
    UI.text('DUST AND SAND SMELT LIKE ORE.', x, y + 1, P.dim)
    y = y + 8
  end
  return y + 5
end

local function tabX(i)
  return 9 + (i - 1) * (TABW + 3)
end

function Book.draw(app)
  local g = app.g
  g.bookPage = g.bookPage or 1
  UI.rect(0, 0, 320, 180, P.dark, 0.85)
  UI.panel(3, 3, 314, 174, P.panel, P.line)
  for i, page in ipairs(PAGES) do
    local on = i == g.bookPage
    local x = tabX(i)
    UI.rect(x, 6, TABW, 10, on and P.line or P.panel2)
    UI.textCenter(i .. ' ' .. page.title, x + TABW / 2, 8, on and P.text or P.dim)
  end
  UI.textRight('TAB CLOSES', 311, 8, P.faint)

  local page = PAGES[g.bookPage]
  if page.cols then
    for c, kinds in ipairs(page.cols) do
      local x, y = 9 + (c - 1) * COLW, 22
      for _, kind in ipairs(kinds) do y = section(app, kind, x, y) end
    end
  else
    -- Sell values, tier by tier.
    local n = #Items.list
    local rows = math.ceil(n / 3)
    for i, id in ipairs(Items.list) do
      local col, row = math.floor((i - 1) / rows), (i - 1) % rows
      local x, y = 9 + col * 102, 22 + row * 11
      UI.sprite(Sprites.item[id], x, y)
      UI.textRight('$' .. Items[id].value, x + 28, y + 2, P.gold)
      UI.text(Items[id].name, x + 32, y + 2, P.dim)
    end
    UI.text('POLISHED: X2.  CRATE OF 4: X4.4.', 9, 168, P.faint)
  end
end

-- A click on a page tab turns to it; anywhere else closes the book.
-- Returns true while the book stays open.
function Book.press(app, x, y)
  if y >= 5 and y < 17 then
    for i = 1, #PAGES do
      if x >= tabX(i) and x < tabX(i) + TABW then
        app.g.bookPage = i
        return true
      end
    end
  end
  return false
end

function Book.key(app, key)
  local g = app.g
  local n = tonumber(key)
  if n and PAGES[n] then
    g.bookPage = n
  elseif key == 'right' or key == 'd' then
    g.bookPage = (g.bookPage or 1) % #PAGES + 1
  elseif key == 'left' or key == 'a' then
    g.bookPage = ((g.bookPage or 1) - 2) % #PAGES + 1
  end
end

return Book
