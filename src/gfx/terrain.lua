-- The site seen from above: wild grass on land you do not own, concrete
-- slabs on land you do, and scenery all around it (a road, a river, fields,
-- woods). All of it is generated from the run's seed and baked into one
-- image per zoom level, rebaked when the land changes.
--
-- Everything is worked out in "world pixels": 16 per tile, the close view's
-- scale, with (0, 0) at the site's top-left corner. The overview samples the
-- same world at half the resolution, so both zoom levels show the same place.

local ffi = require 'ffi'
local bit = require 'bit'
local P = require 'src.gfx.palette'
local Map = require 'src.map'

local Terrain = {}

Terrain.MARGIN = 4          -- tiles of scenery on every side of the site

local floor, sqrt, abs, min, max, sin, cos, atan2 =
  math.floor, math.sqrt, math.abs, math.min, math.max, math.sin, math.cos, math.atan2
local W, H = Map.W, Map.H
local M = Terrain.MARGIN

---------------------------------------------------------------- noise

local band, bxor, lshift, rshift, tobit = bit.band, bit.bxor, bit.lshift, bit.rshift, bit.tobit

-- A well-mixed hash of two integers and a seed, in [0, 1).
local function hash(x, y, s)
  local h = bxor(tobit(x * 73856093), tobit(y * 19349663), tobit(s * 83492791))
  h = bxor(h, lshift(h, 13)); h = bxor(h, rshift(h, 17)); h = bxor(h, lshift(h, 5))
  h = bxor(h, lshift(h, 13)); h = bxor(h, rshift(h, 17)); h = bxor(h, lshift(h, 5))
  return band(h, 0xffff) / 65536
end
Terrain.hash = hash

local function smooth(t) return t * t * (3 - 2 * t) end

-- Smooth value noise in [0, 1).
local function noise(x, y, s)
  local ix, iy = floor(x), floor(y)
  local fx, fy = smooth(x - ix), smooth(y - iy)
  local a, b = hash(ix, iy, s), hash(ix + 1, iy, s)
  local c, d = hash(ix, iy + 1, s), hash(ix + 1, iy + 1, s)
  return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
end

---------------------------------------------------------------- colours

-- Palette colours as bytes.
local C = setmetatable({}, { __index = function(t, k)
  local c = assert(P[k], k)
  local v = { floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5) }
  t[k] = v
  return v
end })

local FLOWERS = { 'flowerW', 'flowerY', 'flowerR', 'flowerB' }

---------------------------------------------------------------- layout

-- Where the bands of scenery run, for a seed. The road runs along one long
-- side of the site, the river along the other; woods fill the short sides.
function Terrain.layout(seed)
  local s = seed % 100003
  local roadSouth = hash(s, 1, 7) < 0.5
  local L = { seed = s, roadSouth = roadSouth, phase = hash(s, 2, 7) * 6.28 }
  local north, south = -M * 16, (H + M) * 16
  if roadSouth then
    L.road = H * 16 + 20                -- top edge of the road, world pixels
    L.river = -3 * 16 - 4               -- middle line of the river's top bank
  else
    L.road = -3 * 16 - 4
    L.river = (H + 1) * 16 + 4
  end
  L.north, L.south = north, south
  return L
end

-- The river's two banks at world column u.
local function riverEdges(L, u)
  local a = L.river + 2.5 * sin(u / 23 + L.phase) + 1.5 * sin(u / 9 + L.phase * 2)
  local b = L.river + 28 + 2.5 * sin(u / 19 + L.phase * 3) + 1.5 * sin(u / 11 + L.phase)
  return a, b
end
Terrain.riverEdges = riverEdges

