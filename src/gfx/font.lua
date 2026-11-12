-- 5-pixel-tall pixel font, drawn from an atlas built at load time.
-- Uppercase only; lowercase input is folded to uppercase. Most glyphs are
-- 3 px wide; a few (M, N, W) are wider. Each glyph advances width + 1.

local Font = { CH = 6 }

local glyphs = {
  ['A'] = '.X./X.X/XXX/X.X/X.X', ['B'] = 'XX./X.X/XX./X.X/XX.', ['C'] = '.XX/X../X../X../.XX',
  ['D'] = 'XX./X.X/X.X/X.X/XX.', ['E'] = 'XXX/X../XX./X../XXX', ['F'] = 'XXX/X../XX./X../X..',
  ['G'] = '.XX/X../X.X/X.X/.XX', ['H'] = 'X.X/X.X/XXX/X.X/X.X', ['I'] = 'XXX/.X./.X./.X./XXX',
  ['J'] = '..X/..X/..X/X.X/.X.', ['K'] = 'X.X/X.X/XX./X.X/X.X', ['L'] = 'X../X../X../X../XXX',
  ['M'] = 'X...X/XX.XX/X.X.X/X...X/X...X', ['N'] = 'X..X/XX.X/X.XX/X..X/X..X',
  ['O'] = '.X./X.X/X.X/X.X/.X.',
  ['P'] = 'XX./X.X/XX./X../X..', ['Q'] = '.X./X.X/X.X/XXX/.XX', ['R'] = 'XX./X.X/XX./X.X/X.X',
  ['S'] = '.XX/X../.X./..X/XX.', ['T'] = 'XXX/.X./.X./.X./.X.', ['U'] = 'X.X/X.X/X.X/X.X/XXX',
  ['V'] = 'X.X/X.X/X.X/X.X/.X.', ['W'] = 'X...X/X...X/X.X.X/XX.XX/X...X',
  ['X'] = 'X.X/X.X/.X./X.X/X.X',
  ['Y'] = 'X.X/X.X/.X./.X./.X.', ['Z'] = 'XXX/..X/.X./X../XXX',
  ['0'] = 'XXX/X.X/X.X/X.X/XXX', ['1'] = '.X./XX./.X./.X./XXX', ['2'] = 'XX./..X/.X./X../XXX',
  ['3'] = 'XX./..X/.X./..X/XX.', ['4'] = 'X.X/X.X/XXX/..X/..X', ['5'] = 'XXX/X../XX./..X/XX.',
  ['6'] = '.XX/X../XXX/X.X/XXX', ['7'] = 'XXX/..X/.X./.X./.X.', ['8'] = 'XXX/X.X/XXX/X.X/XXX',
  ['9'] = 'XXX/X.X/XXX/..X/XX.',
  ['.'] = '.../.../.../.../.X.', [','] = '.../.../.../.X./X..', [':'] = '.../.X./.../.X./...',
  ['!'] = '.X./.X./.X./.../.X.', ['?'] = 'XX./..X/.X./.../.X.', ['+'] = '.../.X./XXX/.X./...',
  ['-'] = '.../.../XXX/.../...', ['*'] = '.../X.X/.X./X.X/...', ['/'] = '..X/..X/.X./X../X..',
  ['%'] = 'X.X/..X/.X./X../X.X', ['$'] = 'XXX/XX./.XX/XXX/.X.',
  ['('] = '.X./X../X../X../.X.',
  [')'] = '.X./..X/..X/..X/.X.', ["'"] = '.X./.X./.../.../...', ['"'] = 'X.X/X.X/.../.../...',
  ['='] = '.../XXX/.../XXX/...', ['<'] = '..X/.X./X../.X./..X', ['>'] = 'X../.X./..X/.X./X..',
  ['#'] = 'X.X/XXX/X.X/XXX/X.X', ['['] = 'XX./X../X../X../XX.', [']'] = '.XX/..X/..X/..X/.XX',
  ['_'] = '.../.../.../.../XXX', ['&'] = '.X./X.X/.X./X.X/.XX', ['|'] = '.X./.X./.X./.X./.X.',
}

local SPACE = 4          -- advance of a space or unknown character
local CELL = 6           -- atlas cell width
local atlas
local quads, widths = {}, {}

function Font.load()
  local order = {}
  for ch in pairs(glyphs) do order[#order + 1] = ch end
  table.sort(order)
  local data = love.image.newImageData(#order * CELL, 5)
  for i, ch in ipairs(order) do
    local row, w = 0, 0
    for line in glyphs[ch]:gmatch('[^/]+') do
      w = #line
      for x = 1, w do
        if line:sub(x, x) == 'X' then data:setPixel((i - 1) * CELL + x - 1, row, 1, 1, 1, 1) end
      end
      row = row + 1
    end
    widths[ch] = w
    quads[ch] = love.graphics.newQuad((i - 1) * CELL, 0, w, 5, #order * CELL, 5)
  end
  atlas = love.graphics.newImage(data)
  atlas:setFilter('nearest', 'nearest')
end

local function advance(ch)
  local w = widths[ch]
  return w and (w + 1) or SPACE
end

-- Pixel width of a string (without the trailing gap).
function Font.width(s, scale)
  s = tostring(s):upper()
  local w = 0
  for i = 1, #s do w = w + advance(s:sub(i, i)) end
  return math.max(0, w - 1) * (scale or 1)
end

-- Draw text with its top-left corner at (x, y) in the current colour.
function Font.print(s, x, y, scale)
  s = tostring(s):upper()
  scale = scale or 1
  x, y = math.floor(x), math.floor(y)
  for i = 1, #s do
    local ch = s:sub(i, i)
    local q = quads[ch]
    if q then love.graphics.draw(atlas, q, x, y, 0, scale, scale) end
    x = x + advance(ch) * scale
  end
end

-- Break text into lines no wider than `maxChars` standard characters.
function Font.wrap(s, maxChars)
  local maxPx = maxChars * 4
  local lines, line = {}, ''
  for word in tostring(s):gmatch('%S+') do
    if #line == 0 then
      line = word
    elseif Font.width(line .. ' ' .. word) <= maxPx then
      line = line .. ' ' .. word
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if #line > 0 then lines[#lines + 1] = line end
  return lines
end

return Font
