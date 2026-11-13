-- Static connectivity: which building pushes items where. Layout only, no
-- item state, so the board can draw corners and merges in build mode too.

local D = require 'src.sim.dirs'
local DX, DY = D.DX, D.DY

local Links = {}

-- Does the building on (x, y) push items out in direction d?
function Links.feeds(F, x, y, d, depth)
  local e = F:at(x, y)
  if not e then return false end
  local b = e.building
  if e.belt or e.port then
    return b.dir == d
  elseif e.machine then
    return e.slot ~= nil and b.dir == d
  elseif e.splitter or e.filter then
    return d ~= (b.dir + 2) % 4
  elseif e.bridge then
    -- A bridge passes on whatever enters it from the far side.
    depth = depth or 0
    if depth > 16 then return false end
    return Links.feeds(F, x - DX[d], y - DY[d], d, depth + 1)
  end
  return false
end

-- How a belt is fed, relative to its own direction.
--   back / left / right : something pushes items in from that side
--   corner              : 'left' or 'right' when that is the only feed
function Links.beltShape(F, e)
  local x, y, b = e.pos.x, e.pos.y, e.building.dir
  local l, r = (b + 3) % 4, (b + 1) % 4
  local shape = {
    back = Links.feeds(F, x - DX[b], y - DY[b], b),
    left = Links.feeds(F, x + DX[l], y + DY[l], r),
    right = Links.feeds(F, x + DX[r], y + DY[r], l),
  }
  if not shape.back and shape.left ~= shape.right then
    shape.corner = shape.left and 'left' or 'right'
  end
  return shape
end

return Links
