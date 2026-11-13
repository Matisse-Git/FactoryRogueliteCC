-- Transfer system: moves every item one step per tick, all at once.
--
-- A "slot" holds at most one item: a belt tile, one lane of a bridge, a
-- splitter, a filter, a port's mouth or a machine's output. Machines and
-- exports are "buffers": they accept by capacity and never chain within a tick.
--
-- Splitters and filters are "routers": one way in (the back), several ways
-- out. A splitter takes its three outputs in turn. A filter sends its chosen
-- item straight on and everything else out of its two sides, in turn.
--
-- Resolution is a memoised depth-first search:
--   leaves(S)  - does the item in slot S move this tick?
--   winner(T)  - which feeder gets to enter slot T this tick?
-- A slot can receive if it is empty or its own item leaves, so a full belt
-- advances as one train. Feeders of a slot take turns (round robin), which
-- makes side-merges fair. Loops of full belts are treated as blocked.

local D = require 'src.sim.dirs'
local Machine = require 'src.sim.machine'
local DX, DY = D.DX, D.DY

local Transfer = {}

function Transfer.newSlot(e, kind)
  return { e = e, kind = kind, item = nil, rr = 0, dir = 0 }
end

-- What does an item leaving (x, y) in direction d run into?
-- Returns slot, nil | nil, bufferEntity | nil, nil.
local function target(F, x, y, d)
  local t = F:at(x + DX[d], y + DY[d])
  if not t then return nil, nil end
  local b = t.building
  if t.belt then
    if d == (b.dir + 2) % 4 then return nil, nil end   -- head-on into its front
    return t.slot, nil
  elseif t.splitter or t.filter then
    if d ~= b.dir then return nil, nil end             -- back entrance only
    return t.slot, nil
  elseif t.bridge then
    return t.bridge.lanes[d % 2 + 1], nil
  elseif t.machine then
    if t.slot and d == (b.dir + 2) % 4 then return nil, nil end  -- output face
    return nil, t
  elseif t.export then
    return nil, t
  end
  return nil, nil
end
Transfer.target = target

-- The slot of entity `se` that could push an item in direction d, if any.
local function sourceSlot(se, d)
  local b = se.building
  if se.belt or se.port then
    if b.dir == d then return se.slot end
  elseif se.machine then
    if se.slot and b.dir == d then return se.slot end
  elseif se.bridge then
    local lane = se.bridge.lanes[d % 2 + 1]
    if lane.item and lane.dir == d then return lane end
  elseif se.splitter then
    if d ~= (b.dir + 2) % 4 then return se.slot end
  elseif se.filter then
    local it = se.slot.item
    if not it then return nil end
    local straight = it.item.type == se.filter.item
    if straight == (d == b.dir) and d ~= (b.dir + 2) % 4 then return se.slot end
  end
  return nil
end

-- Directions slot S may leave through, in priority order.
local function candidates(S)
  local e = S.e
  if S.kind == 'lane' then return { S.dir } end
  local dir = e.building.dir
  if S.kind == 'split' then
    local all = { dir, (dir + 3) % 4, (dir + 1) % 4 }
    local p = e.splitter.ptr
    return { all[p], all[p % 3 + 1], all[(p + 1) % 3 + 1] }
  elseif S.kind == 'filter' then
    if S.item and S.item.item.type == e.filter.item then return { dir } end
    local left, right = (dir + 3) % 4, (dir + 1) % 4
    if e.filter.ptr == 1 then return { left, right } end
    return { right, left }
  end
  return { dir }
end

local function isRouter(S)
  return S.kind == 'split' or S.kind == 'filter'
end

local function reserve(F, t, itemE)
  if t.export then
    local ex = t.export
    if F.rules.exportPeriod > 1 and (ex.cd > 0 or ex.taken > 0) then return false end
    ex.taken = ex.taken + 1
    return true
  end
  return Machine.reserve(F, t, itemE)
end

local leaves, winner

-- Would feeder S move into slot T (reached by travelling d)? Called by
-- winner(T) in priority order, so a `true` here means S is chosen.
local function wants(F, S, T, d)
  if not S.item then return false end
  if S.res ~= nil then return S.res and S.moveSlot == T end
  if not isRouter(S) then return true end
  -- Mid-resolution: its earlier outputs already failed, so it wants exactly
  -- the output it is asking about right now.
  if S.vis then return S.trying == d end
  -- A router prefers its earlier outputs; T only gets the item if those fail.
  local e = S.e
  local cands = candidates(S)
  for i = 1, #cands do
    local c = cands[i]
    local ts, tb = target(F, e.pos.x, e.pos.y, c)
    if ts == T and c == d then
      S.res, S.moveSlot, S.moveDir = true, T, c
      return true
    elseif tb then
      if reserve(F, tb, S.item) then
        S.res, S.moveBuf, S.moveDir = true, tb, c
        return false
      end
    elseif ts and winner(F, ts) == S then
      S.res, S.moveSlot, S.moveDir = true, ts, c
      return false
    end
  end
  return false
end