-- What kind of ground a world pixel outside the site is.
local function outside(L, u, v)
  local ra, rb = riverEdges(L, u)
  if v >= ra and v < rb then return 'water' end
  if v >= ra - 3 and v < rb + 3 then return 'sand' end
  if v >= L.road and v < L.road + 28 then return 'road' end
  if L.roadSouth then
    if v >= L.road + 28 + 6 then return 'field' end
  else
    if v < L.road - 6 then return 'field' end
  end
  if u < 0 or u >= W * 16 then return 'woods' end
  return 'meadow'
end

---------------------------------------------------------------- ground

local function grass(u, v, s, wild)
  local n = noise(u / 40, v / 40, s)
  local n2 = noise(u / 9, v / 9, s + 1)
  local c
  if wild then
    c = (n < 0.42 and 'grassD') or (n > 0.7 and 'grass') or 'moss'
    if n2 > 0.74 then c = 'grassD' end
  else
    c = (n < 0.36 and 'grassD') or (n > 0.66 and 'grassL') or 'grass'
    if n2 > 0.76 then c = 'meadow' end
  end
  local blade = hash(u, floor(v / 2) * 7, s + 3)
  if blade < (wild and 0.05 or 0.03) then c = 'grassDD'
  elseif blade > (wild and 0.975 or 0.98) then c = 'grassL' end
  -- Flowers grow in drifts.
  local f = hash(u, v, s + 4)
  if f < 0.012 and noise(u / 30, v / 30, s + 40) > 0.68 then
    c = FLOWERS[floor(noise(u / 50, v / 50, s + 41) * 4) + 1]
  end
  return c
end

local function concrete(u, v, s, step, owned, tx, ty, pad)
  local lu, lv = u - tx * 16, v - ty * 16
  -- Kerb where the land ends.
  local k = 2
  if (lu < k and not owned(tx - 1, ty)) or (lu >= 16 - k and not owned(tx + 1, ty))
      or (lv < k and not owned(tx, ty - 1)) or (lv >= 16 - k and not owned(tx, ty + 1)) then
    return (hash(u, v, s + 9) < 0.15) and 'concreteD' or 'kerb'
  end
  if pad then
    -- A steel plate ringed with chevrons: whatever stands on it runs faster.
    if lu < 1 + step or lv < 1 + step or lu >= 15 - step or lv >= 15 - step then
      if lu < step or lv < step or lu >= 16 - step or lv >= 16 - step then return 'dark' end
      return (floor((lu + lv) / 3) % 2 == 0) and 'amber' or 'dark'
    end
    if lu < 4 or lv < 4 then return 'padL' end
    return 'pad'
  end
  -- Slabs of 2x2 tiles.
  if (u % 32) >= 32 - step or (v % 32) >= 32 - step then return 'seam' end
  local c = 'concrete'
  -- Each slab is poured a shade apart; the top-left edge catches the light.
  local sx, sy = floor(u / 32), floor(v / 32)
  local hs = hash(sx, sy, s + 7)
  if hash(sx, sy, s + 10) < 0.3 then c = 'concreteL' end
  if (u % 32) < step or (v % 32) < step then c = 'concreteL' end
  local h = hash(u, v, s + 6)
  if h < 0.02 then c = 'concreteD' elseif h > 0.985 then c = 'concreteL' end
  -- A stain or a crack on some slabs.
  if hs < 0.12 then
    local cx, cy = sx * 32 + 8 + hash(sx, sy, s + 8) * 16, sy * 32 + 8 + hash(sy, sx, s + 8) * 16
    local dx, dy = (u - cx) / 3.5, (v - cy) / 2.5
    if dx * dx + dy * dy < 1 + noise(u / 2, v / 2, s) * 0.5 then c = 'concreteD' end
  elseif hs < 0.26 then
    local cx, cy = sx * 32 + 8, sy * 32 + 8 + hash(sx, sy, s + 8) * 16
    local t = u - cx
    if t >= 0 and t < 14 and abs(v - (cy + t * 0.4 + sin(t) * 1.2)) < step * 0.6 then c = 'seam' end
  end
  return c
end

