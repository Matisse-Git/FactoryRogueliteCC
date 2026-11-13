-- The factory: an ECS world laid out on a grid, plus the per-shift state.
-- No love.graphics in here, so it runs headless for the tests.
--
-- Tick order: cleanup -> ports -> power -> machines -> transfer -> oven.
--
-- A shift starts warm: the factory runs for WARMUP ticks first, with nothing
-- sold or counted, so the measured shift is the steady state and what a
-- layout earns is its rates times the length of the shift.

local ECS = require 'src.ecs'
local D = require 'src.sim.dirs'
local Machines = require 'src.data.machines'
local Upgrades = require 'src.data.upgrades'
local Rules = require 'src.rules'
local Machine = require 'src.sim.machine'
local Transfer = require 'src.sim.transfer'

local Factory = {}
Factory.__index = Factory
Factory.W, Factory.H = 14, 10      -- default board size
Factory.WARMUP = 150               -- ticks run before the clock starts
Factory.BUSY = 0.9                 -- share of a shift a machine must work to count as "non-stop"

---------------------------------------------------------------- systems

-- Items that entered a machine or the export last tick disappear now.
local function cleanupSystem(world)
  local items = world:query('item')
  for i = 1, #items do
    if items[i].gone then world:despawn(items[i]) end
  end
end

local function portSystem(world)
  local ports = world:query('port')
  for i = 1, #ports do
    local e = ports[i]
    local p = e.port
    if p.cd > 0 then p.cd = p.cd - 1 end
    if p.cd == 0 and not e.slot.item then
      e.slot.item = world:spawn({
        item = { type = p.item, polished = 0, dist = 0 },
        pos = { x = e.pos.x, y = e.pos.y },
        prev = { x = e.pos.x, y = e.pos.y },
        hidden = true,
      })
      p.cd = p.period
    end
  end
end

-- Supply = board + burning generators. Demand = machines mid-craft.
-- When demand exceeds supply every machine slows down in proportion.
local function powerSystem(world, F)
  local supply, demand = F.rules.basePower, 0
  local machines = world:query('machine')
  for i = 1, #machines do
    local m = machines[i].machine
    if m.def.generator then
      if m.burn > 0 then supply = supply + m.def.generator.watts end
    elseif m.craft then
      demand = demand + m.draw
    end
  end
  local s = F.shift
  s.supply, s.demand = supply, demand
  s.factor = (demand > supply) and (supply / demand) or 1
  s.supplySum = s.supplySum + supply
  s.demandSum = s.demandSum + math.min(demand, supply)
end

local function machineSystem(world, F)
  local machines = world:query('machine')
  for i = 1, #machines do Machine.update(F, machines[i]) end
end

-- Conveyor Oven upgrade: ore on a belt next to a burning generator smelts.
local function ovenSystem(world, F)
  if not F.rules.oven then return end
  for i = 1, #F.ovenBelts do
    local pair = F.ovenBelts[i]
    local it = pair.slot.item
    if it and pair.gen.machine.burn > 0 then
      local ingot = Upgrades.INGOT_OF[it.item.type]
      if ingot then
        it.item.type = ingot
        local pos = pair.slot.e.pos
        F:trigger(F.rules.owner.oven, pos.x, pos.y, 0, 'smelt')
      end
    end
  end
end

---------------------------------------------------------------- factory

function Factory.new(w, h)
  local F = setmetatable({}, Factory)
  F.W, F.H = w or Factory.W, h or Factory.H
  F.world = ECS.world()
  F.grid = {}
  F.slots = {}
  F.events = {}
  F.ovenBelts = {}
  F.recipes = {}
  F.rules = Rules.new({})
  local world = F.world
  world:addSystem('tick', cleanupSystem)
  world:addSystem('tick', portSystem)
  world:addSystem('tick', powerSystem)
  world:addSystem('tick', machineSystem)
  world:addSystem('tick', Transfer.system)
  world:addSystem('tick', ovenSystem)
  return F
end

function Factory:inBounds(x, y)
  return x >= 0 and y >= 0 and x < self.W and y < self.H
end

function Factory:at(x, y)
  if x < 0 or y < 0 or x >= self.W or y >= self.H then return nil end
  return self.grid[y * self.W + x]
end

