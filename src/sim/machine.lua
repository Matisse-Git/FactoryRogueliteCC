-- Machine behaviour: input buffers, crafting, output queue.
-- Used by the machine system and by the transfer system (reserve / deliver).

local M = {}

function M.reset(e)
  local m = e.machine
  m.inbuf = {}        -- item type -> count waiting
  m.pending = {}      -- item type -> count accepted this tick, not yet delivered
  m.pq = {}           -- polisher queue of { type, polished }
  m.pendingN = 0
  m.outq = {}         -- finished item entities waiting to leave
  m.craft = nil       -- { p = progress, r = recipe } or { p, polish = {...} }
  m.burn = 0          -- generator: seconds of fuel left
  m.made = 0
  m.idle = 0          -- ticks spent not crafting after the first craft
  m.started = false
  m.status = 'idle'   -- 'work' | 'idle' | 'blocked'
  m.speed = 1
  m.draw = m.def.draw or 0
end

-- Can the machine take this item right now? Reserves the space if so.
function M.reserve(F, e, itemE)
  local m, def, it = e.machine, e.machine.def, itemE.item
  if def.generator then
    local fuel = def.generator.fuel
    if it.type ~= fuel then return false end
    if (m.inbuf[fuel] or 0) + (m.pending[fuel] or 0) >= 2 then return false end
    m.pending[fuel] = (m.pending[fuel] or 0) + 1
    return true
  end
  if def.polish then
    if it.polished >= F.rules.maxPolish then return false end
    if #m.pq + m.pendingN >= 2 then return false end
    m.pendingN = m.pendingN + 1
    return true
  end

  -- The item must fit a recipe that also covers everything already buffered,
  -- so an assembler never clogs on a mix that cannot become anything.
  local need
  local recipes = F.recipes[def.kind]
  if not recipes then return false end
  for i = 1, #recipes do
    local r = recipes[i]
    local amt = r.need[it.type]
    if amt then
      local ok = true
      for t, n in pairs(m.inbuf) do
        if n > 0 and not r.need[t] then ok = false; break end
      end
      if ok then
        for t, n in pairs(m.pending) do
          if n > 0 and not r.need[t] then ok = false; break end
        end
      end
      if ok and (not need or amt > need) then need = amt end
    end
  end
  if not need then return false end
  local have = (m.inbuf[it.type] or 0) + (m.pending[it.type] or 0)
  if have >= need * 2 then return false end
  m.pending[it.type] = (m.pending[it.type] or 0) + 1
  return true
end

function M.deliver(e, itemE)
  local m, it = e.machine, itemE.item
  if m.def.polish then
    m.pq[#m.pq + 1] = { type = it.type, polished = it.polished }
  else
    m.inbuf[it.type] = (m.inbuf[it.type] or 0) + 1
  end
end

local function emit(F, e, type, polished)
  local m = e.machine
  local item = F.world:spawn({
    item = { type = type, polished = polished or 0, dist = 0 },
    pos = { x = e.pos.x, y = e.pos.y },
    prev = { x = e.pos.x, y = e.pos.y },
    hidden = true,
  })
  m.outq[#m.outq + 1] = item
  m.made = m.made + 1
end

-- Try to begin a craft. Returns true if started; sets m.status otherwise.
local function start(F, e, carry)
  local m, def = e.machine, e.machine.def
  if def.polish then
    if #m.pq == 0 then m.status = 'idle'; return false end
    if #m.outq >= 2 then m.status = 'blocked'; return false end
    m.craft = { p = carry, polish = table.remove(m.pq, 1) }
    m.started = true
    return true
  end
  local recipes = F.recipes[def.kind]
  local blocked = false
  for i = 1, #recipes do
    local r = recipes[i]
    local ok = true
    for j = 1, #r.inputs do
      if (m.inbuf[r.inputs[j][1]] or 0) < r.inputs[j][2] then ok = false; break end
    end
    if ok then
      -- Room for one finished batch besides the one about to be made, so a
      -- machine that emits 2 items per craft is not throttled by its exit.
      if #m.outq + r.outN <= math.max(2, r.outN * 2) then
        for j = 1, #r.inputs do
          local t = r.inputs[j][1]
          m.inbuf[t] = m.inbuf[t] - r.inputs[j][2]
        end
        m.craft = { p = carry, r = r }
        m.started = true
        return true
      end
      blocked = true
    end
  end
  m.status = blocked and 'blocked' or 'idle'
  return false
end

function M.update(F, e)
  local m, def = e.machine, e.machine.def

  if def.generator then
    local g = def.generator
    if m.burn > 0 then m.burn = m.burn - 1 end
    if m.burn <= 0 and (m.inbuf[g.fuel] or 0) > 0 then
      m.inbuf[g.fuel] = m.inbuf[g.fuel] - 1
      m.burn = g.burn
      m.made = m.made + 1
    end
    m.status = m.burn > 0 and 'work' or 'idle'
    return
  end

  local carry = 0
  if m.craft then
    m.craft.p = m.craft.p + F.shift.factor * m.speed
    if m.craft.p >= def.time then
      carry = m.craft.p - def.time
      if m.craft.polish then
        local polished = m.craft.polish.polished + 1
        emit(F, e, m.craft.polish.type, polished)
        -- A polish beyond the first is the doing of whoever raised the limit.
        if polished > 1 then F:trigger(F.rules.owner.maxPolish, e.pos.x, e.pos.y, 0, 'polish') end
      else
        local outs = m.craft.r.outputs
        for i = 1, #outs do
          for _ = 1, outs[i][2] do emit(F, e, outs[i][1]) end
        end
        -- A recipe added by a mod credits that mod.
        F:trigger(F.rules.recipeOwner[m.craft.r], e.pos.x, e.pos.y, 0, 'craft')
      end
      m.craft = nil
    end
  end
  if not m.craft then start(F, e, carry) end
  if m.craft then
    m.status = 'work'
  elseif m.started then
    m.idle = m.idle + 1
  end
end

return M
