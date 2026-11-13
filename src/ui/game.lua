-- The main screen: the site in a viewport that scrolls and zooms, the build
-- palette in a strip under it, the sidebar on the right.
-- Modes: annex -> intro -> build -> run -> summary -> (build | shop | over | win)
--
-- Two zoom levels, both fully playable: close (16 px tiles, scrolls) and
-- overview (8 px tiles, the whole site on screen).

local P = require 'src.gfx.palette'
local Font = require 'src.gfx.font'
local Sprites = require 'src.gfx.sprites'
local UI = require 'src.ui.ui'
local Fx = require 'src.ui.fx'
local Book = require 'src.ui.book'
local Fmt = require 'src.fmt'
local Land = require 'src.ui.land'
local Board = require 'src.ui.board'
local Market = require 'src.market'
local Factory = require 'src.sim.factory'
local Map = require 'src.map'
local D = require 'src.sim.dirs'
local Links = require 'src.sim.links'
local Machines = require 'src.data.machines'
local Items = require 'src.data.items'
local Upgrades = require 'src.data.upgrades'
local Contracts = require 'src.data.contracts'

local Game = {}

local VX, VY, VW, VH = 0, 16, 256, 144   -- board viewport
local SX, SW = 256, 64                   -- sidebar
local PY = 160                           -- palette strip
local CELL = 16                          -- width of a palette entry
local CX = VX + VW / 2                   -- centre of the viewport (overlays)
local TPS = 4                -- simulation ticks per real second at 1x
local PAN = 160              -- camera speed with the keys, pixels per second
local BEAT = 0.4             -- summary: seconds between end-of-shift lines
local COUNT = 0.3            -- summary: seconds the total takes to count up
local STAMP = 0.12           -- summary: seconds a new line stays highlighted
local POPUP_LIFE = 0.5       -- sale popups: seconds on screen
local POPUP_RISE = 32        -- sale popups: pixels per second
local POPUP_MERGE = 0.2      -- sale popups: a sale this soon after the last
                             -- joins its popup, so popups never pile up
local floor, min, max = math.floor, math.min, math.max

local function num(n)
  if n == floor(n) then return tostring(n) end
  return string.format('%.1f', n)
end

-- Items per minute, as the game states every rate.
local function perMin(seconds)
  return num(floor(600 / seconds + 0.5) / 10) .. '/MIN'
end

local function pct(u)
  return floor(u * 100 + 0.5) .. '%'
end

---------------------------------------------------------------- camera

local function clampCam(cam)
  cam.x = max(0, min(Map.W * cam.T - VW, floor(cam.x + 0.5)))
  cam.y = max(0, min(Map.H * cam.T - VH, floor(cam.y + 0.5)))
end

-- Switch to tile size T with tile position (fx, fy) in the middle.
local function setZoom(g, T, fx, fy)
  local cam = g.cam
  cam.T = T
  cam.x, cam.y = fx * T - VW / 2, fy * T - VH / 2
  clampCam(cam)
end

-- Top-left pixel of a tile on the canvas.
local function tilePos(g, cx, cy)
  local cam = g.cam
  return VX + cx * cam.T - cam.x, VY + cy * cam.T - cam.y
end

-- The tile under a canvas position, or nil outside the viewport.
local function cellAt(g, x, y)
  if x < VX or y < VY or x >= VX + VW or y >= VY + VH then return nil end
  local cam = g.cam
  local cx, cy = floor((x - VX + cam.x) / cam.T), floor((y - VY + cam.y) / cam.T)
  if cx < 0 or cy < 0 or cx >= Map.W or cy >= Map.H then return nil end
  return cx, cy
end

-- Middle of the depot, in tiles.
local function depotCentre(run)
  local d = run.map.depot
  return (d[1][1] + d[4][1] + 1) / 2, (d[1][2] + d[4][2] + 1) / 2
end

function Game.enter(app)
  local old, run = app.g, app.run
  local g = {
    mode = 'intro', tool = nil, dir = 0, speed = old and old.speed or 1,
    acc = 0, frac = 0, paused = false,
    popups = {}, summary = nil, drag = nil, book = false,
    stats = old and old.stats or false,   -- U: utilisation on every machine
    fx = Fx.new(),      -- card pops and tile flashes
    reveal = nil,       -- summary playback, see finishShift
    lit = {},           -- mods changing a machine on the board this frame
    hoverMod = nil,     -- the upgrade whose card is under the mouse
    sel = nil,          -- selected rectangle of tiles { x1, y1, x2, y2 }
    clip = nil,         -- what the stamp tool pastes: { w, h, items = { ... } }
    picker = nil,       -- { e = filter entity }: the item chooser is open
    filterItem = nil,   -- the item a filter in hand was set to
    bookPage = old and old.bookPage or 1,
    cam = old and old.run == run and old.cam or nil,
    run = run,
  }
  app.g = g
  if not g.cam then
    g.cam = { T = 16, x = 0, y = 0 }
    setZoom(g, 16, depotCentre(run))
  end
  if run.pendingPlot then
    -- New land is placed on the overview.
    g.mode = 'annex'
    g.back = { T = g.cam.T, x = g.cam.x, y = g.cam.y }
    setZoom(g, 8, 0, 0)
  end
end

---------------------------------------------------------------- tooltips