-- Spawn a building entity. The tile must be empty.
function Factory:place(kind, x, y, dir, extra)
  assert(self:inBounds(x, y) and not self:at(x, y), 'tile not free')
  local def = Machines[kind]
  extra = extra or {}
  local e = {
    pos = { x = x, y = y },
    building = { kind = kind, dir = dir or 0, fixed = def.fixed or false },
  }
  if kind == 'belt' then
    e.belt = true
    e.slot = Transfer.newSlot(e, 'belt')
  elseif kind == 'bridge' then
    e.bridge = { lanes = { Transfer.newSlot(e, 'lane'), Transfer.newSlot(e, 'lane') } }
  elseif kind == 'splitter' then
    e.splitter = { ptr = 1, count = 0 }
    e.slot = Transfer.newSlot(e, 'split')
  elseif kind == 'port' then
    e.port = { item = extra.item, period = extra.period or 2, cd = 0, sent = 0 }
    e.slot = Transfer.newSlot(e, 'port')
  elseif kind == 'export' then
    e.export = { cd = 0, taken = 0, sold = 0, log = {} }
  elseif kind == 'rubble' then
    e.rubble = true
  else
    e.machine = { def = def }
    if not def.generator then e.slot = Transfer.newSlot(e, 'out') end
    Machine.reset(e)
  end
  self.world:spawn(e)
  self.grid[y * self.W + x] = e
  return e
end

-- Remove the building on a tile. Returns its kind and direction.
function Factory:remove(x, y, evenFixed)
  local e = self:at(x, y)
  if not e or (e.building.fixed and not evenFixed) then return nil end
  self.world:despawn(e)
  self.grid[y * self.W + x] = nil
  return e.building.kind, e.building.dir
end

-- How many of each kind are on the board.
function Factory:counts()
  local c = {}
  local list = self.world:query('building')
  for i = 1, #list do
    local k = list[i].building.kind
    c[k] = (c[k] or 0) + 1
  end
  return c
end

function Factory:clearItems()
  local items = self.world:query('item')
  for i = 1, #items do self.world:despawn(items[i]) end
  local list = self.world:query('building')
  for i = 1, #list do
    local e = list[i]
    if e.slot then e.slot.item = nil; e.slot.dup = false end
    if e.bridge then e.bridge.lanes[1].item = nil; e.bridge.lanes[2].item = nil end
    if e.machine then e.machine.outq = {} end
  end
end

-- Watts the placed machines would draw if all of them were crafting.
function Factory:plannedDraw(rules)
  local total = 0
  local machines = self.world:query('machine')
  for i = 1, #machines do
    local e = machines[i]
    if not e.machine.def.generator then
      total = total + rules:draw(self, e, e.machine.def.draw or 0)
    end
  end
  return total
end

local function newShift(rules, ledger)
  return {
    tick = 0, len = rules.shiftLen,
    revenue = 0, plain = 0, sales = 0, sold = {}, order = {},
    supply = rules.basePower, demand = 0, factor = 1,
    supplySum = 0, demandSum = 0,
    ledger = ledger,
  }
end

