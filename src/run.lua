-- One run: the site and its factory, blueprints, upgrades, credits and
-- contract progress.
--
-- Between contracts: payout -> choose one of two offers (land + market) ->
-- shop -> advance -> place the land -> build.

local Factory = require 'src.sim.factory'
local Map = require 'src.map'
local Market = require 'src.market'
local Rules = require 'src.rules'
local Rng = require 'src.rng'
local Machines = require 'src.data.machines'
local Upgrades = require 'src.data.upgrades'
local Investments = require 'src.data.investments'
local Alternates = require 'src.data.alternates'
local Contracts = require 'src.data.contracts'

local Run = {}
Run.__index = Run

function Run.new(seed)
  local r = setmetatable({}, Run)
  r.seed = seed
  r.layoutRng = Rng.new(seed * 7 + 1)
  r.shopRng = Rng.new(seed * 13 + 5)
  r.marketRng = Rng.new(seed * 17 + 3)
  r.credits = Contracts.startCredits
  r.blueprints = {}          -- machine kinds unlocked for the run
  for _, kind in ipairs(Contracts.startBlueprints) do r.blueprints[kind] = true end
  r.upgrades = {}            -- module ids, in slot order
  r.levels = {}              -- investment id -> level
  r.recipes = {}             -- alternate recipe ids, in the order bought
  r.index = 1                -- current contract
  r.progress = 0             -- revenue banked on the current contract
  r.shiftsUsed = 0
  r.soldValue = {}           -- item -> revenue on the current contract
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

  -- The first contract has no choice: a market the starting kit can fill.
  r.market = Market.roll(r.marketRng, {
    resources = r:resources(), owned = r:kinds(), sector = 1, easy = true,
  })
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
    quota = Contracts.quota(index),
    newSector = index % per == 1,
  }
end

-- Watts the site supplies before any mod: the grid, what was invested in
-- it, and power nodes.
function Run:basePower()
  return Contracts.basePower + Investments.watts(self.levels) + self.map:nodes() * Map.NODE_WATTS
end

