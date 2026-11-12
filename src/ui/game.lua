-- The main screen: board on the left, sidebar on the right.
-- Modes: intro -> build -> run -> summary -> (build | shop | over | win)

local P = require 'src.gfx.palette'
local Font = require 'src.gfx.font'
local Sprites = require 'src.gfx.sprites'
local UI = require 'src.ui.ui'
local Book = require 'src.ui.book'
local Factory = require 'src.sim.factory'
local D = require 'src.sim.dirs'
local Machines = require 'src.data.machines'
local Items = require 'src.data.items'
local Upgrades = require 'src.data.upgrades'
local Contracts = require 'src.data.contracts'

local Game = {}

local T = 16                 -- tile size
local BX, BY = 0, 20         -- board origin
local SX = 224               -- sidebar origin
local TPS = 4                -- simulation ticks per real second at 1x
local floor, min, max = math.floor, math.min, math.max

local function num(n)
  if n == floor(n) then return tostring(n) end
  return string.format('%.1f', n)
end

function Game.enter(app)
  local speed = app.g and app.g.speed or 1
  app.g = {
    mode = 'intro', tool = nil, dir = 0, speed = speed,
    acc = 0, frac = 0, paused = false,
    popups = {}, summary = nil, drag = nil, book = false,
  }
end

local function cellAt(x, y)
  if x < BX or y < BY or x >= BX + Factory.W * T or y >= BY + Factory.H * T then return nil end
  return floor((x - BX) / T), floor((y - BY) / T)
end

---------------------------------------------------------------- tooltips