-- info.warm overrides the number of warm-up ticks (0 = a cold start).
function Factory:beginShift(rules, info)
  self.rules = rules
  self.shiftId = (self.shiftId or 0) + 1
  self:clearItems()

  self.recipes = {}
  for _, kind in ipairs(Machines.list) do
    self.recipes[kind] = rules:recipesFor(kind)
  end

  -- What each mod did this shift: $ credited and how often it triggered.
  local ledger = {}
  for _, m in ipairs(rules.mods) do ledger[m] = { delta = 0, n = 0 } end

  self.slots = {}
  self.ovenBelts = {}
  local list = self.world:query('building')
  for i = 1, #list do
    local e = list[i]
    if e.slot then
      e.slot.rr = 0
      self.slots[#self.slots + 1] = e.slot
    end
    if e.bridge then
      for l = 1, 2 do
        e.bridge.lanes[l].rr = 0
        self.slots[#self.slots + 1] = e.bridge.lanes[l]
      end
    end
    if e.splitter then e.splitter.ptr = 1; e.splitter.count = 0 end
    if e.port then e.port.cd = 0; e.port.sent = 0 end
    if e.export then e.export.cd = 0; e.export.sold = 0; e.export.log = {} end
    if e.machine then
      Machine.reset(e)
      e.machine.shiftId = self.shiftId
      e.machine.speed = rules:speed(self, e)
      e.machine.draw = rules:draw(self, e, e.machine.def.draw or 0)
      -- Mods that change this machine where it stands count once per machine.
      e.machine.mods = rules:affecting(self, e)
      for _, m in ipairs(e.machine.mods or {}) do ledger[m].n = ledger[m].n + 1 end
      if e.machine.def.generator then
        for d = 0, 3 do
          local n = self:at(e.pos.x + D.DX[d], e.pos.y + D.DY[d])
          if n and n.belt then
            self.ovenBelts[#self.ovenBelts + 1] = { slot = n.slot, gen = e }
          end
        end
      end
    end
  end

  self.shift = newShift(rules, ledger)
  self.events = {}
  rules:resetShift()

  local warm = info and info.warm or Factory.WARMUP
  if warm > 0 then
    -- Run until the factory is flowing; nothing is sold or counted.
    self.shift.warming = true
    for _ = 1, warm do self.world:run('tick', self) end
    self.shift.warming = nil
  end
  self:zeroCounters()
end

-- Start the clock from zero, with whatever is on the belts left there.
function Factory:zeroCounters()
  local s = self.shift
  s.tick, s.supplySum, s.demandSum = 0, 0, 0
  local list = self.world:query('building')
  for i = 1, #list do
    local e = list[i]
    if e.slot then e.slot.passed = 0 end
    if e.bridge then e.bridge.lanes[1].passed = 0; e.bridge.lanes[2].passed = 0 end
    if e.port then e.port.sent = 0 end
    if e.export then e.export.sold = 0; e.export.log = {} end
    if e.machine then
      local m = e.machine
      m.made, m.idle, m.busy = 0, 0, 0
    end
  end
  self.events = {}
  self.rules:resetShift()
end

-- A mod did something at tile (x, y): book it and tell whoever is watching.
-- `what` is 'sale' | 'dup' | 'smelt' | 'craft' | 'polish'. A nil mod (a rule
-- field nobody owns) is ignored, and so is anything during the warm-up.
function Factory:trigger(mod, x, y, delta, what)
  if not mod or self.shift.warming then return end
  local ledger = self.shift.ledger
  local rec = ledger[mod]
  if not rec then
    rec = { delta = 0, n = 0 }
    ledger[mod] = rec
  end
  rec.delta = rec.delta + delta
  rec.n = rec.n + 1
  self.events[#self.events + 1] = { kind = 'trigger', mod = mod, x = x, y = y, delta = delta, what = what }
end

function Factory:step()
  self.events = {}
  self.shift.tick = self.shift.tick + 1
  self.world:run('tick', self)
end

function Factory:finished()
  return self.shift.tick >= self.shift.len
end

function Factory:sell(itemE, exportE)
  local s = self.shift
  if s.warming then return end        -- the warm-up sells nothing
  local value, ctx, fired = self.rules:sale(itemE.item, s.tick, s.len)
  s.revenue = s.revenue + value
  s.plain = s.plain + ctx.plain
  s.sales = s.sales + 1
  local rec = s.sold[ctx.type]
  if not rec then
    rec = { n = 0, total = 0 }
    s.sold[ctx.type] = rec
    s.order[#s.order + 1] = ctx.type
  end
  rec.n = rec.n + 1
  rec.total = rec.total + value
  local ex = exportE.export
  ex.sold = ex.sold + 1
  ex.log[ctx.type] = (ex.log[ctx.type] or 0) + 1
  local x, y = exportE.pos.x, exportE.pos.y
  self.events[#self.events + 1] = { kind = 'sale', x = x, y = y, value = value, fired = fired }
  if fired then
    for i = 1, #fired do self:trigger(fired[i].mod, x, y, fired[i].delta, 'sale') end
  end
end

-- Share of the shift so far that machine entity e spent crafting (0..1), or
-- nil for a generator, a machine placed since the last shift began, or
-- before any tick has run. Stays readable after the shift, while rebuilding.
function Factory:utilisation(e)
  local m = e.machine
  local ticks = self.shift and self.shift.tick or 0
  if not m or m.def.generator or ticks <= 0 or m.shiftId ~= self.shiftId then return nil end
  return math.min(1, (m.busy or 0) / ticks)
end

-- Close the shift: apply end-of-shift rules and return the summary.
function Factory:endShift()
  local s = self.shift
  local perfect, any = true, false
  local lowest
  local machines = self.world:query('machine')
  for i = 1, #machines do
    local e = machines[i]
    local u = self:utilisation(e)
    if u then
      any = true
      if u < Factory.BUSY then perfect = false end
      if not lowest or u < lowest.u then lowest = { u = u, kind = e.building.kind } end
    end
  end
  local ticks = math.max(1, s.tick)
  local supply, demand = s.supplySum / ticks, s.demandSum / ticks
  local sc = {
    revenue = s.revenue, mult = 1, notes = {},
    sold = s.sold, kinds = #s.order,
    perfect = any and perfect,
    spare = math.max(0, supply - demand),
  }
  local results = self.rules:shiftEnd(sc)
  local total = math.floor(s.revenue * sc.mult + 0.5)
  local last
  for _, res in ipairs(results) do
    if res.fired then
      local rec = s.ledger[res.mod]
      rec.delta = rec.delta + res.delta
      rec.n = rec.n + 1
      last = res
    end
  end
  if last then   -- rounding goes to the last multiplier, as it does per sale
    local resid = total - s.revenue * sc.mult
    last.delta = last.delta + resid
    s.ledger[last.mod].delta = s.ledger[last.mod].delta + resid
  end
  -- `plain` + every ledger delta = `total`.
  return {
    base = s.revenue, mult = sc.mult, notes = sc.notes, total = total,
    sold = s.sold, order = s.order, perfect = sc.perfect,
    plain = s.plain, ledger = s.ledger, results = results,
    ticks = s.tick, supply = supply, demand = demand, lowest = lowest,
  }
end

return Factory
