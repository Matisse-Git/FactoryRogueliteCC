-- All pixel art, authored as text and turned into images at load time.
-- Placeholder art: replace any entry with love.graphics.newImage('file.png').
--
-- Everything on the board exists at two sizes, one per zoom level:
--   Sprites.set[16]  close view: 16 px tiles, 8 px items
--   Sprites.set[8]   overview:    8 px tiles, 4 px items
-- Both sets have the same keys: floor, pad, locked, belt[1..4], corner[1..4],
-- inlet, machine[kind], item[id]. Sprites.machine / item / belt are the big
-- set, for the screens that do not zoom.

local P = require 'src.gfx.palette'
local Items = require 'src.data.items'

local Sprites = { set = { [16] = {}, [8] = {} } }

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
  barrel = {
    '..0000..',
    '.0CCCC0.',
    '.0AAAA0.',
    '.0BBBB0.',
    '.0AAAA0.',
    '.0AAAA0.',
    '.0BBBB0.',
    '..0000..',
  },
  pane = {
    '........',
    '..00000.',
    '.0CCAA0.',
    '.0CAAA0.',
    '0AAAAB0.',
    '0AAABB0.',
    '00000...',
    '........',
  },
  brick = {
    '........',
    '.00.00..',
    '0CA0CA0.',
    '0AB0AB0.',
    '.00000..',
    '.0CAAB0.',
    '.0ABBB0.',
    '..0000..',
  },
  blob = {
    '........',
    '...00...',
    '..0AA0..',
    '.0ACAA0.',
    '.0AAAA0.',
    '0AAAAAB0',
    '0BAAABB0',
    '.000000.',
  },
  plate = {
    '........',
    '........',
    '.000000.',
    '0CCCCCC0',
    '0AAAAAA0',
    '0BBBBBB0',
    '.000000.',
    '........',
  },
  lens = {
    '........',
    '..0000..',
    '.0ACCA0.',
    '0ACAAAB0',
    '0AAAAAB0',
    '.0AAAB0.',
    '..0000..',
    '........',
  },
  wafer = {
    '........',
    '.000000.',
    '0ACACAC0',
    '0CACACA0',
    '0ACACAB0',
    '0BABABB0',
    '.000000.',
    '........',
  },
  cable = {
    '........',
    '..0000..',
    '.0AAAA0.',
    '0A0000A0',
    '0A0uu0A0',
    '0B0000B0',
    '.0BBBB0.',
    '..0000..',
  },
  chip = {
    '........',
    '.d.dd.d.',
    '.000000.',
    'd0AAAC0d',
    'd0AAAA0d',
    '.000000.',
    '.d.dd.d.',
    '........',
  },
  lamp = {
    '..0000..',
    '.0CyyC0.',
    '0CyyyyA0',
    '0AyyyyA0',
    '.0AyyA0.',
    '..0330..',
    '..0220..',
    '...00...',
  },
  engine = {
    '........',
    '.000000.',
    '0C33C330',
    '03u33u34',
    '03u33u34',
    '0B22B220',
    '.000000.',
    '.0....0.',
  },
  computer = {
    '00000000',
    '0cccccc0',
    '0cwcccc0',
    '0cccccc0',
    '00000000',
    '..0330..',
    '.033330.',
    '.000000.',
  },
  robot = {
    '..0330..',
    '.000000.',
    '.03c3c0.',
    '.033330.',
    '00000000',
    '3.0330.3',
    '..0220..',
    '..0..0..',
  },
  camera = {
    '..00....',
    '.000000.',
    '03333330',
    '030cc030',
    '030cc030',
    '03333330',
    '.000000.',
    '........',
  },
}

-- A crate: the packed item is drawn small in its window.
local CRATE = {
  '00000000',
  '0DddddD0',
  '0d0000d0',
  '0d0..0d0',
  '0d0..0d0',
  '0d0000d0',
  '0DddddD0',
  '00000000',
}
local CRATE_SMALL = { 'dddd', 'd00d', 'd00d', 'dddd' }

