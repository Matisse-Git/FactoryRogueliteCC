-- All pixel art, authored as text and turned into images at load time.
-- Placeholder art: replace any entry with love.graphics.newImage('file.png').
--
-- Everything on the board exists at two sizes, one per zoom level:
--   Sprites.set[16]  close view: 16 px tiles, 8 px items
--   Sprites.set[8]   overview:    8 px tiles, 4 px items
-- Both sets have the same keys: floor, pad, locked, belt[1..4], corner[1..4],
-- inlet, machine[kind], anim[kind] (frames, see src/gfx/art.lua), item[id].
-- Sprites.machine / item / belt are the big set, for the screens that do
-- not zoom.

local P = require 'src.gfx.palette'
local Items = require 'src.data.items'
local Art = require 'src.gfx.art'

local Sprites = { set = { [16] = {}, [8] = {} } }

-- Characters used in the sprite text below.
local SP = P.sprite
local MAP = {
  ['0'] = P.dark, ['1'] = SP.panel2, ['2'] = P.ironD, ['3'] = P.iron, ['4'] = P.ironL,
  w = SP.white, o = SP.orange, y = SP.yellow, r = SP.red, g = SP.green, G = P.greenD,
  b = SP.blue, p = SP.purple, c = SP.cyan, k = P.coal, K = P.coalL,
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

-- Floor of an owned plot. `pad` marks a booster pad.
local function floorTile(size, pad)
  local data = love.image.newImageData(size, size)
  local last = size - 1
  for y = 0, last do
    for x = 0, last do
      local c = (x == last or y == last) and P.concreteD or P.concrete
      if pad then
        -- A steel plate ringed with chevrons: whatever stands here runs faster.
        local edge = x == 0 or y == 0 or x == last or y == last
        c = P.pad
        if edge then c = ((x + y) % 2 == 0) and P.amber or P.dark end
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
      local c = ((x * 7 + y * 13) % 11 == 0) and P.grassD or P.grass
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
        c = (x % (4 * k) == 0) and P.kerb or P.rail     -- rivets on the frame
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


local function buildSet(size)
  local set = { belt = {}, corner = {}, machine = {}, item = {}, anim = {} }
  set.floor = floorTile(size)
  set.pad = floorTile(size, true)
  set.locked = lockedTile(size)
  for f = 0, 3 do
    set.belt[f + 1] = beltFrame(size, f)
    set.corner[f + 1] = cornerFrame(size, f)
  end
  set.inlet = inletTile(size)
  for _, kind in ipairs(Art.kinds) do
    local frames = Art.frames(kind)[size]
    set.machine[kind], set.anim[kind] = frames[1], frames
  end
  set.machine.bridge = bridgeTile(size)
  set.machine.rubble = require('src.gfx.terrain').boulder(size)
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