local function kindTip(kind)
  local def = Machines[kind]
  local lines = { def.desc }
  if def.time then
    lines[#lines + 1] = perMin(def.time) .. ', ' .. def.draw .. 'W'
  end
  return { title = def.name, color = P.text, lines = lines }
end

local function upgradeTip(def)
  return { title = def.name, color = P[def.color], lines = { def.desc } }
end

local STATUS = { work = 'WORKING', idle = 'WAITING FOR INPUT', blocked = 'OUTPUT BLOCKED' }

local function entityTip(app, e)
  local g, F = app.g, app.run.factory
  local live = g.mode == 'run' or g.mode == 'summary'
  local tip = kindTip(e.building.kind)
  if e.port then
    tip.title = Items[e.port.item].name .. ' PORT'
    tip.lines = { perMin(e.port.period) .. ': ' ..
      floor(app.run.rules.shiftLen / e.port.period) .. ' PER SHIFT' }
    if live then tip.lines[2] = 'SENT ' .. e.port.sent end
  elseif e.export then
    if live then tip.lines[#tip.lines + 1] = 'SOLD ' .. e.export.sold end
    for d = 0, 3 do
      if e.export.premium[d] then
        tip.lines[#tip.lines + 1] = 'PREMIUM FACE: ITEMS HEADING ' .. D.NAME[d] ..
          ' INTO IT SELL FOR X' .. num(e.export.premium[d])
      end
    end
  elseif e.machine and live then
    local m = e.machine
    tip.lines = { (m.def.generator and 'BURNED ' or 'MADE ') .. m.made, STATUS[m.status] }
    if m.speed ~= 1 then tip.lines[3] = 'SPEED X' .. num(m.speed) end
    local u = F:utilisation(e)
    if u then tip.lines[#tip.lines + 1] = 'BUSY ' .. pct(u) .. ' OF THE SHIFT' end
  elseif e.machine then
    local sp = app.run.rules:speed(F, e) * F:padSpeed(e)
    if e.machine.def.time and sp ~= 1 then
      tip.lines[#tip.lines] = perMin(e.machine.def.time / sp) .. ', ' .. e.machine.def.draw .. 'W'
      tip.lines[#tip.lines + 1] = 'SPEED X' .. num(sp)
    end
    local u = F:utilisation(e)
    if u then tip.lines[#tip.lines + 1] = 'LAST SHIFT: BUSY ' .. pct(u) end
  elseif e.filter then
    if e.filter.item then
      tip.lines = { Items[e.filter.item].name .. ' GOES STRAIGHT ON. EVERYTHING ELSE LEAVES THROUGH THE SIDES.' }
    else
      tip.lines = { 'NO ITEM SET: EVERYTHING LEAVES THROUGH THE SIDES.' }
    end
    if not live then tip.lines[2] = 'F: CHOOSE THE ITEM' end
  elseif e.belt and e.slot.passed and F.shift and F.shift.tick > 0 then
    tip.lines[#tip.lines + 1] = (live and 'CARRIED ' or 'LAST SHIFT: ') .. e.slot.passed ..
      ' (' .. pct(e.slot.passed / F.shift.tick) .. ' FULL)'
  end
  return tip
end

-- Words for a plot: what it brings.
local function plotLines(plot)
  local lines = {}
  for _, p in ipairs(plot.ports) do
    lines[#lines + 1] = Items[p.item].name .. ' ' .. perMin(p.period)
  end
  if plot.special then lines[#lines + 1] = Map.SPECIAL_TEXT[plot.special] end
  return lines
end

---------------------------------------------------------------- editing

-- Can `kind` go on this tile? Only on your own land, never over a fixed
-- piece; a machine may replace a belt.
local function canPlace(app, kind, x, y)
  local run = app.run
  if not run:canBuild(x, y) or not run:unlocked(kind) then return false end
  local e = run.factory:at(x, y)
  if not e then return true end
  if e.building.fixed then return false end
  return e.building.kind == kind or (e.belt and kind ~= 'belt')
end

-- extra: what Factory:place takes (a filter's item). Returns the piece.
local function placeAt(app, kind, x, y, dir, extra)
  if not canPlace(app, kind, x, y) then return false end
  local F = app.run.factory
  local e = F:at(x, y)
  if e and e.building.kind == kind then
    e.building.dir = dir
    return e
  end
  if e then F:remove(x, y) end
  return F:place(kind, x, y, dir, extra)
end

local function rotate(app, step)
  local g = app.g
  if g.mode ~= 'build' then return end
  if g.tool == 'stamp' then
    -- Turn the whole stamp a quarter clockwise.
    local clip = g.clip
    for _ = 1, step % 4 do
      for _, it in ipairs(clip.items) do
        it.dx, it.dy = clip.h - 1 - it.dy, it.dx
        it.dir = (it.dir + 1) % 4
      end
      clip.w, clip.h = clip.h, clip.w
    end
    return
  end
  if g.tool and g.tool ~= 'select' then
    g.dir = (g.dir + step) % 4
    return
  end
  local cx, cy = cellAt(g, UI.mx, UI.my)
  local e = cx and app.run.factory:at(cx, cy)
  if e and not e.building.fixed then
    e.building.dir = (e.building.dir + step) % 4
  end
end

-- Selection: copy the pieces in the rectangle onto the stamp (and remove
-- them, for a cut). Fixed pieces stay where they are.
local function copySelection(app, cut)
  local g, F = app.g, app.run.factory
  local sel = g.sel
  if not sel then return false end
  local clip = { w = sel.x2 - sel.x1 + 1, h = sel.y2 - sel.y1 + 1, items = {} }
  for y = sel.y1, sel.y2 do
    for x = sel.x1, sel.x2 do
      local e = F:at(x, y)
      if e and not e.building.fixed then
        clip.items[#clip.items + 1] = {
          dx = x - sel.x1, dy = y - sel.y1, kind = e.building.kind, dir = e.building.dir,
          item = e.filter and e.filter.item or nil,
        }
        if cut then F:remove(x, y) end
      end
    end
  end
  if #clip.items == 0 then return false end
  g.clip, g.tool, g.sel = clip, 'stamp', nil
  return true
end

local function deleteSelection(app)
  local g, F = app.g, app.run.factory
  local sel = g.sel
  if not sel then return end
  for y = sel.y1, sel.y2 do
    for x = sel.x1, sel.x2 do F:remove(x, y) end
  end
  g.sel = nil
end

-- Would the stamp fit with its top-left corner on (cx, cy)? Every piece
-- needs a tile of your land that holds nothing fixed.
local function stampFits(app, cx, cy)
  local run = app.run
  for _, it in ipairs(app.g.clip.items) do
    local x, y = cx + it.dx, cy + it.dy
    local e = run.factory:at(x, y)
    if not run:canBuild(x, y) or (e and e.building.fixed) then return false end
  end
  return true
end

local function pasteStamp(app, cx, cy)
  if not stampFits(app, cx, cy) then return false end
  local run, F = app.run, app.run.factory
  for _, it in ipairs(app.g.clip.items) do
    local x, y = cx + it.dx, cy + it.dy
    if run:unlocked(it.kind) then
      if F:at(x, y) then F:remove(x, y) end
      F:place(it.kind, x, y, it.dir, { item = it.item })
    end
  end
  return true
end

---------------------------------------------------------------- shift control

local function startShift(app)
  local g = app.g
  g.tool, g.drag, g.sel, g.picker = nil, nil, nil, nil
  app.run:beginShift()
  g.mode, g.acc, g.frac, g.paused, g.popups = 'run', 0, 0, false, {}
  g.fx = Fx.new()
end

-- The summary plays out: the items at once, then one end-of-shift line per
-- BEAT (its card popping) while the total counts up. `shown` lines are up.
local function finishShift(app)
  local g = app.g
  g.summary = app.run:endShift()
  g.mode, g.frac = 'summary', 1
  g.reveal = { t = 0, shown = 0, n = #g.summary.results }
end

local function revealDone(g)
  local r = g.reveal
  return r.n == 0 or r.t >= BEAT * (r.n + 1)
end

local function completeReveal(g)
  local r = g.reveal
  r.t, r.shown = math.huge, r.n
end

local function advanceReveal(g, dt)
  local r, s = g.reveal, g.summary
  r.t = r.t + dt
  while r.shown < r.n and r.t >= BEAT * (r.shown + 1) do
    r.shown = r.shown + 1
    local res = s.results[r.shown]
    if res.fired then Fx.pop(g.fx, res.mod, res.delta < 0) end
  end
end

-- The shift total as far as the summary has revealed it.
local function revealedTotal(g)
  local r, s = g.reveal, g.summary
  local v = s.base
  for i = 1, r.shown do
    local res = s.results[i]
    if res.fired then v = v + res.delta * min(1, (r.t - BEAT * i) / COUNT) end
  end
  return floor(v + 0.5)
end

local function stepSim(app)
  local g, F = app.g, app.run.factory
  F:step()
  for _, ev in ipairs(F.events) do
    if ev.kind == 'sale' then
      -- The popup takes the colour of the mod that added the most.
      local best, color = 0, nil
      for _, f in ipairs(ev.fired or {}) do
        if f.delta > best then best, color = f.delta, Fx.color(f.mod) end
      end
      local last = g.popups[#g.popups]
      if last and last.x == ev.x and last.y == ev.y
          and (last.tick == F.shift.tick or last.age < POPUP_MERGE) then
        last.value = last.value + ev.value
        if best > last.best then last.best, last.color = best, color end
      else
        g.popups[#g.popups + 1] = {
          x = ev.x, y = ev.y, value = ev.value, age = 0, tick = F.shift.tick,
          best = best, color = color,
        }
      end
    elseif ev.kind == 'trigger' then
      Fx.trigger(g.fx, ev)
    end
  end
  if F:finished() then finishShift(app) end
end

-- Runs the rest of the shift at once. Not bound to any input: players watch
-- their shifts. Only the screenshot script uses it.
local function fastForward(app)
  while app.g.mode == 'run' do stepSim(app) end
end

local function afterSummary(app)
  local g, run = app.g, app.run
  local status = g.summary.status
  run.factory:clearItems()
  if status == 'next' then
    g.mode = 'build'
  elseif status == 'cleared' then
    run:payout()
    if run.index >= run:total() then
      run.won = true
      g.mode = 'win'
    else
      -- Choose the next contract first, then shop for it.
      run:rollOffers()
      app.state = 'board'
    end
  else
    g.mode = 'over'
  end
end

function Game.update(app, dt)
  local g = app.g
  Fx.update(g.fx, dt)
  if g.mode == 'summary' then advanceReveal(g, dt) end
  if g.mode == 'run' and not g.paused then
    g.acc = g.acc + dt * TPS * g.speed
    local guard = 0
    while g.acc >= 1 and g.mode == 'run' and guard < 64 do
      g.acc = g.acc - 1
      guard = guard + 1
      stepSim(app)
    end
    if g.mode == 'run' then g.frac = min(g.acc, 1) end
  end
  for i = #g.popups, 1, -1 do
    local p = g.popups[i]
    p.age = p.age + dt
    if p.age > POPUP_LIFE then table.remove(g.popups, i) end
  end
  -- The camera follows held keys (close view only; the overview shows it all).
  if love.keyboard and not g.book and g.mode ~= 'annex' then
    local down = love.keyboard.isDown
    local dx = ((down('d') or down('right')) and 1 or 0) - ((down('a') or down('left')) and 1 or 0)
    local dy = ((down('s') or down('down')) and 1 or 0) - ((down('w') or down('up')) and 1 or 0)
    if dx ~= 0 or dy ~= 0 then Game.pan(app, dx * PAN * dt, dy * PAN * dt) end
  end
end

-- Move the camera by a number of pixels.
function Game.pan(app, dx, dy)
  local cam = app.g.cam
  cam.fx, cam.fy = (cam.fx or 0) + dx, (cam.fy or 0) + dy   -- keep the fractions
  local ix, iy = floor(cam.fx), floor(cam.fy)
  cam.fx, cam.fy = cam.fx - ix, cam.fy - iy
  cam.x, cam.y = cam.x + ix, cam.y + iy
  clampCam(cam)
end

---------------------------------------------------------------- drawing: board

-- A mark on the edge of a tile: where a machine or port puts its items out.
local function nub(x, y, dir, c, a, T)
  UI.color(c, a)
  if T == 16 then
    if dir == 0 then love.graphics.rectangle('fill', x + 14, y + 6, 2, 4)
    elseif dir == 1 then love.graphics.rectangle('fill', x + 6, y + 14, 4, 2)
    elseif dir == 2 then love.graphics.rectangle('fill', x, y + 6, 2, 4)
    else love.graphics.rectangle('fill', x + 6, y, 4, 2) end
  else
    if dir == 0 then love.graphics.rectangle('fill', x + 7, y + 3, 1, 2)
    elseif dir == 1 then love.graphics.rectangle('fill', x + 3, y + 7, 2, 1)
    elseif dir == 2 then love.graphics.rectangle('fill', x, y + 3, 1, 2)
    else love.graphics.rectangle('fill', x + 3, y, 2, 1) end
  end
end

local STATUS_COLOR = { work = P.green, idle = P.faint, blocked = P.yellow }

-- A belt takes its shape from what feeds it: a lone side feed makes a
-- rounded corner, any other side feed opens the rail on that side.
local function drawBelt(S, F, e, x, y, frame)
  local dir = e.building.dir
  local shape = Links.beltShape(F, e)
  if shape.corner then
    UI.sprite(S.corner[frame], x, y, dir, 1, shape.corner == 'right')
    return
  end
  UI.sprite(S.belt[frame], x, y, dir)
  if shape.left then UI.sprite(S.inlet, x, y, dir) end
  if shape.right then UI.sprite(S.inlet, x, y, dir, 1, true) end
end

-- Any piece other than a belt in a line. `b` = { kind, dir }.
local function drawPiece(S, T, b, x, y, alpha, item, hasOutput)
  local kind = b.kind
  if kind == 'belt' then
    UI.sprite(S.belt[1], x, y, b.dir, alpha)
    return
  end
  UI.sprite(S.machine[kind], x, y, Sprites.rotates[kind] and b.dir or 0, alpha)
  if item then UI.sprite(S.item[item], x + T / 4, y + T / 4, 0, alpha) end
  if hasOutput then nub(x, y, b.dir, P.yellow, alpha, T) end
end

local function drawBuilding(S, T, e, x, y, live)
  local b = e.building
  drawPiece(S, T, b, x, y, 1, e.port and e.port.item, e.port or (e.machine and e.slot))
  if e.filter and e.filter.item then
    -- What it lets straight through.
    if T == 16 then
      UI.rect(x + 5, y + 5, 6, 6, P.dark)
      UI.sprite(Sprites.set[8].item[e.filter.item], x + 6, y + 6)
    else
      UI.rect(x + 3, y + 3, 2, 2, P[Items[e.filter.item].mat] or P.white)
    end
  end
  if e.export then
    -- A premium face: gold on the edge the items come in through.
    for d = 0, 3 do
      if e.export.premium[d] then nub(x, y, (d + 2) % 4, P.gold, 1, T) end
    end
  elseif e.machine and live then
    local m = e.machine
    local big = T == 16
    if big then
      UI.rect(x + 11, y + 2, 2, 2, STATUS_COLOR[m.status] or P.faint)
    else
      UI.rect(x + 6, y + 1, 1, 1, STATUS_COLOR[m.status] or P.faint)
    end
    local bx, by, bw = x + (big and 3 or 1), y + (big and 12 or 6), big and 10 or 6
    if m.craft then
      UI.rect(bx, by, bw, 1, P.dark)
      UI.rect(bx, by, floor(bw * min(1, m.craft.p / m.def.time)), 1, P.white)
    elseif m.def.generator and m.burn > 0 then
      UI.rect(bx, by, bw, 1, P.dark)
      UI.rect(bx, by, floor(bw * m.burn / m.burnMax), 1, P.orange)
    end
  end
end

-- A plot's fixed pieces, drawn at plot slot (sx, sy): the preview of land
-- that is on offer.
local function drawPlot(g, T, plot, sx, sy, alpha)
  local ox, oy = tilePos(g, sx * Map.PW, sy * Map.PH)
  Land.draw(plot, ox, oy, T, alpha)
end

local function drawBoard(app)
  local g, run = app.g, app.run
  local F, map = run.factory, run.map
  local world = F.world
  local live = g.mode == 'run' or g.mode == 'summary'
  local cam = g.cam
  local T = cam.T
  local S = Sprites.set[T]
  local big = T == 16

  love.graphics.setScissor(VX, VY, VW, VH)

  -- Visible tiles.
  local x0, y0 = floor(cam.x / T), floor(cam.y / T)
  local x1, y1 = min(Map.W - 1, floor((cam.x + VW - 1) / T)), min(Map.H - 1, floor((cam.y + VH - 1) / T))
  local function visible(e)
    return e.pos.x >= x0 and e.pos.x <= x1 and e.pos.y >= y0 and e.pos.y <= y1
  end

  for y = y0, y1 do
    for x = x0, x1 do
      local px, py = tilePos(g, x, y)
      if not map:owned(x, y) then
        UI.sprite(S.locked, px, py)
      elseif F:floorAt(x, y) == 'pad' then
        UI.sprite(S.pad, px, py)
      else
        UI.sprite(S.floor, px, py)
      end
    end
  end

  -- The edge of your land.
  for sy = 0, Map.ROWS - 1 do
    for sx = 0, Map.COLS - 1 do
      if map:has(sx, sy) then
        local px, py = tilePos(g, sx * Map.PW, sy * Map.PH)
        local w, h = Map.PW * T, Map.PH * T
        if not map:has(sx - 1, sy) then UI.rect(px - 1, py - 1, 1, h + 1, P.line) end
        if not map:has(sx + 1, sy) then UI.rect(px + w - 1, py - 1, 1, h + 1, P.line) end
        if not map:has(sx, sy - 1) then UI.rect(px - 1, py - 1, w + 1, 1, P.line) end
        if not map:has(sx, sy + 1) then UI.rect(px - 1, py + h - 1, w + 1, 1, P.line) end
      end
    end
  end

  local beltFrame = 1
  if live then beltFrame = floor((F.shift.tick + g.frac) * 8) % 4 + 1 end

  -- Things items ride on.
  local buildings = world:query('building')
  for i = 1, #buildings do
    local e = buildings[i]
    if visible(e) then
      local px, py = tilePos(g, e.pos.x, e.pos.y)
      if e.belt then
        drawBelt(S, F, e, px, py, beltFrame)
      elseif e.bridge or e.splitter or e.filter then
        drawBuilding(S, T, e, px, py, live)
      end
    end
  end

  -- Items, sliding from their previous tile to the current one.
  if live then
    local items = world:query('item')
    local f = g.frac
    local off = T / 4
    for i = 1, #items do
      local it = items[i]
      if not it.hidden then
        local x = VX + (it.prev.x + (it.pos.x - it.prev.x) * f) * T + off - cam.x
        local y = VY + (it.prev.y + (it.pos.y - it.prev.y) * f) * T + off - cam.y
        x, y = floor(x + 0.5), floor(y + 0.5)
        if x > VX - T and x < VX + VW and y > VY - T and y < VY + VH then
          if it.item.pack then
            -- A crate, with what is in it showing through the window.
            UI.sprite(S.crate, x, y)
            if big then UI.sprite(Sprites.set[8].item[it.item.type], x + 2, y + 2) end
          else
            UI.sprite(S.item[it.item.type], x, y)
          end
          if it.item.polished > 0 then
            if big then
              local blink = floor(app.time * 6 + it.id) % 3
              UI.rect(x + 6, y + blink, 1, 1, P.white)
              if it.item.polished > 1 then UI.rect(x + 1, y + 6 - blink, 1, 1, P.white) end
            else
              UI.rect(x + 3, y, 1, 1, P.white)
            end
          end
        end
      end
    end
  end

  -- Things items disappear into.
  for i = 1, #buildings do
    local e = buildings[i]
    if not (e.belt or e.bridge or e.splitter or e.filter) and visible(e) then
      local px, py = tilePos(g, e.pos.x, e.pos.y)
      drawBuilding(S, T, e, px, py, live)
    end
  end

  -- Machines changed by a speed or draw mod where they stand carry a pip per
  -- mod, while building too: these upgrades are placement puzzles. Hovering
  -- the upgrade's card outlines its machines.
  g.lit = {}
  for i = 1, #buildings do
    local e = buildings[i]
    local mods = e.machine and run.rules:affecting(F, e)
    if mods then
      local x, y = tilePos(g, e.pos.x, e.pos.y)
      local step = big and 3 or 2
      UI.rect(x, y, #mods * step + 1, big and 4 or 3, P.dark)
      for k = 1, #mods do
        local m = mods[k]
        g.lit[m] = true
        UI.rect(x + 1 + (k - 1) * step, y + 1, step - 1, step - 1, Fx.color(m))
        if m == g.hoverMod then UI.frame(x, y, T, T, Fx.color(m)) end
      end
    end
  end

  -- U: how busy each machine was, as measured (this shift, or the last one).
  if g.stats then
    for i = 1, #buildings do
      local e = buildings[i]
      local u = e.machine and visible(e) and F:utilisation(e)
      if u then
        local n = floor(u * 100 + 0.5)
        local label = tostring(big and n or min(n, 99))
        local x, y = tilePos(g, e.pos.x, e.pos.y)
        local w = Font.width(label)
        local color = u >= Factory.BUSY and P.green or (u >= 0.5 and P.yellow or P.red)
        if big then
          UI.rect(x + 15 - w - 2, y + 8, w + 2, 7, P.dark)
          UI.text(label, x + 15 - w - 1, y + 9, color)
        else
          UI.rect(x, y + 1, 8, 7, P.dark)
          UI.text(label, x + 8 - w, y + 2, color)
        end
      end
    end
  end

  Fx.drawFlashes(g.fx, VX - cam.x, VY - cam.y, T)

  local overlay = g.mode == 'intro' or g.mode == 'summary' or g.mode == 'over' or g.mode == 'win'
    or g.book or g.picker
  local cx, cy = cellAt(g, UI.mx, UI.my)

  if g.mode == 'annex' then
    -- Free slots, and the plot on offer under the mouse.
    local plot = run.pendingPlot
    local hsx, hsy
    if cx then hsx, hsy = Map.slotOf(cx, cy) end
    for _, s in ipairs(map:free()) do
      local px, py = tilePos(g, s[1] * Map.PW, s[2] * Map.PH)
      local w, h = Map.PW * T, Map.PH * T
      if s[1] == hsx and s[2] == hsy then
        drawPlot(g, T, plot, s[1], s[2], 1)
        UI.frame(px, py, w, h, P.white)
      else
        UI.rect(px + 1, py + 1, w - 2, h - 2, P.cyanD, 0.25)
        UI.frame(px, py, w, h, P.cyan, 0.8)
      end
    end
  end

  -- The selection.
  if g.sel and g.mode == 'build' then
    local sel = g.sel
    local px, py = tilePos(g, sel.x1, sel.y1)
    UI.rect(px, py, (sel.x2 - sel.x1 + 1) * T, (sel.y2 - sel.y1 + 1) * T, P.yellow, 0.12)
    UI.frame(px, py, (sel.x2 - sel.x1 + 1) * T, (sel.y2 - sel.y1 + 1) * T, P.yellow)
  end

  -- Hover, ghost and tooltip.
  if cx and not overlay and g.mode ~= 'annex' then
    local x, y = tilePos(g, cx, cy)
    local e = F:at(cx, cy)
    if e then
      UI.tip = entityTip(app, e)
    elseif not map:owned(cx, cy) then
      UI.tip = { title = 'NOT YOUR LAND', color = P.faint, lines = { 'EVERY CONTRACT ADDS A PLOT.' } }
    elseif F:floorAt(cx, cy) == 'pad' then
      UI.tip = { title = 'BOOSTER PAD', color = P.cyan, lines = { 'A MACHINE HERE RUNS 50% FASTER.' } }
    end
    if g.mode == 'build' and g.tool == 'stamp' then
      local ok = stampFits(app, cx, cy)
      for _, it in ipairs(g.clip.items) do
        local px, py = x + it.dx * T, y + it.dy * T
        local def = Machines[it.kind]
        drawPiece(S, T, it, px, py, 0.6, nil, def.time ~= nil)
      end
      UI.frame(x, y, g.clip.w * T, g.clip.h * T, ok and P.white or P.red, 0.8)
    elseif g.mode == 'build' and g.tool and g.tool ~= 'select' then
      local ok = canPlace(app, g.tool, cx, cy)
      local def = Machines[g.tool]
      drawPiece(S, T, { kind = g.tool, dir = g.dir }, x, y, 0.7, nil, def.time ~= nil)
      UI.frame(x, y, T, T, ok and P.white or P.red, 0.8)
    else
      UI.frame(x, y, T, T, P.white, 0.35)
    end
  end

  -- Sale popups: red when the sale was zeroed, the colour of the mod that
  -- added the most when one did, green for a plain sale.
  for _, p in ipairs(g.popups) do
    local label, color = '+$' .. Fmt.num(p.value), p.color or P.green
    if p.value == 0 then label, color = '$0', P.red end
    local px, py = tilePos(g, p.x, p.y)
    local x = px + T / 2 - Font.width(label) / 2
    x = max(VX + 1, min(x, VX + VW - Font.width(label) - 2))
    -- They rise, or sink where the top bar would swallow them.
    local y = py - 6 - p.age * POPUP_RISE
    if py - VY < 2 * T then y = py + T + 1 + p.age * POPUP_RISE end
    UI.text(label, x + 1, y + 1, P.dark)
    UI.text(label, x, y, color)
  end

  love.graphics.setScissor()
end

---------------------------------------------------------------- drawing: top bar

local function drawTopBar(app)
  local g, run = app.g, app.run
  local F = run.factory
  local c = run:contract()
  local rules = run.rules
  UI.rect(0, 0, 320, VY, P.panel)
  UI.rect(0, VY - 1, 320, 1, P.line)

  local label = 'CONTRACT ' .. c.index .. '/' .. run:total()
  UI.text(label, 3, 2, P.text)
  if c.boss then
    -- The boss has no card: its label takes the hit when its twist bites.
    local text, bx = 'BOSS: ' .. c.boss.name, 3 + Font.width(label) + 8
    local pop = Fx.popOf(g.fx, c.boss)
    if pop > 0 then
      bx = bx + Fx.shake(pop)
      UI.rect(bx - 2, 1, Font.width(text) + 4, 7, P.red)
    end
    UI.text(text, bx, 2, pop > 0 and P.dark or P.red)
    if UI.inside(0, 0, 200, 8) then
      UI.tip = { title = c.boss.name, color = P.red, lines = { c.boss.desc } }
    end
  end
  UI.textRight('$' .. run.credits, 286, 2, P.gold)
  if UI.inside(250, 0, 38, 8) then
    UI.tip = { title = 'CREDITS', color = P.gold, lines = { 'SPENT IN THE SHOP BETWEEN CONTRACTS.' } }
  end
  if UI.button('MENU', 291, 0, 27, 8) then app.openPause() end

  local live = g.mode == 'run' or g.mode == 'summary'
  local earned = run.progress + ((g.mode == 'run') and F.shift.revenue or 0)
  if g.mode == 'summary' then   -- no spoilers while the summary plays out
    earned = earned - g.summary.total + revealedTotal(g)
  end
  local bw = 96
  UI.rect(3, 9, bw, 5, P.bg)
  UI.rect(3, 9, floor(bw * min(1, earned / c.quota)), 5, earned >= c.quota and P.green or P.gold)
  UI.frame(3, 9, bw, 5, P.line)
  UI.text(Fmt.money(earned) .. '/' .. Fmt.num(c.quota), 3 + bw + 4, 9, earned >= c.quota and P.green or P.text)

  local tick = live and F.shift.tick or 0
  UI.textRight(tick .. '/' .. rules.shiftLen .. 'S', 316, 9, g.mode == 'run' and P.text or P.dim)
  local building = not live
  local shiftNo = min(rules.shifts, run.shiftsUsed + (building and 1 or 0))
  UI.textRight('SHIFT ' .. shiftNo .. '/' .. rules.shifts, 284, 9, P.dim)
  -- What the factory is earning per second, as measured so far.
  if live and tick > 0 then
    local rate = F.shift.revenue / tick
    local label = rate < 100 and ('$' .. num(floor(rate * 10 + 0.5) / 10)) or Fmt.money(rate)
    UI.textRight(label .. '/S', 240, 9, P.gold)
  end
end

---------------------------------------------------------------- drawing: sidebar

-- The shift ledger: what each upgrade (in slot order), the site's own rules
-- and the boss did this shift, as { mod, delta, n }. Nil if there is nobody
-- to list. End-of-shift credit stays out until the summary has revealed it.
local function ledgerRows(app)
  local g, run = app.g, app.run
  local ledger = run.factory.shift.ledger
  local hidden = {}
  if g.mode == 'summary' then
    for i = g.reveal.shown + 1, g.reveal.n do
      local res = g.summary.results[i]
      if res.fired then hidden[res.mod] = res.delta end
    end
  end
  local rows = {}
  local function add(mod)
    local rec = ledger[mod]
    if not rec then return end
    local held = hidden[mod]
    rows[#rows + 1] = { mod = mod, delta = rec.delta - (held or 0), n = rec.n - (held and 1 or 0), i = #rows + 1 }
  end
  if run.market then add(Market.mod(run.market)) end
  for _, id in ipairs(run.upgrades) do add(Upgrades.byId[id]) end
  add(Contracts.premium)
  local boss = run:contract().boss
  if boss then add(boss) end
  return #rows > 0 and rows or nil
end

local HINTS = {
  annex = { 'CLICK A FREE', 'PLOT TO PLACE', 'YOUR NEW LAND.' },
  build = { 'R   ROTATE', 'V   SELECT', 'F   FILTER', 'TAB RECIPES', 'U   BUSY %', 'WHEEL ZOOM', 'WASD MOVE' },
  select = { 'DRAG A BOX', 'C   COPY', 'X   CUT', 'DEL REMOVE', 'Q   CANCEL' },
  stamp = { 'LMB PASTE', 'R   ROTATE', 'Q   DONE' },
  run = { 'SPACE PAUSE', '1 2 3 SPEED', 'HOVER A', 'MACHINE TO', 'SEE HOW BUSY', 'IT IS.' },
}

local function drawSidebar(app)
  local g, run = app.g, app.run
  local F = run.factory
  local rules = run.rules
  UI.rect(SX, VY, SW, 180 - VY, P.panel)
  UI.rect(SX, VY, 1, 180 - VY, P.line)
  local x0, w = SX + 3, SW - 6

  -- Power.
  local live = g.mode == 'run' or g.mode == 'summary'
  local supply, demand
  if live then
    supply, demand = F.shift.supply, F.shift.demand
  else
    supply, demand = rules.basePower, F:plannedDraw(rules)
  end
  local over = demand > supply
  UI.text('POWER', x0, 19, P.dim)
  UI.textRight(num(demand) .. '/' .. num(supply) .. 'W', SX + SW - 3, 19, over and P.red or P.blue)
  UI.rect(x0, 26, w, 2, P.bg)
  UI.rect(x0, 26, floor(w * min(1, demand / max(supply, 1))), 2, over and P.red or P.blue)
  if UI.inside(SX, VY, SW, 13) then
    UI.tip = { title = 'POWER', color = P.blue, lines = {
      'WHAT YOUR MACHINES DRAW WHEN ALL OF THEM WORK / WHAT THE SITE SUPPLIES.',
      'OVER THE LIMIT, EVERY MACHINE SLOWS DOWN IN PROPORTION.' } }
  end

  -- Upgrades. A card pops when its upgrade triggers.
  UI.text('UPGRADES', x0, 31, P.dim)
  g.hoverMod = nil
  for i = 1, Contracts.upgradeSlots do
    local x, y = x0 + ((i - 1) % 3) * 19, 38 + floor((i - 1) / 3) * 18
    local id = run.upgrades[i]
    if id then
      local def = Upgrades.byId[id]
      local pop, bad = Fx.popOf(g.fx, def)
      UI.card(def, x, y, pop, bad, g.lit[def])
      if UI.inside(x, y, 16, 16) then
        UI.tip = upgradeTip(def)
        g.hoverMod = def
      end
    else
      UI.emptySlot(x, y)
    end
  end

  -- The market: what is in demand this contract, and how much of each
  -- demand this shift has filled.
  local y = 75
  local market = run.market
  if market then
    UI.text('MARKET', x0, y, P.dim)
    y = y + 8
    for _, d in ipairs(market.demand) do
      local filled = live and min(d.units, Market.filled(rules, d.item)) or 0
      UI.sprite(Sprites.item[d.item], x0, y - 1)
      UI.text('X' .. d.mult, x0 + 10, y + 1, P.green)
      UI.textRight(live and (filled .. '/' .. d.units) or tostring(d.units), SX + SW - 3, y + 1,
        filled >= d.units and P.green or (live and P.text or P.dim))
      if UI.inside(SX, y - 1, SW, 9) then
        local def = Items[d.item]
        local tip = { title = def.name .. ' IN DEMAND', color = P.green, lines = {
          'SELLS FOR X' .. d.mult .. ': ' .. Fmt.money(def.value * d.mult) .. ' INSTEAD OF ' .. Fmt.money(def.value) .. '.',
          'ON THE FIRST ' .. d.units .. ' SOLD EACH SHIFT. AFTER THAT, THE NORMAL PRICE.' } }
        local missing = Market.missing(d.item, run:resources(), run:kinds())
        if missing == nil then
          tip.lines[3] = 'NOTHING ON YOUR SITE MAKES IT.'
        elseif #missing > 0 then
          local names = {}
          for i, kind in ipairs(missing) do names[i] = Machines[kind].name end
          tip.lines[3] = 'NEEDS: ' .. table.concat(names, ', ') .. '.'
        end
        UI.tip = tip
      end
      y = y + 9
    end
    if market.slump then
      local s = market.slump
      UI.sprite(Sprites.item[s.item], x0, y - 1)
      UI.text('X' .. num(s.mult), x0 + 10, y + 1, P.red)
      UI.textRight('SLUMP', SX + SW - 3, y + 1, P.red)
      if UI.inside(SX, y - 1, SW, 9) then
        local def = Items[s.item]
        UI.tip = { title = def.name .. ' SLUMP', color = P.red, lines = {
          'SELLS FOR X' .. num(s.mult) .. ' THIS CONTRACT: ' .. Fmt.money(def.value * s.mult) ..
          ' INSTEAD OF ' .. Fmt.money(def.value) .. '.' } }
      end
      y = y + 9
    end
    y = y + 2
  end

  -- During a shift: the ledger. Otherwise: the keys that matter right now.
  local rows = live and ledgerRows(app)
  if g.mode == 'annex' then
    UI.text('NEW LAND', x0, y, P.cyan)
    y = y + 8
    for _, line in ipairs(plotLines(run.pendingPlot)) do
      y = UI.paragraph(line, x0, y, 14, P.text)
    end
    y = y + 3
  end
  if rows then
    -- What fits, the rows that did something first.
    table.sort(rows, function(a, b)
      local ta, tb = a.n > 0, b.n > 0
      if ta ~= tb then return ta end
      return a.i < b.i
    end)
    for _, row in ipairs(rows) do
      if y > 154 then break end
      local amount, color = Fx.amount(row)
      local name = Fx.fit(row.mod.name, w - Font.width(amount) - 3)
      UI.text(name, x0, y, row.n > 0 and Fx.color(row.mod) or P.faint)
      UI.textRight(amount, SX + SW - 3, y, color)
      y = y + 7
    end
  else
    local hints = HINTS[g.mode]
    if g.mode == 'build' and (g.tool == 'select' or g.sel) then hints = HINTS.select end
    if g.mode == 'build' and g.tool == 'stamp' then hints = HINTS.stamp end
    for _, line in ipairs(hints or {}) do
      if y > 154 then break end
      UI.text(line, x0, y, P.faint)
      y = y + 7
    end
  end

  -- Controls.
  if g.mode == 'build' then
    if UI.button('RUN', x0, 164, 44, 13, { color = P.green }) then startShift(app) end
    if UI.button('?', x0 + 46, 164, 12, 13) then g.book = true end
  elseif g.mode == 'run' then
    for i, s in ipairs({ 1, 2, 4 }) do
      if UI.button(s .. 'X', x0 + (i - 1) * 20, 164, 18, 13, { active = g.speed == s and not g.paused, color = P.blue }) then
        g.speed, g.paused = s, false
      end
    end
  end
end

---------------------------------------------------------------- drawing: palette

-- The palette strip: the select tool, then every kind the run can build.
local function paletteEntries(run)
  local list = { 'select' }
  for _, kind in ipairs(run:palette()) do list[#list + 1] = kind end
  return list
end

local function drawPalette(app)
  local g, run = app.g, app.run
  UI.rect(0, PY, SX, 180 - PY, P.panel)
  UI.rect(0, PY, SX, 1, P.line)
  local entries = paletteEntries(run)
  g.entries = entries
  for i, kind in ipairs(entries) do
    local x, y = (i - 1) * CELL, PY + 2
    local sel = g.tool == kind or (kind == 'select' and g.sel ~= nil and g.tool == nil)
    if sel then UI.rect(x, PY + 1, CELL, 19, P.line) end
    if kind == 'select' then
      -- A dashed box.
      for k = 0, 2 do
        UI.rect(x + 3 + k * 4, y + 3, 2, 1, P.text); UI.rect(x + 3 + k * 4, y + 12, 2, 1, P.text)
        UI.rect(x + 3, y + 3 + k * 4, 1, 2, P.text); UI.rect(x + 12, y + 3 + k * 4, 1, 2, P.text)
      end
    else
      UI.sprite(Sprites.machine[kind], x, y)
    end
    if sel then UI.frame(x, PY + 1, CELL, 19, P.yellow) end
    if UI.inside(x, PY + 1, CELL, 19) then
      local tip
      if kind == 'select' then
        tip = { title = 'SELECT', color = P.text, lines = {
          'DRAG A BOX OVER PIECES, THEN C TO COPY, X TO CUT OR DELETE TO REMOVE THEM.', 'KEY V' } }
      else
        tip = kindTip(kind)
        if i - 1 <= 10 then tip.lines[#tip.lines + 1] = 'KEY ' .. ((i - 1) % 10) end
      end
      UI.tip = tip
    end
    if g.mode == 'build' and UI.clicked(x, PY + 1, CELL, 19) then
      g.tool = (g.tool ~= kind) and kind or nil
      g.sel, g.filterItem = nil, nil
    end
  end
end

---------------------------------------------------------------- drawing: overlays

local function dim()
  UI.rect(VX, VY, VW, VH, P.dark, 0.6)
end

-- The item chooser of a filter: every item in the game, one click to set.
local PICK = { cols = 10, cell = 14 }

local function drawPicker(app)
  local g = app.g
  local e = g.picker.e
  local rows = math.ceil(#Items.list / PICK.cols)
  local w, h = PICK.cols * PICK.cell + 8, rows * PICK.cell + 34
  local x, y = floor(CX - w / 2), floor(VY + (VH - h) / 2)
  dim()
  UI.panel(x, y, w, h, P.panel, P.line)
  UI.text('FILTER: WHICH ITEM GOES STRAIGHT ON?', x + 4, y + 4, P.text)
  local hover
  for i, id in ipairs(Items.list) do
    local cx = x + 4 + ((i - 1) % PICK.cols) * PICK.cell
    local cy = y + 13 + floor((i - 1) / PICK.cols) * PICK.cell
    local hot = UI.inside(cx, cy, PICK.cell, PICK.cell)
    if e.filter.item == id then UI.rect(cx, cy, PICK.cell, PICK.cell, P.line) end
    if hot then
      UI.frame(cx, cy, PICK.cell, PICK.cell, P.yellow)
      hover = id
    end
    UI.sprite(Sprites.item[id], cx + 3, cy + 3)
    if UI.clicked(cx, cy, PICK.cell, PICK.cell) then
      e.filter.item = id
      g.filterItem = id
      g.picker = nil
      return
    end
  end
  local by = y + h - 18
  UI.text(hover and Items[hover].name or (e.filter.item and ('NOW: ' .. Items[e.filter.item].name) or 'NOTHING SET'),
    x + 4, by + 4, hover and P.gold or P.dim)
  if UI.button('NONE', x + w - 34, by, 30, 12) then
    e.filter.item = nil
    g.picker = nil
    return
  end
  -- A click anywhere else closes it.
  if UI.click and not UI.inside(x, y, w, h) then g.picker = nil end
end

local function drawIntro(app)
  local g, run = app.g, app.run
  local c, rules = run:contract(), run.rules
  dim()
  local w, h = 200, 132
  local x, y = floor(CX - w / 2), 22
  local cx = x + w / 2
  UI.panel(x, y, w, h, P.panel, c.boss and P.red or P.line)
  UI.textCenter('CONTRACT ' .. c.index .. (c.index <= run:total() and (' OF ' .. run:total()) or ''), cx, y + 5, P.dim)
  UI.textCenter('QUOTA ' .. Fmt.money(c.quota), cx, y + 13, P.gold, 2)
  UI.textCenter(rules.shifts .. ' SHIFTS OF ' .. rules.shiftLen .. ' SECONDS', cx, y + 27, P.text)
  local yy = y + 37
  if c.index == 1 then
    for _, line in ipairs(Font.wrap('LAY BELTS FROM THE PORTS TO THE DEPOT. MACHINES ON THE WAY ADD VALUE: '
        .. 'BUILD AS MANY AS YOUR POWER ALLOWS.', 46)) do
      UI.textCenter(line, cx, yy, P.dim)
      yy = yy + 7
    end
    yy = yy + 2
  end
  if run.market then
    UI.text('IN DEMAND', x + 8, yy, P.green)
    yy = Board.marketRows(run, run.market, nil, x + 8, yy + 8, w - 16) + 2
  end
  if c.boss then
    UI.textCenter('BOSS: ' .. c.boss.name, cx, yy, P.red)
    yy = yy + 8
    for _, line in ipairs(Font.wrap(c.boss.desc, 42)) do
      UI.textCenter(line, cx, yy, P.text)
      yy = yy + 7
    end
  end
  if UI.button('START', cx - 25, y + h - 18, 50, 13, { color = P.green }) then g.mode = 'build' end
end

local function drawSummary(app)
  local g, run = app.g, app.run
  local s, c = g.summary, run:contract()
  dim()
  local w, h = 190, 138
  local x, y = floor(CX - w / 2), 19
  local cx = x + w / 2
  UI.panel(x, y, w, h, P.panel, P.line)
  UI.textCenter('SHIFT ' .. run.shiftsUsed .. ' COMPLETE', cx, y + 5, P.text)

  local order = {}
  for i, t in ipairs(s.order) do order[i] = t end
  table.sort(order, function(a, b)
    if s.sold[a].total ~= s.sold[b].total then return s.sold[a].total > s.sold[b].total end
    return a < b
  end)
  local yy = y + 15
  local shown = min(#order, 5)
  for i = 1, shown do
    local t = order[i]
    local rec = s.sold[t]
    UI.sprite(Sprites.item[t], x + 8, yy - 1)
    UI.text(Items[t].name, x + 20, yy + 1, P.dim)
    UI.textRight('X' .. rec.n, x + 130, yy + 1, P.text)
    UI.textRight(Fmt.money(rec.total), x + w - 8, yy + 1, P.text)
    yy = yy + 9
  end
  if #order > shown then
    UI.text('+ ' .. (#order - shown) .. ' MORE TYPES', x + 20, yy + 1, P.faint)
    yy = yy + 9
  elseif #order == 0 then
    UI.textCenter('NOTHING WAS SOLD', cx, yy + 1, P.faint)
    yy = yy + 9
  end
  -- Where the factory fell short: the machine that worked the least.
  if s.lowest then
    local u = s.lowest.u
    UI.text('LEAST BUSY: ' .. Machines[s.lowest.kind].name .. ' ' .. pct(u), x + 8, yy + 1,
      u >= Factory.BUSY and P.green or (u >= 0.5 and P.yellow or P.red))
    yy = yy + 8
  end
  UI.rect(x + 8, yy + 1, w - 16, 1, P.line)
  yy = yy + 5
  -- End-of-shift mods stamp in one at a time, met or not.
  local r = g.reveal
  for i = 1, r.n do
    if i <= r.shown then
      local res = s.results[i]
      if res.fired then
        local fresh = r.t - BEAT * i < STAMP
        local color = Fx.color(res.mod)
        if fresh then UI.rect(x + 6, yy - 1, w - 12, 7, color) end
        local amount = (res.label and (res.label .. '  ') or '') .. Fx.money(res.delta)
        UI.text(res.mod.name, x + 8, yy, fresh and P.dark or color)
        UI.textRight(amount, x + w - 8, yy, fresh and P.dark or color)
      else
        UI.text(res.mod.name, x + 8, yy, P.faint)
        UI.textRight('NOT MET', x + w - 8, yy, P.faint)
      end
    end
    yy = yy + 8
  end
  UI.text('SHIFT TOTAL', x + 8, yy, P.text)
  UI.textRight(Fmt.money(revealedTotal(g)), x + w - 8, yy, P.gold)
  if not revealDone(g) then return end

  yy = yy + 9
  local met = run.progress >= c.quota
  UI.text('CONTRACT', x + 8, yy, P.dim)
  UI.textRight(Fmt.money(run.progress) .. ' / ' .. Fmt.money(c.quota), x + w - 8, yy, met and P.green or P.text)

  local by = y + h - 18
  local label, msg, color = 'NEXT SHIFT', run:shiftsLeft() .. ' SHIFTS LEFT', P.text
  if s.status == 'cleared' then label, msg, color = 'COLLECT', 'QUOTA MET!', P.green
  elseif s.status == 'failed' then label, msg, color = 'END RUN', 'QUOTA MISSED', P.red end
  UI.text(msg, x + 8, by + 4, color)
  if UI.button(label, x + w - 68, by, 60, 13, { color = color == P.text and P.green or color }) then
    afterSummary(app)
  end
end

local function drawEnd(app, won)
  local run = app.run
  dim()
  local w, h = 180, 84
  local x, y = floor(CX - w / 2), 46
  local cx = x + w / 2
  UI.panel(x, y, w, h, P.panel, won and P.gold or P.red)
  if won then
    UI.textCenter('ALL QUOTAS MET', cx, y + 10, P.gold, 2)
    UI.textCenter('THE FACTORY IS YOURS.', cx, y + 28, P.text)
  else
    UI.textCenter('RUN OVER', cx, y + 10, P.red, 2)
    UI.textCenter('STOPPED AT CONTRACT ' .. run.index .. ' OF ' .. run:total(), cx, y + 28, P.text)
    UI.textCenter(Fmt.money(run.progress) .. ' OF ' .. Fmt.money(run:contract().quota), cx, y + 37, P.dim)
  end
  UI.textCenter('SEED ' .. run.seed, cx, y + 48, P.faint)
  if UI.button('TITLE', cx - 30, y + h - 19, 60, 13, { color = P.green }) then app.toTitle() end
end

function Game.draw(app)
  local g = app.g
  drawBoard(app)
  drawTopBar(app)
  drawSidebar(app)
  drawPalette(app)
  if g.mode == 'run' and g.paused then
    UI.textCenter('PAUSED', CX, VY + 4, P.yellow)
  end
  if g.mode == 'annex' then
    UI.rect(VX, VY, VW, 10, P.dark, 0.8)
    UI.textCenter('NEW LAND: CLICK A FREE PLOT TO PLACE IT', CX, VY + 2, P.cyan)
  end
  if g.mode == 'intro' then drawIntro(app)
  elseif g.mode == 'summary' then drawSummary(app)
  elseif g.mode == 'over' then drawEnd(app, false)
  elseif g.mode == 'win' then drawEnd(app, true) end
  if g.picker then drawPicker(app) end
  if g.book then
    Book.draw(app)
  elseif UI.tip and not g.picker then
    UI.drawTip(UI.tip, UI.mx, UI.my)
  end
end

---------------------------------------------------------------- input

function Game.press(app, x, y, b)
  local g = app.g
  if g.book then
    g.book = Book.press(app, x, y)
    return
  end
  if g.picker then
    UI.click = { x = x, y = y, b = b }     -- the chooser handles its own clicks
    return
  end
  if g.mode == 'summary' and not revealDone(g) then
    completeReveal(g)     -- the first press only finishes the playback
    return
  end
  local cx, cy = cellAt(g, x, y)
  if b == 3 and cx and g.mode ~= 'annex' then
    g.panning = { x = x, y = y }       -- drag the site with the middle button
    return
  end
  if g.mode == 'annex' and cx and b == 1 then
    local sx, sy = Map.slotOf(cx, cy)
    if app.run:annex(sx, sy) then
      -- Back to work, looking at the new land.
      g.mode = 'intro'
      setZoom(g, 16, sx * Map.PW + Map.PW / 2, sy * Map.PH + Map.PH / 2)
    end
    return
  end
  if g.mode ~= 'build' or not cx then
    if b == 2 and g.mode == 'build' then g.tool, g.sel = nil, nil end
    UI.click = { x = x, y = y, b = b }
    return
  end
  local F = app.run.factory
  if b == 1 then
    if g.tool == 'select' then
      g.sel = { x1 = cx, y1 = cy, x2 = cx, y2 = cy }
      g.drag = { select = true, x = cx, y = cy }
    elseif g.tool == 'stamp' then
      pasteStamp(app, cx, cy)
    elseif g.tool then
      local fresh = F:at(cx, cy) == nil or F:at(cx, cy).building.kind ~= g.tool
      local e = placeAt(app, g.tool, cx, cy, g.dir, { item = g.filterItem })
      g.drag = { x = cx, y = cy, tool = g.tool }
      -- A new filter asks at once what it should let through.
      if e and fresh and e.filter and not e.filter.item then g.picker = { e = e } end
    else
      g.sel = nil
      local e = F:at(cx, cy)
      if e and not e.building.fixed then       -- pick it up to move it
        g.tool, g.dir = e.building.kind, e.building.dir
        g.filterItem = e.filter and e.filter.item or nil
        F:remove(cx, cy)
      end
    end
  elseif b == 2 then
    F:remove(cx, cy)
    g.drag = { x = cx, y = cy, erase = true }
  end
end

function Game.release(app)
  local g = app.g
  g.drag, g.panning = nil, nil
end

function Game.moved(app, x, y)
  local g = app.g
  if g.panning then
    Game.pan(app, g.panning.x - x, g.panning.y - y)
    g.panning.x, g.panning.y = x, y
    return
  end
  local d = g.drag
  if not d or g.mode ~= 'build' then return end
  local cx, cy = cellAt(g, x, y)
  if not cx then return end
  if d.select then
    g.sel = { x1 = min(d.x, cx), y1 = min(d.y, cy), x2 = max(d.x, cx), y2 = max(d.y, cy) }
    return
  end
  local F = app.run.factory
  while d.x ~= cx or d.y ~= cy do
    local dx, dy = cx - d.x, cy - d.y
    local dir
    if math.abs(dx) >= math.abs(dy) then dir = dx > 0 and 0 or 2 else dir = dy > 0 and 1 or 3 end
    local nx, ny = d.x + D.DX[dir], d.y + D.DY[dir]
    if d.erase then
      F:remove(nx, ny)
    elseif d.tool == 'belt' then
      local prev = F:at(d.x, d.y)
      if prev and prev.belt then prev.building.dir = dir end
      g.dir = dir
      placeAt(app, 'belt', nx, ny, dir)
    end
    d.x, d.y = nx, ny
  end
end

-- The wheel zooms: in on the tile under the mouse, out to the whole site.
function Game.wheel(app, dy)
  local g = app.g
  if g.book or g.mode == 'annex' then return end
  local cam = g.cam
  if dy > 0 and cam.T == 8 then
    local cx, cy = cellAt(g, UI.mx, UI.my)
    if not cx then cx, cy = depotCentre(app.run) end
    setZoom(g, 16, cx + 0.5, cy + 0.5)
  elseif dy < 0 and cam.T == 16 then
    setZoom(g, 8, 0, 0)
  end
end

function Game.key(app, key)
  local g = app.g
  if key == 'tab' then g.book = not g.book; return end
  if g.book then Book.key(app, key); return end
  if g.picker then return end
  if key == 'u' then g.stats = not g.stats; return end
  if key == 'z' and g.mode ~= 'annex' then
    Game.wheel(app, g.cam.T == 8 and 1 or -1)
    return
  end
  if g.mode == 'intro' then
    if key == 'space' or key == 'return' then g.mode = 'build' end
  elseif g.mode == 'build' then
    if key == 'r' then rotate(app, 1)
    elseif key == 'f' then
      -- Choose what the filter under the mouse lets through.
      local cx, cy = cellAt(g, UI.mx, UI.my)
      local e = cx and app.run.factory:at(cx, cy)
      if e and e.filter then g.picker = { e = e } end
    elseif key == 'q' then g.tool, g.sel, g.filterItem = nil, nil, nil
    elseif key == 'v' then g.tool = (g.tool ~= 'select') and 'select' or nil
    elseif key == 'c' then copySelection(app, false)
    elseif key == 'x' then copySelection(app, true)
    elseif key == 'delete' or key == 'backspace' then deleteSelection(app)
    elseif key == 'space' or key == 'return' then startShift(app)
    else
      local n = tonumber(key)
      if n == 0 then n = 10 end
      local kind = n and g.entries and g.entries[n + 1]
      if kind then
        g.tool = (g.tool ~= kind) and kind or nil
        g.sel, g.filterItem = nil, nil
      end
    end
  elseif g.mode == 'run' then
    if key == 'space' then g.paused = not g.paused
    elseif key == '1' then g.speed, g.paused = 1, false
    elseif key == '2' then g.speed, g.paused = 2, false
    elseif key == '3' then g.speed, g.paused = 4, false end
  elseif g.mode == 'summary' then
    if key == 'space' or key == 'return' then
      if revealDone(g) then afterSummary(app) else completeReveal(g) end
    end
  end
end

-- Esc: close the recipe book, or put away the tool or the selection. Returns
-- false when there was nothing to cancel (the app then opens the pause menu).
function Game.cancel(app)
  local g = app.g
  if g.book then g.book = false; return true end
  if g.picker then g.picker = nil; return true end
  if g.mode == 'build' and (g.tool or g.sel) then g.tool, g.sel, g.filterItem = nil, nil, nil; return true end
  return false
end

---------------------------------------------------------------- for scripts

-- Canvas position of the middle of a tile, at the current zoom.
function Game.cellXY(app, cx, cy)
  local x, y = tilePos(app.g, cx, cy)
  return x + app.g.cam.T / 2, y + app.g.cam.T / 2
end

-- Canvas position of a palette entry ('select' or a kind), or nil.
function Game.paletteXY(app, kind)
  for i, k in ipairs(paletteEntries(app.run)) do
    if k == kind then return (i - 1) * CELL + CELL / 2, PY + 10 end
  end
end

-- Canvas positions of the fixed buttons.
Game.at = {
  run = { SX + 25, 170 }, book = { SX + 55, 170 },
  speed = { { SX + 12, 170 }, { SX + 32, 170 }, { SX + 52, 170 } },
  menu = { 304, 4 },
  intro = { CX, 143 },          -- START
  summary = { CX + 57, 146 },   -- NEXT SHIFT / COLLECT / END RUN
  finish = { CX, 118 },         -- TITLE on the end screen
}

Game.startShift, Game.fastForward, Game.afterSummary, Game.placeAt = startShift, fastForward, afterSummary, placeAt
Game.setZoom, Game.cellAt, Game.copySelection = setZoom, cellAt, copySelection

return Game