-- The same shapes at 4x4, for the overview. Forms without an entry are a blob.
local MINI_FORMS = {
  default = { '.AA.', 'ACAA', 'AAAB', '.BB.' },
  dust    = { '....', '.A..', 'ACA.', 'BAAB' },
  ingot   = { '....', 'CCCC', 'AAAB', 'BBBB' },
  gear    = { '.AA.', 'A00A', 'A00A', '.AA.' },
  wire    = { 'CCCC', '.AA.', 'AAAA', '.BB.' },
  foil    = { '..CC', '.CAB', 'CAB.', 'BB..' },
  beam    = { 'CCCC', '.AA.', '.AA.', 'BBBB' },
  motor   = { '000.', '3u34', '3u34', '000.' },
  circuit = { 'gggg', 'gdgd', 'gddg', 'GGGG' },
  gem     = { '.Cw.', 'CwAB', '.AB.', '....' },
  barrel  = { '.CC.', 'AAAA', 'BBBB', 'AAAA' },
  pane    = { '.CCA', 'CAAA', 'AAAB', 'AAB.' },
  brick   = { 'CA.A', 'AB.B', '.CAB', '.ABB' },
  blob    = { '.A..', 'ACA.', 'AAAB', 'BAAB' },
  plate   = { '....', 'CCCC', 'AAAA', 'BBBB' },
  lens    = { '.CC.', 'CAAB', 'AAAB', '.BB.' },
  wafer   = { 'ACAC', 'CACA', 'ACAB', 'BABB' },
  cable   = { '.AA.', 'A00A', 'B00B', '.BB.' },
  chip    = { 'd.d.', 'AAAC', 'AAAA', '.d.d' },
  lamp    = { '.yy.', 'yyyy', '.yy.', '.33.' },
  engine  = { '0000', '3u34', '3u34', '0000' },
  computer = { 'cccc', 'cwcc', '0000', '.33.' },
  robot   = { '.33.', '3c3c', '0000', '3..3' },
  camera  = { '0...', '3333', '3cc3', '3333' },
}

---------------------------------------------------------------- machine icons
-- BIG: 10x10, drawn on a 16x16 bevelled body. SMALL: 6x6, on an 8x8 body.