function winner(F, T)
  if T.wres ~= nil then return T.wres or nil end
  if T.wvis then return nil end
  T.wvis = true
  local w = false
  local free = T.item == nil or (not T.dup and leaves(F, T))
  if free then
    local x, y = T.e.pos.x, T.e.pos.y
    for i = 1, 4 do
      local d = (T.rr + i) % 4
      local se = F:at(x - DX[d], y - DY[d])
      if se then
        local S = sourceSlot(se, d)
        if S and S ~= T and S.item and target(F, se.pos.x, se.pos.y, d) == T
            and wants(F, S, T, d) then
          w = S
          break
        end
      end
    end
  end
  T.wvis = false
  T.wres = w
  return w or nil
end

function leaves(F, S)
  if S.res ~= nil then return S.res end
  if not S.item or S.vis then return false end
  S.vis = true
  local e = S.e
  local res = false
  local cands = candidates(S)
  for i = 1, #cands do
    local d = cands[i]
    S.trying = d
    local ts, tb = target(F, e.pos.x, e.pos.y, d)
    if tb then
      if reserve(F, tb, S.item) then
        res, S.moveBuf, S.moveDir = true, tb, d
        break
      end
    elseif ts and winner(F, ts) == S then
      res, S.moveSlot, S.moveDir = true, ts, d
      break
    end
    if S.res ~= nil then break end
  end
  S.vis = false
  if S.res == nil then S.res = res end
  return S.res
end

-- The system. F.slots is rebuilt by the factory at the start of each shift.
function Transfer.system(world, F)
  local slots = F.slots

  -- Reset per-tick state.
  for i = 1, #slots do
    local S = slots[i]
    S.res, S.wres, S.vis, S.wvis = nil, nil, false, false
    S.moveSlot, S.moveBuf, S.moveDir = nil, nil, nil
    if S.kind == 'out' then S.item = S.e.machine.outq[1] end
  end
  local machines = world:query('machine')
  for i = 1, #machines do
    local m = machines[i].machine
    for k in pairs(m.pending) do m.pending[k] = nil end
    m.pendingN = 0
  end
  local exports = world:query('export')
  for i = 1, #exports do exports[i].export.taken = 0 end

  -- Resolve, then collect the moves.
  for i = 1, #slots do
    if slots[i].item then leaves(F, slots[i]) end
  end
  local moves = {}
  for i = 1, #slots do
    local S = slots[i]
    if S.res and S.item and (S.moveSlot or S.moveBuf) then
      moves[#moves + 1] = { S = S, item = S.item, slot = S.moveSlot, buf = S.moveBuf, d = S.moveDir }
    end
  end

  -- Lift every moving item off its slot ...
  for i = 1, #moves do
    local S = moves[i].S
    S.passed = (S.passed or 0) + 1
    if S.kind == 'out' then
      local q = S.e.machine.outq
      table.remove(q, 1)
      S.item = q[1]
    elseif S.kind == 'split' and S.dup then
      -- Leaky Splitter: a copy stays behind.
      local src = moves[i].item
      S.dup = false
      S.item = world:spawn({
        item = { type = src.item.type, polished = src.item.polished, dist = src.item.dist },
        pos = { x = S.e.pos.x, y = S.e.pos.y },
        prev = { x = S.e.pos.x, y = S.e.pos.y },
      })
      F:trigger(F.rules.owner.leakEvery, S.e.pos.x, S.e.pos.y, 0, 'dup')
    else
      S.item = nil
    end
    if S.kind == 'split' then
      -- Next item starts with the output after the one just used.
      local dir = S.e.building.dir
      local d = moves[i].d
      local idx = (d == dir) and 1 or (d == (dir + 3) % 4) and 2 or 3
      S.e.splitter.ptr = idx % 3 + 1
    elseif S.kind == 'filter' then
      -- The two sides take turns.
      local dir = S.e.building.dir
      local d = moves[i].d
      if d == (dir + 3) % 4 then S.e.filter.ptr = 2
      elseif d == (dir + 1) % 4 then S.e.filter.ptr = 1 end
    elseif S.kind == 'port' then
      S.e.port.sent = S.e.port.sent + 1
    end
  end

  -- ... then set them all down.
  for i = 1, #moves do
    local mv = moves[i]
    local it, d = mv.item, mv.d
    it.prev.x, it.prev.y = it.pos.x, it.pos.y
    it.pos.x, it.pos.y = it.pos.x + DX[d], it.pos.y + DY[d]
    it.hidden = nil
    if mv.slot then
      local T = mv.slot
      T.item = it
      T.rr = d
      if T.kind == 'lane' then T.dir = d end
      it.item.dist = it.item.dist + 1
      if T.kind == 'split' then
        local sp = T.e.splitter
        sp.count = sp.count + 1
        if F.rules.leakEvery and sp.count % F.rules.leakEvery == 0 then T.dup = true end
      end
    else
      if mv.buf.export then
        F:sell(it, mv.buf, d)
      else
        Machine.deliver(mv.buf, it)
      end
      it.gone = true   -- drawn sliding in for one tick, then despawned
    end
  end

  -- Narrow Dock: the export needs a pause between items.
  local period = F.rules.exportPeriod
  if period > 1 then
    for i = 1, #exports do
      local ex = exports[i].export
      if ex.taken > 0 then ex.cd = period - 1
      elseif ex.cd > 0 then ex.cd = ex.cd - 1 end
    end
  end
end

return Transfer
