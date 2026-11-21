-- Machine art: every building drawn from a few primitives (boxes, tanks,
-- wheels) on a 16x16 grid, lit from the top-left and seen from a little in
-- front, with an ink outline and a drop shadow. Each kind has its own shape
-- and paint so a factory reads at a glance, and its own animation while it
-- works. The overview's 8x8 sprites are shrunk from the same drawings.
--
--   Art.frames(kind)   { image16, ... } and { image8, ... }, frame 1 at rest
--   Art.smoke[kind]    where smoke leaves it while it works (16 px coords)

local P = require 'src.gfx.palette'

local Art = {}

local hex = P.hex
local INK = P.dark
local SHADOW = { 0, 0, 0, 0.3, shadow = true }

local function pal(a, A, h) return { a = hex(a), A = hex(A), h = hex(h) } end

local PAINT = {
  metal    = pal('9aa0a8', '5f646c', 'd4d8de'),
  brick    = pal('a5493a', '7a3328', 'c4664f'),
  press    = pal('4f6d8f', '34495f', '7393b5'),
  crusher  = pal('c09a3e', '8a6a24', 'dcbc62'),
  wiremill = pal('b0683a', '7f4426', 'd88d58'),
  foundry  = pal('6a665f', '45423d', '8f8a80'),
  refinery = pal('4f8a8a', '326262', '7ab3ad'),
  assembler = pal('5f8a4a', '40622f', '86ae68'),
  manufacturer = pal('3f5f8a', '2a4060', '6587b8'),
  polisher = pal('8a6aaa', '634a80', 'b294cf'),
  packer   = pal('b8925a', '8a6a3a', 'd8b47a'),
  generator = pal('4a6a4f', '334a36', '6e8f72'),
  wood     = pal('a3825d', '6a4f36', 'c4a378'),
  node     = pal('8f8a80', '5d5a55', 'b9b4a8'),
}
local FIRE = { hex('f08a30'), hex('ffe060'), hex('e0524a'), hex('fff3c0') }
local AMBER, GLASS, GLASSD, WHITE, COPPER, RUBBER =
  hex('e0a92a'), hex('9fd8ee'), hex('4f8fa8'), hex('fffaf0'), hex('d9773a'), hex('45403a')

---------------------------------------------------------------- drawing

local function new()
  local g = {}
  for y = 0, 15 do g[y] = {} end
  return g
end

local function px(g, x, y, c)
  if x >= 0 and x < 16 and y >= 0 and y < 16 then g[y][x] = c end
end

local function rect(g, x, y, w, h, c)
  for yy = y, y + h - 1 do
    for xx = x, x + w - 1 do px(g, xx, yy, c) end
  end
end

local function outline(g, x, y, w, h)
  rect(g, x, y, w, 1, INK); rect(g, x, y + h - 1, w, 1, INK)
  rect(g, x, y, 1, h, INK); rect(g, x + w - 1, y, 1, h, INK)
  -- Rounded corners.
  px(g, x, y, nil); px(g, x + w - 1, y, nil); px(g, x, y + h - 1, nil); px(g, x + w - 1, y + h - 1, nil)
end

-- A box: a lit top, a darker front `depth` rows deep, an ink outline.
local function box(g, x, y, w, h, depth, p)
  rect(g, x, y, w, h, p.a)
  rect(g, x + 1, y + 1, w - 2, 1, p.h)
  rect(g, x + 1, y + 1, 1, h - depth - 2, p.h)
  rect(g, x, y + h - depth, w, depth, p.A)
  rect(g, x + 1, y + h - depth - 1, w - 2, 1, p.a)
  outline(g, x, y, w, h)
  rect(g, x + 1, y + h - depth, w - 2, 1, INK)
end

-- A filled circle (centre and radius in pixels, may be fractional).
local function disc(g, cx, cy, r, c)
  for y = math.floor(cy - r), math.ceil(cy + r) do
    for x = math.floor(cx - r), math.ceil(cx + r) do
      local dx, dy = x + 0.5 - cx, y + 0.5 - cy
      if dx * dx + dy * dy <= r * r then px(g, x, y, c) end
    end
  end
