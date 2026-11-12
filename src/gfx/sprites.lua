-- All pixel art, authored as text and turned into images at load time.
-- Placeholder art: replace any entry with love.graphics.newImage('file.png').

local P = require 'src.gfx.palette'
local Items = require 'src.data.items'

local Sprites = { item = {}, machine = {}, belt = {} }

-- Characters used in the sprite text below.
local MAP = {
  ['0'] = P.dark, ['1'] = P.panel2, ['2'] = P.ironD, ['3'] = P.iron, ['4'] = P.ironL,
  w = P.white, o = P.orange, y = P.yellow, r = P.red, g = P.green, G = P.greenD,
  b = P.blue, p = P.purple, c = P.cyan, k = P.coal, K = P.coalL,
  u = P.copper, U = P.copperL, d = P.gold, D = P.goldL,
}

local function paint(data, rows, map, ox, oy)
  for y = 1, #rows do
    local row = rows[y]
    for x = 1, #row do
      local c = map[row:sub(x, x)]
      if c then data:setPixel(ox + x - 1, oy + y - 1, c[1], c[2], c[3], 1) end
    end
  end
end

local function image(data)
  local img = love.graphics.newImage(data)
  img:setFilter('nearest', 'nearest')
  return img
end

local function fromRows(rows, map)
  local data = love.image.newImageData(#rows[1], #rows)
  paint(data, rows, map or MAP, 0, 0)
  return image(data)
end

---------------------------------------------------------------- items (8x8)
-- A = material colour, B = its shade, C = its highlight.

local FORMS = {
  ore = {
    '..0000..',
    '.0ACA00.',
    '0AACAAB0',
    '0ABAAAB0',
    '0AAABAA0',
    '.0BAAB0.',
    '..0000..',
    '........',
  },
  dust = {
    '........',
    '........',
    '...A....',
    '..ACA.A.',
    '.ABAACA.',
    '0AAABAA0',
    '.000000.',
    '........',
  },
  ingot = {
    '........',
    '.000000.',
    '0CCCCCC0',
    '0AAAAAB0',
    '0AAAABB0',
    '0BBBBBB0',
    '.000000.',
    '........',
  },
  gear = {
    '..A..A..',
    '.AAAAAA.',
    'AAB00BAA',
    '.A0..0A.',
    '.A0..0A.',
    'AAB00BAA',
    '.AAAAAA.',
    '..A..A..',
  },
  wire = {
    '........',
    '.CCCCCC.',
    '..A00A..',
    '.AAAAAA.',
    '..A00A..',
    '.AAAAAA.',
    '..B00B..',
    '.BBBBBB.',
  },
  foil = {
    '........',
    '....CCC.',
    '..CCAAC.',
    '.CAAAAB.',
    'CAAAAB..',
    'BAABB...',
    '.BB.....',
    '........',
  },
  beam = {
    '........',
    '00000000',
    '0CCCCCC0',
    '000AA000',
    '..0AA0..',
    '000AA000',
    '0ABBBBB0',
    '00000000',
  },
  motor = {
    '........',
    '.00000..',
    '03u3u30.',
    '03u3u344',
    '03u3u344',
    '02u2u20.',
    '.00000..',
    '........',
  },
  circuit = {
    '........',
    '.000000.',
    '0gggggg0',
    '0gdggdg0',
    '0ggddgg0',
    '0gdggdg0',
    '0GGGGGG0',
    '.000000.',
  },
  gem = {
    '........',
    '..0000..',
    '.0CwCA0.',
    '0CwCAAB0',
    '.0AAAB0.',
    '..0AB0..',
    '...00...',
    '........',
  },
}

---------------------------------------------------------------- machine icons (10x10)

local ICONS = {
  smelter = {
    '....o.....',
    '...oo.....',
    '...oyo....',
    '..ooyo.o..',
    '..oyyoooo.',
    '.ooyyyyoo.',
    '.oyywwyyo.',
    '.oyywwyyo.',
    '..oyyyyo..',
    '...oooo...',
  },
  press = {
    '.44444444.',
    '.33333333.',
    '....33....',
    '....33....',
    '..333333..',
    '..........',
    '...dddd...',
    '.22222222.',
    '.33333333.',
    '..........',
  },
  assembler = {
    '4........4',
    '44......44',
    '.44....44.',
    '..44..44..',
    '...4444...',
    '....44....',
    '....44....',
    '..444444..',
    '...4444...',
    '....44....',
  },
  crusher = {
    '4444444444',
    '.4.4.4.4.4',
    '..........',
    '..u..u....',
    '....u..u..',
    '.u.....u..',
    '..........',
    '4.4.4.4.4.',
    '4444444444',
    '..........',
  },
  polisher = {
    '....w.....',
    '....w.....',
    '...wpw....',
    '.wwpppww..',
    '...wpw....',
    '....w..w..',
    '....w.wpw.',
    '.......w..',
    '..........',
    '..........',
  },
  generator = {
    '......yy..',
    '.....yy...',
    '....yy....',
    '...yyyyy..',
    '.....yy...',
    '....yy....',
    '...yy.....',
    '..yy......',
    '..........',
    '..........',
  },
  splitter = {   -- drawn facing east, rotated at draw time
    '....4.....',
    '...444....',
    '....4.....',
    '....4...4.',
    '4444444444',
    '....4...4.',
    '....4.....',
    '...444....',
    '....4.....',
    '..........',
  },
  export = {
    '....ww....',
    '..wwwwww..',
    '.ww.ww....',
    '.ww.ww....',
    '..wwwwww..',
    '....ww.ww.',
    '....ww.ww.',
    '..wwwwww..',
    '....ww....',
    '..........',
  },
}

local BODY = {   -- body, highlight, shade
  smelter   = { '5a2c2c', '7c4242', '3a1b1e' },
  press     = { '3a4766', '55668c', '252e46' },
  assembler = { '2a5654', '3f7a76', '1a3838' },
  crusher   = { '5a5034', '7c7050', '3a3320' },
  polisher  = { '4a3870', '6a5498', '2e2248' },
  generator = { '6a5a22', '8e7c38', '443a14' },
  splitter  = { '3a3852', '55527a', '25233a' },
  export    = { '2c6e3a', '46a058', '1a4424' },
  port      = { '2b2846', '47436e', '1a182c' },
}

local RUBBLE = {
  '................',
  '................',
  '......0000......',
  '....00233200....',
  '...0233332320...',
  '..023343322220..',
  '..0233332222210.',
  '.02332222221110.',
  '.0222220022110..',
  '.022220330210...',
  '..0000233320....',
  '....02333220....',
  '....0222210.....',
  '.....00000......',
  '................',
  '................',
}

-- A 16x16 bevelled machine body with an optional 10x10 icon on top.
local function chassis(kind)
  local body, light, shade = P.hex(BODY[kind][1]), P.hex(BODY[kind][2]), P.hex(BODY[kind][3])
  local data = love.image.newImageData(16, 16)
  for y = 1, 14 do
    for x = 1, 14 do
      local corner = (x == 1 or x == 14) and (y == 1 or y == 14)
      if not corner then
        local c = body
        if x == 1 or x == 14 or y == 1 or y == 14 then c = P.dark
        elseif x == 2 or y == 2 then c = light
        elseif x == 13 or y == 13 then c = shade end
        data:setPixel(x, y, c[1], c[2], c[3], 1)
      end
    end
  end
  if ICONS[kind] then paint(data, ICONS[kind], MAP, 3, 3) end
  return image(data)
end

local function floorTile()
  local data = love.image.newImageData(16, 16)
  for y = 0, 15 do
    for x = 0, 15 do
      local c = (x == 15 or y == 15) and P.bg or P.floor
      if x == 0 and y == 0 then c = P.floor2 end
      data:setPixel(x, y, c[1], c[2], c[3], 1)
    end
  end
  return image(data)
end

-- Belt facing east; `frame` scrolls the chevrons 2 px.
local function beltFrame(frame)
  local data = love.image.newImageData(16, 16)
  for y = 2, 13 do
    for x = 0, 15 do
      local c
      if y == 2 or y == 13 then
        c = P.rail
      else
        local v = (x + math.abs(y - 7.5) - 0.5 - frame * 2) % 8
        c = (v < 2) and P.beltL or P.belt
      end
      data:setPixel(x, y, c[1], c[2], c[3], 1)
    end
  end
  return image(data)
end

local function bridgeTile()
  local data = love.image.newImageData(16, 16)
  local function px(x, y, c) data:setPixel(x, y, c[1], c[2], c[3], 1) end
  for y = 2, 13 do            -- lower lane, east-west
    for x = 0, 15 do px(x, y, (y == 2 or y == 13) and P.rail or P.belt) end
  end
  for y = 0, 15 do            -- upper lane, north-south
    for x = 2, 13 do
      local c = P.beltL
      if x == 2 or x == 13 then c = P.ironD end
      if (x == 3 or x == 12) then c = P.iron end
      px(x, y, c)
    end
  end
  for i = 5, 10 do px(i, 7, P.rail); px(i, 8, P.rail) end
  return image(data)
end

function Sprites.load()
  Sprites.floor = floorTile()
  for f = 0, 3 do Sprites.belt[f + 1] = beltFrame(f) end
  for _, kind in ipairs({ 'smelter', 'press', 'assembler', 'crusher', 'polisher',
                          'generator', 'splitter', 'export', 'port' }) do
    Sprites.machine[kind] = chassis(kind)
  end
  Sprites.machine.bridge = bridgeTile()
  Sprites.machine.rubble = fromRows(RUBBLE)
  Sprites.machine.belt = Sprites.belt[1]

  for id, def in pairs(Items) do
    if type(def) == 'table' and def.form then
      local map = setmetatable({
        A = P[def.mat], B = P[def.mat .. 'D'], C = P[def.mat .. 'L'],
      }, { __index = MAP })
      Sprites.item[id] = fromRows(FORMS[def.form], map)
    end
  end
end

-- Kinds whose sprite turns with the building's direction.
Sprites.rotates = { belt = true, splitter = true }

return Sprites
