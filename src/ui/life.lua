-- Ambient life on the site: workers, delivery trucks, rabbits, deer, ducks,
-- birds and the shadows of clouds, plus what each boss does to the place.
-- All of it is for looking at: nothing here touches the simulation, blocks
-- building or takes a click, and it draws its randomness from LÖVE's own
-- generator, never from the run's.
--
-- Positions are in tiles (floats), with (0, 0) the site's top-left corner.

local P = require 'src.gfx.palette'
local UI = require 'src.ui.ui'
local Map = require 'src.map'
local Terrain = require 'src.gfx.terrain'
local Particles = require 'src.ui.particles'

local Life = {}

local floor, min, max, abs, sin, cos, sqrt = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.sqrt
local rnd = function(a, b)
  local r = love.math.random()
  if a then return a + (b - a) * r end
  return r
end
local M = Terrain.MARGIN

local WALK = 1.4             -- worker speed, tiles per second
local TRUCK_SPEED = 3.2      -- tiles per second
local MAX_WORKERS = 14

local SKIN = { P.hex('e8b98a'), P.hex('c98d5e'), P.hex('8a5a3a') }
local VESTS = { P.hex('f08a30'), P.hex('4f7fb0'), P.hex('d9c24a'), P.hex('5f8a4a') }
local TRUCKS = { P.hex('c4453a'), P.hex('2e6da4'), P.hex('3d8b3d'), P.hex('e0a92a'), P.hex('7b55b5') }
local HAT, PANTS, WHITE, SIGN = P.hex('ffe060'), P.hex('34495f'), P.hex('fffaf0'), P.hex('f1e8d0')

function Life.new()
  return {
    workers = {}, trucks = {}, animals = nil, birds = {}, clouds = nil,
    truckIn = 1.5, birdsIn = rnd(3, 8), t = 0,
  }
end

---------------------------------------------------------------- helpers

local function free(F, map, x, y)
  return map:owned(x, y) and F:at(x, y) == nil
end