local function outsideColour(L, kind, u, v, s, step)
  if kind == 'water' then
    local ra, rb = riverEdges(L, u)
    if v < ra + 2 or v >= rb - 2 then return 'waterD' end
    local r = noise(u / 16, v / 2.5, s + 11)
    if r > 0.72 then return 'waterL' end
    return 'water'
  elseif kind == 'sand' then
    return hash(u, v, s + 12) < 0.2 and 'sandD' or 'sand'
  elseif kind == 'road' then
    local rv = v - L.road
    if rv < step or rv >= 28 - step then return 'roadD' end
    if rv < 1 + 2 * step or rv >= 27 - 2 * step then return 'roadL' end
    if abs(rv - 14) < step and (u % 16) < 8 then return 'paint' end
    local h = hash(u, v, s + 13)
    return (h < 0.08 and 'roadD') or (h > 0.94 and 'roadL') or 'road'
  elseif kind == 'field' then
    -- Parcels of crops between hedges.
    local px = floor((u + 400) / 88)
    local local_u = (u + 400) % 88
    if local_u < 3 then return (hash(u, v, s) < 0.5) and 'leafD' or 'leaf' end
    local crop = hash(px, 0, s + 14)
    if crop < 0.4 then
      if floor(v / 3) % 2 == 0 then return hash(u, v, s) < 0.15 and 'cropL' or 'crop' end
      return 'cropD'
    elseif crop < 0.7 then
      if floor(v / 3) % 2 == 0 then return 'soilL' end
      return hash(u, v, s) < 0.2 and 'soilD' or 'soil'
    end
    return grass(u, v, s, false)
  elseif kind == 'woods' then
    local c = grass(u, v, s + 20, true)
    if c == 'moss' then c = 'grassD' end
    return c
  end
  return grass(u, v, s, false)
end

---------------------------------------------------------------- objects

-- Trees, bushes and stones, as { kind, x, y, r, seed } in world pixels.
local function objects(L, map)
  local list = {}
  local s = L.seed
  local function add(kind, x, y, r) list[#list + 1] = { kind = kind, x = x, y = y, r = r, h = hash(floor(x), floor(y), s) } end
  for ty = -M, H + M - 1 do
    for tx = -M, W + M - 1 do
      local h1, h2, h3 = hash(tx, ty, s + 30), hash(tx, ty, s + 31), hash(tx, ty, s + 32)
      local cx, cy = tx * 16 + 8, ty * 16 + 8
      local inside = tx >= 0 and ty >= 0 and tx < W and ty < H
      if inside then
        if not map:owned(tx, ty) then
          if h1 < 0.10 then add('tree', cx + (h2 - 0.5) * 2, cy + (h3 - 0.5) * 2, 6 + h2)
          elseif h1 < 0.30 then add('bush', cx + (h2 - 0.5) * 8, cy + (h3 - 0.5) * 8, 3 + h3 * 1.5)
          elseif h1 < 0.34 then add('stone', cx + (h2 - 0.5) * 8, cy + (h3 - 0.5) * 8, 2 + h3) end
        end
      else
        local kind = outside(L, cx, cy)
        if kind == 'woods' then
          if h1 < 0.85 then add('tree', cx + (h2 - 0.5) * 8, cy + (h3 - 0.5) * 8, 7 + h2 * 3) end
          if h1 > 0.6 then add('bush', tx * 16 + h3 * 16, ty * 16 + h2 * 16, 3 + h1 * 2) end
        elseif kind == 'meadow' then
          if h1 < 0.07 then add('tree', cx + (h2 - 0.5) * 6, cy + (h3 - 0.5) * 6, 6 + h2 * 2)
          elseif h1 < 0.22 then add('bush', cx + (h2 - 0.5) * 10, cy + (h3 - 0.5) * 10, 3 + h3 * 1.5)
          elseif h1 < 0.26 then add('stone', cx + (h2 - 0.5) * 10, cy + (h3 - 0.5) * 10, 2 + h3) end
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.y < b.y end)
  return list