end

-- A ring of ink round a disc.
local function ring(g, cx, cy, r)
  for y = math.floor(cy - r - 1), math.ceil(cy + r + 1) do
    for x = math.floor(cx - r - 1), math.ceil(cx + r + 1) do
      local dx, dy = x + 0.5 - cx, y + 0.5 - cy
      local d = dx * dx + dy * dy
      if d > r * r and d <= (r + 1) * (r + 1) then px(g, x, y, INK) end
    end
  end
end

-- A wheel with spokes, turned by `a` (radians).
local function wheel(g, cx, cy, r, rim, hub, a)
  disc(g, cx, cy, r, rim)
  disc(g, cx, cy, r - 1.2, hub)
  ring(g, cx, cy, r)
  for k = 0, 1 do
    local t = a + k * math.pi / 2
    for s = -r + 1.4, r - 1.4, 0.5 do
      px(g, math.floor(cx + math.cos(t) * s), math.floor(cy + math.sin(t) * s), rim)
    end
  end
  px(g, math.floor(cx), math.floor(cy), INK)
end

-- A vertical tank: rounded top, a highlight down its left side.
local function tank(g, x, y, w, h, p)
  rect(g, x, y + 2, w, h - 2, p.a)
  rect(g, x + 1, y + 2, 1, h - 3, p.h)
  rect(g, x + w - 2, y + 2, 1, h - 3, p.A)
  rect(g, x + 1, y, w - 2, 3, p.h)
  rect(g, x + 1, y + h - 2, w - 2, 1, p.A)
  outline(g, x, y, w, h)
  rect(g, x + 1, y + 3, w - 2, 1, p.A)
  px(g, x + 1, y + 1, p.h)
end

local function line(g, x0, y0, x1, y1, c)
  local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
  for i = 0, n do
    local t = n == 0 and 0 or i / n
    px(g, math.floor(x0 + (x1 - x0) * t + 0.5), math.floor(y0 + (y1 - y0) * t + 0.5), c)
  end
end

---------------------------------------------------------------- the machines

local M = {}
local N = {}            -- frames per kind
Art.smoke = {}

N.smelter = 2
Art.smoke.smelter = { 12, 0 }
M.smelter = function(g, f)
  local p = PAINT.brick
  box(g, 1, 4, 14, 11, 4, p)
  -- Brickwork on the top.
  for _, y in ipairs({ 6, 8 }) do rect(g, 2, y, 12, 1, p.A) end
  for x = 3, 13, 4 do px(g, x, 7, p.A); px(g, x + 2, 9, p.A); px(g, x + 2, 5, p.A) end
  -- The fire door.
  rect(g, 5, 11, 6, 3, INK)
  rect(g, 6, 12, 4, 2, FIRE[f == 1 and 1 or 2])
  px(g, 7 + (f == 1 and 0 or 1), 12, FIRE[f == 1 and 2 or 4])
  -- Chimney.
  box(g, 10, 0, 4, 7, 2, PAINT.metal)
  rect(g, 11, 1, 2, 1, INK)
end

N.press = 2
M.press = function(g, f)
  local p = PAINT.press
  box(g, 1, 7, 14, 8, 3, p)
  -- The die.
  rect(g, 5, 9, 6, 2, AMBER)
  rect(g, 5, 11, 6, 1, INK)
  -- Columns and crossbeam.
  box(g, 1, 1, 3, 10, 1, PAINT.metal)
  box(g, 12, 1, 3, 10, 1, PAINT.metal)
  box(g, 1, 0, 14, 4, 1, p)
  -- The ram: up, then down on the die.
  local ry = f == 1 and 4 or 6
  box(g, 5, ry, 6, 3, 1, PAINT.metal)
  rect(g, 7, 3, 2, ry - 3, PAINT.metal.A)
