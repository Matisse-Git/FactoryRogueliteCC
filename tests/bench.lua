-- The balance benchmark. Run with:  lovec . --bench
--
-- Three parts, from the most real to the most modelled:
--
--   1. Real lines in the real simulation, next to what the calculator in
--      tests/plan.lua says they should make and draw. If these agree, the
--      calculator can be trusted for lines too big to lay out by hand.
--   2. Real runs through the Run API with no shopping at all: naive lines
--      (port -> smelter -> press -> depot), every contract until one fails.
--      Shows that the first contracts need no upgrades and the later ones do.
--   3. Reference runs: three styles of player modelled contract by contract
--      (land, credits, purchases, the best factory the site can run), against
--      every quota. This is a model: its assumptions are listed where they
--      are made, and it knows nothing of how hard a layout is to build.
--
-- Returns true if the "solid" reference run clears all 12 contracts and the
-- "lazy" one does not.

local layout = require 'tests.layout'
local Route = require 'tests.route'
local Plan = require 'tests.plan'
local Rules = require 'src.rules'
local Run = require 'src.run'
local Fmt = require 'src.fmt'
local Items = require 'src.data.items'
local Machines = require 'src.data.machines'
local Investments = require 'src.data.investments'
local Contracts = require 'src.data.contracts'

local ALL = {}
for _, kind in ipairs(Machines.list) do ALL[kind] = true end

---------------------------------------------------------------- 1. real lines

local function shift(F, watts)
  F:beginShift(Rules.new({}, { basePower = watts or 1000 }))
  while not F:finished() do F:step() end
  return F:endShift()
end

local LINES = {
  { name = '4 smelters : 3 presses', item = 'gear', rate = 60, rows = {
    '.. s> b> bv .. .. ..',
    'I> y> .. bv .. .. ..',
    '.. s> b> bv p> E< ..',
    '.. .. .. b> y> p> E<',
    '.. s> b> b^ p> E< ..',
    'I> y> .. b^ .. .. ..',
    '.. s> b> b^ .. .. ..',
  } },
  { name = 'motor line', item = 'motor', rate = 10, rows = {
    'I> s> p> b> bv ..',
    '.. .. .. .. a> E<',
    'C> s> w> b> b^ ..',
  } },
  { name = 'steel line', item = 'steel', rate = 12, rows = {
    'I> s> bv ..',
    '.. .. f> E<',
    'K> b> b^ ..',
  } },
  { name = 'lens line', item = 'lens', rate = 15, rows = { 'Q> s> p> E<' } },
}

local function realLines()
  print('1. real lines: simulation against calculator')
  print(string.format('   %-24s %14s %14s', '', 'simulated', 'calculated'))
  local ok = true
  for _, line in ipairs(LINES) do
    local s = shift(layout(line.rows))
    local cost = Plan.cost(line.item, ALL)
    local revenue, watts = line.rate * Items[line.item].value, cost.watts * line.rate
    print(string.format('   %-24s %7s %5.1fW %7s %5.1fW', line.name,
      Fmt.money(s.total), s.demand, Fmt.money(revenue), watts))
    if math.abs(s.total - revenue) > 0.01 * revenue or math.abs(s.demand - watts) > 0.05 * watts + 0.2 then ok = false end
  end
  print(ok and '   they agree.' or '   THEY DISAGREE: do not trust part 3.')
  return ok
end

---------------------------------------------------------------- 2. real runs, no shopping

local function naiveBuild(run)
  local F = run.factory
  for y = 0, F.H - 1 do
    for x = 0, F.W - 1 do F:remove(x, y) end
  end
  for _, port in ipairs(Route.ports(run)) do
    local item = port.port.item
    local machines = (item == 'coal' or item == 'crude') and {} or { 'smelter', 'press' }
    Route.belt(run, port, machines)
  end
end

