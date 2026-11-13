-- Headless simulation tests. Run with:  lovec . --test

local Factory = require 'src.sim.factory'
local Rules = require 'src.rules'
local Run = require 'src.run'
local Upgrades = require 'src.data.upgrades'
local Contracts = require 'src.data.contracts'

local passed, failed = 0, 0

local function check(name, cond, detail)
  if cond then
    passed = passed + 1
    print('  ok    ' .. name)
  else
    failed = failed + 1
    print('  FAIL  ' .. name .. (detail and ('  -> ' .. tostring(detail)) or ''))
  end
end

local function rules(...)
  local mods = {}
  for _, id in ipairs({ ... }) do
    mods[#mods + 1] = Upgrades.byId[id] or error('no upgrade ' .. id)
  end
  return Rules.new(mods)
end

local function belts(F, x1, x2, y, dir)
  for x = x1, x2 do F:place('belt', x, y, dir or 0) end
end

local function runShift(F, r)
  F:beginShift(r or Rules.new({}))
  while not F:finished() do F:step() end
  return F:endShift()
end

-- Like runShift, but also logs every trigger event. `sale` is the number of
-- the sale it happened on (a sale's triggers follow its sale event).
local function watchShift(F, r)
  F:beginShift(r or Rules.new({}))
  local log = { sales = 0 }
  while not F:finished() do
    F:step()
    for _, ev in ipairs(F.events) do
      if ev.kind == 'sale' then
        log.sales = log.sales + 1
      elseif ev.kind == 'trigger' then
        log[#log + 1] = { mod = ev.mod, what = ev.what, delta = ev.delta, x = ev.x, y = ev.y, sale = log.sales }
      end
    end
  end
  return F:endShift(), log
end

local function soldString(s)
  local parts = {}
  for _, t in ipairs(s.order) do parts[#parts + 1] = t .. '=' .. s.sold[t].n end
  return table.concat(parts, ',') .. ' $' .. s.total
end

-- A layout that uses every transport piece, for determinism checks.
local function busyFactory()
  local F = Factory.new()
  F:place('port', 0, 1, 0, { item = 'iron_ore' })
  F:place('port', 0, 5, 0, { item = 'copper_ore' })
  F:place('export', 13, 3, 2)
  belts(F, 1, 2, 1)
  F:place('splitter', 3, 1, 0)
  F:place('belt', 4, 1, 0)
  F:place('smelter', 5, 1, 0)
  F:place('press', 6, 1, 0)
  belts(F, 7, 12, 1)
  F:place('belt', 13, 1, 1)
  F:place('belt', 13, 2, 1)
  F:place('belt', 3, 2, 1)
  F:place('belt', 3, 3, 0)
  belts(F, 4, 12, 3)
  belts(F, 1, 4, 5)
  F:place('smelter', 5, 5, 0)
  belts(F, 6, 12, 5)
  F:place('belt', 13, 5, 3)
  F:place('belt', 13, 4, 3)
  return F
end

return function()
  print('simulation tests')

  -- 1. A straight belt: 1 ore every 2s. The shift starts warm, so the belt
  -- is already full and the shift sells exactly its rate times its length.
  do
    local F = Factory.new()
    F:place('port', 0, 2, 0, { item = 'iron_ore' })
    belts(F, 1, 12, 2)
    F:place('export', 13, 2, 2)
    local s = runShift(F)
    check('straight belt sells 30 ore for $30', s.total == 30, soldString(s))
    F:beginShift(Rules.new({}), { warm = 0 })
    while not F:finished() do F:step() end
    s = F:endShift()
    check('a cold start loses the travel time (24 ore)', s.total == 24, soldString(s))
  end

  -- 2. Smelter fed directly by a port: 4s per ingot.
  do
    local F = Factory.new()
    F:place('port', 0, 2, 0, { item = 'iron_ore' })
    F:place('smelter', 1, 2, 0)
    F:place('export', 2, 2, 2)
    local s = runShift(F)
    local n = s.sold.iron_ingot and s.sold.iron_ingot.n or 0
    check('one smelter makes 15 ingots in a shift', n == 15, soldString(s))
    check('and it never stops', F:utilisation(F:at(1, 2)) == 1, F:utilisation(F:at(1, 2)))
  end

  -- 3. Two smelters behind a splitter keep up with one port.
  do
    local F = Factory.new()
    F:place('port', 0, 2, 0, { item = 'iron_ore' })
    F:place('splitter', 1, 2, 0)
    F:place('smelter', 1, 1, 0)
    F:place('smelter', 1, 3, 0)
    F:place('export', 2, 1, 2)
    F:place('export', 2, 3, 2)
    local s = runShift(F)
    local n = s.sold.iron_ingot and s.sold.iron_ingot.n or 0
    check('splitter + 2 smelters make all 30 ingots', n == 30, soldString(s))
  end

  -- 4. Side merge is fair: two ports into one belt.
  do
    local F = Factory.new()
    F:place('port', 0, 2, 0, { item = 'iron_ore', period = 1 })
    F:place('port', 0, 4, 0, { item = 'copper_ore', period = 1 })
    belts(F, 1, 12, 2)
    belts(F, 1, 4, 4)
    F:place('belt', 5, 4, 3)
    F:place('belt', 5, 3, 3)
    F:place('export', 13, 2, 2)
    local s = runShift(F)
    local a = s.sold.iron_ore and s.sold.iron_ore.n or 0
    local b = s.sold.copper_ore and s.sold.copper_ore.n or 0
    check('merge alternates fairly', math.abs(a - b) <= 4 and a + b >= 40, soldString(s))
  end

  -- 5. Splitter alternates between two outputs.
  do
    local F = Factory.new()
    F:place('port', 0, 2, 0, { item = 'iron_ore', period = 1 })
    F:place('splitter', 1, 2, 0)
    local top = F:place('export', 1, 1, 0)
    local bottom = F:place('export', 1, 3, 0)
    runShift(F)
    local a, b = top.export.sold, bottom.export.sold
    check('splitter splits evenly', math.abs(a - b) <= 1 and a + b >= 56, a .. ' / ' .. b)
  end

  -- 6. Bridge: two lines cross without mixing.
  do
    local F = Factory.new()
    F:place('port', 0, 2, 0, { item = 'iron_ore' })
    F:place('port', 2, 0, 1, { item = 'copper_ore' })
    F:place('belt', 1, 2, 0)
    F:place('belt', 2, 1, 1)
    F:place('bridge', 2, 2, 0)
    F:place('belt', 3, 2, 0)
    F:place('belt', 2, 3, 1)
    local east = F:place('export', 4, 2, 2)
    local south = F:place('export', 2, 4, 3)
    runShift(F)
    local okE = (east.export.log.iron_ore or 0) > 20 and not east.export.log.copper_ore
    local okS = (south.export.log.copper_ore or 0) > 20 and not south.export.log.iron_ore
    check('bridge keeps the two lines apart', okE and okS)
  end

  -- 7. Full-speed belt through a splitter chain does not lose throughput.
  do
    local F = Factory.new()
    F:place('port', 0, 2, 0, { item = 'iron_ore', period = 1 })
    belts(F, 1, 3, 2)
    F:place('splitter', 4, 2, 0)
    belts(F, 5, 6, 2)
    F:place('export', 7, 2, 2)
    local s = runShift(F)
    check('splitter passes a full belt (52+ sold)', s.total >= 52, soldString(s))
  end

  -- 8. Same layout, same result.
  do
    local a = soldString(runShift(busyFactory()))
    local b = soldString(runShift(busyFactory()))
    local F = busyFactory()
    runShift(F)
    local c = soldString(runShift(F))
    check('deterministic across factories', a == b, a .. ' vs ' .. b)
    check('deterministic across shifts', a == c, a .. ' vs ' .. c)
    print('        busy layout: ' .. a)
  end

  -- 9. Rule hooks.
  do
    local function straight()
      local F = Factory.new()
      F:place('port', 0, 2, 0, { item = 'iron_ore' })
      belts(F, 1, 12, 2)
      F:place('export', 13, 2, 2)
      return F
    end
    local s = runShift(straight(), rules('fools_gold'))
    check("Fool's Gold: iron ore sells as gold ore", s.total == 60 and s.sold.gold_ore ~= nil, soldString(s))
    s = runShift(straight(), rules('scrap_dealer'))
    check('Scrap Dealer: ore sells as ingot', s.total == 90, soldString(s))
    s = runShift(straight(), rules('fools_gold', 'scrap_dealer'))
    check('both: iron ore sells as gold ingot', s.total == 30 * 8, soldString(s))
    s = runShift(straight(), rules('monopoly'))
    check('Monopoly doubles a single-type shift', s.total == 60 and s.mult == 2, soldString(s))
    s = runShift(straight(), rules('scenic_route'))
    check('Scenic Route pays for distance', s.total == 30 * (1 + 3), soldString(s))
    s = runShift(straight(), rules('overtime'))
    check('Overtime lengthens the shift', s.total > 30, soldString(s))
    s = runShift(straight(), rules('minimalist'))
    check('Minimalist pays for unused power (16W spare: +48%)', s.total == 44 and s.spare == nil, soldString(s))
  end

  -- 10. Power: demand over supply slows machines down.
  do
    local F = Factory.new()
    F:place('port', 0, 2, 0, { item = 'iron_ore' })
    F:place('smelter', 1, 2, 0)
    F:place('export', 2, 2, 2)
    local r = Rules.new({ { setup = function(rr) rr.basePower = 1.5 end } })
    local s = runShift(F, r)
    local n = s.sold.iron_ingot and s.sold.iron_ingot.n or 0
    check('half power halves output', n >= 6 and n <= 8, soldString(s))
  end

  -- 10b. The remaining machines, built from ASCII layouts.
  do
    local layout = require 'tests.layout'
    local function count(s, t) return s.sold[t] and s.sold[t].n or 0 end

    local s = runShift(layout({ 'I> o> E<' }))
    check('polisher keeps up with a port (30 ore for $60)', count(s, 'iron_ore') == 30 and s.total == 60, soldString(s))

    s = runShift(layout({ 'I> o> o> E<' }))
    check('an item cannot be polished twice by default', s.total == 0, soldString(s))
    s = runShift(layout({ 'I> o> o> E<' }), rules('double_polish'))
    check('Mirror Finish allows a second polish (x4)', s.total > 0 and s.total == count(s, 'iron_ore') * 4, soldString(s))

    s = runShift(layout({ 'I> c> E<' }))
    check('crusher turns 1 ore into 2 dust', count(s, 'iron_dust') >= 54, soldString(s))

    local noPower = { setup = function(r) r.basePower = 0 end }
    s = runShift(layout({ 'I> s> E<' }), Rules.new({ noPower }))
    check('no power, no ingots', s.total == 0, soldString(s))
    s = runShift(layout({ 'K> g>', 'I> s> E<' }), Rules.new({ noPower }))
    check('a coal generator powers the smelter', count(s, 'iron_ingot') >= 12, soldString(s))

    s = runShift(layout({
      'I> s> p> b> bv ..',
      '.. .. .. .. a> E<',
      'C> s> p> b> b^ ..',
    }))
    check('assembler builds motors from gear + wire', count(s, 'motor') >= 6 and s.total == count(s, 'motor') * 20, soldString(s))

    s = runShift(layout({ 'K> p> E<' }), rules('pressure'))
    check('Pressure: press makes diamonds from coal', count(s, 'diamond') >= 15, soldString(s))

    local plain = runShift(layout({ 'I> y> b> E<' })).total
    local leaky = runShift(layout({ 'I> y> b> E<' }), rules('leaky_splitter')).total
    check('Leaky Splitter duplicates items', leaky > plain, plain .. ' -> ' .. leaky)

    s = runShift(layout({ 'I> s> E<' }), rules('perfect_ratio'))
    check('Perfect Ratio: saturated smelter doubles revenue', s.mult == 2, soldString(s))
    s = runShift(layout({ 'I> s> p> E<' }), rules('perfect_ratio'))
    check('Perfect Ratio: an idling press does not', s.mult == 1 and s.lowest.kind == 'press', soldString(s))
    -- 4 smelters at 15/min feed 3 presses at 20/min: nothing idles.
    local ratio = layout({
      '.. s> b> bv .. .. ..',
      'I> y> .. bv .. .. ..',
      '.. s> b> bv p> E< ..',
      '.. .. .. b> y> p> E<',
      '.. s> b> b^ p> E< ..',
      'I> y> .. b^ .. .. ..',
      '.. s> b> b^ .. .. ..',
    })
    s = runShift(ratio, rules('perfect_ratio'))
    check('16W cannot run 21W of machines flat out (45 gears)', count(s, 'gear') == 45, soldString(s))
    s = runShift(ratio, Rules.new({ Upgrades.byId.perfect_ratio }, { basePower = 21 }))
    check('Perfect Ratio: 4 smelters to 3 presses run flat out (60 gears, x2)',
      count(s, 'gear') == 60 and s.mult == 2 and s.total == 840,
      soldString(s) .. ', lowest ' .. s.lowest.kind .. ' ' .. math.floor(s.lowest.u * 100) .. '%')

    local full = layout({ 'I> b> b> E<' })
    full.world:query('port')[1].port.period = 1
    local wide = runShift(full).total
    full = layout({ 'I> b> b> E<' })
    full.world:query('port')[1].port.period = 1
    local narrow = runShift(full, Rules.new({ { setup = function(r) r.exportPeriod = 2 end } })).total
    check('Narrow Dock halves what the export takes', narrow <= wide / 2 + 1 and narrow > 0, wide .. ' -> ' .. narrow)

    s = runShift(layout({ 'K> g>', 'I> b> b> E<' }), rules('conveyor_oven'))
    check('Conveyor Oven smelts ore passing a generator', count(s, 'iron_ingot') > 0, soldString(s))
  end

  -- 10d. Belt shapes (corners and merges) follow what feeds each belt.
  do
    local layout = require 'tests.layout'
    local Links = require 'src.sim.links'
    local F = layout({
      'bv .. bv .. sv .. ..',
      'b> b> b> b> b> .. ..',
      '.. .. b^ .. .. .. ..',
      '.. b> .. b> x. b> ..',
      '.. b^ .. .. x. b> ..',
    })
    local function shape(x, y) return Links.beltShape(F, F:at(x, y)) end
    check('belt fed only from its left is a left corner', shape(0, 1).corner == 'left')
    check('belt fed only from its right is a right corner', shape(1, 3).corner == 'right')
    local s = shape(1, 1)
    check('belt fed from behind is straight', s.back and not s.corner and not s.left and not s.right)
    s = shape(2, 1)
    check('belt fed from behind and both sides is a merge', s.back and s.left and s.right and not s.corner)
    s = shape(4, 1)
    check('a machine output from the side also opens the rail', s.back and s.left)
    check('a belt feeds through a bridge', shape(5, 3).back == true)
    check('an unfed bridge feeds nothing', shape(5, 4).back == false)
    check('an unfed belt is straight', shape(0, 0).corner == nil and not shape(0, 0).back)
  end

  -- 10c. Boss rubble comes and goes with the contract, on owned land only.
  do
    local run = Run.new(5)
    for _, b in ipairs(Contracts.bosses) do
      if b.id == 'rockfall' then run.bosses[1] = b end
    end
    run.index = 2
    run:advance()
    local rubble, onLand = run.factory.world:query('rubble'), true
    for _, e in ipairs(rubble) do onLand = onLand and run.map:owned(e.pos.x, e.pos.y) end
    check('Rockfall buries 8 tiles of your land', #rubble == 8 and onLand, #rubble)
    run:advance()
    check('rubble is cleared for the next contract', #run.factory.world:query('rubble') == 0)
  end

  -- 10e. The site: plots, the depot, and what the land does.
  do
    local Map = require 'src.map'
    local Route = require 'tests.route'
    local run = Run.new(11)
    local F, map = run.factory, run.map
    check('the site is 4x3 plots of 8x6 tiles', F.W == 32 and F.H == 18 and Map.W == 32 and Map.H == 18)
    check('a run starts on one plot in the middle row', map.count == 1 and (map:has(1, 1) or map:has(2, 1)))
    local depot = F.world:query('export')
    check('the depot is a fixed 2x2 block', #depot == 4 and depot[1].building.fixed
      and depot[4].pos.x == depot[1].pos.x + 1 and depot[4].pos.y == depot[1].pos.y + 1)
    check('the depot has 8 faces', #map:depotFaces() == 8)
    local ports = F.world:query('port')
    check('the start plot has an iron and a copper port at 30/min',
      #ports == 2 and ports[1].port.period == 2 and ports[2].port.period == 2
      and ports[1].port.item ~= ports[2].port.item)
    local d = depot[1].pos
    check('you can build on your plot, not off it',
      run:canBuild(d.x - 1, d.y) and not run:canBuild((d.x + 16) % 32, d.y))
    check('contract 1 brings no new land', run.pendingPlot == nil)

    -- Both ports belted to the depot: 60 ore a shift, wherever the ports are.
    for _, port in ipairs(Route.ports(run)) do
      check('a port can be routed to the depot', Route.belt(run, port) ~= nil)
    end
    run:beginShift()
    while not F:finished() do F:step() end
    local s = run:endShift()
    check('two belted ports sell 60 ore a shift', s.total == 60 and run.progress == 60, s.total)
    check('run API: status is set', s.status == 'next' or s.status == 'cleared', s.status)

    -- The next contract comes with a plot, placed in a slot touching your land.
    run.progress = 0
    run:advance()
    local plot = run.pendingPlot
    check('contract 2 offers a plot with ports', plot ~= nil and #plot.ports >= 1)
    local free = map:free()
    local sx = map:has(1, 1) and 1 or 2
    check('free slots are the ones touching your land', #free == 4, #free)
    check('land cannot be placed away from yours', not run:annex(sx == 1 and 3 or 0, 0))
    check('land cannot be placed on yours', not run:annex(sx, 1))
    local before = #F.world:query('port')
    check('the plot goes into a free slot', run:annex(free[1][1], free[1][2]) and run.pendingPlot == nil)
    check('and brings its ports', #F.world:query('port') == before + #plot.ports and map.count == 2)
    check('its tiles are yours now', run:canBuild(free[1][1] * 8 + 3, free[1][2] * 6 + 3))

    -- Specials.
    local rng = require('src.rng').new(3)
    local node = Map.generate(rng, { items = { 'coal' }, rocks = 2, special = 'node' })
    local watts = run:basePower()
    run.pendingPlot = node
    local slot = map:free()[1]
    run:annex(slot[1], slot[2])
    check('a power node adds 12W', run:basePower() == watts + 12 and run.rules.basePower == watts + 12)
    check('rocks cannot be built on or removed', #node.rocks == 2
      and F:at(slot[1] * 8 + node.rocks[1].x, slot[2] * 6 + node.rocks[1].y).building.fixed)

    local rich = Map.generate(rng, { items = { 'coal', 'iron_ore' }, special = 'rich' })
    local n = 0
    for _, p in ipairs(rich.ports) do n = n + (p.period == 1 and 1 or 0) end
    check('a rich port runs at 60/min', n == 1)

    local premium = Map.generate(rng, { items = { 'coal' }, special = 'premium' })
    run.pendingPlot = premium
    slot = map:free()[1]
    run:annex(slot[1], slot[2])
    local face = premium.face
    check('a premium plot upgrades one depot face',
      face ~= nil and F:at(face[1], face[2]).export.premium[face[3]] == Map.PREMIUM)
    check('the premium rule joins the rules', run.rules.mods[1] == Contracts.premium)
  end

  -- 10f. Booster pads and premium faces in the simulation.
  do
    local layout = require 'tests.layout'
    local function count(s, t) return s.sold[t] and s.sold[t].n or 0 end
    local plain = layout({ 'I> s> E<' })
    local padded = layout({ 'I> s> E<' })
    padded:remove(1, 0)
    padded:setFloor(1, 0, 'pad')
    padded:place('smelter', 1, 0, 0)
    local a, b = count(runShift(plain), 'iron_ingot'), count(runShift(padded), 'iron_ingot')
    check('a booster pad makes a machine 50% faster (15 -> 22 ingots)', a == 15 and b >= 22 and b <= 23, a .. ' -> ' .. b)

    local F = layout({ 'I> s> E<' })
    F:at(2, 0).export.premium[0] = 1.5
    local s = runShift(F, Rules.new({ Contracts.premium }))
    check('a premium face pays 1.5x (15 ingots at $4.50, rounded per sale: $75)', s.total == 75, soldString(s))
    check('and the ledger credits it', s.ledger[Contracts.premium].n == 15)
  end

  -- 11. Runs are reproducible from the seed.
  do
    local function describe(seed)
      local run = Run.new(seed)
      local parts = {}
      local list = run.factory.world:query('building')
      for _, e in ipairs(list) do
        parts[#parts + 1] = e.building.kind .. e.pos.x .. ',' .. e.pos.y .. (e.port and e.port.item or '')
      end
      run:openShop()
      for _, o in ipairs(run.shop.offers) do parts[#parts + 1] = o.id end
      for _, b in ipairs(run.bosses) do parts[#parts + 1] = b.id end
      return table.concat(parts, ' ')
    end
    check('same seed, same run', describe(1234) == describe(1234))
    check('different seed, different run', describe(1234) ~= describe(99))
  end

  -- 12. Blueprints and the shop, through the Run API.
  do
    local run = Run.new(7)

    -- Blueprints: a kind is unlocked for the whole run, in any number.
    check('a run starts with the smelter and press blueprints',
      run:unlocked('smelter') and run:unlocked('press') and not run:unlocked('assembler'))
    check('logistics need no blueprint', run:unlocked('belt') and run:unlocked('splitter') and run:unlocked('bridge'))
    check('fixed pieces cannot be built', not run:unlocked('port') and not run:unlocked('export'))
    run.credits = 50
    run:openShop()
    local bought
    for i, o in ipairs(run.shop.offers) do
      if o.type == 'blueprint' and not bought then
        check('the shop never offers an owned blueprint', not run.blueprints[o.id], o.id)
        run:buy(i)
        bought = o.id
      end
    end
    check('buying a blueprint unlocks the machine', bought ~= nil and run:unlocked(bought), bought)
    local watts, credits = run.rules.basePower, run.credits
    run:buyPower()
    check('buying power raises the supply', run.rules.basePower == watts + Contracts.powerStep and run.credits < credits)
    check('quota table matches contract count', #Contracts.quotas == 9)
  end

  -- 13. Triggers: which mod did what, when, and for how much.
  do
    local layout = require 'tests.layout'
    local U = Upgrades.byId
    local function straight(port)
      local F = Factory.new()
      F:place('port', 0, 2, 0, { item = port or 'iron_ore' })
      belts(F, 1, 12, 2)
      F:place('export', 13, 2, 2)
      return F
    end
    local function near(a, b) return math.abs(a - b) < 1e-6 end
    local function boss(id)
      for _, b in ipairs(Contracts.bosses) do
        if b.id == id then return b end
      end
    end
    -- plain value + everything credited to a mod
    local function ledgerSum(s)
      local t = s.plain
      for _, rec in pairs(s.ledger) do t = t + rec.delta end
      return t
    end
    local function all(log, test)
      for _, t in ipairs(log) do
        if not test(t) then return false end
      end
      return true
    end

    -- Sale-time: only when the hook changed the sale.
    local s, log = watchShift(straight(), rules('bulk_order'))
    local at = {}
    for _, t in ipairs(log) do at[#at + 1] = t.sale end
    check('Bulk Order triggers on exactly every 8th sale', table.concat(at, ',') == '8,16,24', table.concat(at, ','))
    local rec = s.ledger[U.bulk_order]
    check('Bulk Order is credited $3 a time', rec.n == 3 and near(rec.delta, 9) and s.total == 39, rec.delta)

    s, log = watchShift(layout({ 'I> b> b> E<' }), rules('scenic_route'))
    check('Scenic Route stays quiet under 4 tiles', #log == 0 and s.ledger[U.scenic_route].n == 0 and s.total > 0, #log)
    s, log = watchShift(straight(), rules('scenic_route'))
    check('Scenic Route triggers on every sale off a long belt',
      #log == 30 and near(s.ledger[U.scenic_route].delta, 90) and all(log, function(t) return t.what == 'sale' and t.x == 13 end), #log)

    s, log = watchShift(straight(), rules('gold_standard'))
    check('Gold Standard stays quiet with no gold sold', #log == 0, #log)

    s, log = watchShift(straight(), rules('fools_gold'))
    check("Fool's Gold is credited the difference in type", near(s.ledger[U.fools_gold].delta, 30) and #log == 30, s.ledger[U.fools_gold].delta)

    -- Harmful triggers have a negative delta.
    s, log = watchShift(straight('copper_ore'), rules('embargo'))
    check('Embargo on copper registers as harmful',
      #log == 30 and all(log, function(t) return t.delta < 0 end) and s.total == 0 and near(s.ledger[U.embargo].delta, -30), s.total)
    s, log = watchShift(straight(), rules('embargo'))
    check('Embargo on iron registers as a gain', #log == 30 and all(log, function(t) return t.delta > 0 end) and s.total == 90, s.total)
    local tariff = boss('tariff')
    s, log = watchShift(straight('copper_ore'), Rules.new({ tariff }))
    check('Tariff is credited to the boss, and is harmful',
      #log == 30 and all(log, function(t) return t.mod == tariff and t.delta < 0 end) and near(s.ledger[tariff].delta, -30), #log)
    s, log = watchShift(straight('copper_ore'), Rules.new({ U.embargo, tariff }))
    check('a sale already worth $0 triggers nothing further', s.ledger[tariff].n == 0 and s.ledger[U.embargo].n == 30, s.ledger[tariff].n)

    -- Credit is marginal, in slot order.
    s = watchShift(straight(), rules('fools_gold', 'scrap_dealer'))
    check("slot order: Fool's Gold first", near(s.ledger[U.fools_gold].delta, 30) and near(s.ledger[U.scrap_dealer].delta, 180) and s.total == 240,
      s.ledger[U.fools_gold].delta .. ' / ' .. s.ledger[U.scrap_dealer].delta)
    s = watchShift(straight(), rules('scrap_dealer', 'fools_gold'))
    check('slot order: Scrap Dealer first', near(s.ledger[U.scrap_dealer].delta, 60) and near(s.ledger[U.fools_gold].delta, 150) and s.total == 240,
      s.ledger[U.scrap_dealer].delta .. ' / ' .. s.ledger[U.fools_gold].delta)

    -- The ledger always adds up, fractions and multipliers included.
    s = watchShift(straight(), rules('fools_gold', 'gold_standard', 'scenic_route', 'last_call'))
    check('ledger adds up to the revenue (fractional values)', near(ledgerSum(s), s.total) and s.ledger[U.gold_standard].n > 0,
      ledgerSum(s) .. ' vs ' .. s.total)
    s = watchShift(straight(), rules('fools_gold', 'gold_standard', 'monopoly', 'minimalist'))
    check('ledger adds up to the total (with two multipliers)', near(ledgerSum(s), s.total) and near(s.mult, 2 * 1.48),
      ledgerSum(s) .. ' vs ' .. s.total)

    -- End of shift: one result per mod with a shiftEnd hook, fired or not.
    s = watchShift(layout({ 'I> s> E<' }), rules('perfect_ratio'))
    local res = s.results[1]
    check('Perfect Ratio reports that it fired', #s.results == 1 and res.mod == U.perfect_ratio and res.fired and near(res.delta, s.base) and res.label == 'x2')
    s = watchShift(layout({ 'I> s> p> E<' }), rules('perfect_ratio'))
    res = s.results[1]
    check('Perfect Ratio reports "not met"', #s.results == 1 and res.mod == U.perfect_ratio and not res.fired and s.ledger[U.perfect_ratio].n == 0)

    -- On-board events are credited to whoever set the rule, at the tile.
    check('rule fields remember who set them',
      rules('leaky_splitter').owner.leakEvery == U.leaky_splitter and rules('overtime').owner.shiftLen == U.overtime)
    s, log = watchShift(layout({ 'I> y> b> E<' }), rules('leaky_splitter'))
    check('Leaky Splitter triggers at the splitter',
      #log > 0 and #log == s.ledger[U.leaky_splitter].n and all(log, function(t) return t.what == 'dup' and t.x == 1 and t.y == 0 end), #log)
    s, log = watchShift(layout({ 'K> g>', 'I> b> b> E<' }), rules('conveyor_oven'))
    check('Conveyor Oven triggers on the belt by the generator',
      #log > 0 and all(log, function(t) return t.mod == U.conveyor_oven and t.what == 'smelt' and t.x == 1 and t.y == 1 end), #log)
    s, log = watchShift(layout({ 'K> p> E<' }), rules('pressure'))
    check('Pressure triggers on each diamond craft',
      #log >= s.sold.diamond.n and all(log, function(t) return t.mod == U.pressure and t.what == 'craft' and t.x == 1 end), #log)
    s, log = watchShift(layout({ 'I> s> p> E<' }), rules('pressure'))
    check('Pressure stays quiet on ordinary recipes', #log == 0 and s.total > 0, #log)
    s, log = watchShift(layout({ 'I> o> o> E<' }), rules('double_polish'))
    check('Mirror Finish triggers on the second polish only',
      #log > 0 and all(log, function(t) return t.mod == U.double_polish and t.what == 'polish' and t.x == 2 end), #log)

    -- Static modifiers mark the machines they change.
    local function affecting(F, r, x, y)
      local list = r:affecting(F, F:at(x, y)) or {}
      return #list == 1 and list[1] or (#list == 0 and 'none' or 'many')
    end
    local pair = layout({ 'I> s> E<', '.. s> ..' })
    local lone = layout({ 'I> s> E<' })
    local chain = layout({ 'I> s> p> E<' })
    check('Assembly Line marks adjacent twins, not a lone machine',
      affecting(pair, rules('assembly_line'), 1, 0) == U.assembly_line and affecting(lone, rules('assembly_line'), 1, 0) == 'none')
    check('Hand Crank marks a lone machine, not neighbours',
      affecting(lone, rules('isolation'), 1, 0) == U.isolation and affecting(pair, rules('isolation'), 1, 0) == 'none')
    check('Direct Drive marks the machine feeding another',
      affecting(chain, rules('direct_drive'), 1, 0) == U.direct_drive and affecting(chain, rules('direct_drive'), 2, 0) == 'none')
    s = watchShift(pair, rules('assembly_line'))
    check('the ledger counts the machines a static modifier changes', s.ledger[U.assembly_line].n == 2, s.ledger[U.assembly_line].n)

    -- Setup-only mods never trigger.
    s, log = watchShift(straight(), Rules.new({ U.overtime, boss('narrow_dock'), boss('brownout'), boss('rockfall') }))
    check('setup-only mods never trigger', #log == 0 and s.ledger[U.overtime].n == 0 and s.total > 0, #log)
  end

  print(string.format('%d passed, %d failed', passed, failed))
  return failed == 0
end