end

N.crusher = 2
M.crusher = function(g, f)
  local p = PAINT.crusher
  box(g, 1, 3, 14, 12, 3, p)
  -- The hopper and its jaws.
  rect(g, 3, 5, 10, 5, INK)
  for x = 4, 11 do
    local up = (x + f) % 2 == 0
    px(g, x, up and 6 or 8, PAINT.metal.h)
    px(g, x, 7, PAINT.metal.A)
  end
  -- Hazard stripes on the front.
  for x = 2, 13 do if (x + f) % 4 < 2 then px(g, x, 12, AMBER) else px(g, x, 12, INK) end end
end

N.wiremill = 4
M.wiremill = function(g, f)
  local p = PAINT.wiremill
  box(g, 1, 6, 14, 9, 3, p)
  -- Two spools winding wire.
  local a = f * math.pi / 4
  wheel(g, 4.5, 6.5, 3.5, COPPER, PAINT.wood.A, a)
  wheel(g, 11.5, 6.5, 3.5, COPPER, PAINT.wood.A, -a)
  line(g, 7, 8, 9, 8, COPPER)
end

N.foundry = 2
Art.smoke.foundry = { 3, 0 }
M.foundry = function(g, f)
  local p = PAINT.foundry
  box(g, 1, 4, 14, 11, 4, p)
  -- The crucible of molten metal.
  disc(g, 8.5, 8, 3.3, INK)
  disc(g, 8.5, 8, 2.4, FIRE[f == 1 and 1 or 2])
  px(g, 8, 7, FIRE[f == 1 and 2 or 4])
  -- Chimney.
  box(g, 1, 0, 4, 7, 2, PAINT.metal)
  rect(g, 2, 1, 2, 1, INK)
  -- Rivets on the front.
  for x = 3, 13, 3 do px(g, x, 12, p.h) end
end

N.refinery = 2
M.refinery = function(g, f)
  local p = PAINT.refinery
  tank(g, 1, 1, 7, 14, p)
  tank(g, 8, 4, 7, 11, p)
  -- Pipes between them.
  rect(g, 6, 9, 4, 2, PAINT.metal.a)
  rect(g, 6, 9, 4, 1, PAINT.metal.h)
  -- Gauge with a valve light.
  disc(g, 11.5, 9.5, 1.6, WHITE)
  ring(g, 11.5, 9.5, 1.6)
  px(g, 11, 9, INK)
  px(g, 4, 4, f == 1 and AMBER or FIRE[3])
  -- Bands on the tanks.
  rect(g, 2, 11, 5, 1, p.A); rect(g, 9, 12, 5, 1, p.A)
end

N.assembler = 2
M.assembler = function(g, f)
  local p = PAINT.assembler
  box(g, 1, 6, 14, 9, 3, p)
  -- A strip of conveyor on the bench.
  rect(g, 2, 9, 12, 2, RUBBER)
  for x = 3, 13, 3 do px(g, x + (f - 1), 9, PAINT.metal.A) end
  -- The robot arm, swinging between two poses.
  disc(g, 4, 8, 2.2, PAINT.metal.A)
  ring(g, 4, 8, 2.2)
  local ex, ey = f == 1 and 10 or 12, f == 1 and 2 or 5
  line(g, 4, 7, 7, 3, AMBER)
  line(g, 5, 7, 8, 3, AMBER)
  line(g, 7, 3, ex, ey, AMBER)
  line(g, 7, 2, ex, ey - 1, INK)
  px(g, ex, ey + 1, INK); px(g, ex + 1, ey, INK); px(g, ex - 1, ey, INK)
end

