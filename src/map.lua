-- The site: a 4x3 grid of plot slots, each 8x6 tiles, 32x18 tiles in all.
-- A run starts on one plot with the depot in its middle and annexes one more
-- plot per contract, into any free slot touching land it already owns.
--
-- A plot (coordinates local to the plot, 0-based):
--   ports   { { x, y, dir, item, period }, ... }
--   rocks   { { x, y }, ... }            unbuildable
--   pads    { { x, y }, ... }            booster pads: a machine there runs 50% faster
--   node    { x, y } or nil              power node: extra watts while you own the plot
--   premium true or nil                  one more depot face pays extra
--   depot   true or nil                  the starting plot: a 2x2 depot in the middle
--   special 'pad' | 'node' | 'rich' | 'premium' | nil   (for the description)

local D = require 'src.sim.dirs'

local Map = {}
Map.__index = Map
Map.COLS, Map.ROWS = 4, 3
Map.PW, Map.PH = 8, 6
Map.W, Map.H = Map.COLS * Map.PW, Map.ROWS * Map.PH

Map.NODE_WATTS = 12        -- per power node
Map.PAD_SPEED = 1.5        -- speed of a machine on a booster pad
Map.PREMIUM = 1.5          -- price multiplier at a premium depot face
Map.DEPOT = { { 3, 2 }, { 4, 2 }, { 3, 3 }, { 4, 3 } }   -- plot-local depot tiles

function Map.new()
  return setmetatable({ plots = {}, count = 0, premium = 0 }, Map)
end

local function slotIndex(sx, sy) return sy * Map.COLS + sx end

function Map:has(sx, sy)
  if sx < 0 or sy < 0 or sx >= Map.COLS or sy >= Map.ROWS then return false end
  return self.plots[slotIndex(sx, sy)] ~= nil
end

function Map:plotAt(sx, sy)
  return self.plots[slotIndex(sx, sy)]
end

-- The slot a tile belongs to.
function Map.slotOf(x, y)
  return math.floor(x / Map.PW), math.floor(y / Map.PH)
end

function Map:owned(x, y)
  if x < 0 or y < 0 or x >= Map.W or y >= Map.H then return false end
  return self:has(Map.slotOf(x, y))
end