-- Active rule set, in the order the rules apply to a sale: the site's own
-- rules, investments, the market, alternate recipes, modules left to right,
-- then the boss twist. A product in demand is tripled after its material
-- bonuses, and a module's multiplier lands on top of both.
function Run:refreshRules()
  local mods = {}
  if self.map.premium > 0 then mods[#mods + 1] = Contracts.premium end
  for _, mod in ipairs(Investments.mods(self.levels)) do mods[#mods + 1] = mod end
  if self.market then mods[#mods + 1] = Market.mod(self.market) end
  for _, id in ipairs(self.recipes) do mods[#mods + 1] = Alternates.byId[id] end
  for _, id in ipairs(self.upgrades) do mods[#mods + 1] = Upgrades.byId[id] end
  local c = self:contract()
  if c.boss then mods[#mods + 1] = c.boss end
  self.rules = Rules.new(mods, { basePower = self:basePower(), portRate = Investments.rates(self.levels) })
  return self.rules
end

---------------------------------------------------------------- land

-- Can the player build on this tile? Only on plots they own.
function Run:canBuild(x, y)
  return self.map:owned(x, y)
end

-- The raw items the site's ports supply, as a set. `plot` adds a plot that
-- is on offer.
function Run:resources(plot)
  local set = {}
  for _, e in ipairs(self.factory.world:query('port')) do set[e.port.item] = true end
  for _, p in ipairs(plot and plot.ports or {}) do set[p.item] = true end
  return set
end

-- The machine kinds the run can build, as a set.
function Run:kinds()
  local set = {}
  for _, kind in ipairs(Machines.list) do
    if self:unlocked(kind) then set[kind] = true end
  end
  return set
end

-- A plot for a contract in this sector.
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
  self.soldValue = {}
  local c = self:contract()
  self:clearRubble()
  if c.boss and c.boss.rubble then self:placeRubble(c.boss.rubble) end
  self:refreshRules()
end

---------------------------------------------------------------- offers

-- The two contracts on offer after the current one: each a plot (while the
-- site has room) and a market. Seen before the shop, so it can be shopped for.
function Run:rollOffers()
  local c = self:contract(self.index + 1)
  local room = #self.map:free() > 0
  local owned = self:kinds()
  local offers = {}
  for i = 1, 2 do
    local plot = room and self:rollPlot(c.sector) or nil
    local resources = self:resources(plot)
    -- From the second sector on something slumps: on one offer the product
    -- you sold most of, on the other any product you can make.
    local slump
    if c.sector >= 2 then slump = (i == 1 and self:topSeller()) or 'random' end
    local market = Market.roll(self.marketRng, {
      resources = resources, owned = owned, sector = c.sector, slump = slump,
    })
    local stretch = 0
    for _, d in ipairs(market.demand) do
      local missing = Market.missing(d.item, resources, owned)
      if missing and #missing > 0 then stretch = stretch + 1 end
    end
    offers[i] = { plot = plot, market = market, bonus = stretch * Contracts.reward.perStretch }
  end
  self.offers, self.chosen = offers, nil
  return offers
end

function Run:choose(i)
  if not self.offers or not self.offers[i] then return false end
  self.chosen = self.offers[i]
  return true
end

-- The item that earned the most on the current contract, or nil.
function Run:topSeller()
  local best, top
  for item, value in pairs(self.soldValue) do
    if not best or value > best or (value == best and item < top) then best, top = value, item end
  end
  return top
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
  self.factory:beginShift(self:refreshRules(), { shiftNo = self.shiftsUsed })
end

-- Returns the shift summary with .status = 'next' | 'cleared' | 'failed'.
function Run:endShift()
  local s = self.factory:endShift()
  self.progress = self.progress + s.total
  for item, rec in pairs(s.sold) do
    self.soldValue[item] = (self.soldValue[item] or 0) + rec.total
  end
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
    stretch = self.bonus or 0,
    overshoot = 0,
    times = self.progress / c.quota,
  }
  for _, step in ipairs(R.overshoot) do
    if p.times >= step[1] then p.overshoot = p.overshoot + step[2] end
  end
  p.total = p.base + p.unused + p.interest + p.stretch + p.overshoot
  self.credits = self.credits + p.total
  self.lastPayout = p
  return p
end

-- Move on to the chosen contract, after the shop. Its land still has to be
-- placed (see Run:annex).
function Run:advance()
  local offer = self.chosen or (self.offers and self.offers[1])
  self.index = self.index + 1
  if offer then
    self.market = offer.market
    self.pendingPlot = offer.plot
    self.bonus = offer.bonus
  end
  self.offers, self.chosen = nil, nil
  self:startContract()
end

---------------------------------------------------------------- shop

function Run:hasRecipe(id)
  for _, r in ipairs(self.recipes) do
    if r == id then return true end
  end
  return false
end

-- One blueprint or alternate recipe, 2 modules, 3 investments.
--   offer = { type = 'blueprint' | 'recipe' | 'upgrade' | 'invest', id, cost, sold }
function Run:rollShop()
  local rng = self.shopRng
  local offers = {}

  -- Slot 1: a machine you cannot build yet, or a new recipe for one you can.
  local pool = {}
  for _, kind in ipairs(Machines.list) do
    local def = Machines[kind]
    if def.cost and not self.blueprints[kind] and (not def.needs or self.blueprints[def.needs]) then
      pool[#pool + 1] = { { type = 'blueprint', id = kind, cost = def.cost }, (def.weight or 1) * 2 }
    end
  end
  for _, alt in ipairs(Alternates.list) do
    if not self:hasRecipe(alt.id) and self:unlocked(alt.kind) then
      pool[#pool + 1] = { { type = 'recipe', id = alt.id, cost = alt.cost }, 2 }
    end
  end
  if #pool > 0 then offers[#offers + 1] = rng:weighted(pool) end

  -- Slots 2-3: modules you do not hold.
  local owned = {}
  for _, id in ipairs(self.upgrades) do owned[id] = true end
  local ups = {}
  for _, u in ipairs(Upgrades.list) do
    if not owned[u.id] then ups[#ups + 1] = { u, Upgrades.WEIGHT[u.rarity] } end
  end
  for _ = 1, math.min(2, #ups) do
    local u = rng:weighted(ups)
    for i, entry in ipairs(ups) do
      if entry[1] == u then table.remove(ups, i); break end
    end
    offers[#offers + 1] = { type = 'upgrade', id = u.id, cost = u.cost }
  end

  -- Slots 4-6: investments that would do something on this site.
  local resources, kinds = self:resources(), self:kinds()
  local inv = {}
  for _, def in ipairs(Investments.list) do
    if Investments.eligible(def, self.levels[def.id] or 0, resources, kinds) then inv[#inv + 1] = def end
  end
  rng:shuffle(inv)
  for i = 1, math.min(3, #inv) do
    offers[#offers + 1] = { type = 'invest', id = inv[i].id, cost = Investments.cost(inv[i], self.levels[inv[i].id] or 0) }
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

-- Why offer i cannot be bought outright, or nil if it can. 'slots full'
-- means a module has to make room: see Run:replaceUpgrade.
function Run:buyBlocked(i)
  local o = self.shop.offers[i]
  if not o or o.sold then return 'sold' end
  if o.type == 'upgrade' and #self.upgrades >= Upgrades.slots then return 'slots full' end
  if self.credits < o.cost then return 'too expensive' end
  return nil
end

function Run:buy(i)
  if self:buyBlocked(i) then return false end
  local o = self.shop.offers[i]
  self.credits = self.credits - o.cost
  o.sold = true
  if o.type == 'blueprint' then
    self.blueprints[o.id] = true
  elseif o.type == 'recipe' then
    self.recipes[#self.recipes + 1] = o.id
  elseif o.type == 'invest' then
    self.levels[o.id] = (self.levels[o.id] or 0) + 1
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
  self.credits = self.credits + Upgrades.refund(Upgrades.byId[id])
  self:refreshRules()
  return true
end

-- Can module offer i take the place of the module in `slot`? The refund
-- for the old one counts towards the price.
function Run:canReplace(slot, i)
  local o, id = self.shop.offers[i], self.upgrades[slot]
  if not o or o.sold or o.type ~= 'upgrade' or not id then return false end
  return self.credits + Upgrades.refund(Upgrades.byId[id]) >= o.cost
end

-- Sell the module in `slot` and put offer i in its place, keeping the order
-- of the others.
function Run:replaceUpgrade(slot, i)
  if not self:canReplace(slot, i) then return false end
  local o = self.shop.offers[i]
  self.credits = self.credits + Upgrades.refund(Upgrades.byId[self.upgrades[slot]]) - o.cost
  self.upgrades[slot] = o.id
  o.sold = true
  self:refreshRules()
  return true
end

return Run