N.manufacturer = 4
M.manufacturer = function(g, f)
  local p = PAINT.manufacturer
  box(g, 0, 1, 16, 14, 4, p)
  -- Three hatches with lamps that chase while it works.
  for k = 0, 2 do
    local x = 2 + k * 4
    rect(g, x, 3, 3, 4, INK)
    rect(g, x + 1, 4, 1, 2, GLASS)
    px(g, x + 1, 8, (f - 1) == k and AMBER or INK)
  end
  -- A gear on the side.
  wheel(g, 13, 7, 2, PAINT.metal.a, PAINT.metal.A, f * math.pi / 4)
  -- Rivets.
  for x = 2, 13, 3 do px(g, x, 12, p.h) end
end

N.polisher = 2
M.polisher = function(g, f)
  local p = PAINT.polisher
  box(g, 2, 7, 12, 8, 3, p)
  -- The buffing wheel.
  wheel(g, 8, 6, 4.3, PAINT.metal.h, PAINT.metal.a, f * math.pi / 4)
  -- Sparkles.
  if f == 1 then px(g, 2, 3, WHITE); px(g, 14, 5, WHITE) else px(g, 13, 2, WHITE); px(g, 3, 6, WHITE); px(g, 2, 6, WHITE) end
end

N.packer = 2
M.packer = function(g, f)
  local p = PAINT.packer
  box(g, 1, 6, 14, 9, 3, p)
  -- A crate on top, its tape going on.
  box(g, 4, 1, 8, 8, 2, PAINT.wood)
  rect(g, 7, 2, 2, 5, PAINT.packer.h)
  rect(g, 5, 4, f == 1 and 3 or 6, 1, PAINT.packer.h)
  rect(g, 2, 11, 12, 1, p.A)
end

N.generator = 4
Art.smoke.generator = { 12, 0 }
M.generator = function(g, f)
  local p = PAINT.generator
  box(g, 1, 5, 14, 10, 4, p)
  -- Flywheel.
  wheel(g, 5, 7, 3.4, PAINT.metal.a, PAINT.metal.A, f * math.pi / 4)
  -- Firebox.
  rect(g, 9, 11, 4, 2, INK)
  rect(g, 10, 11, 2, 1, FIRE[f % 2 == 1 and 1 or 2])
  -- Chimney.
  box(g, 10, 0, 4, 8, 2, PAINT.metal)
  rect(g, 11, 1, 2, 1, INK)
end

N.node = 2
M.node = function(g, f)
  local p = PAINT.node
  box(g, 2, 5, 12, 10, 4, p)
  -- Cooling fins.
  for x = 4, 11, 2 do rect(g, x, 7, 1, 3, p.A) end
  -- Insulators on top.
  for _, x in ipairs({ 4, 8, 12 }) do
    rect(g, x - 1, 1, 2, 5, WHITE)
    rect(g, x - 1, 2, 2, 1, PAINT.metal.A)
    rect(g, x - 1, 4, 2, 1, PAINT.metal.A)
  end
  -- A warning plate.
  rect(g, 6, 11, 4, 2, AMBER)
  px(g, 7 + (f - 1), 11, INK)
end

-- Splitter and filter are drawn facing east; the board turns them.
N.splitter = 1
M.splitter = function(g)
  local p = PAINT.metal
  box(g, 1, 1, 14, 14, 2, p)
  -- In from the west, out three ways.
  rect(g, 2, 7, 7, 2, AMBER)
  rect(g, 8, 3, 2, 10, AMBER)
  rect(g, 8, 7, 6, 2, AMBER)
  px(g, 7, 3, AMBER); px(g, 7, 12, AMBER); px(g, 12, 6, AMBER); px(g, 12, 9, AMBER)
  px(g, 8, 2, AMBER); px(g, 9, 2, AMBER); px(g, 8, 13, AMBER); px(g, 9, 13, AMBER)
end

N.filter = 1
M.filter = function(g)
  local p = PAINT.metal
  box(g, 1, 1, 14, 14, 2, p)
  -- A funnel: the chosen item straight on, the rest out of the sides.
  rect(g, 4, 4, 1, 8, INK)
  rect(g, 5, 5, 1, 6, INK)
  rect(g, 6, 6, 7, 4, GLASSD)
  rect(g, 6, 7, 8, 2, AMBER)
  rect(g, 8, 2, 1, 3, AMBER); rect(g, 8, 11, 1, 3, AMBER)