end

---------------------------------------------------------------- baking

local function bake(run, T)
  local map = run.map
  local L = Terrain.layout(run.seed or 1)
  local s = L.seed
  local step = 16 / T                         -- world pixels per image pixel
  local IW, IH = (W + 2 * M) * T, (H + 2 * M) * T
  local data = love.image.newImageData(IW, IH)
  local px = ffi.cast('uint8_t*', data:getFFIPointer())
  local hard = ffi.new('uint8_t[?]', IW * IH)   -- 1 where objects may not paint
  local owned = function(tx, ty) return map:owned(tx, ty) end
  local F = run.factory

  local function put(i, c)
    px[i * 4], px[i * 4 + 1], px[i * 4 + 2], px[i * 4 + 3] = c[1], c[2], c[3], 255
  end

  for y = 0, IH - 1 do
    local v = y * step - M * 16
    for x = 0, IW - 1 do
      local u = x * step - M * 16
      local tx, ty = floor(u / 16), floor(v / 16)
      local name
      if tx >= 0 and ty >= 0 and tx < W and ty < H then
        if map:owned(tx, ty) then
          name = concrete(u, v, s, step, owned, tx, ty, F and F:floorAt(tx, ty) == 'pad')
          hard[y * IW + x] = 1
        else
          name = grass(u, v, s, true)
        end
      else
        name = outsideColour(L, outside(L, u, v), u, v, s, step)
        local k = outside(L, u, v)
        if k == 'road' or k == 'water' then hard[y * IW + x] = 1 end
      end
      put(y * IW + x, C[name])
    end
  end

  -- Objects: every shadow first, then the objects from the back.
  local list = objects(L, map)
  local function paint(o, fn)
    local reach = o.r + 5
    local x0, x1 = floor((o.x - reach + M * 16) / step), floor((o.x + reach + M * 16) / step)
    local y0, y1 = floor((o.y - reach + M * 16) / step), floor((o.y + reach + M * 16) / step)
    for y = max(0, y0), min(IH - 1, y1) do
      for x = max(0, x0), min(IW - 1, x1) do
        if hard[y * IW + x] == 0 then
          local u, v = (x + 0.5) * step - M * 16, (y + 0.5) * step - M * 16
          local c, a = fn(u - o.x, v - o.y, u, v)
          if c then
            local i = (y * IW + x) * 4
            if a then
              local sh = C.shadow
              px[i] = px[i] + (sh[1] - px[i]) * a
              px[i + 1] = px[i + 1] + (sh[2] - px[i + 1]) * a
              px[i + 2] = px[i + 2] + (sh[3] - px[i + 2]) * a
            else
              px[i], px[i + 1], px[i + 2] = c[1], c[2], c[3]
            end
          end
        end
      end
    end
  end

  for _, o in ipairs(list) do
    local off = o.kind == 'tree' and 3 or 1.5
    paint(o, function(dx, dy)
      local ex, ey = (dx - off) / (o.r * 1.05), (dy - off * 1.2) / (o.r * 0.9)
      if ex * ex + ey * ey < 1 then return C.shadow, 0.32 end
    end)
  end

  for _, o in ipairs(list) do
    if o.kind == 'stone' then
      paint(o, function(dx, dy, u, v)
        local ex, ey = dx / (o.r * 1.2), dy / o.r
        local d = ex * ex + ey * ey
        if d >= 1 then return nil end
        if d > 0.6 then return C.stoneD end
        if dx + dy < -o.r * 0.3 then return C.stoneL end
        return C.stone
      end)
    else
      local tree = o.kind == 'tree'
      local lit, base, dark, edge = C.leafL, C.leaf, C.leafD, C.leafD
      if not tree then
        if o.h < 0.5 then lit, base, dark = C.leafLL, C.leafL, C.leaf else lit, base, dark = C.leafL, C.moss, C.leafD end
      end
      local ph = o.h * 6.28
      paint(o, function(dx, dy, u, v)
        local d = sqrt(dx * dx + dy * dy)
        local a = atan2(dy, dx)
        local rr = o.r + (tree and 1.1 or 0.6) * sin(a * 5 + ph) + 0.5 * sin(a * 9 + ph * 2)
        if d >= rr then return nil end
        if d > rr - step * 1.1 then return edge end
        local hx, hy = dx + o.r * 0.35, dy + o.r * 0.4
        local h = hash(floor(u), floor(v), 77)
        if hx * hx + hy * hy < (o.r * 0.55) ^ 2 then
          if tree and h < 0.1 then return C.leafLL end
          return lit
        end
        if dx + dy > o.r * 0.55 then return dark end
        if h < 0.1 then return dark end
        if not tree and h > 0.96 and o.h > 0.7 then return C.flowerR end
        return base
      end)
    end
  end

  local img = love.graphics.newImage(data)
  img:setFilter('nearest', 'nearest')
  return img
