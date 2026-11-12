-- One run: the factory, the kit, upgrades, credits and contract progress.

local Factory = require 'src.sim.factory'
local Rules = require 'src.rules'
local Rng = require 'src.rng'
local Machines = require 'src.data.machines'
local Upgrades = require 'src.data.upgrades'
local Contracts = require 'src.data.contracts'

local Run = {}
Run.__index = Run

function Run.new(seed)
  local r = setmetatable({}, Run)
  r.seed = seed
  r.layoutRng = Rng.new(seed * 7 + 1)
  r.shopRng = Rng.new(seed * 13 + 5)
  r.credits = Contracts.startCredits
  r.kit = {}
  for k, n in pairs(Contracts.startKit) do r.kit[k] = n end
  r.upgrades = {}            -- upgrade ids, in slot order
  r.index = 1                -- current contract
  r.progress = 0             -- revenue banked on the current contract
  r.shiftsUsed = 0
  r.factory = Factory.new()
  r.won, r.lost = false, false
  r.shop = nil

  -- One boss per sector, fixed by the seed.
  local pool = {}
  for i, b in ipairs(Contracts.bosses) do pool[i] = b end
  Rng.new(seed * 3 + 11):shuffle(pool)
  r.bosses = {}
  for s = 1, math.ceil(#Contracts.quotas / Contracts.perSector) do r.bosses[s] = pool[s] end

  r:startContract()
  return r
end

function Run:total() return #Contracts.quotas end

function Run:contract(index)
  index = index or self.index
  local per = Contracts.perSector
  local sector = math.ceil(index / per)
  local isBoss = index % per == 0
  return {
    index = index, sector = sector, isBoss = isBoss,
    boss = isBoss and self.bosses[sector] or nil,
    quota = Contracts.quotas[index],
    newSector = index % per == 1,
  }
end

-- Active rule set: upgrades left to right, then the boss twist.
function Run:refreshRules()
  local mods = {}
  for _, id in ipairs(self.upgrades) do mods[#mods + 1] = Upgrades.byId[id] end
  local c = self:contract()
  if c.boss then mods[#mods + 1] = c.boss end
  self.rules = Rules.new(mods)
  return self.rules
end

---------------------------------------------------------------- board setup

-- Pick `n` rows with at least one free row between them.
local function pickRows(rng, n, H)
  for _ = 1, 50 do
    local rows, ok = {}, true
    for i = 1, n do rows[i] = rng:int(0, H - 1) end
    table.sort(rows)
    for i = 2, n do
      if rows[i] - rows[i - 1] < 2 then ok = false end
    end
    if ok then return rows end
  end
  local rows = {}
  for i = 1, n do rows[i] = (i - 1) * 2 end
  return rows
end

function Run:rollPorts(sector)
  local F, rng = self.factory, self.layoutRng
  -- Out with the old ports.
  for y = 0, Factory.H - 1 do
    for x = 0, Factory.W - 1 do
      local e = F:at(x, y)
      if e and (e.port or e.export) then F:remove(x, y, true) end
    end
  end
  local spec = Contracts.sectorPorts[math.min(sector, #Contracts.sectorPorts)]
  local items = {}
  for i, entry in ipairs(spec) do
    items[i] = type(entry) == 'table' and rng:pick(entry) or entry
  end
  rng:shuffle(items)
  local rows = pickRows(rng, #items, Factory.H)
  for i, item in ipairs(items) do
    if F:at(0, rows[i]) then F:remove(0, rows[i], true) end
    F:place('port', 0, rows[i], 0, { item = item })
  end
  local ey = rng:int(1, Factory.H - 2)
  if F:at(Factory.W - 1, ey) then F:remove(Factory.W - 1, ey, true) end
  F:place('export', Factory.W - 1, ey, 2)
end

function Run:clearRubble()
  local F = self.factory
  for y = 0, Factory.H - 1 do
    for x = 0, Factory.W - 1 do
      local e = F:at(x, y)
      if e and e.rubble then F:remove(x, y, true) end
    end
  end
end

function Run:placeRubble(n)
  local F, rng = self.factory, self.layoutRng
  local placed, guard = 0, 0
  while placed < n and guard < 500 do
    guard = guard + 1
    local x, y = rng:int(1, Factory.W - 2), rng:int(0, Factory.H - 1)
    local e = F:at(x, y)
    if not e or not e.building.fixed then
      if e then F:remove(x, y) end     -- the piece goes back to the kit
      F:place('rubble', x, y, 0)
      placed = placed + 1
    end
  end
end

function Run:startContract()
  self.progress = 0
  self.shiftsUsed = 0
  local c = self:contract()
  self:clearRubble()
  if c.newSector then self:rollPorts(c.sector) end
  if c.boss and c.boss.rubble then self:placeRubble(c.boss.rubble) end
  self:refreshRules()
end

---------------------------------------------------------------- kit

-- Pieces of `kind` still in the box. Belts are unlimited.
function Run:available(kind)
  if Machines[kind].free then return math.huge end
  local placed = self.factory:counts()[kind] or 0
  return (self.kit[kind] or 0) - placed
end

function Run:unplaced()
  local counts, n = self.factory:counts(), 0
  for kind, owned in pairs(self.kit) do
    n = n + math.max(0, owned - (counts[kind] or 0))
  end
  return n
end

---------------------------------------------------------------- shifts

function Run:shiftsLeft()
  return math.max(0, self.rules.shifts - self.shiftsUsed)
end

function Run:beginShift()
  self.shiftsUsed = self.shiftsUsed + 1
  self.factory:beginShift(self:refreshRules(), { unplaced = self:unplaced() })
end

-- Returns the shift summary with .status = 'next' | 'cleared' | 'failed'.
function Run:endShift()
  local s = self.factory:endShift()
  self.progress = self.progress + s.total
  local quota = self:contract().quota
  if self.progress >= quota then
    s.status = 'cleared'
  elseif self:shiftsLeft() > 0 then
    s.status = 'next'
  else
    s.status = 'failed'
    self.lost = true
  end
  return s
end

-- Pay out the cleared contract. Returns the breakdown.
function Run:payout()
  local R = Contracts.reward
  local c = self:contract()
  local p = {
    base = c.isBoss and R.boss or R.normal,
    unused = self:shiftsLeft() * R.perUnusedShift,
    interest = math.min(R.interestCap, math.floor(self.credits / R.interestPer)),
  }
  p.total = p.base + p.unused + p.interest
  self.credits = self.credits + p.total
  self.lastPayout = p
  return p
end

-- Move on after the shop. Sets self.won after the last contract.
function Run:advance()
  if self.index >= self:total() then
    self.won = true
    return
  end
  self.index = self.index + 1
  self:startContract()
end

---------------------------------------------------------------- shop

function Run:rollShop()
  local rng = self.shopRng
  local offers = {}
  local pool = {}
  for _, kind in ipairs(Machines.list) do
    local def = Machines[kind]
    if def.cost then pool[#pool + 1] = { kind, def.weight or 1 } end
  end
  for _ = 1, 2 do
    local kind = rng:weighted(pool)
    offers[#offers + 1] = { type = 'machine', id = kind, cost = Machines[kind].cost }
  end
  local owned = {}
  for _, id in ipairs(self.upgrades) do owned[id] = true end
  local ups = {}
  for _, u in ipairs(Upgrades.list) do
    if not owned[u.id] then ups[#ups + 1] = u end
  end
  rng:shuffle(ups)
  for i = 1, math.min(2, #ups) do
    offers[#offers + 1] = { type = 'upgrade', id = ups[i].id, cost = ups[i].cost }
  end
  self.shop = self.shop or { rerolls = 0 }
  self.shop.offers = offers
  return self.shop
end

function Run:openShop()
  self.shop = { rerolls = 0 }
  return self:rollShop()
end

function Run:rerollCost()
  return Contracts.rerollCost + self.shop.rerolls
end

function Run:reroll()
  local cost = self:rerollCost()
  if self.credits < cost then return false end
  self.credits = self.credits - cost
  self.shop.rerolls = self.shop.rerolls + 1
  self:rollShop()
  return true
end

-- Why offer i cannot be bought, or nil if it can.
function Run:buyBlocked(i)
  local o = self.shop.offers[i]
  if not o or o.sold then return 'sold' end
  if self.credits < o.cost then return 'too expensive' end
  if o.type == 'upgrade' and #self.upgrades >= Contracts.upgradeSlots then return 'slots full' end
  return nil
end

function Run:buy(i)
  if self:buyBlocked(i) then return false end
  local o = self.shop.offers[i]
  self.credits = self.credits - o.cost
  o.sold = true
  if o.type == 'machine' then
    self.kit[o.id] = (self.kit[o.id] or 0) + 1
  else
    self.upgrades[#self.upgrades + 1] = o.id
  end
  self:refreshRules()
  return true
end

function Run:sellUpgrade(slot)
  local id = self.upgrades[slot]
  if not id then return false end
  table.remove(self.upgrades, slot)
  self.credits = self.credits + math.floor(Upgrades.byId[id].cost / 2)
  self:refreshRules()
  return true
end

function Run:sellMachine(kind)
  if (self.kit[kind] or 0) <= 0 then return false end
  -- If every copy is on the board, pull the most recently placed one.
  if self:available(kind) <= 0 then
    local list = self.factory.world:query('building')
    for i = #list, 1, -1 do
      local e = list[i]
      if e.building.kind == kind then
        self.factory:remove(e.pos.x, e.pos.y)
        break
      end
    end
  end
  self.kit[kind] = self.kit[kind] - 1
  self.credits = self.credits + math.floor(Machines[kind].cost / 2)
  return true
end

return Run
