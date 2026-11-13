-- One run: the site and its factory, blueprints, upgrades, credits and
-- contract progress.

local Factory = require 'src.sim.factory'
local Map = require 'src.map'
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
  r.blueprints = {}          -- machine kinds unlocked for the run
  for _, kind in ipairs(Contracts.startBlueprints) do r.blueprints[kind] = true end
  r.power = Contracts.basePower
  r.powerBought = 0
  r.upgrades = {}            -- upgrade ids, in slot order
  r.index = 1                -- current contract
  r.progress = 0             -- revenue banked on the current contract
  r.shiftsUsed = 0
  r.won, r.lost = false, false
  r.shop = nil

  -- The site: one factory for the whole run, growing a plot per contract.
  r.factory = Factory.new(Map.W, Map.H)
  r.map = Map.new()
  local start = Map.generate(r.layoutRng, {
    items = Contracts.startPlot.items, rocks = Contracts.startPlot.rocks, depot = true,
  })
  r.map:annex(start, r.layoutRng:int(1, 2), 1, r.factory)

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

-- Watts the site supplies before any mod: bought power plus power nodes.
function Run:basePower()
  return self.power + self.map:nodes() * Map.NODE_WATTS
end

-- Active rule set: the site's own rules, upgrades left to right, then the
-- boss twist.
function Run:refreshRules()
  local mods = {}
  if self.map.premium > 0 then mods[#mods + 1] = Contracts.premium end
  for _, id in ipairs(self.upgrades) do mods[#mods + 1] = Upgrades.byId[id] end
  local c = self:contract()
  if c.boss then mods[#mods + 1] = c.boss end
  self.rules = Rules.new(mods, { basePower = self:basePower() })
  return self.rules
end

---------------------------------------------------------------- land

-- Can the player build on this tile? Only on plots they own.
function Run:canBuild(x, y)
  return self.map:owned(x, y)
end

-- The plot offered for a contract in this sector.
function Run:rollPlot(sector)
  local rng = self.layoutRng
  local land = Contracts.land[math.min(sector, #Contracts.land)]
  local pool = {}
  for i, item in ipairs(land.resources) do pool[i] = item end
  rng:shuffle(pool)
  local items = {}
  for i = 1, rng:int(land.ports[1], land.ports[2]) do items[i] = pool[(i - 1) % #pool + 1] end
  local special
  if rng:int(1, 100) <= Contracts.specialChance then special = rng:pick(Contracts.specials) end
  return Map.generate(rng, {
    items = items, rocks = rng:int(land.rocks[1], land.rocks[2]), special = special,
  })
end

-- Put the pending plot into a free slot touching the land already owned.
function Run:annex(sx, sy)
  if not self.pendingPlot or not self.map:canAnnex(sx, sy) then return false end
  self.map:annex(self.pendingPlot, sx, sy, self.factory)
  self.pendingPlot = nil
  self:refreshRules()
  return true
end

function Run:clearRubble()
  local F = self.factory
  local list = F.world:query('rubble')
  for i = #list, 1, -1 do F:remove(list[i].pos.x, list[i].pos.y, true) end
end

-- Bury n tiles of owned land. Whatever stood there is removed.
function Run:placeRubble(n)
  local F, rng = self.factory, self.layoutRng
  local placed, guard = 0, 0
  while placed < n and guard < 2000 do
    guard = guard + 1
    local x, y = rng:int(0, Map.W - 1), rng:int(0, Map.H - 1)
    local e = F:at(x, y)
    if self.map:owned(x, y) and (not e or not e.building.fixed) then
      if e then F:remove(x, y) end
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
  -- Every contract after the first comes with new land, while there is room.
  self.pendingPlot = nil
  if c.index > 1 and #self.map:free() > 0 then self.pendingPlot = self:rollPlot(c.sector) end
  if c.boss and c.boss.rubble then self:placeRubble(c.boss.rubble) end
  self:refreshRules()
end

---------------------------------------------------------------- blueprints

-- Can this kind be built? Logistics are free; machines need their blueprint.
function Run:unlocked(kind)
  local def = Machines[kind]
  return def ~= nil and not def.fixed and (def.free or self.blueprints[kind]) and true or false
end

-- The kinds the player can build, in palette order.
function Run:palette()
  local list = {}
  for _, kind in ipairs(Machines.list) do
    if self:unlocked(kind) then list[#list + 1] = kind end
  end
  return list
end

---------------------------------------------------------------- shifts

function Run:shiftsLeft()
  return math.max(0, self.rules.shifts - self.shiftsUsed)
end

function Run:beginShift()
  self.shiftsUsed = self.shiftsUsed + 1
  self.factory:beginShift(self:refreshRules())
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

-- 2 blueprints not owned yet (fewer when they run out) and 2 upgrades.
function Run:rollShop()
  local rng = self.shopRng
  local offers = {}
  local pool = {}
  for _, kind in ipairs(Machines.list) do
    local def = Machines[kind]
    if def.cost and not self.blueprints[kind] then pool[#pool + 1] = { kind, def.weight or 1 } end
  end
  for _ = 1, math.min(2, #pool) do
    local kind = rng:weighted(pool)
    for i, entry in ipairs(pool) do
      if entry[1] == kind then table.remove(pool, i); break end
    end
    offers[#offers + 1] = { type = 'blueprint', id = kind, cost = Machines[kind].cost }
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
  if o.type == 'blueprint' then
    self.blueprints[o.id] = true
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

-- Power is bought in steps; each one costs a credit more than the last.
function Run:powerCost()
  return Contracts.powerCost + self.powerBought
end

function Run:buyPower()
  local cost = self:powerCost()
  if self.credits < cost then return false end
  self.credits = self.credits - cost
  self.powerBought = self.powerBought + 1
  self.power = self.power + Contracts.powerStep
  self:refreshRules()
  return true
end

return Run