-- Free slots that touch owned land, as { { sx, sy }, ... } in reading order.
function Map:free()
  local list = {}
  for sy = 0, Map.ROWS - 1 do
    for sx = 0, Map.COLS - 1 do
      if not self:has(sx, sy) and (self:has(sx - 1, sy) or self:has(sx + 1, sy)
          or self:has(sx, sy - 1) or self:has(sx, sy + 1)) then
        list[#list + 1] = { sx, sy }
      end
    end
  end
  return list
end

function Map:canAnnex(sx, sy)
  for _, s in ipairs(self:free()) do
    if s[1] == sx and s[2] == sy then return true end
  end
  return self.count == 0 and sx >= 0 and sy >= 0 and sx < Map.COLS and sy < Map.ROWS
end

function Map:nodes()
  local n = 0
  for _, plot in pairs(self.plots) do
    if plot.node then n = n + 1 end
  end
  return n
end

-- The depot's faces: every way an item can enter it, as { x, y, d } where
-- (x, y) is the depot tile and d the direction the item travels. Fixed order.
function Map:depotFaces()
  local faces = {}
  if not self.depot then return faces end
  local on = {}
  for _, t in ipairs(self.depot) do on[t[2] * Map.W + t[1]] = true end
  for _, t in ipairs(self.depot) do
    for d = 0, 3 do
      local fx, fy = t[1] - D.DX[d], t[2] - D.DY[d]
      if not on[fy * Map.W + fx] then faces[#faces + 1] = { t[1], t[2], d } end
    end
  end
  return faces
end

-- Put a plot into slot (sx, sy) and stamp its fixed pieces onto factory F.
function Map:annex(plot, sx, sy, F)
  assert(self:canAnnex(sx, sy), 'slot not free')
  plot.sx, plot.sy = sx, sy
  self.plots[slotIndex(sx, sy)] = plot
  self.count = self.count + 1
  self:stamp(plot, F)
  return plot
end

-- Place a plot's fixed pieces (also used when a saved run is loaded).
function Map:stamp(plot, F)
  local ox, oy = plot.sx * Map.PW, plot.sy * Map.PH
  if plot.depot then
    self.depot = {}
    for i, t in ipairs(Map.DEPOT) do
      self.depot[i] = { ox + t[1], oy + t[2] }
      F:place('export', ox + t[1], oy + t[2], 0)
    end
  end
  for _, p in ipairs(plot.ports) do
    F:place('port', ox + p.x, oy + p.y, p.dir, { item = p.item, period = p.period })
  end
  for _, r in ipairs(plot.rocks) do F:place('rock', ox + r.x, oy + r.y, 0) end
  for _, p in ipairs(plot.pads or {}) do F:setFloor(ox + p.x, oy + p.y, 'pad') end
  if plot.node then F:place('node', ox + plot.node.x, oy + plot.node.y, 0) end
  if plot.premium then
    -- The next depot face in line turns premium.
    local faces = self:depotFaces()
    self.premium = self.premium + 1
    local f = faces[(self.premium * 3 - 2) % #faces + 1]   -- spread around the depot
    local e = F:at(f[1], f[2])
    e.export.premium[f[3]] = Map.PREMIUM
    plot.face = f
  end
end

---------------------------------------------------------------- generation

local SPECIAL_TEXT = {
  pad = 'BOOSTER PADS',
  node = 'POWER NODE +' .. Map.NODE_WATTS .. 'W',
  rich = 'RICH PORT',
  premium = 'PREMIUM DEPOT FACE',
}
Map.SPECIAL_TEXT = SPECIAL_TEXT

local function taken(used, x, y) return used[y * Map.PW + x] end
local function take(used, x, y) used[y * Map.PW + x] = true end

-- A tile on the plot's border (not a corner), with the direction that
-- points into the plot.
local function borderTile(rng)
  local side = rng:int(0, 3)
  if side == 0 then return 0, rng:int(1, Map.PH - 2), 0             -- west edge, facing east
  elseif side == 1 then return rng:int(1, Map.PW - 2), 0, 1         -- north edge, facing south
  elseif side == 2 then return Map.PW - 1, rng:int(1, Map.PH - 2), 2
  else return rng:int(1, Map.PW - 2), Map.PH - 1, 3 end
end

local function interiorTile(rng)
  return rng:int(1, Map.PW - 2), rng:int(1, Map.PH - 2)
end

-- spec = { items = { item, ... } one per port, rocks = n, special = name or nil,
--          depot = bool, period = seconds per item (default 2) }
function Map.generate(rng, spec)
  local plot = { ports = {}, rocks = {}, special = spec.special, depot = spec.depot or nil }
  local used = {}
  if spec.depot then
    -- Keep the depot and a ring around it clear.
    for _, t in ipairs(Map.DEPOT) do
      for dy = -1, 1 do
        for dx = -1, 1 do take(used, t[1] + dx, t[2] + dy) end
      end
    end
  end

  for i, item in ipairs(spec.items) do
    for _ = 1, 200 do
      local x, y, dir = borderTile(rng)
      local fx, fy = x + D.DX[dir], y + D.DY[dir]
      local clear = not taken(used, x, y) and not taken(used, fx, fy)
      -- Ports keep their distance, so each has room to be belted away.
      for _, p in ipairs(plot.ports) do
        if math.abs(p.x - x) + math.abs(p.y - y) < 3 then clear = false end
      end
      if clear then
        plot.ports[#plot.ports + 1] = { x = x, y = y, dir = dir, item = item, period = spec.period or 2 }
        take(used, x, y)
        take(used, fx, fy)          -- the tile in front stays free
        break
      end
    end
    assert(#plot.ports == i, 'no room for a port')
  end

  for _ = 1, spec.rocks or 0 do
    for _ = 1, 50 do
      local x, y = interiorTile(rng)
      if not taken(used, x, y) then
        plot.rocks[#plot.rocks + 1] = { x = x, y = y }
        take(used, x, y)
        break
      end
    end
  end

  if spec.special == 'pad' then
    plot.pads = {}
    for _ = 1, 3 do
      for _ = 1, 50 do
        local x, y = interiorTile(rng)
        if not taken(used, x, y) then
          plot.pads[#plot.pads + 1] = { x = x, y = y }
          take(used, x, y)
          break
        end
      end
    end
  elseif spec.special == 'node' then
    for _ = 1, 50 do
      local x, y = interiorTile(rng)
      if not taken(used, x, y) then
        plot.node = { x = x, y = y }
        take(used, x, y)
        break
      end
    end
  elseif spec.special == 'rich' then
    local p = plot.ports[rng:int(1, #plot.ports)]
    p.period = 1
    p.rich = true
  elseif spec.special == 'premium' then
    plot.premium = true
  end
  return plot
end

return Map
