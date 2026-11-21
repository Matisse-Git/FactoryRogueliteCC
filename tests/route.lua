-- Lay a belt from a port to the depot along the shortest free path, for
-- tests, benchmarks and the screenshot script.
--
--   local path = Route.belt(run, portEntity)
--
-- Returns the tiles of the path as { { x, y, dir }, ... } from the tile in
-- front of the port to the tile that pushes into the depot, or nil if there
-- is no way through. Only free tiles of owned land are used, so two routes
-- never share a belt.

local D = require 'src.sim.dirs'

local Route = {}

function Route.find(run, port)
  local F, map = run.factory, run.map
  local W = F.W
  local sx, sy = port.pos.x + D.DX[port.building.dir], port.pos.y + D.DY[port.building.dir]
  local function free(x, y)
    return map:owned(x, y) and F:at(x, y) == nil
  end
  if not free(sx, sy) then return nil end
  local from, queue, head = { [sy * W + sx] = false }, { { sx, sy } }, 1
  while queue[head] do
    local x, y = queue[head][1], queue[head][2]
    head = head + 1
    for d = 0, 3 do
      local nx, ny = x + D.DX[d], y + D.DY[d]
      local e = F:at(nx, ny)
      if e and e.export then
        -- Walk back to the start.
        local path, cx, cy, dir = {}, x, y, d
        while true do
          table.insert(path, 1, { cx, cy, dir })
          local prev = from[cy * W + cx]
          if not prev then break end
          dir = prev[3]
          cx, cy = prev[1], prev[2]
        end
        return path
      elseif free(nx, ny) and from[ny * W + nx] == nil then
        from[ny * W + nx] = { x, y, d }
        queue[#queue + 1] = { nx, ny }
      end
    end
  end
  return nil
end

-- Lay the belt. `machines` is an optional list of kinds to put on the path
-- in order, starting `skip` tiles in (default 1), in place of belts.
function Route.belt(run, port, machines, skip)
  local path = Route.find(run, port)
  if not path then return nil end
  local F = run.factory
  for _, t in ipairs(path) do F:place('belt', t[1], t[2], t[3]) end
  for i, kind in ipairs(machines or {}) do
    local t = path[(skip or 1) + i]
    if t then
      F:remove(t[1], t[2])
      F:place(kind, t[1], t[2], t[3])
    end
  end
  return path
end

-- Every port of the run, in a fixed order.
function Route.ports(run)
  return run.factory.world:query('port')
end

return Route