-- Breadth-first path over free tiles from (sx, sy) to (tx, ty), as a list of
-- tiles, or nil. The start tile may be taken (a worker built over).
local function path(F, map, sx, sy, tx, ty)
  local W = Map.W
  local key = function(x, y) return y * W + x end
  local prev = { [key(sx, sy)] = -1 }
  local queue, head = { { sx, sy } }, 1
  while head <= #queue do
    local c = queue[head]
    head = head + 1
    if c[1] == tx and c[2] == ty then
      local out = {}
      local k = key(tx, ty)
      while k ~= -1 do
        table.insert(out, 1, { k % W, floor(k / W) })
        k = prev[k]
      end
      return out
    end
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = c[1] + d[1], c[2] + d[2]
      local k = key(nx, ny)
      if nx >= 0 and ny >= 0 and nx < W and ny < Map.H and not prev[k] and free(F, map, nx, ny) then
        prev[k] = key(c[1], c[2])
        queue[#queue + 1] = { nx, ny }
      end
    end
  end
  return nil
end

local function randomFree(F, map, near)
  local list = {}
  for y = 0, Map.H - 1 do
    for x = 0, Map.W - 1 do
      if free(F, map, x, y) and (not near or near(x, y)) then list[#list + 1] = { x, y } end
    end
  end
  if #list == 0 then return nil end
  return list[love.math.random(#list)]
end

local function depotRing(map)
  local d = map.depot
  if not d then return function() return false end end
  local x0, y0 = d[1][1], d[1][2]
  return function(x, y)
    return x >= x0 - 1 and x <= x0 + 2 and y >= y0 - 1 and y <= y0 + 2
  end
end

local function adjacentTo(list)
  local set = {}
  for _, e in ipairs(list) do set[e.pos.y * Map.W + e.pos.x] = true end
  return function(x, y)
    return set[y * Map.W + x + 1] or set[y * Map.W + x - 1] or set[(y + 1) * Map.W + x] or set[(y - 1) * Map.W + x]
  end
end

---------------------------------------------------------------- workers

local function newWorker(F, map)
  local at = randomFree(F, map, depotRing(map)) or randomFree(F, map)
  if not at then return nil end
  return {
    x = at[1] + 0.5, y = at[2] + 0.5, jx = rnd(-0.18, 0.18), jy = rnd(-0.12, 0.18),
    state = 'idle', timer = rnd(0, 1.5), path = nil,
    skin = SKIN[love.math.random(#SKIN)], vest = VESTS[love.math.random(#VESTS)],
    phase = rnd(0, 6.28), face = 1,
  }
end

-- Where a worker goes next, given what the factory is doing.
local function chooseTask(w, ctx)
  local F, map = ctx.F, ctx.map
  local boss = ctx.bossId
  local target, state, stay
  if boss == 'strike' and not w.inspector then
    target, state, stay = randomFree(F, map, depotRing(map)), 'picket', rnd(3, 6)
  elseif ctx.live and not w.inspector then
    local working = {}
    for _, e in ipairs(ctx.machines) do
      if e.machine.status == 'work' then working[#working + 1] = e end
    end
    if #working > 0 and rnd() < 0.8 then
      local pick = working[love.math.random(#working)]
      target = randomFree(F, map, adjacentTo({ pick }))
      state, stay = 'work', rnd(2, 5)
      w.lookAt = pick
    end
  end
  if not target then
    if w.inspector then
      target, state, stay = randomFree(F, map, ctx.machines[1] and adjacentTo(ctx.machines) or nil), 'inspect', rnd(1.5, 3)
    elseif rnd() < 0.45 then
      target, state, stay = randomFree(F, map, depotRing(map)), 'sit', rnd(4, 9)
    else
      target, state, stay = randomFree(F, map), 'idle', rnd(1, 4)
    end
  end
  if not target then w.state, w.timer = 'idle', 1 return end
  local p = path(F, map, floor(w.x), floor(w.y), target[1], target[2])
  if not p then w.state, w.timer = 'idle', rnd(0.5, 1.5) return end
  w.path, w.step, w.next, w.stay = p, 1, state, stay
  w.state = 'walk'
end

local function updateWorker(w, dt, ctx)
  local F, map = ctx.F, ctx.map
  -- Built over: step aside.
  if w.state ~= 'walk' and not free(F, map, floor(w.x), floor(w.y)) then
    local at = randomFree(F, map, function(x, y) return abs(x - floor(w.x)) <= 2 and abs(y - floor(w.y)) <= 2 end)
      or randomFree(F, map)
    if at then w.x, w.y = at[1] + 0.5, at[2] + 0.5 end
  end
  if w.state == 'walk' then
    local tile = w.path[w.step]
    if not tile then
      w.state, w.timer, w.path = w.next, w.stay, nil
      return
    end
    if w.step > 1 and not free(F, map, tile[1], tile[2]) then
      w.state, w.timer = 'idle', 0.2      -- the way is blocked now: think again
      return
    end
    local tx, ty = tile[1] + 0.5, tile[2] + 0.5
    local dx, dy = tx - w.x, ty - w.y
    local d = sqrt(dx * dx + dy * dy)
    local speed = WALK * (ctx.bossId == 'rush' and 2 or 1)
    if d < speed * dt then
      w.x, w.y, w.step = tx, ty, w.step + 1
    else
      w.x, w.y = w.x + dx / d * speed * dt, w.y + dy / d * speed * dt
      if abs(dx) > 0.01 then w.face = dx > 0 and 1 or -1 end
    end
    w.phase = w.phase + dt * 10
  else
    w.timer = w.timer - dt
    if w.state == 'work' or w.state == 'inspect' then w.phase = w.phase + dt * 6 end
    if w.timer <= 0 then chooseTask(w, ctx) end
  end
end

local function drawWorker(w, ox, oy, T)
  local k = T / 16
  local x = floor(ox + (w.x + w.jx) * T + 0.5)
  local y = floor(oy + (w.y + w.jy) * T + 0.5)
  if k < 1 then
    -- Overview: three pixels tall.
    UI.rect(x, y - 2, 1, 1, w.inspector and WHITE or HAT)
    UI.rect(x, y - 1, 1, 1, w.inspector and WHITE or w.vest)
    UI.rect(x, y, 1, 1, PANTS)
    return
  end
  UI.rect(x - 2, y + 2, 5, 1, P.dark, 0.25)                    -- shadow
  if w.state == 'sit' then
    UI.rect(x - 1, y - 3, 3, 1, HAT)
    UI.rect(x - 1, y - 2, 3, 1, w.skin)
    UI.rect(x - 2, y - 1, 5, 2, w.vest)
    UI.rect(x - 2, y + 1, 5, 1, PANTS)
    return
  end
  local walking = w.state == 'walk'
  local step = walking and (sin(w.phase) > 0 and 1 or 0) or 0
  local hat = w.inspector and WHITE or HAT
  local body = w.inspector and WHITE or w.vest
  UI.rect(x - 1, y - 6, 3, 1, hat)
  UI.rect(x - 1, y - 5, 3, 2, w.skin)
  UI.rect(x - 2, y - 3, 5, 3, body)
  UI.rect(x - 1, y, 1, 2 - step, PANTS)
  UI.rect(x + 1, y, 1, 1 + step, PANTS)
  if w.state == 'work' then
    -- Hammering away.
    local up = sin(w.phase) > 0
    UI.rect(x + 2 * w.face, y - (up and 5 or 3), 1, 2, PANTS)
  elseif w.state == 'inspect' then
    UI.rect(x + 2, y - 3, 2, 3, SIGN)                      -- clipboard
    UI.rect(x + 2, y - 3, 2, 1, P.clipD)
  elseif w.state == 'picket' then
    UI.rect(x + 2, y - 9, 1, 7, P.bark)                    -- the sign on its stick
    UI.rect(x, y - 13, 6, 4, SIGN)
    UI.rect(x + 1, y - 12, 4, 1, P.red)
    UI.rect(x + 1, y - 10, 3, 1, P.red)
  end
end

---------------------------------------------------------------- trucks

local function spawnTruck(L, ctx)
  local road = ctx.layout.road
  local east = rnd() < 0.5
  local span = Map.W + 2 * M
  L.trucks[#L.trucks + 1] = {
    east = east,
    x = east and (-M - 2) or (Map.W + M + 1),
    y = (road + (east and 21 or 7)) / 16,
    color = TRUCKS[love.math.random(#TRUCKS)],
    wait = 0, span = span,
  }
end

local BOOTH_X = Map.W / 2 + 0.5

local function updateTrucks(L, dt, ctx)
  L.truckIn = L.truckIn - dt
  if L.truckIn <= 0 then
    spawnTruck(L, ctx)
    local rate = ctx.rate or 0
    L.truckIn = ctx.live and max(1.2, 7 / (1 + math.log10(1 + rate))) or rnd(6, 11)
    L.truckIn = L.truckIn * rnd(0.7, 1.3)
  end
  for i = #L.trucks, 1, -1 do
    local t = L.trucks[i]
    local dir = t.east and 1 or -1
    if ctx.bossId == 'tariff' and not t.paid then
      -- Everyone stops at the toll booth.
      local before = (BOOTH_X - t.x) * dir
      if before > 0 and before < 1.4 then
        t.wait = t.wait + dt
        if t.wait > 0.9 then t.paid = true end
        goto continue
      end
    end
    t.x = t.x + dir * TRUCK_SPEED * dt
    if t.x < -M - 4 or t.x > Map.W + M + 4 then table.remove(L.trucks, i) end
    ::continue::
  end
end

local function drawTruck(t, ox, oy, T)
  if T < 16 then return end
  local x = floor(ox + t.x * T + 0.5)
  local y = floor(oy + t.y * T + 0.5) - 4
  local f = t.east and 1 or -1
  -- Drawn facing east around x, mirrored for west.
  local function r(dx, dy, w, h, c, a)
    if f == 1 then UI.rect(x + dx, y + dy, w, h, c, a) else UI.rect(x - dx - w, y + dy, w, h, c, a) end
  end
  r(-9, 7, 18, 2, P.dark, 0.3)          -- shadow
  r(-9, 0, 12, 7, P.dark)               -- trailer
  r(-8, 1, 10, 5, P.paperL)
  r(-8, 3, 10, 1, t.color)
  r(3, 1, 6, 6, P.dark)                 -- cab
  r(4, 2, 4, 4, t.color)
  r(7, 2, 1, 4, P.glass)
  r(-7, 7, 2, 1, P.dark); r(-3, 7, 2, 1, P.dark); r(5, 7, 2, 1, P.dark)
end

local function drawBooth(L, ox, oy, T, ctx)
  if T < 16 then return end
  local road = ctx.layout.road
  local x = floor(ox + (BOOTH_X - 0.5) * T)
  local y = floor(oy + road / 16 * T)
  -- The booth on the verge, a barrier across each lane.
  local by = ctx.layout.roadSouth and (y + 30) or (y - 10)
  UI.rect(x - 4, by, 9, 8, P.dark)
  UI.rect(x - 3, by + 1, 7, 6, P.paperL)
  UI.rect(x - 3, by + 1, 7, 2, P.red)
  UI.rect(x - 1, by + 4, 3, 2, P.glass)
  for lane = 0, 1 do
    local ly = y + 2 + lane * 14
    for k = 0, 11 do UI.rect(x + 3 + (lane == 0 and -16 or 0) + k, ly + 5, 1, 2, (floor(k / 2) % 2 == 0) and P.red or P.white) end
  end
end

---------------------------------------------------------------- animals

local function placeAnimals(L, ctx)
  local list = {}
  local layout, map = ctx.layout, ctx.map
  local function where(kinds, tries)
    for _ = 1, tries or 200 do
      local u, v = rnd(-M * 16, (Map.W + M) * 16), rnd(-M * 16, (Map.H + M) * 16)
      local g = Terrain.groundAt(layout, map, u, v)
      if kinds[g] then return u / 16, v / 16 end
    end
  end
  for _ = 1, 7 do
    local x, y = where({ wild = true, meadow = true })
    if x then list[#list + 1] = { kind = 'rabbit', x = x, y = y, timer = rnd(0, 3), face = 1 } end
  end
  for _ = 1, 3 do
    local x, y = where({ woods = true })
    if x then list[#list + 1] = { kind = 'deer', x = x, y = y, timer = rnd(0, 5), face = rnd() < 0.5 and 1 or -1 } end
  end
  for _ = 1, 5 do
    local x, y = where({ water = true })
    if x then list[#list + 1] = { kind = 'duck', x = x, y = y, timer = rnd(0, 4), face = rnd() < 0.5 and 1 or -1, phase = rnd(0, 6) } end
  end
  L.animals = list
end

local HOME = { rabbit = { wild = true, meadow = true }, deer = { woods = true, meadow = true }, duck = { water = true } }

local function updateAnimal(a, dt, ctx)
  local layout, map = ctx.layout, ctx.map
  local home = HOME[a.kind]
  -- Land became yours (or rock fell): move off it.
  if not home[Terrain.groundAt(layout, map, a.x * 16, a.y * 16)] and not a.hop then
    a.timer = 0
  end
  if a.hop then
    a.hop.t = a.hop.t + dt
    local t = min(1, a.hop.t / a.hop.d)
    a.x, a.y = a.hop.x0 + (a.hop.x1 - a.hop.x0) * t, a.hop.y0 + (a.hop.y1 - a.hop.y0) * t
    if t >= 1 then a.hop = nil end
    return
  end
  if a.kind == 'duck' then
    a.phase = a.phase + dt
    local nx = a.x + a.face * dt * 0.12
    if home[Terrain.groundAt(layout, map, nx * 16, a.y * 16)] then a.x = nx else a.face = -a.face end
  end
  a.timer = a.timer - dt
  if a.timer > 0 then return end
  local reach = a.kind == 'rabbit' and 0.5 or (a.kind == 'deer' and 0.35 or 0.25)
  for _ = 1, 8 do
    local ang = rnd(0, 6.28)
    local x1, y1 = a.x + cos(ang) * reach, a.y + sin(ang) * reach
    if home[Terrain.groundAt(layout, map, x1 * 16, y1 * 16)] then
      a.hop = { x0 = a.x, y0 = a.y, x1 = x1, y1 = y1, t = 0, d = a.kind == 'rabbit' and 0.22 or 0.9 }
      a.face = x1 > a.x and 1 or -1
      break
    end
  end
  if not a.hop and not home[Terrain.groundAt(layout, map, a.x * 16, a.y * 16)] then
    -- Stranded: slip away and come back somewhere else.
    a.gone = true
  end
  a.timer = a.kind == 'rabbit' and (rnd() < 0.7 and rnd(0.2, 0.6) or rnd(2, 5)) or rnd(2, 6)
end

local function drawAnimal(a, ox, oy, T)
  local x = floor(ox + a.x * T + 0.5)
  local y = floor(oy + a.y * T + 0.5)
  local f = a.face
  local function r(dx, dy, w, h, c, al)
    if f == 1 then UI.rect(x + dx, y + dy, w, h, c, al) else UI.rect(x - dx - w + 1, y + dy, w, h, c, al) end
  end
  if T < 16 then
    UI.rect(x, y, a.kind == 'deer' and 2 or 1, 1, a.kind == 'duck' and WHITE or P.soilL)
    return
  end
  if a.kind == 'rabbit' then
    local up = a.hop and 1 or 0
    r(-1, 1, 4, 1, P.dark, 0.25)
    r(-1, -1 - up, 3, 2, P.soilL)
    r(1, -3 - up, 1, 2, P.soil)
    r(-2, -1 - up, 1, 1, WHITE)
  elseif a.kind == 'deer' then
    r(-3, 3, 7, 1, P.dark, 0.25)
    r(-3, -1, 6, 3, P.soil)
    r(-3, 1, 6, 1, P.soilL)
    r(-3, 2, 1, 1, P.soilD); r(2, 2, 1, 1, P.soilD)
    r(3, -3, 2, 2, P.soil)
    r(4, -5, 1, 2, P.soilD)
  else
    local bob = sin(a.phase * 3) > 0.6 and 1 or 0
    r(-2, 1, 5, 1, P.waterL)
    r(-1, -1 + bob, 3, 2, WHITE)
    r(1, -2 + bob, 2, 1, P.leafD)
    r(3, -2 + bob, 1, 1, P.amber)
  end
end

---------------------------------------------------------------- birds and clouds

local function spawnBirds(L)
  local fromLeft = rnd() < 0.5
  local y = rnd(-M + 1, Map.H + M - 1)
  local vy = rnd(-0.6, 0.6)
  local n = love.math.random(2, 4)
  for i = 1, n do
    L.birds[#L.birds + 1] = {
      x = (fromLeft and (-M - 1) or (Map.W + M + 1)) - (fromLeft and 1 or -1) * i * 0.6,
      y = y + (i % 2 == 0 and 1 or -1) * i * 0.35,
      vx = (fromLeft and 1 or -1) * rnd(3.2, 3.8), vy = vy, phase = rnd(0, 6.28),
    }
  end
end

local function cloudImage(T, seed)
  local w, h = 9 * 16, 5 * 16
  local blobs = {}
  for i = 1, 6 do
    blobs[i] = { love.math.random(30, w - 30), love.math.random(25, h - 25), love.math.random(16, 28) }
  end
  local k = T / 16
  local data = love.image.newImageData(floor(w * k), floor(h * k))
  for y = 0, data:getHeight() - 1 do
    for x = 0, data:getWidth() - 1 do
      local u, v = (x + 0.5) / k, (y + 0.5) / k
      for _, b in ipairs(blobs) do
        local dx, dy = u - b[1], (v - b[2]) * 1.4
        if dx * dx + dy * dy < b[3] * b[3] then
          data:setPixel(x, y, P.shadow[1], P.shadow[2], P.shadow[3], 0.13)
          break
        end
      end
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter('nearest', 'nearest')
  return img
end

local function makeClouds(L)
  L.clouds = {}
  for i = 1, 3 do
    L.clouds[i] = {
      x = rnd(-M - 9, Map.W + M), y = rnd(-M - 2, Map.H + M - 4),
      speed = rnd(0.15, 0.3), imgs = {},
    }
  end
end

---------------------------------------------------------------- the update

-- ctx = { run, F, map, layout, live, rate (revenue per second), bossId,
--         boss, parts, machines }
function Life.update(L, dt, ctx)
  L.t = L.t + dt
  local F, map = ctx.F, ctx.map
  ctx.machines = F.world:query('machine')

  -- As many workers as the factory needs, give or take.
  local want = min(MAX_WORKERS, 2 + floor(#ctx.machines / 3))
  local workers = L.workers
  for i = #workers, 1, -1 do
    if workers[i].inspector and ctx.bossId ~= 'inspection' then table.remove(workers, i) end
  end
  local plain = 0
  for _, w in ipairs(workers) do if not w.inspector then plain = plain + 1 end end
  if plain < want and rnd() < dt * 2 then
    local w = newWorker(F, map)
    if w then workers[#workers + 1] = w end
  elseif plain > want then
    for i = #workers, 1, -1 do
      if not workers[i].inspector then table.remove(workers, i) break end
    end
  end
  if ctx.bossId == 'inspection' then
    local has = false
    for _, w in ipairs(workers) do if w.inspector then has = true end end
    if not has then
      local w = newWorker(F, map)
      if w then w.inspector = true; workers[#workers + 1] = w end
    end
  end
  for _, w in ipairs(workers) do updateWorker(w, dt, ctx) end

  updateTrucks(L, dt, ctx)

  if not L.animals then placeAnimals(L, ctx) end
  for i = #L.animals, 1, -1 do
    local a = L.animals[i]
    updateAnimal(a, dt, ctx)
    if a.gone then table.remove(L.animals, i) end
  end
  if #L.animals < 12 and rnd() < dt * 0.1 then
    -- Something wanders back in.
    local before = L.animals
    placeAnimals(L, ctx)
    local fresh = L.animals[love.math.random(max(1, #L.animals))]
    L.animals = before
    if fresh then L.animals[#L.animals + 1] = fresh end
  end

  L.birdsIn = L.birdsIn - dt
  if L.birdsIn <= 0 then
    spawnBirds(L)
    L.birdsIn = rnd(8, 20)
  end
  for i = #L.birds, 1, -1 do
    local b = L.birds[i]
    b.x, b.y, b.phase = b.x + b.vx * dt, b.y + b.vy * dt, b.phase + dt * 9
    if b.x < -M - 6 or b.x > Map.W + M + 6 then table.remove(L.birds, i) end
  end

  if not L.clouds then makeClouds(L) end
  for _, c in ipairs(L.clouds) do
    c.x = c.x + c.speed * dt
    if c.x > Map.W + M then c.x, c.y = -M - 9, rnd(-M - 2, Map.H + M - 4) end
  end

  -- Bosses.
  local parts, id = ctx.parts, ctx.bossId
  if parts and id then
    if (id == 'surge' or id == 'gridlock') and ctx.live then
      for _, e in ipairs(ctx.machines) do
        if e.machine.status == 'work' and rnd() < dt * 0.8 then
          for _ = 1, 3 do
            Particles.add(parts, { x = e.pos.x + rnd(0.2, 0.8), y = e.pos.y + rnd(0.1, 0.5),
              vx = rnd(-1.5, 1.5), vy = rnd(-2, -0.5), grav = 6, life = 0.3, size = 1, color = P.sprite.yellow })
          end
        end
      end
    elseif id == 'rockfall' then
      for _, e in ipairs(F.world:query('rubble')) do
        if rnd() < dt * 0.25 then
          Particles.add(parts, { x = e.pos.x + rnd(0.2, 0.8), y = e.pos.y + rnd(0.3, 0.8),
            vx = rnd(-0.2, 0.2), vy = rnd(-0.4, -0.2), life = 1.2, size = 2, grow = 3, alpha = 0.6, color = P.stoneL })
        end
      end
    elseif id == 'saturation' and map.depot and rnd() < dt * (ctx.live and 3 or 0.6) then
      local d = map.depot[1]
      Particles.add(parts, { x = d[1] + rnd(0.3, 1.7), y = d[2] + rnd(0.3, 1.7),
        vx = rnd(-0.8, 0.8), vy = rnd(-1.2, -0.6), drag = 1, grav = 0.3, life = 1.6, size = 2, color = WHITE })
    elseif id == 'long_haul' and ctx.live then
      local belts = F.world:query('belt')
      if #belts > 0 and rnd() < dt * 4 then
        local e = belts[love.math.random(#belts)]
        Particles.add(parts, { x = e.pos.x + rnd(0.2, 0.8), y = e.pos.y + 0.5,
          vx = rnd(-0.2, 0.2), vy = 0.2, life = 0.8, size = 1, color = P.money })
      end
    end
  end
end

---------------------------------------------------------------- drawing

-- On the ground, among the buildings: workers, animals, trucks, the booth.
function Life.drawGround(L, ox, oy, T, ctx)
  if L.animals then
    for _, a in ipairs(L.animals) do drawAnimal(a, ox, oy, T) end
  end
  table.sort(L.workers, function(a, b) return a.y < b.y end)
  for _, w in ipairs(L.workers) do drawWorker(w, ox, oy, T) end
  for _, t in ipairs(L.trucks) do drawTruck(t, ox, oy, T) end
  if ctx.bossId == 'tariff' then drawBooth(L, ox, oy, T, ctx) end
  if ctx.bossId == 'drought' then
    -- The dry ports' ground has cracked.
    for _, e in ipairs(ctx.F.world:query('port')) do
      if e.port.item == ctx.boss.params.item then
        local x, y = ox + e.pos.x * T, oy + e.pos.y * T
        local k = T / 16
        UI.color(P.sandD, 0.9)
        for _, seg in ipairs({ { -6, -3, 3, 2 }, { 3, 2, 10, -1 }, { 10, -1, 18, 4 }, { 3, 2, 6, 12 }, { 6, 12, 1, 19 }, { 6, 12, 14, 16 }, { -6, -3, -4, 9 } }) do
          love.graphics.line(x + seg[1] * k + 0.5, y + seg[2] * k + 0.5, x + seg[3] * k + 0.5, y + seg[4] * k + 0.5)
        end
      end
    end
  end
  if ctx.bossId == 'narrow_dock' then
    -- Barricades at the closed faces.
    for _, e in ipairs(ctx.F.world:query('export')) do
      for d = 0, 3 do
        if e.export.closed[d] then
          local x, y = ox + e.pos.x * T, oy + e.pos.y * T
          local h = (d + 2) % 4         -- the side items would come in from
          local bx, by, bw, bh
          if h == 0 then bx, by, bw, bh = x + T, y + 1, 2, T - 2
          elseif h == 2 then bx, by, bw, bh = x - 2, y + 1, 2, T - 2
          elseif h == 1 then bx, by, bw, bh = x + 1, y + T, T - 2, 2
          else bx, by, bw, bh = x + 1, y - 2, T - 2, 2 end
          UI.rect(bx, by, bw, bh, P.dark)
          for k = 0, max(bw, bh) - 1, 2 do
            if bw > bh then UI.rect(bx + k, by, 1, bh, P.red) else UI.rect(bx, by + k, bw, 1, P.red) end
          end
        end
      end
    end
  end
  if ctx.bossId == 'glut' and T == 16 then
    -- Unsold crates stacked by the road.
    local road = ctx.layout.road
    local y = oy + (ctx.layout.roadSouth and (road / 16 * T - 7) or ((road + 30) / 16 * T))
    for i = 0, 5 do
      local x = ox + (Map.W / 2 - 3) * T + i * 9
      for j = 0, (i % 3 == 1) and 1 or 0 do
        UI.rect(x, y - j * 6, 8, 6, P.dark)
        UI.rect(x + 1, y + 1 - j * 6, 6, 4, P.deskL)
        UI.rect(x + 1, y + 3 - j * 6, 6, 1, P.desk)
      end
    end
  end
end

-- Above everything: birds and their shadows, cloud shadows, and the dark
-- of a plot without power.
function Life.drawSky(L, ox, oy, T, ctx, vx, vy, vw, vh)
  local id = ctx.bossId
  if id == 'blackout' or id == 'foreclosure' then
    for _, p in ipairs(ctx.boss.params.plots or {}) do
      UI.rect(ox + p[1] * Map.PW * T, oy + p[2] * Map.PH * T, Map.PW * T, Map.PH * T, P.dark, 0.38)
    end
  end
  for _, b in ipairs(L.birds) do
    local x, y = floor(ox + b.x * T), floor(oy + b.y * T)
    UI.rect(x + floor(T * 0.6), y + floor(T * 1.2), 3, 1, P.dark, 0.18)
    local up = sin(b.phase) > 0
    if T == 16 then
      if up then
        UI.rect(x - 2, y - 1, 1, 1, P.dark); UI.rect(x + 2, y - 1, 1, 1, P.dark)
        UI.rect(x - 1, y, 1, 1, P.dark); UI.rect(x + 1, y, 1, 1, P.dark)
      else
        UI.rect(x - 2, y + 1, 2, 1, P.dark); UI.rect(x + 1, y + 1, 2, 1, P.dark)
      end
      UI.rect(x, y, 1, 2, P.dark)
    else
      UI.rect(x, y, 1, 1, P.dark)
      UI.rect(x + (up and -1 or 1), y - (up and 1 or 0), 1, 1, P.dark)
    end
  end
  if L.clouds then
    for _, c in ipairs(L.clouds) do
      c.imgs[T] = c.imgs[T] or cloudImage(T)
      UI.sprite(c.imgs[T], floor(ox + c.x * T), floor(oy + c.y * T))
    end
  end
  if id == 'brownout' or id == 'gridlock' then
    -- The lights keep dipping.
    local t = L.t
    local dip = max(0, sin(t * 1.7) * sin(t * 0.63 + 1) - 0.3)
    if dip > 0 then UI.rect(vx, vy, vw, vh, P.dark, dip * 0.35) end
  end
end

return Life