local BIG = {
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
  wiremill = {
    '..........',
    '.UUUUUUUU.',
    'u........u',
    '.UUUUUUUU.',
    'u........u',
    '.UUUUUUUU.',
    'u........u',
    '.uuuuuuuu.',
    '..........',
    '..........',
  },
  foundry = {
    'o........o',
    'oo......oo',
    '.oo....oo.',
    '.oyyyyyyo.',
    '.oyywwyyo.',
    '..oyyyyo..',
    '...oooo...',
    '....33....',
    '..333333..',
    '..........',
  },
  refinery = {
    '..cc......',
    '..cc..cc..',
    '..cc..cc..',
    '..cc..cc..',
    '.cccccccc.',
    '.c.cccc.c.',
    '.c.cccc.c.',
    '.cccccccc.',
    '..........',
    '..........',
  },
  manufacturer = {
    '...4444...',
    '..44..44..',
    '.44....44.',
    '.4..ww..4.',
    '.4.wwww.4.',
    '.4.wwww.4.',
    '.4..ww..4.',
    '.44....44.',
    '..44..44..',
    '...4444...',
  },
  packer = {
    '.DDDDDDDD.',
    '.d.dddd.d.',
    '.dddddddd.',
    '.d......d.',
    '.d..dd..d.',
    '.d..dd..d.',
    '.d......d.',
    '.dddddddd.',
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
  filter = {     -- drawn facing east, rotated at draw time
    '4.........',
    '44........',
    '444.......',
    '4444......',
    '444444444.',
    '4444......',
    '444.......',
    '44........',
    '4.........',
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
  node = {
    '......cc..',
    '.....cc...',
    '....cc....',
    '...ccccc..',
    '.....cc...',
    '....cc....',
    '...cc.....',
    '..cc......',
    '..........',
    '..........',
  },
}

local SMALL = {
  smelter      = { '..o...', '.oyo..', '.oyyo.', 'oywwyo', 'oyyyyo', '.oooo.' },
  press        = { '444444', '..33..', '..33..', '.3333.', '......', '222222' },
  assembler    = { '4....4', '.4..4.', '..44..', '..44..', '.4444.', '..44..' },
  crusher      = { '444444', '.4.4.4', '......', '.u..u.', '4.4.4.', '444444' },
  polisher     = { '..w...', '.wpw..', 'wpppw.', '.wpw.w', '..w.wp', '.....w' },
  generator    = { '...yy.', '..yy..', '.yyyy.', '..yy..', '.yy...', 'yy....' },
  wiremill     = { '.UUUU.', 'u....u', '.UUUU.', 'u....u', '.uuuu.', '......' },
  foundry      = { 'o....o', 'oo..oo', '.oyyo.', '.oyyo.', '..oo..', '.3333.' },
  refinery     = { '.cc...', '.cc.cc', '.cc.cc', 'cccccc', 'c.cc.c', 'cccccc' },
  manufacturer = { '.4444.', '44..44', '4.ww.4', '4.ww.4', '44..44', '.4444.' },
  packer       = { 'DDDDDD', 'd.dd.d', 'dddddd', 'd....d', 'd....d', 'dddddd' },
  splitter     = { '..4.4.', '...44.', '444444', '...44.', '..4.4.', '......' },
  filter       = { '4.....', '44....', '44444.', '44....', '4.....', '......' },
  export       = { '.wwww.', 'ww....', '.www..', '...ww.', 'wwww..', '..w...' },
  node         = { '...cc.', '..cc..', '.cccc.', '..cc..', '.cc...', 'cc....' },
}

local BODY = {   -- body, highlight, shade
  smelter      = { '5a2c2c', '7c4242', '3a1b1e' },
  press        = { '3a4766', '55668c', '252e46' },
  assembler    = { '2a5654', '3f7a76', '1a3838' },
  crusher      = { '5a5034', '7c7050', '3a3320' },
  polisher     = { '4a3870', '6a5498', '2e2248' },
  generator    = { '6a5a22', '8e7c38', '443a14' },
  wiremill     = { '4a3524', '6e5238', '2e2014' },
  foundry      = { '5e3a1e', '84562e', '3c2412' },
  refinery     = { '234a5a', '386e82', '14303a' },
  manufacturer = { '3a3a5e', '56568a', '24243e' },
  packer       = { '5a4a2a', '80693e', '3a2f18' },
  splitter     = { '3a3852', '55527a', '25233a' },
  filter       = { '3a3852', '55527a', '25233a' },
  export       = { '2c6e3a', '46a058', '1a4424' },
  port         = { '2b2846', '47436e', '1a182c' },
  node         = { '1f3f66', '32609a', '12263f' },
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

local RUBBLE_SMALL = {
  '........',
  '..0000..',
  '.034320.',
  '03433220',
  '03322210',
  '.022210.',
  '..0000..',
  '........',
}

-- A bevelled machine body with an optional icon on top, 16 or 8 px.
local function chassis(kind, size)
  local body, light, shade = P.hex(BODY[kind][1]), P.hex(BODY[kind][2]), P.hex(BODY[kind][3])
  local data = love.image.newImageData(size, size)
  if size == 16 then
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
    if BIG[kind] then paint(data, BIG[kind], MAP, 3, 3) end
  else
    for y = 0, 7 do
      for x = 0, 7 do
        local c = body
        if x == 0 or y == 0 then c = light
        elseif x == 7 or y == 7 then c = shade end
        data:setPixel(x, y, c[1], c[2], c[3], 1)
      end
    end
    if SMALL[kind] then paint(data, SMALL[kind], MAP, 1, 1) end
  end
  return image(data)
end

-- Floor of an owned plot. `pad` marks a booster pad.
local function floorTile(size, pad)
  local data = love.image.newImageData(size, size)
  local last = size - 1
  for y = 0, last do
    for x = 0, last do
      local c = (x == last or y == last) and P.bg or P.floor
      if x == 0 and y == 0 then c = P.floor2 end
      if pad then
        -- A ring of chevrons: whatever stands here runs faster.
        local edge = x == 0 or y == 0 or x == last - 1 or y == last - 1
        if edge and (x + y) % 2 == 0 and x < last and y < last then c = P.cyanD end
        if not edge and x < last and y < last then c = P.pad end
      end
      data:setPixel(x, y, c[1], c[2], c[3], 1)
    end
  end
  return image(data)
end

-- Land that is not yours (yet).
local function lockedTile(size)
  local data = love.image.newImageData(size, size)
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local c = P.bg
      if x == size / 2 and y == size / 2 then c = P.floor end
      data:setPixel(x, y, c[1], c[2], c[3], 1)
    end
  end
  return image(data)
end

-- Belt facing east; `frame` scrolls the chevrons a quarter of their spacing.
local function beltFrame(size, frame)
  local k = size / 16
  local data = love.image.newImageData(size, size)
  local top, bottom = 2 * k, size - 2 * k - 1
  for y = top, bottom do
    for x = 0, size - 1 do
      local c
      if y == top or y == bottom then
        c = P.rail
      else
        local v = (x / k + math.abs(y / k - 7.5 + (k < 1 and 0.5 or 0)) - 0.5 - frame * 2) % 8
        c = (v < 2) and P.beltL or P.belt
      end
      data:setPixel(x, y, c[1], c[2], c[3], 1)
    end
  end
  return image(data)
end

-- Rounded corner: exits east, fed from the north (the belt's left side).
-- Flip it vertically for a feed from the south; rotate for other headings.
-- The chevrons fan around the top-right corner of the tile and stay in
-- phase with the straight belts on either end.
local function cornerFrame(size, frame)
  local k = size / 16
  local data = love.image.newImageData(size, size)
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local dx, dy = size - (x + 0.5), y + 0.5
      local r = math.sqrt(dx * dx + dy * dy) / k
      if r >= 2 and r < 14 then
        local c
        if r < 2 + 1 / k or r >= 14 - 1 / k then
          c = P.rail
        else
          local along = math.atan2(dy, dx) / (math.pi / 2) * 16
          local v = (along + math.abs(r - 8) - 0.5 - frame * 2) % 8
          c = (v < 2) and P.beltL or P.belt
        end
        data:setPixel(x, y, c[1], c[2], c[3], 1)
      end
    end
  end
  return image(data)
end

-- Overlay for a straight belt (facing east) that is fed from the north:
-- opens the rail and carries the incoming belt's surface in.
local function inletTile(size)
  local k = size / 16
  local data = love.image.newImageData(size, size)
  local l, r = 2 * k, size - 2 * k - 1
  for y = 0, 2 * k do
    for x = l, r do
      local edge = x == l or x == r
      if not (edge and y == 2 * k) then
        local c = edge and P.rail or P.belt
        data:setPixel(x, y, c[1], c[2], c[3], 1)
      end
    end
  end
  if size == 16 then
    -- A small arrowhead pointing into the belt.
    for i = 0, 2 do
      data:setPixel(5 + i, i, P.beltL[1], P.beltL[2], P.beltL[3], 1)
      data:setPixel(10 - i, i, P.beltL[1], P.beltL[2], P.beltL[3], 1)
    end
  end
  return image(data)
end

local function bridgeTile(size)
  local k = size / 16
  local data = love.image.newImageData(size, size)
  local function px(x, y, c) data:setPixel(x, y, c[1], c[2], c[3], 1) end
  local a, b = 2 * k, size - 2 * k - 1
  for y = a, b do              -- lower lane, east-west
    for x = 0, size - 1 do px(x, y, (y == a or y == b) and P.rail or P.belt) end
  end
  for y = 0, size - 1 do       -- upper lane, north-south
    for x = a, b do
      local c = P.beltL
      if x == a or x == b then c = P.ironD end
      if size == 16 and (x == a + 1 or x == b - 1) then c = P.iron end
      px(x, y, c)
    end
  end
  local m = size / 2
  for i = math.floor(m - 3 * k), math.ceil(m + 3 * k) - 1 do px(i, m - 1, P.rail); px(i, m, P.rail) end
  return image(data)
end

local MACHINES = {
  'smelter', 'press', 'assembler', 'crusher', 'polisher', 'generator',
  'wiremill', 'foundry', 'refinery', 'manufacturer', 'packer',
  'splitter', 'filter', 'export', 'port', 'node',
}

local function buildSet(size)
  local set = { belt = {}, corner = {}, machine = {}, item = {} }
  set.floor = floorTile(size)
  set.pad = floorTile(size, true)
  set.locked = lockedTile(size)
  for f = 0, 3 do
    set.belt[f + 1] = beltFrame(size, f)
    set.corner[f + 1] = cornerFrame(size, f)
  end
  set.inlet = inletTile(size)
  for _, kind in ipairs(MACHINES) do set.machine[kind] = chassis(kind, size) end
  set.machine.bridge = bridgeTile(size)
  set.machine.rubble = fromRows(size == 16 and RUBBLE or RUBBLE_SMALL)
  set.machine.rock = set.machine.rubble
  set.machine.belt = set.belt[1]
  set.crate = fromRows(size == 16 and CRATE or CRATE_SMALL)

  for id, def in pairs(Items) do
    if type(def) == 'table' and def.form then
      local map = setmetatable({
        A = P[def.mat], B = P[def.mat .. 'D'], C = P[def.mat .. 'L'],
      }, { __index = MAP })
      if size == 16 then
        set.item[id] = fromRows(FORMS[def.form], map)
      else
        set.item[id] = fromRows(MINI_FORMS[def.form] or MINI_FORMS.default, map)
      end
    end
  end
  return set
end

function Sprites.load()
  Sprites.set[16] = buildSet(16)
  Sprites.set[8] = buildSet(8)
  local big = Sprites.set[16]
  Sprites.floor, Sprites.belt, Sprites.corner, Sprites.inlet = big.floor, big.belt, big.corner, big.inlet
  Sprites.machine, Sprites.item = big.machine, big.item
end

-- Kinds whose sprite turns with the building's direction.
Sprites.rotates = { belt = true, splitter = true, filter = true }

return Sprites