local function kindTip(kind)
  local def = Machines[kind]
  local lines = { def.desc }
  if def.time then
    lines[#lines + 1] = def.time .. 'S PER CRAFT, ' .. def.draw .. 'W'
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
    tip.lines = { '1 EVERY ' .. e.port.period .. 'S: ' ..
      floor(app.run.rules.shiftLen / e.port.period) .. ' PER SHIFT' }
    if live then tip.lines[2] = 'SENT ' .. e.port.sent end
  elseif e.export then
    if live then tip.lines[2] = 'SOLD ' .. e.export.sold end
  elseif e.machine and live then
    local m = e.machine
    tip.lines = { (m.def.generator and 'BURNED ' or 'MADE ') .. m.made, STATUS[m.status] }
    if m.speed ~= 1 then tip.lines[3] = 'SPEED X' .. num(m.speed) end
    if m.started and m.idle > 0 then tip.lines[#tip.lines + 1] = 'IDLE FOR ' .. m.idle .. 'S' end
  elseif e.machine then
    local sp = app.run.rules:speed(F, e)
    if sp ~= 1 then tip.lines[#tip.lines + 1] = 'SPEED X' .. num(sp) end
  end
  return tip
end

local function defaultTip(app)
  local mode = app.g.mode
  if mode == 'run' then
    return { title = 'SHIFT RUNNING', color = P.green,
      lines = { 'SPACE PAUSES.', 'HOVER A MACHINE TO SEE WHAT IT IS DOING.' } }
  elseif mode == 'summary' then
    return { title = 'SHIFT OVER', color = P.text,
      lines = { 'YOU CAN REBUILD BEFORE THE NEXT SHIFT.' } }
  elseif mode == 'over' or mode == 'win' then
    return { title = 'RUN ENDED', color = P.text, lines = {} }
  end
  return { title = 'BUILD', color = P.text,
    lines = { 'LEFT CLICK: PLACE, DRAG BELTS, PICK UP.', 'RIGHT CLICK: REMOVE.',
      'R: ROTATE. TAB: RECIPES.' } }
end

---------------------------------------------------------------- editing

local function placeAt(app, kind, x, y, dir)
  local run, F = app.run, app.run.factory
  local e = F:at(x, y)
  if e then
    if e.building.fixed then return false end
    if e.building.kind == kind then
      e.building.dir = dir
      return true
    end
    if kind == 'belt' or not e.belt then return false end
    if run:available(kind) <= 0 then return false end
    F:remove(x, y)                       -- a machine may replace a belt
  elseif run:available(kind) <= 0 then
    return false
  end
  F:place(kind, x, y, dir)
  return true
end

local function clearBoard(app)
  local F = app.run.factory
  for y = 0, Factory.H - 1 do
    for x = 0, Factory.W - 1 do F:remove(x, y) end
  end
end

local function rotate(app, step)
  local g = app.g
  if g.mode ~= 'build' then return end
  if g.tool then
    g.dir = (g.dir + step) % 4
    return
  end
  local cx, cy = cellAt(UI.mx, UI.my)
  local e = cx and app.run.factory:at(cx, cy)
  if e and not e.building.fixed then
    e.building.dir = (e.building.dir + step) % 4
  end
end

---------------------------------------------------------------- shift control

local function startShift(app)
  local g = app.g
  g.tool, g.drag = nil, nil
  app.run:beginShift()
  g.mode, g.acc, g.frac, g.paused, g.popups = 'run', 0, 0, false, {}
end

local function finishShift(app)
  local g = app.g
  g.summary = app.run:endShift()
  g.mode, g.frac = 'summary', 1
end

local function stepSim(app)
  local g, F = app.g, app.run.factory
  F:step()
  for _, ev in ipairs(F.events) do
    if ev.kind == 'sale' then
      local last = g.popups[#g.popups]
      if last and last.tick == F.shift.tick and last.x == ev.x and last.y == ev.y then
        last.value = last.value + ev.value
      else
        g.popups[#g.popups + 1] = { x = ev.x, y = ev.y, value = ev.value, age = 0, tick = F.shift.tick }
      end
    end
  end
  if F:finished() then finishShift(app) end
end

local function skipShift(app)
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
      run:openShop()
      app.state = 'shop'
    end
  else
    g.mode = 'over'
  end
end

function Game.update(app, dt)
  local g = app.g
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
    if p.age > 0.9 then table.remove(g.popups, i) end
  end
end

---------------------------------------------------------------- drawing: board

local function nub(x, y, dir, c, a)
  UI.color(c, a)
  if dir == 0 then love.graphics.rectangle('fill', x + 14, y + 6, 2, 4)
  elseif dir == 1 then love.graphics.rectangle('fill', x + 6, y + 14, 4, 2)
  elseif dir == 2 then love.graphics.rectangle('fill', x, y + 6, 2, 4)
  else love.graphics.rectangle('fill', x + 6, y, 4, 2) end
end

local STATUS_COLOR = { work = P.green, idle = P.faint, blocked = P.yellow }

local function drawBuilding(e, x, y, live, beltFrame, alpha)
  local b = e.building
  local kind = b.kind
  if kind == 'belt' then
    UI.sprite(Sprites.belt[beltFrame], x, y, b.dir, alpha)
    return
  end
  UI.sprite(Sprites.machine[kind], x, y, Sprites.rotates[kind] and b.dir or 0, alpha)
  if e.port then
    UI.sprite(Sprites.item[e.port.item], x + 4, y + 4, 0, alpha)
    nub(x, y, b.dir, P.yellow, alpha)
  elseif e.machine then
    if e.slot then nub(x, y, b.dir, P.yellow, alpha) end
    if live then
      local m = e.machine
      UI.rect(x + 11, y + 2, 2, 2, STATUS_COLOR[m.status] or P.faint)
      if m.craft then
        UI.rect(x + 3, y + 12, 10, 1, P.dark)
        UI.rect(x + 3, y + 12, floor(10 * min(1, m.craft.p / m.def.time)), 1, P.white)
      elseif m.def.generator and m.burn > 0 then
        UI.rect(x + 3, y + 12, 10, 1, P.dark)
        UI.rect(x + 3, y + 12, floor(10 * m.burn / m.def.generator.burn), 1, P.orange)
      end
    end
  end
end

local function drawBoard(app)
  local g, run = app.g, app.run
  local F = run.factory
  local world = F.world
  local live = g.mode == 'run' or g.mode == 'summary'

  for y = 0, Factory.H - 1 do
    for x = 0, Factory.W - 1 do
      UI.sprite(Sprites.floor, BX + x * T, BY + y * T)
    end
  end

  local beltFrame = 1
  if live then beltFrame = floor((F.shift.tick + g.frac) * 8) % 4 + 1 end

  -- Things items ride on.
  local buildings = world:query('building')
  for i = 1, #buildings do
    local e = buildings[i]
    if e.belt or e.bridge or e.splitter then
      drawBuilding(e, BX + e.pos.x * T, BY + e.pos.y * T, live, beltFrame)
    end
  end

  -- Items, sliding from their previous tile to the current one.
  if live then
    local items = world:query('item')
    local f = g.frac
    for i = 1, #items do
      local it = items[i]
      if not it.hidden then
        local x = BX + (it.prev.x + (it.pos.x - it.prev.x) * f) * T + 4
        local y = BY + (it.prev.y + (it.pos.y - it.prev.y) * f) * T + 4
        x, y = floor(x + 0.5), floor(y + 0.5)
        UI.sprite(Sprites.item[it.item.type], x, y)
        if it.item.polished > 0 then
          local blink = floor(app.time * 6 + it.id) % 3
          UI.rect(x + 6, y + blink, 1, 1, P.white)
          if it.item.polished > 1 then UI.rect(x + 1, y + 6 - blink, 1, 1, P.white) end
        end
      end
    end
  end

  -- Things items disappear into.
  for i = 1, #buildings do
    local e = buildings[i]
    if not (e.belt or e.bridge or e.splitter) then
      drawBuilding(e, BX + e.pos.x * T, BY + e.pos.y * T, live, beltFrame)
    end
  end

  -- Hover, ghost and tooltip.
  local overlay = g.mode == 'intro' or g.mode == 'summary' or g.mode == 'over' or g.mode == 'win' or g.book
  local cx, cy = cellAt(UI.mx, UI.my)
  if cx and not overlay then
    local x, y = BX + cx * T, BY + cy * T
    local e = F:at(cx, cy)
    if e then UI.tip = entityTip(app, e) end
    if g.mode == 'build' and g.tool then
      local ok = (not e and run:available(g.tool) > 0)
        or (e and not e.building.fixed and (e.building.kind == g.tool or (e.belt and g.tool ~= 'belt')))
      local ghost = { building = { kind = g.tool, dir = g.dir }, slot = not Machines[g.tool].generator }
      if g.tool == 'belt' or g.tool == 'splitter' or g.tool == 'bridge' then
        UI.sprite(Sprites.machine[g.tool], x, y, Sprites.rotates[g.tool] and g.dir or 0, 0.7)
      else
        UI.sprite(Sprites.machine[g.tool], x, y, 0, 0.7)
        if ghost.slot then nub(x, y, g.dir, P.yellow, 0.9) end
      end
      UI.frame(x, y, T, T, ok and P.white or P.red, 0.8)
    else
      UI.frame(x, y, T, T, P.white, 0.35)
    end
  end

  -- Sale popups.
  for _, p in ipairs(g.popups) do
    local label = '+$' .. p.value
    local x = BX + p.x * T + 8 - Font.width(label) / 2
    x = min(x, SX - Font.width(label) - 2)
    local y = BY + p.y * T - 6 - p.age * 14
    UI.text(label, x + 1, y + 1, P.dark)
    UI.text(label, x, y, P.green)
  end
end

---------------------------------------------------------------- drawing: top bar

local function drawTopBar(app)
  local g, run = app.g, app.run
  local F = run.factory
  local c = run:contract()
  local rules = run.rules
  UI.rect(0, 0, SX, BY, P.panel)
  UI.rect(0, BY - 1, SX, 1, P.line)

  local label = 'CONTRACT ' .. c.index .. '/' .. run:total()
  UI.text(label, 3, 3, P.text)
  if c.boss then
    UI.text('BOSS: ' .. c.boss.name, 3 + Font.width(label) + 8, 3, P.red)
    if UI.inside(0, 0, SX, 9) then
      UI.tip = { title = c.boss.name, color = P.red, lines = { c.boss.desc } }
    end
  end

  local building = g.mode == 'build' or g.mode == 'intro'
  local shiftNo = min(rules.shifts, run.shiftsUsed + (building and 1 or 0))
  UI.textRight('SHIFT ' .. shiftNo .. '/' .. rules.shifts, SX - 4, 3, P.dim)

  local earned = run.progress + ((g.mode == 'run') and F.shift.revenue or 0)
  local bw = 112
  UI.rect(3, 11, bw, 6, P.bg)
  UI.rect(3, 11, floor(bw * min(1, earned / c.quota)), 6, earned >= c.quota and P.green or P.gold)
  UI.frame(3, 11, bw, 6, P.line)
  UI.text('$' .. earned .. '/' .. c.quota, 3 + bw + 4, 11, earned >= c.quota and P.green or P.text)

  local tick = (g.mode == 'run' or g.mode == 'summary') and F.shift.tick or 0
  UI.textRight(tick .. '/' .. rules.shiftLen .. 'S', SX - 4, 11, g.mode == 'run' and P.text or P.dim)
end

---------------------------------------------------------------- drawing: sidebar

local function drawSidebar(app)
  local g, run = app.g, app.run
  local F = run.factory
  local rules = run.rules
  UI.rect(SX, 0, 96, 180, P.panel)
  UI.rect(SX, 0, 1, 180, P.line)

  UI.text('$' .. run.credits, SX + 4, 3, P.gold)
  UI.textRight('SEED ' .. run.seed, 317, 3, P.faint)

  -- Power.
  local live = g.mode == 'run' or g.mode == 'summary'
  local supply, demand
  if live then
    supply, demand = F.shift.supply, F.shift.demand
  else
    supply, demand = rules.basePower, F:plannedDraw(rules)
  end
  local over = demand > supply
  UI.text('POWER ' .. num(demand) .. '/' .. num(supply) .. 'W', SX + 4, 11, over and P.red or P.blue)
  UI.rect(SX + 4, 18, 88, 2, P.bg)
  UI.rect(SX + 4, 18, floor(88 * min(1, demand / max(supply, 1))), 2, over and P.red or P.blue)
  if UI.inside(SX, 9, 96, 13) then
    UI.tip = { title = 'POWER', color = P.blue, lines = {
      'DEMAND / SUPPLY. OVER THE LIMIT, EVERY MACHINE SLOWS DOWN IN PROPORTION.' } }
  end

  -- Kit palette.
  local entries = {}
  for _, kind in ipairs(Machines.list) do
    if Machines[kind].free or (run.kit[kind] or 0) > 0 then entries[#entries + 1] = kind end
  end
  g.entries = entries
  for i, kind in ipairs(entries) do
    local x = SX + 3 + ((i - 1) % 4) * 23
    local y = 24 + floor((i - 1) / 4) * 21
    local avail = run:available(kind)
    local sel = g.tool == kind
    UI.rect(x, y, 22, 20, sel and P.line or P.panel2)
    if sel then UI.frame(x, y, 22, 20, P.yellow) end
    UI.sprite(Sprites.machine[kind], x + 3, y + 2, 0, avail > 0 and 1 or 0.3)
    if avail ~= math.huge then
      local label = tostring(avail)
      local w = Font.width(label)
      UI.rect(x + 19 - w, y + 13, w + 2, 7, P.dark)
      UI.text(label, x + 20 - w, y + 14, avail > 0 and P.text or P.red)
    end
    if UI.inside(x, y, 22, 20) then
      local tip = kindTip(kind)
      tip.lines[#tip.lines + 1] = 'KEY ' .. i
      UI.tip = tip
    end
    if g.mode == 'build' and UI.clicked(x, y, 22, 20) then
      g.tool = (not sel and avail > 0) and kind or nil
    end
  end

  -- Upgrades.
  UI.text('UPGRADES', SX + 4, 89, P.dim)
  for i = 1, Contracts.upgradeSlots do
    local x, y = SX + 3 + (i - 1) * 18, 96
    local id = run.upgrades[i]
    if id then
      local def = Upgrades.byId[id]
      UI.card(def, x, y)
      if UI.inside(x, y, 16, 16) then UI.tip = upgradeTip(def) end
    else
      UI.emptySlot(x, y)
    end
  end

  -- Tooltip box.
  UI.panel(SX + 3, 115, 90, 46, P.bg, P.faint)
  local tip = UI.tip or defaultTip(app)
  UI.text(tip.title, SX + 6, 118, tip.color or P.text)
  local y = 126
  for _, s in ipairs(tip.lines) do
    if s and y < 156 then y = UI.paragraph(s, SX + 6, y, 21, P.dim) end
  end

  -- Controls.
  if g.mode == 'build' then
    if UI.button('RUN SHIFT', SX + 3, 164, 64, 13, { color = P.green }) then startShift(app) end
    if UI.button('?', SX + 70, 164, 23, 13) then g.book = true end
  elseif g.mode == 'run' then
    for i, s in ipairs({ 1, 2, 4 }) do
      if UI.button(s .. 'X', SX + 3 + (i - 1) * 21, 164, 19, 13, { active = g.speed == s and not g.paused, color = P.blue }) then
        g.speed, g.paused = s, false
      end
    end
    if UI.button('SKIP', SX + 66, 164, 27, 13) then skipShift(app) end
  end
end

---------------------------------------------------------------- drawing: overlays

local function dim()
  UI.rect(0, BY, SX, 160, P.dark, 0.6)
end

local function drawIntro(app)
  local g, run = app.g, app.run
  local c, rules = run:contract(), run.rules
  dim()
  local w, h = 188, 108
  local x, y = floor((SX - w) / 2), 46
  local cx = x + w / 2
  UI.panel(x, y, w, h, P.panel, c.boss and P.red or P.line)
  UI.textCenter('CONTRACT ' .. c.index .. ' OF ' .. run:total(), cx, y + 6, P.dim)
  UI.textCenter('QUOTA $' .. c.quota, cx, y + 15, P.gold, 2)
  UI.textCenter(rules.shifts .. ' SHIFTS OF ' .. rules.shiftLen .. ' SECONDS', cx, y + 30, P.text)
  local yy = y + 42
  if c.index == 1 then
    for _, line in ipairs(Font.wrap('LAY BELTS FROM THE PORTS ON THE LEFT TO THE EXPORT ON THE RIGHT. '
        .. 'MACHINES IN BETWEEN ADD VALUE.', 42)) do
      UI.textCenter(line, cx, yy, P.dim)
      yy = yy + 7
    end
  elseif c.newSector then
    UI.textCenter('NEW SECTOR: THE PORTS HAVE CHANGED', cx, yy, P.cyan)
    yy = yy + 10
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
  local x, y = floor((SX - w) / 2), 31
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
  local shown = min(#order, 6)
  for i = 1, shown do
    local t = order[i]
    local rec = s.sold[t]
    UI.sprite(Sprites.item[t], x + 8, yy - 1)
    UI.text(Items[t].name, x + 20, yy + 1, P.dim)
    UI.textRight('X' .. rec.n, x + 130, yy + 1, P.text)
    UI.textRight('$' .. rec.total, x + w - 8, yy + 1, P.text)
    yy = yy + 9
  end
  if #order > shown then
    UI.text('+ ' .. (#order - shown) .. ' MORE TYPES', x + 20, yy + 1, P.faint)
    yy = yy + 9
  elseif #order == 0 then
    UI.textCenter('NOTHING WAS SOLD', cx, yy + 1, P.faint)
    yy = yy + 9
  end
  UI.rect(x + 8, yy + 1, w - 16, 1, P.line)
  yy = yy + 5
  for _, note in ipairs(s.notes) do
    UI.text(note[1], x + 8, yy, P.purple)
    UI.textRight(note[2], x + w - 8, yy, P.purple)
    yy = yy + 8
  end
  UI.text('SHIFT TOTAL', x + 8, yy, P.text)
  UI.textRight('$' .. s.total, x + w - 8, yy, P.gold)
  yy = yy + 9
  local met = run.progress >= c.quota
  UI.text('CONTRACT', x + 8, yy, P.dim)
  UI.textRight('$' .. run.progress .. ' / $' .. c.quota, x + w - 8, yy, met and P.green or P.text)

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
  local x, y = floor((SX - w) / 2), 58
  local cx = x + w / 2
  UI.panel(x, y, w, h, P.panel, won and P.gold or P.red)
  if won then
    UI.textCenter('ALL QUOTAS MET', cx, y + 10, P.gold, 2)
    UI.textCenter('THE FACTORY IS YOURS.', cx, y + 28, P.text)
  else
    UI.textCenter('RUN OVER', cx, y + 10, P.red, 2)
    UI.textCenter('STOPPED AT CONTRACT ' .. run.index .. ' OF ' .. run:total(), cx, y + 28, P.text)
    UI.textCenter('$' .. run.progress .. ' OF $' .. run:contract().quota, cx, y + 37, P.dim)
  end
  UI.textCenter('SEED ' .. run.seed, cx, y + 48, P.faint)
  if UI.button('TITLE', cx - 30, y + h - 19, 60, 13, { color = P.green }) then app.toTitle() end
end

function Game.draw(app)
  local g = app.g
  drawBoard(app)
  drawTopBar(app)
  drawSidebar(app)
  if g.mode == 'run' and g.paused then
    UI.textCenter('PAUSED', SX / 2, BY + 4, P.yellow)
  end
  if g.mode == 'intro' then drawIntro(app)
  elseif g.mode == 'summary' then drawSummary(app)
  elseif g.mode == 'over' then drawEnd(app, false)
  elseif g.mode == 'win' then drawEnd(app, true) end
  if g.book then Book.draw(app) end
end

---------------------------------------------------------------- input

function Game.press(app, x, y, b)
  local g = app.g
  if g.book then g.book = false; return end
  local cx, cy = cellAt(x, y)
  if g.mode ~= 'build' or not cx then
    if b == 2 and g.mode == 'build' then g.tool = nil end
    UI.click = { x = x, y = y, b = b }
    return
  end
  local F = app.run.factory
  if b == 1 then
    if g.tool then
      placeAt(app, g.tool, cx, cy, g.dir)
      g.drag = { x = cx, y = cy, tool = g.tool }
      if g.tool ~= 'belt' and app.run:available(g.tool) <= 0 then g.tool = nil end
    else
      local e = F:at(cx, cy)
      if e and not e.building.fixed then       -- pick it up to move it
        g.tool, g.dir = e.building.kind, e.building.dir
        F:remove(cx, cy)
      end
    end
  elseif b == 2 then
    F:remove(cx, cy)
    g.drag = { x = cx, y = cy, erase = true }
  end
end

function Game.release(app)
  app.g.drag = nil
end

function Game.moved(app, x, y)
  local g = app.g
  local d = g.drag
  if not d or g.mode ~= 'build' then return end
  local cx, cy = cellAt(x, y)
  if not cx then return end
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

function Game.wheel(app, dy)
  rotate(app, dy > 0 and 3 or 1)
end

function Game.key(app, key)
  local g = app.g
  if key == 'tab' then g.book = not g.book; return end
  if g.book then
    if key == 'escape' then g.book = false end
    return
  end
  if g.mode == 'intro' then
    if key == 'space' or key == 'return' then g.mode = 'build' end
  elseif g.mode == 'build' then
    if key == 'r' then rotate(app, 1)
    elseif key == 'escape' or key == 'q' then g.tool = nil
    elseif key == 'space' or key == 'return' then startShift(app)
    elseif key == 'x' then clearBoard(app)
    else
      local n = tonumber(key)
      local kind = n and g.entries and g.entries[n]
      if kind then
        g.tool = (g.tool ~= kind and app.run:available(kind) > 0) and kind or nil
      end
    end
  elseif g.mode == 'run' then
    if key == 'space' then g.paused = not g.paused
    elseif key == '1' then g.speed, g.paused = 1, false
    elseif key == '2' then g.speed, g.paused = 2, false
    elseif key == '3' then g.speed, g.paused = 4, false
    elseif key == '4' or key == 'return' then skipShift(app) end
  elseif g.mode == 'summary' then
    if key == 'space' or key == 'return' then afterSummary(app) end
  end
end

-- Exposed for the screenshot script.
Game.startShift, Game.skipShift, Game.afterSummary, Game.placeAt = startShift, skipShift, afterSummary, placeAt

return Game