end

-- A port: a timber headframe over the shaft, the raw item shows through the
-- middle (the board draws it), and a pulley turns while it supplies.
N.port = 4
M.port = function(g, f)
  local p = PAINT.wood
  rect(g, 1, 1, 14, 14, p.a)
  rect(g, 4, 4, 8, 8, INK)
  rect(g, 2, 2, 12, 1, p.h)
  rect(g, 2, 2, 1, 11, p.h)
  rect(g, 1, 12, 14, 2, p.A)
  for x = 5, 11, 3 do px(g, x, 2, p.A) end
  outline(g, 1, 1, 14, 14)
  -- Corner posts.
  for _, c in ipairs({ { 1, 1 }, { 12, 1 }, { 1, 11 }, { 12, 11 } }) do
    rect(g, c[1], c[2], 3, 3, p.A)
    px(g, c[1] + 1, c[2] + 1, INK)
  end
  -- The pulley.
  wheel(g, 8, 2, 1.6, PAINT.metal.h, PAINT.metal.A, f * math.pi / 4)
end

-- The depot's tiles (the board draws the building over all four instead).
N.export = 1
M.export = function(g)
  box(g, 1, 1, 14, 14, 3, PAINT.brick)
  rect(g, 4, 4, 8, 6, WHITE)
  rect(g, 7, 4, 2, 6, hex('3d8b3d'))
end

---------------------------------------------------------------- images

-- The grid, with a drop shadow, as ImageData.
local function render(g)
  local data = love.image.newImageData(16, 16)
  for y = 0, 15 do
    for x = 0, 15 do
      local c = g[y][x]
      if c then
        data:setPixel(x, y, c[1], c[2], c[3], 1)
      elseif (g[y - 1] and g[y - 1][x - 1]) and x > 0 then
        data:setPixel(x, y, 0, 0, 0, SHADOW[4])
      end
    end
  end
  return data
end

-- Half size: each 2x2 block becomes its commonest colour, ink winning
-- ties so outlines survive.
local function shrink(src)
  local data = love.image.newImageData(8, 8)
  for y = 0, 7 do
    for x = 0, 7 do
      local count, best, bestN = {}, nil, 0
      local solid = 0
      for dy = 0, 1 do
        for dx = 0, 1 do
          local r, g, b, a = src:getPixel(x * 2 + dx, y * 2 + dy)
          if a > 0.9 then
            solid = solid + 1
            local key = string.format('%.3f,%.3f,%.3f', r, g, b)
            count[key] = (count[key] or 0) + 1
            local n = count[key] + ((r + g + b) < 0.5 and 0.5 or 0)
            if n > bestN then best, bestN = { r, g, b }, n end
          end
        end
      end
      if solid >= 2 and best then
        data:setPixel(x, y, best[1], best[2], best[3], 1)
      elseif solid == 0 then
        local _, _, _, a = src:getPixel(x * 2 + 1, y * 2 + 1)
        if a > 0 then data:setPixel(x, y, 0, 0, 0, a) end
      end
    end
  end
  return data
end

local function image(data)
  local img = love.graphics.newImage(data)
  img:setFilter('nearest', 'nearest')
  return img
end

Art.kinds = {}
for kind in pairs(M) do Art.kinds[#Art.kinds + 1] = kind end
table.sort(Art.kinds)

-- { [16] = { frame images }, [8] = { frame images } } for a kind.
local cache = {}
function Art.frames(kind)
  if cache[kind] then return cache[kind] end
  if not M[kind] then return nil end
  local out = { [16] = {}, [8] = {} }
  for f = 1, N[kind] or 1 do
    local g = new()
    M[kind](g, f)
    local data = render(g)
    out[16][f] = image(data)
    out[8][f] = image(shrink(data))
  end
  cache[kind] = out
  return out
end

return Art