end

-- The baked ground for a run at tile size T, rebaked when the land changes.
local cache = {}
function Terrain.image(run, T)
  local key = tostring(run) .. ':' .. T .. ':' .. #run.map.order
  local c = cache[T]
  if not c or c.key ~= key then
    c = { key = key, img = bake(run, T) }
    cache[T] = c
  end
  return c.img
end

-- Forget every bake (a new run, a loaded one).
function Terrain.reset()
  cache = {}
end

---------------------------------------------------------------- the depot

-- The depot, one 2x2 building: a warehouse with a corrugated roof, a loading
-- apron with hazard stripes all the way round, and the company's sign.
local DOLLAR = {
  '..X..',
  '.XXXX',
  'X.X..',
  '.XXX.',
  '..X.X',
  'XXXX.',
  '..X..',
}

local function depotPixel(u, v)
  -- u, v in 0..31
  if u < 2 or v < 2 or u >= 30 or v >= 30 then
    -- The apron: hazard stripes.
    if u < 1 or v < 1 or u >= 31 or v >= 31 then return 'dark' end
    return (floor((u + v) / 3) % 2 == 0) and 'amber' or 'dark'
  end
  if u < 3 or v < 3 or u >= 29 or v >= 29 then return 'dark' end
  -- The walls show below the roof's front edge.
  if v >= 25 then
    if v == 25 then return 'roofD' end
    if (u >= 6 and u < 12) or (u >= 20 and u < 26) then
      return (v % 2 == 0) and 'stoneD' or 'stone'       -- roller doors
    end
    return 'concreteD'
  end
  -- The sign.
  local sx, sy = u - 13, v - 9
  if sx >= -2 and sx < 7 and sy >= -2 and sy < 9 then
    if sx < -1 or sy < -1 or sx >= 6 or sy >= 8 then return 'dark' end
    local row = DOLLAR[sy + 1]
    if row and sx >= 0 and sx < 5 and row:sub(sx + 1, sx + 1) == 'X' then return 'green' end
    return 'paperL'
  end
  -- Corrugated roof, a ridge across the middle.
  if v == 14 then return 'roofL' end
  if v == 4 then return 'roofL' end
  if u % 3 == 0 then return 'roofD' end
  if u % 3 == 1 and v < 14 then return 'roofL' end
  return 'roof'
end

local depotCache = {}
function Terrain.depot(T)
  if depotCache[T] then return depotCache[T] end
  local n = 2 * T
  local data = love.image.newImageData(n, n)
  local step = 32 / n
  for y = 0, n - 1 do
    for x = 0, n - 1 do
      local c = C[depotPixel(floor((x + 0.5) * step), floor((y + 0.5) * step))]
      data:setPixel(x, y, c[1] / 255, c[2] / 255, c[3] / 255, 1)
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter('nearest', 'nearest')
  depotCache[T] = img
  return img
end

return Terrain