-- Plays until a quota is missed (or `limit` contracts). Returns the shifts
-- each cleared contract took.
local function naiveRun(seed, limit)
  local run = Run.new(seed)
  local took = {}
  for _ = 1, limit do
    naiveBuild(run)
    local status
    repeat
      run:beginShift()
      while not run.factory:finished() do run.factory:step() end
      status = run:endShift().status
    until status ~= 'next'
    if status ~= 'cleared' then break end
    took[#took + 1] = run.shiftsUsed
    run:payout()
    run:afterContract()
    if run.reward then run.reward = nil end      -- no shopping: not even the free blueprint
    run:choose(1)
    run:advance()
    local slot = run.map:free()[1]
    if slot then run:annex(slot[1], slot[2]) end
  end
  return took
end

local function realRuns()
  print('')
  print('2. real runs with no shopping: port -> smelter -> press -> depot on every ore port')
  local reached = {}
  for seed = 1, 10 do
    local took = naiveRun(seed, 8)
    reached[#reached + 1] = #took
    print(string.format('   seed %-3d clears %d contracts (shifts used: %s)', seed, #took, table.concat(took, ' ')))
  end
  table.sort(reached)
  print(string.format('   worst %d, median %d, best %d contracts cleared without buying anything.',
    reached[1], reached[math.ceil(#reached / 2)], reached[#reached]))
  return reached
end

---------------------------------------------------------------- 3. reference runs

-- Expected land at contract k: ports per raw item, and power nodes.
-- Assumes plots as Contracts.land rolls them, resources evenly spread.
local function landAt(k)
  local ports = {}
  for _, item in ipairs(Plan.RAW) do ports[item] = 0 end
  for _, item in ipairs(Contracts.startPlot.items) do ports[item] = ports[item] + 1 end
  local nodes = 0
  for c = 2, math.min(k, #Contracts.quotas) do
    local land = Contracts.land[math.min(math.ceil(c / Contracts.perSector), #Contracts.land)]
    local n = (land.ports[1] + land.ports[2]) / 2
    for _, item in ipairs(land.resources) do ports[item] = ports[item] + n / #land.resources end
    nodes = nodes + Contracts.specialChance / 100 / #Contracts.specials
  end
  return ports, nodes
end

-- Three styles of player.
--   order    blueprints in the order they are wanted (one per shop at most,
--            plus the free pick after each boss)
--   income   credits per cleared contract in the first sector; later
--            sectors and bosses pay more, as Contracts.reward says
--   power    share of what is left after blueprints that goes into power;
--            the rest goes into the value of the materials being sold
--   modules  what the five module slots multiply revenue by, by contract:
--            the one number here that is a judgement, not a calculation
local PROFILES = {
  {
    name = 'lazy', order = {}, income = 9, power = 0.5,
    modules = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
    note = 'never buys a blueprint or a module; invests in power and value only',
  },
  {
    name = 'solid', income = 11, power = 0.4,
    order = { 'wiremill', 'assembler', 'foundry', 'polisher', 'refinery', 'manufacturer', 'crusher', 'packer' },
    modules = { 1, 1, 1.2, 1.3, 1.5, 1.7, 2, 2.3, 2.7, 3.1, 3.6, 4 },
    note = 'buys depth first, then invests; modules worth x4 by the end',
  },
  {
    name = 'strong', income = 15, power = 0.4,
    order = { 'assembler', 'wiremill', 'foundry', 'polisher', 'manufacturer', 'refinery', 'crusher', 'packer' },
    modules = { 1, 1.2, 1.5, 1.8, 2.2, 2.8, 3.5, 4.5, 5.5, 7, 8, 8 },
    note = 'clears early for more credits; modules that fit the build, worth x8 by the end',
  },
}

local BOSS_COST = 0.75      -- what a boss contract leaves of the revenue, on average
local COAL_TO_POWER = 0.8   -- share of the coal that is burnt (1W per coal a minute)

local function referenceRun(profile)
  local kinds = { smelter = true, press = true }
  for _, kind in ipairs(Machines.list) do
    if Machines[kind].free then kinds[kind] = true end
  end
  local levels, credits, nextBlueprint = {}, Contracts.startCredits, 1
  local topItem
  local rows = {}

  local function unlock()
    local kind = profile.order[nextBlueprint]
    if not kind then return nil end
    kinds[kind] = true
    nextBlueprint = nextBlueprint + 1
    return kind
  end
  local function buyLevel(id)
    local def = Investments.byId[id]
    local level = levels[id] or 0
    if def.max and level >= def.max then return false end
    local cost = Investments.cost(def, level)
    if credits < cost then return false end
    credits, levels[id] = credits - cost, level + 1
    return true
  end

  for k = 1, #Contracts.quotas do
    local sector = math.ceil(k / Contracts.perSector)
    if k > 1 then
      -- The shop after contract k - 1.
      local wasBoss = (k - 1) % Contracts.perSector == 0
      local R = Contracts.reward
      credits = credits + profile.income + R.perSector * (math.ceil((k - 1) / Contracts.perSector) - 1)
        + (wasBoss and R.boss or 0)
      if wasBoss then unlock() end
      local want = profile.order[nextBlueprint]
      if want and credits >= Machines[want].cost then
        credits = credits - Machines[want].cost
        unlock()
      end
      -- Then investments: power up to its share, the rest into the value of
      -- whatever the last factory sold most of, cheapest level first.
      local budget = credits
      local spentPower = 0
      while spentPower < budget * profile.power and buyLevel('power') do
        spentPower = budget - credits
      end
      local mats = topItem and Items[topItem].mats or { 'iron', 'copper' }
      for _ = 1, 40 do
        local best
        for _, mat in ipairs(mats) do
          local id = 'value:' .. mat
          if not best or (levels[id] or 0) < (levels[best] or 0) then best = id end
        end
        if not buyLevel(best) then break end
      end
    end

    local count, nodes = landAt(k)
    local ports, resources = {}, {}
    for item, n in pairs(count) do
      ports[item] = n * 30
      if n >= 0.5 then resources[item] = true end
    end
    local watts = Contracts.basePower + nodes * 12 + Investments.watts(levels) + ports.coal * COAL_TO_POWER
    ports.coal = ports.coal * (1 - COAL_TO_POWER)

    local mult = profile.modules[k]
    local function value(item)
      local v = Items[item].value * mult
      for _, mat in ipairs(Items[item].mats) do
        v = v * Investments.valueFactor(levels['value:' .. mat] or 0)
      end
      return v
    end

    -- The best factory the site can run. Prices never move, so it is the
    -- same factory, grown, from one contract to the next.
    local revenue, lines = Plan.best({
      kinds = kinds, watts = watts, ports = ports, value = value, polish = kinds.polisher,
    })
    if k % Contracts.perSector == 0 then revenue = revenue * BOSS_COST end
    topItem = lines[1] and lines[1].item or topItem
    rows[k] = { revenue = revenue, top = topItem, watts = watts }
  end
  return rows
end

local function referenceRuns()
  print('')
  print('3. reference runs (a model: see tests/bench.lua for what it assumes)')
  local runs = {}
  for i, profile in ipairs(PROFILES) do
    runs[i] = referenceRun(profile)
    print(string.format('   %-7s %s', profile.name, profile.note))
  end
  print('')
  print('   revenue per shift, and how many of the 3 shifts the quota takes (- = missed)')
  print(string.format('   %-3s %8s  %-17s %-17s %-17s %s', '', 'quota', 'lazy', 'solid', 'strong', 'solid sells / has'))
  local clears = {}
  for k = 1, #Contracts.quotas do
    local quota = Contracts.quota(k)
    local cells = {}
    for i, rows in ipairs(runs) do
      local need = quota / rows[k].revenue
      clears[i] = (clears[i] == nil or clears[i]) and need <= Contracts.shifts
      cells[i] = string.format('%7s %-9s', Fmt.money(rows[k].revenue),
        need <= Contracts.shifts and string.format('(%.1f)', need) or '(-)')
    end
    print(string.format('   %-3d %8s  %s %s %s %s, %dW', k, Fmt.money(quota), cells[1], cells[2], cells[3],
      runs[2][k].top, runs[2][k].watts))
  end
  return clears
end

return function()
  local agree = realLines()
  realRuns()
  local clears = referenceRuns()
  print('')
  print(string.format('   lazy clears all 12: %s.  solid: %s.  strong: %s.',
    tostring(clears[1]), tostring(clears[2]), tostring(clears[3])))
  return agree and clears[2] and not clears[1]
end
