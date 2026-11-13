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
    check("Fool's Gold: iron ore sells as gold ore", s.total == 90 and s.sold.gold_ore ~= nil, soldString(s))
    s = runShift(straight(), rules('scrap_dealer'))
    check('Scrap Dealer: ore sells as ingot', s.total == 90, soldString(s))
    s = runShift(straight(), rules('fools_gold', 'scrap_dealer'))
    check('both: iron ore sells as gold ingot', s.total == 30 * 9, soldString(s))
    s = runShift(straight(), rules('monopoly'))
    check('Monopoly doubles a single-type shift', s.total == 60 and s.mult == 2, soldString(s))
    s = runShift(straight(), rules('scenic_route'))
    check('Scenic Route pays 2% a tile (12 tiles: 30 ore at $1.24)', s.total == 37 and math.abs(s.exact - 37.2) < 1e-6, soldString(s))
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
      'C> s> w> b> b^ ..',
    }))
    check('assembler builds 10 motors a minute from gear + wire', count(s, 'motor') == 10 and s.total == 320, soldString(s))

    local Alternates = require 'src.data.alternates'
    s = runShift(layout({ 'K> p> E<' }), Rules.new({ Alternates.byId.pressure }))
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
      count(s, 'gear') == 60 and s.mult == 2 and s.total == 960,
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
    local Bosses = require 'src.data.bosses'
    local run = Run.new(5)
    run.bosses[1] = Bosses.make(Bosses.byId.rockfall)
    run.index = 2
    run:advance()
    local rubble, onLand = run.factory.world:query('rubble'), true
    for _, e in ipairs(rubble) do onLand = onLand and run.map:owned(e.pos.x, e.pos.y) end
    check('Rockfall buries 10 tiles of your land', #rubble == 10 and onLand, #rubble)
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
    local offers = run:rollOffers()
    check('two contracts are on offer, each with land and a market',
      #offers == 2 and offers[1].plot ~= nil and offers[2].plot ~= nil
      and #offers[1].market.demand == 2 and offers[1].plot ~= offers[2].plot)
    check('choosing takes one of them', run:choose(2) and run.chosen == offers[2] and not run:choose(3))
    run:advance()
    check('the chosen contract brings its market', run.index == 2 and run.market == offers[2].market
      and run.rules.mods[1].market == offers[2].market and run.offers == nil)
    local plot = run.pendingPlot
    check('and its land', plot == offers[2].plot)
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

  -- 10g. The roster: every machine shape, the filter, the byproduct, crates.
  do
    local layout = require 'tests.layout'
    local Items = require 'src.data.items'
    local Recipes = require 'src.data.recipes'
    local Machines = require 'src.data.machines'
    local function count(s, t) return s.sold[t] and s.sold[t].n or 0 end
    local power = { basePower = 200 }

    local s = runShift(layout({ 'C> s> w> E<' }))
    check('wire mill: 1 ingot to 2 wires (15 ingots -> 30 wires)', count(s, 'wire') == 30 and s.total == 120, soldString(s))

    s = runShift(layout({ 'Q> c> b> E<' }))
    check('crusher: quartz to 2 sand each', count(s, 'sand') == 60, soldString(s))
    s = runShift(layout({ 'Q> s> p> E<' }))
    check('quartz smelts to glass, glass presses to lenses', count(s, 'lens') == 15 and s.total == 120, soldString(s))

    s = runShift(layout({
      'I> s> bv ..',
      '.. .. f> E<',
      'K> b> b^ ..',
    }))
    check('foundry: iron ingot + coal to steel (12 a minute)', count(s, 'steel') == 12 and s.total == 132, soldString(s))

    -- The refinery puts out plastic and tar on one belt; a filter parts them.
    local F = layout({
      '.. .. .. E. ..',
      'O> r> b> t> E<',
      '.. .. .. .. ..',
    })
    F:at(3, 1).filter.item = 'plastic'
    s = runShift(F)
    check('refinery: crude to plastic and tar; the filter sends plastic straight on',
      count(s, 'plastic') == 15 and count(s, 'tar') == 15
      and F:at(4, 1).export.log.plastic == 15 and not F:at(4, 1).export.log.tar
      and F:at(3, 0).export.log.tar == 15, soldString(s))
    F = layout({ 'O> r> b> t> E<' })
    F:at(3, 0).filter.item = 'plastic'
    s = runShift(F)
    check('tar with nowhere to go stops the refinery', count(s, 'plastic') == 0 and s.lowest.u == 0, soldString(s))
    F = layout({ 'O> r> b> t> E<' })
    s = runShift(F)
    check('a filter with no item set lets nothing straight through', s.total == 0, soldString(s))

    F = layout({
      '.. .. .. g. ..',
      'O> r> b> t> E<',
      '.. .. .. .. ..',
    })
    F:at(3, 1).filter.item = 'plastic'
    s = runShift(F, Rules.new({}, { basePower = 6 }))
    local gen = F:at(3, 0)
    check('a generator burns the tar (+10W while it does)', gen.machine.made >= 14 and s.supply > 6 and count(s, 'plastic') == 15,
      gen.machine.made .. ' burned, supply ' .. s.supply)

    -- Two ports on one belt, sorted again by a filter.
    F = layout({
      'I> bv .. E. ..',
      '.. b> b> t> E<',
      'C> b^ .. E. ..',
    })
    F:at(3, 1).filter.item = 'iron_ore'
    s = runShift(F)
    local straight, up, down = F:at(4, 1).export.log, F:at(3, 0).export.log, F:at(3, 2).export.log
    check('filter: its item straight on, the rest out of both sides in turn',
      straight.iron_ore == 30 and not straight.copper_ore
      and (up.copper_ore or 0) == 15 and (down.copper_ore or 0) == 15 and not up.iron_ore,
      soldString(s))

    -- Three inputs to one product.
    F = Factory.new()
    F:place('port', 0, 1, 0, { item = 'motor' })
    F:place('port', 1, 0, 1, { item = 'beam' })
    F:place('port', 1, 2, 3, { item = 'cable' })
    F:place('manufacturer', 1, 1, 0)
    F:place('export', 2, 1, 2)
    s = runShift(F, Rules.new({}, power))
    check('manufacturer: motor + beam + cable to 6 engines a minute', count(s, 'engine') == 6 and s.total == 6 * 232, soldString(s))

    -- Crates.
    s = runShift(layout({ 'I> s> k> E<' }))
    check('packer: 4 ingots to a crate, sold as 4 items for 10% more (3 crates at $13.20)',
      count(s, 'iron_ingot') == 12 and math.abs(s.exact - 39.6) < 1e-6, soldString(s))
    s = runShift(layout({ 'I> s> k> p> E<' }))
    check('nothing opens a crate', s.total == 0, soldString(s))
    s = runShift(layout({ 'I> s> o> k> E<' }), Rules.new({}, power))
    local packed = count(s, 'iron_ingot')
    check('polish first, then pack: crates of polished ingots at $26.40',
      packed >= 12 and packed % 4 == 0 and math.abs(s.exact - packed / 4 * 26.4) < 1e-6, soldString(s))

    -- Depth pays: every recipe is worth 2x to 3.5x what goes in.
    local worst, best = math.huge, 0
    for _, kind in ipairs(Machines.list) do
      if kind ~= 'crusher' then
        for _, r in ipairs(Recipes[kind] or {}) do
          local vin, vout = 0, 0
          for _, i in ipairs(r.inputs) do vin = vin + Items[i[1]].value * i[2] end
          for _, o in ipairs(r.outputs) do vout = vout + Items[o[1]].value * o[2] end
          if Items[r.inputs[1][1]].form ~= 'dust' then
            worst, best = math.min(worst, vout / vin), math.max(best, vout / vin)
          end
        end
      end
    end
    check('every recipe multiplies value by 2x to 3.5x', worst >= 2 and best <= 3.5,
      string.format('%.2f .. %.2f', worst, best))
    local n = 0
    for _, id in ipairs(Items.list) do
      n = n + 1
      if not Items[id] then n = -1000 end
    end
    check('37 items in 5 tiers', n == 37 and Items.computer.tier == 5 and Items.iron_ore.tier == 1, n)
  end

  -- 10h. Markets, quotas and payouts.
  do
    local Market = require 'src.market'
    local Fmt = require 'src.fmt'
    local Items = require 'src.data.items'
    local layout = require 'tests.layout'
    local function count(s, t) return s.sold[t] and s.sold[t].n or 0 end
    local function straight(item)
      local F = Factory.new()
      F:place('port', 0, 2, 0, { item = item })
      belts(F, 1, 5, 2)
      F:place('export', 6, 2, 2)
      return F
    end

    local q = Contracts.quotas
    local steady = true
    for i = 2, #q do steady = steady and q[i] / q[i - 1] > 2.2 and q[i] / q[i - 1] < 3 end
    check('12 quotas from $120 to $5M, each 2.2x to 3x the last', #q == 12 and q[1] == 120 and q[12] == 5000000 and steady)
    check('endless mode keeps growing at 2.6x', Contracts.quota(13) == 13000000 and Contracts.quota(14) == 34000000,
      Contracts.quota(13) .. ' ' .. Contracts.quota(14))
    check('big numbers are written short',
      Fmt.num(950) == '950' and Fmt.num(9999) == '9999' and Fmt.num(12345) == '12.3K'
      and Fmt.num(5000000) == '5M' and Fmt.num(1234567) == '1.23M' and Fmt.money(2500000000) == '$2.5B',
      Fmt.num(12345) .. ' ' .. Fmt.num(5000000) .. ' ' .. Fmt.num(1234567))

    -- Demand has volume: x3 on the first N units a shift, then the normal price.
    local market = { demand = { { item = 'gear', mult = 3, units = 10 } } }
    local mod = Market.mod(market)
    local s = runShift(straight('gear'), Rules.new({ mod }))
    check('demand pays x3 on the first 10 gears, then $8 (10 x 24 + 20 x 8)', s.total == 400, soldString(s))
    check('the ledger credits the market', math.abs(s.ledger[mod].delta - 160) < 1e-6 and s.ledger[mod].n == 10,
      s.ledger[mod].delta)
    s = runShift(straight('gear'), Rules.new({ mod }))
    check('demand starts afresh every shift', s.total == 400, soldString(s))
    s = runShift(straight('plate'), Rules.new({ mod }))
    check('other products sell at the normal price', s.total == 240 and s.ledger[mod].n == 0, soldString(s))

    local slump = Market.mod({ demand = {}, slump = { item = 'gear', mult = 0.5 } })
    s = runShift(straight('gear'), Rules.new({ slump }))
    check('a slump halves every unit (30 gears at $4)', s.total == 120 and s.ledger[slump].delta < 0, soldString(s))

    -- A crate can straddle the edge of the demand.
    local F = Factory.new()
    F:place('port', 0, 2, 0, { item = 'gear' })
    F:place('packer', 1, 2, 0)
    F:place('export', 2, 2, 2)
    s = runShift(F, Rules.new({ Market.mod({ demand = { { item = 'gear', mult = 3, units = 6 } } }) }))
    local crates = count(s, 'gear') / 4
    check('a crate of 4 with 2 units of demand left pays x3 on those 2 ($105.60, $70.40, then $35.20 each)',
      crates >= 7 and math.abs(s.exact - (105.6 + 70.4 + (crates - 2) * 35.2)) < 1e-6, soldString(s))

    -- What a site can make, and what it would take.
    local res = { iron_ore = true, copper_ore = true }
    local own = { smelter = true, press = true }
    local reach = Market.closure(res, own)
    check('reach: smelter + press on iron and copper make gears and plates, not wire',
      reach.gear and reach.plate and reach.iron_ingot and not reach.wire and not reach.motor)
    local missing = Market.missing('motor', res, own)
    check('a motor would need the wire mill and the assembler',
      #missing == 2 and missing[1] == 'wiremill' and missing[2] == 'assembler', table.concat(missing, ','))
    check('steel cannot be made without coal', Market.missing('steel', res, own) == nil)
    check('demand grows with the sector and shrinks with the tier',
      Market.units('gear', 1) == 24 and Market.units('gear', 2) == 36 and Market.units('motor', 1) == 12
      and Market.units('wire', 1) == 48 and Market.units('computer', 4) == 18 and Market.units('computer', 5) == 27)

    local rng = require('src.rng').new(9)
    local ok = true
    for _ = 1, 30 do
      local m = Market.roll(rng, { resources = res, owned = own, sector = 1, easy = true })
      ok = ok and #m.demand == 2 and m.demand[1].item ~= m.demand[2].item and m.slump == nil
      for _, d in ipairs(m.demand) do ok = ok and reach[d.item] and Items[d.item].tier >= 2 end
    end
    check('the first contract only asks for what the starting kit makes', ok)
    local stretched = 0
    for _ = 1, 30 do
      local m = Market.roll(rng, { resources = res, owned = own, sector = 2, slump = 'random' })
      ok = ok and reach[m.demand[1].item] and m.slump ~= nil and reach[m.slump.item]
        and m.slump.item ~= m.demand[1].item and m.slump.item ~= m.demand[2].item
      if not reach[m.demand[2].item] then stretched = stretched + 1 end
    end
    check('later contracts: one demand within reach, one to stretch for, one slump', ok and stretched == 30, stretched)

    -- A run: its first market, the choice, the payout.
    local run = Run.new(21)
    check('a run opens with a market of two reachable products',
      run.market ~= nil and #run.market.demand == 2 and run.rules.mods[1].market == run.market)
    run.soldValue = { gear = 500, plate = 200 }
    check('the top seller is tracked', run:topSeller() == 'gear')
    run.index = 3
    local offers = run:rollOffers()
    check('from sector 2 on, something slumps on every offer',
      offers[1].market.slump ~= nil and offers[2].market.slump ~= nil)
    check('on the first offer it is your best seller, unless that is in demand',
      offers[1].market.slump.item == 'gear' or offers[1].market.demand[1].item == 'gear'
      or offers[1].market.demand[2].item == 'gear', offers[1].market.slump.item)
    local stretch = 0
    for _, d in ipairs(offers[1].market.demand) do
      local miss = Market.missing(d.item, run:resources(offers[1].plot), run:kinds())
      if miss and #miss > 0 then stretch = stretch + 1 end
    end
    check('an offer that needs a machine you lack pays more', offers[1].bonus == stretch * 2, offers[1].bonus)

    run.index, run.credits, run.shiftsUsed, run.bonus = 1, 0, 1, 0
    run:refreshRules()
    run.progress = Contracts.quota(1) * 4
    local p = run:payout()
    check('beating the quota 4x pays 2 + 2 credits on top', p.overshoot == 4 and p.unused == 4 and p.total == 5 + 4 + 4, p.total)
    run.progress, run.credits = Contracts.quota(1) * 1.9, 0
    check('1.9x pays nothing extra', run:payout().overshoot == 0)
  end

  -- 10i. Bosses, their reward, and endless mode.
  do
    local Bosses = require 'src.data.bosses'
    local Market = require 'src.market'
    local Map = require 'src.map'
    local layout = require 'tests.layout'
    local function count(s, t) return s.sold[t] and s.sold[t].n or 0 end
    local function near(a, b) return math.abs(a - b) < 1e-6 end
    local function boss(id, params) return Bosses.make(Bosses.byId[id], params) end
    local function straight(item)
      local F = Factory.new()
      F:place('port', 0, 2, 0, { item = item })
      belts(F, 1, 5, 2)
      F:place('export', 6, 2, 2)
      return F
    end

    local regular, final = Bosses.pool(false), Bosses.pool(true)
    check('12 bosses and 3 for the last contract', #regular == 12 and #final == 3)

    -- Announced three contracts ahead.
    local run = Run.new(31)
    local c = run:contract()
    check('the first boss is known from contract 1', c.sectorBoss ~= nil and c.boss == nil and c.bossIn == 2
      and run:contract(3).boss == c.sectorBoss and type(c.sectorBoss.desc) == 'string')
    local rng = require('src.rng').new(4)
    check('a boss that needs room does not come to a one-plot site',
      Bosses.byId.blackout.pick(run, rng) == nil and Bosses.byId.drought.pick(run, rng) == nil
      and Bosses.byId.foreclosure.pick(run, rng) == nil)
    check('its target is picked from what the site has',
      run.blueprints[Bosses.byId.strike.pick(run, rng).kind] == true
      and ({ iron = true, copper = true })[Bosses.byId.tariff.pick(run, rng).mat] == true)
    check('the last sector draws from the final pool',
      run:revealBoss(2) ~= nil and run:revealBoss(3) ~= nil and run:revealBoss(4).def.final == true)
    local seen, distinct = {}, true
    for sector = 1, 4 do
      if seen[run.bosses[sector].id] then distinct = false end
      seen[run.bosses[sector].id] = true
    end
    check('a run sees four different bosses', distinct)

    -- What each does.
    local F = layout({ 'I> s> E<' })
    local dark = boss('blackout', { plots = { { 0, 0 } } })
    local r = Rules.new({ dark }, { basePower = 16 })
    local s = runShift(F, r)
    check('Blackout: machines on the marked plot do not run, and draw nothing',
      s.total == 0 and F:at(1, 0).machine.status == 'off' and F:plannedDraw(r) == 0 and r:affecting(F, F:at(1, 0)) ~= nil)
    F = Factory.new()
    F:place('port', 8, 0, 0, { item = 'iron_ore' })
    F:place('smelter', 9, 0, 0)
    F:place('export', 10, 0, 2)
    s = runShift(F, Rules.new({ dark }))
    check('and the plot next door is fine', count(s, 'iron_ingot') == 15, soldString(s))

    s = runShift(straight('iron_ore'), Rules.new({ boss('drought', { item = 'iron_ore' }) }))
    check('Drought: the port supplies nothing', s.total == 0, soldString(s))
    s = runShift(layout({ 'I> s> E<' }), Rules.new({ boss('strike', { kind = 'smelter' }) }))
    check('Strike: the smelter makes half (7 or 8 ingots)', count(s, 'iron_ingot') >= 7 and count(s, 'iron_ingot') <= 8, soldString(s))
    local market = Market.mod({ demand = { { item = 'gear', mult = 3, units = 10 } } })
    s = runShift(straight('gear'), Rules.new({ market, boss('glut') }))
    check('Glut: demand pays nothing extra', s.total == 240, soldString(s))
    F = layout({ 'I> s> E<' })
    runShift(F, Rules.new({ boss('surge') }))
    check('Surge Pricing: machines draw 50% more', F:at(1, 0).machine.draw == 4.5)
    s = runShift(straight('gear'), Rules.new({ boss('long_haul') }))
    check('Long Haul: 5 tiles of belt cost 15%', near(s.exact, 240 * 0.85), s.exact)
    s = runShift(layout({ 'I> s> E<' }), Rules.new({ boss('inspection') }))
    check('Inspection: ingots are worthless', s.total == 0 and count(s, 'iron_ingot') == 15, soldString(s))
    s = runShift(straight('gear'), Rules.new({ boss('inspection') }))
    check('but gears are not', s.total == 240, soldString(s))
    s = runShift(straight('gear'), Rules.new({ boss('saturation') }))
    check('Saturation: each gear sold makes the next worth 1% less', near(s.exact, 8 * (30 - 4.35)), s.exact)
    r = Rules.new({ boss('gridlock') }, { basePower = 16 })
    F = layout({ 'I> s> E<' })
    runShift(F, r)
    check('Gridlock: half the power, 25% more draw', r.basePower == 8 and F:at(1, 0).machine.draw == 3.75)
    r = Rules.new({ boss('rush') })
    check('Rush Order: 40 second shifts', r.shiftLen == 40)
    F = straight('gear')
    F:at(6, 2).export.closed[0] = true
    s = runShift(F)
    check('a closed depot face takes nothing', s.total == 0, soldString(s))

    -- On the board.
    run = Run.new(31)
    run.bosses[1] = boss('narrow_dock')
    run.index = 2
    run:advance()
    local closed = 0
    for _, e in ipairs(run.factory.world:query('export')) do
      for d = 0, 3 do closed = closed + (e.export.closed[d] and 1 or 0) end
    end
    check('Narrow Dock closes 4 of the 8 faces', closed == 4, closed)
    run:advance()
    closed = 0
    for _, e in ipairs(run.factory.world:query('export')) do
      for d = 0, 3 do closed = closed + (e.export.closed[d] and 1 or 0) end
    end
    check('and they open again for the next contract', closed == 0 and run:contract().sectorBoss ~= nil and run.index == 4)

    -- Beating a boss: one of three blueprints.
    run = Run.new(31)
    run.index = 3
    run:afterContract()
    local options = run.reward and run.reward.options
    local fresh = options ~= nil and #options == 3
    for _, o in ipairs(options or {}) do
      fresh = fresh and o.type == 'blueprint' and not run.blueprints[o.id] and o.id ~= 'manufacturer'
    end
    check('a boss win offers 3 blueprints you do not have', fresh)
    check('and the next contracts, and the next boss', #run.offers == 2 and run.bosses[2] ~= nil)
    local want = options[2].id
    check('taking one unlocks it', run:takeReward(2) and run:unlocked(want) and run.reward == nil and not run:takeReward(1))
    run.index = 2
    run.reward = nil
    run:afterContract()
    check('an ordinary contract gives no such reward', run.reward == nil)

    -- Endless mode.
    run = Run.new(31)
    run.index = 12
    run:afterContract()
    check('clearing contract 12 wins the run and still offers a 13th',
      run.won and #run.offers == 2 and run:contract(13).quota == 13000000)
    run:choose(1)
    run:advance()
    check('endless contracts keep their bosses', run.index == 13 and run:contract().sectorBoss ~= nil
      and run:contract(15).isBoss and run:contract(15).sector == 5)
    check('and their demand keeps growing', Market.units('gear', 5) == 108 and Market.units('gear', 6) == 162,
      Market.units('gear', 5))
  end

  -- 10j. Saving a run and picking it up again.
  do
    local Save = require 'src.save'
    local Records = require 'src.records'
    local Route = require 'tests.route'
    local Bosses = require 'src.data.bosses'

    check('a save holds data, never code',
      Save.encode({ b = 1, a = function() end, mod = { x = 1 }, list = { 'x', true, 2.5 } }) == 'return {b=1,list={[1]="x",[2]=true,[3]=2.5}}',
      Save.encode({ b = 1, a = function() end, mod = { x = 1 }, list = { 'x', true, 2.5 } }))
    check('and loading one runs none', Save.decode('return os.time()') == nil and Save.decode('return {') == nil
      and Save.decode('return 5') == nil and Save.decode('return {a={b=2}}').a.b == 2)

    -- A run with a bit of everything in it.
    local function describe(run)
      local parts = { run.credits, run.index, run.progress, run.shiftsUsed, run:basePower() }
      -- Every piece on the board, whatever order it was placed in.
      local pieces = {}
      for _, e in ipairs(run.factory.world:query('building')) do
        local b = e.building
        pieces[#pieces + 1] = b.kind .. e.pos.x .. ',' .. e.pos.y .. ',' .. b.dir
          .. (e.port and (e.port.item .. e.port.period) or '') .. (e.filter and tostring(e.filter.item) or '')
      end
      table.sort(pieces)
      parts[#parts + 1] = table.concat(pieces, ' ')
      for _, d in ipairs(run.market.demand) do parts[#parts + 1] = d.item .. d.units end
      for _, id in ipairs(run.upgrades) do parts[#parts + 1] = id end
      for _, id in ipairs(run.recipes) do parts[#parts + 1] = id end
      for _, m in ipairs(run.rules.mods) do parts[#parts + 1] = m.id end
      for sector = 1, 5 do parts[#parts + 1] = run.bosses[sector] and run.bosses[sector].desc or '-' end
      return table.concat(parts, ' ')
    end
    local function play(run)
      run:beginShift()
      while not run.factory:finished() do run.factory:step() end
      return run:endShift()
    end
    local function offerText(run)
      local parts = {}
      for _, o in ipairs(run:rollOffers()) do
        for _, p in ipairs(o.plot and o.plot.ports or {}) do parts[#parts + 1] = p.item .. p.x .. p.y end
        for _, d in ipairs(o.market.demand) do parts[#parts + 1] = d.item end
      end
      run:openShop()
      for _, o in ipairs(run.shop.offers) do parts[#parts + 1] = o.id end
      return table.concat(parts, ' ')
    end

    local run = Run.new(77)
    run.credits = 200
    run.blueprints.assembler, run.blueprints.wiremill = true, true
    run.upgrades = { 'bullion', 'scenic_route' }
    run.levels = { power = 2, ['value:iron'] = 3, ['speed:smelter'] = 1, ['rate:copper_ore'] = 2 }
    run.recipes = { 'twin_dies' }
    run:rollOffers()
    run:choose(2)
    run:advance()
    local slot = run.map:free()[1]
    run:annex(slot[1], slot[2])
    run.pendingPlot = require('src.map').generate(require('src.rng').new(5), { items = { 'coal' }, special = 'premium' })
    slot = run.map:free()[2]
    run:annex(slot[1], slot[2])
    run.bosses[1] = Bosses.make(Bosses.byId.blackout, { plots = { { slot[1], slot[2] } } })
    for i, port in ipairs(Route.ports(run)) do
      Route.belt(run, port, i <= 2 and { 'smelter', 'press' } or { 'filter' })
    end
    for _, e in ipairs(run.factory.world:query('filter')) do e.filter.item = 'coal' end
    run:placeRubble(3)
    run:refreshRules()
    play(run)
    run:rollOffers()
    run:choose(1)
    run:openShop()

    local copy = Run.restore(Save.decode(Save.encode(run:snapshot())))
    check('a restored run is the same run', describe(copy) == describe(run), describe(copy))
    check('down to the land, the rubble, the premium face and what is on offer',
      copy.map.count == run.map.count and copy.map.premium == 1 and #copy.factory.world:query('rubble') == 3
      and #copy.offers == 2 and copy.chosen == copy.offers[1] and #copy.shop.offers == #run.shop.offers
      and copy.shop.offers[1].id == run.shop.offers[1].id)
    local a, b = play(run), play(copy)
    check('it earns the same', a.total == b.total and a.total > 0 and copy.progress == run.progress, a.total .. ' vs ' .. b.total)
    check('and its dice roll on from where they were', offerText(copy) == offerText(run))

    -- Records.
    Records.persist = false
    Records.shift, Records.contract, Records.wins = 100, 3, 0
    check('a better shift is a record, a worse one is not',
      Records.shiftEnded(150) and Records.shift == 150 and not Records.shiftEnded(120) and Records.shift == 150)
    check('so is clearing more contracts than ever', Records.contractCleared(4, 12, 9) and Records.seed == 9
      and not Records.contractCleared(4, 12, 10) and Records.seed == 9)
    check('clearing the twelfth counts as a win', Records.contractCleared(12, 12, 11) and Records.wins == 1)
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
    check('a premium face pays 1.5x (15 ingots at $4.50: $67.50)', math.abs(s.exact - 67.5) < 1e-6 and s.total == 68, soldString(s))
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
    check('a run is 12 contracts, with a boss order fixed by the seed',
      run:total() == 12 and #run.bossOrder == 12 and #run.finalOrder == 3)
  end

  -- 12b. The shop: one blueprint or recipe, two modules, three investments.
  do
    local Investments = require 'src.data.investments'
    local Alternates = require 'src.data.alternates'
    local Machines = require 'src.data.machines'
    local run = Run.new(7)
    run.credits = 500
    run:openShop()
    local offers = run.shop.offers
    local kinds = {}
    for i, o in ipairs(offers) do kinds[i] = o.type end
    check('six offers: blueprint or recipe, 2 modules, 3 investments',
      #offers == 6 and (kinds[1] == 'blueprint' or kinds[1] == 'recipe') and kinds[2] == 'upgrade' and kinds[3] == 'upgrade'
      and kinds[4] == 'invest' and kinds[5] == 'invest' and kinds[6] == 'invest', table.concat(kinds, ','))
    check('the two modules differ, and so do the investments',
      offers[2].id ~= offers[3].id and offers[4].id ~= offers[5].id and offers[5].id ~= offers[6].id and offers[4].id ~= offers[6].id)

    -- Over many rolls: never anything owned, never an investment that does nothing here.
    local ok, sawBlueprint, sawRecipe = true, false, false
    run.upgrades = { 'bullion', 'middleman' }
    run.recipes = { 'twin_dies' }
    for _ = 1, 60 do
      run:rollShop()
      for _, o in ipairs(run.shop.offers) do
        if o.type == 'blueprint' then
          sawBlueprint = true
          ok = ok and not run.blueprints[o.id] and o.id ~= 'manufacturer'
        elseif o.type == 'recipe' then
          sawRecipe = true
          ok = ok and o.id ~= 'twin_dies' and run:unlocked(Alternates.byId[o.id].kind)
        elseif o.type == 'upgrade' then
          ok = ok and o.id ~= 'bullion' and o.id ~= 'middleman'
        else
          local def = Investments.byId[o.id]
          ok = ok and def.item ~= 'crude' and def.kind ~= 'assembler' and def.mat ~= 'oil'
        end
      end
    end
    check('offers: nothing owned, nothing useless on this site, no manufacturer before the assembler',
      ok and sawBlueprint and sawRecipe)

    -- Buying each kind of thing.
    run.upgrades, run.recipes = {}, {}
    run.shop.offers = {
      { type = 'blueprint', id = 'assembler', cost = 8 },
      { type = 'recipe', id = 'twin_dies', cost = 8 },
      { type = 'upgrade', id = 'bullion', cost = 5 },
      { type = 'invest', id = 'power', cost = 3 },
      { type = 'invest', id = 'value:iron', cost = 4 },
    }
    local credits, watts = run.credits, run.rules.basePower
    for i = 1, 5 do run:buy(i) end
    check('buying a blueprint unlocks the machine', run:unlocked('assembler'))
    check('buying a recipe adds it to the rules', run:hasRecipe('twin_dies') and #run.rules:recipesFor('press') == 6)
    check('buying a module fills a slot', run.upgrades[1] == 'bullion')
    check('a grid upgrade adds 10W', run.rules.basePower == watts + 10 and run.levels.power == 1)
    check('an investment gains a level, and the next one costs more',
      run.levels['value:iron'] == 1 and Investments.cost(Investments.byId['value:iron'], 1) == 6)
    check('credits are spent, and nothing can be bought twice', run.credits == credits - 28 and not run:buy(1))

    -- Five slots, then replace.
    run.upgrades = { 'bullion', 'middleman', 'monopoly', 'embargo', 'last_call' }
    run.shop.offers = { { type = 'upgrade', id = 'perfect_ratio', cost = 10 } }
    run.credits = 7
    check('a sixth module cannot simply be bought', run:buyBlocked(1) == 'slots full' and not run:buy(1))
    check('the refund counts towards the price (7 + 2 < 10, 7 + 3 >= 10)',
      not run:canReplace(1, 1) and run:canReplace(3, 1))
    check('replacing swaps it into the same slot', run:replaceUpgrade(3, 1)
      and run.upgrades[3] == 'perfect_ratio' and #run.upgrades == 5 and run.credits == 0 and run.upgrades[4] == 'embargo')
    check('selling pays half the price', run:sellUpgrade(3) and run.credits == 5 and #run.upgrades == 4)

    -- What is on sale depends on the site.
    local res, own = { iron_ore = true }, { smelter = true }
    local I = Investments.byId
    check('investments must do something here',
      Investments.eligible(I.power, 9, res, own) and Investments.eligible(I['rate:iron_ore'], 0, res, own)
      and not Investments.eligible(I['rate:crude'], 0, res, own) and not Investments.eligible(I['speed:press'], 0, res, own)
      and Investments.eligible(I['value:iron'], 20, res, own) and not Investments.eligible(I['value:gold'], 0, res, own))
    check('rates stop at a full belt, speeds at level 5',
      not Investments.eligible(I['rate:iron_ore'], 4, res, own) and not Investments.eligible(I['speed:smelter'], 5, res, own))
    local n = 0
    for _ in ipairs(Investments.list) do n = n + 1 end
    check('23 investments: power, 6 rates, 10 speeds, 6 values', n == 23, n)
    check('7 alternate recipes, each for a real machine', #Alternates.list == 7 and Machines[Alternates.list[7].kind] ~= nil)
  end

  -- 12c. Investments, alternate recipes and modules at work.
  do
    local Investments = require 'src.data.investments'
    local Alternates = require 'src.data.alternates'
    local Market = require 'src.market'
    local layout = require 'tests.layout'
    local U = Upgrades.byId
    local function count(s, t) return s.sold[t] and s.sold[t].n or 0 end
    local function near(a, b) return math.abs(a - b) < 1e-6 end
    local function straight(item)
      local F = Factory.new()
      F:place('port', 0, 2, 0, { item = item })
      belts(F, 1, 5, 2)
      F:place('export', 6, 2, 2)
      return F
    end
    local function with(levels, mods)
      local list = Investments.mods(levels)
      for _, m in ipairs(mods or {}) do list[#list + 1] = m end
      return Rules.new(list, { basePower = 200 + Investments.watts(levels), portRate = Investments.rates(levels) })
    end

    local s = runShift(straight('gear'), with({ ['value:iron'] = 2 }))
    check('iron value 2: gears sell for +40% (30 x $11.20)', near(s.exact, 336), s.exact)
    s = runShift(straight('motor'), with({ ['value:iron'] = 1, ['value:copper'] = 1 }))
    check('a motor gets the iron and the copper bonus, multiplied (x1.44)', near(s.exact, 30 * 32 * 1.44), s.exact)
    s = runShift(straight('glass'), with({ ['value:iron'] = 3 }))
    check('and glass gets neither', near(s.exact, 90), s.exact)

    s = runShift(straight('iron_ore'), with({ ['rate:iron_ore'] = 2 }))
    check('iron rate 2: the port supplies 45 a minute', count(s, 'iron_ore') == 45, soldString(s))
    s = runShift(straight('iron_ore'), with({ ['rate:iron_ore'] = 4 }))
    check('iron rate 4: a full belt, 60 a minute', count(s, 'iron_ore') == 60, soldString(s))
    local F = straight('iron_ore')
    F.world:query('port')[1].port.period = 1
    s = runShift(F, with({ ['rate:iron_ore'] = 4 }))
    check('a rich port cannot go past a full belt', count(s, 'iron_ore') == 60, soldString(s))

    s = runShift(layout({ 'I> s> E<' }), with({ ['speed:smelter'] = 5 }))
    check('smelter speed 5: one smelter keeps up with a port (30 ingots)', count(s, 'iron_ingot') == 30, soldString(s))
    F = layout({ 'I> s> E<' })
    local r = with({ ['speed:smelter'] = 1, ['value:iron'] = 1 })
    s = runShift(F, r)
    check('investments leave no marks on the board', r:affecting(F, F:at(1, 0)) == nil and F:at(1, 0).machine.speed == 1.2)
    local credited = 0
    for mod, rec in pairs(s.ledger) do
      if mod.investment then credited = credited + rec.delta end
    end
    check('but the ledger credits them (18 ingots x $0.60)', near(credited, count(s, 'iron_ingot') * 0.6), credited)
    check('power comes in steps of 10W', Investments.watts({ power = 3 }) == 30)

    -- Alternate recipes.
    s = runShift(layout({ 'I> s> p> E<' }), Rules.new({ Alternates.byId.twin_dies }))
    check('Twin Dies: 2 gears from every ingot (30 gears)', count(s, 'gear') == 30, soldString(s))
    s = runShift(layout({ 'I> bv ..', '.. f> E<', 'K> b^ ..' }), Rules.new({ Alternates.byId.blast_furnace }))
    check('Blast Furnace: steel straight from ore and coal', count(s, 'steel') == 12, soldString(s))
    F = layout({ 'O> r> b> t> r> E<', '.. .. .. E. .. ..' })
    F:at(3, 0).filter.item = 'tar'
    s = runShift(F, Rules.new({ Alternates.byId.cracking }, { basePower = 100 }))
    check('Cracking: tar becomes plastic too (15 + 15)', count(s, 'plastic') == 30 and count(s, 'tar') == 0, soldString(s))
    s = runShift(layout({ 'I> s> w> E<' }), Rules.new({ Alternates.byId.iron_wire }))
    check('Iron Wire: a wire mill takes iron ingots', count(s, 'wire') == 30, soldString(s))

    -- Modules: 40 of them, priced by rarity.
    local byRarity, codes, clash = {}, {}, false
    for _, u in ipairs(Upgrades.list) do
      byRarity[u.rarity] = (byRarity[u.rarity] or 0) + 1
      if codes[u.code] or u.cost ~= Upgrades.COST[u.rarity] or not u.desc then clash = true end
      codes[u.code] = true
    end
    check('40 modules: 19 common, 18 uncommon, 3 rare, each with its own code',
      #Upgrades.list == 40 and byRarity.common == 19 and byRarity.uncommon == 18 and byRarity.rare == 3 and not clash)

    s = runShift(straight('iron_ingot'), rules('bullion'))
    check('Bullion: tier 2 sells for triple', s.total == 270, soldString(s))
    s = runShift(straight('gear'), rules('middleman', 'deep_pockets'))
    check('Middleman x2 and Deep Pockets +30% on a tier 3 gear', near(s.exact, 30 * 8 * 2 * 1.3), s.exact)
    s = runShift(straight('engine'), rules('heavy_industry', 'top_shelf'))
    check('Heavy Industry +60% and Top Shelf +50% on an engine', near(s.exact, 30 * 232 * 1.6 * 1.5), s.exact)
    s = runShift(straight('motor'), rules('heavy_industry', 'top_shelf'))
    check('neither applies to a motor (2 materials, tier 4)', s.total == 960, soldString(s))
    s = runShift(straight('gear'), rules('short_haul'))
    check('Short Haul stays quiet after 5 tiles', s.total == 240, soldString(s))
    s = runShift(layout({ 'I> s> b> b> E<' }), rules('short_haul'))
    check('and pays +40% within 3', near(s.exact, 15 * 3 * 1.4), s.exact)

    local market = Market.mod({ demand = { { item = 'gear', mult = 3, units = 10 } }, slump = { item = 'plate', mult = 0.5 } })
    s = runShift(straight('gear'), Rules.new({ market, U.bull_run }))
    check('Bull Run: demand pays x4 (10 x 32 + 20 x 8)', s.total == 480, soldString(s))
    s = runShift(straight('gear'), Rules.new({ market, U.cornered_market }))
    check('Cornered Market: demand never runs out (30 x 24)', s.total == 720, soldString(s))
    s = runShift(straight('plate'), Rules.new({ market, U.contrarian }))
    check('Contrarian: the slump pays double (30 x 16)', s.total == 480, soldString(s))

    F = straight('gear')
    F:beginShift(rules('night_shift'), { shiftNo = 1 })
    while not F:finished() do F:step() end
    local first = F:endShift()
    F:beginShift(rules('night_shift'), { shiftNo = 2 })
    while not F:finished() do F:step() end
    check('Night Shift doubles the first shift only', first.mult == 2 and F:endShift().mult == 1)

    s = runShift(layout({ 'I> y> s> E<', '.. s> E< ..' }), rules('efficiency'))
    check('Efficiency Bonus: +2% per machine that kept busy', near(s.mult, 1.04), s.mult)
    s = runShift(layout({ 'I> s> p> E<' }), rules('efficiency'))
    check('and nothing for one that idled', near(s.mult, 1.02), s.mult)

    F = layout({ 'I> s> E<' })
    r = Rules.new({ U.overclock }, { basePower = 100 })
    s = runShift(F, r)
    check('Overclock: 25% faster for 50% more watts, with no marks on the board',
      F:at(1, 0).machine.speed == 1.25 and F:at(1, 0).machine.draw == 4.5 and r:affecting(F, F:at(1, 0)) == nil)
    F = layout({ 'I> bv ..', '.. f> E<', 'K> b^ ..' })
    r = Rules.new({ U.twin_feed }, { basePower = 100 })
    check('Twin Feed marks a machine fed from two sides', r:affecting(F, F:at(1, 1)) ~= nil
      and r:affecting(layout({ 'I> s> E<' }), layout({ 'I> s> E<' }):at(1, 0)) == nil)
    F = layout({ 'I> s> b> b> b> s> E<' })
    r = rules('depot_district')
    check('Depot District marks machines within 2 tiles of the depot',
      r:affecting(F, F:at(5, 0)) ~= nil and r:affecting(F, F:at(1, 0)) == nil)

    s = runShift(layout({ 'I> s> k> E<' }), rules('bulk_freight'))
    check('Bulk Freight: crates +30%', near(s.exact, count(s, 'iron_ingot') / 4 * 13.2 * 1.3), s.exact)
    s = runShift(layout({ 'I> o> E<' }), Rules.new({ U.premium_brand }, { basePower = 100 }))
    check('Premium Brand: polished items a further +50% (30 ore at $3)', s.total == 90, soldString(s))
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
    local Bosses = require 'src.data.bosses'
    local function boss(id, params)
      return Bosses.make(Bosses.byId[id], params)
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

    s, log = watchShift(layout({ 'I> E<' }), rules('scenic_route'))
    check('Scenic Route stays quiet with no belt', #log == 0 and s.ledger[U.scenic_route].n == 0 and s.total > 0, #log)
    s, log = watchShift(straight(), rules('scenic_route'))
    check('Scenic Route triggers on every sale off a long belt',
      #log == 30 and near(s.ledger[U.scenic_route].delta, 7.2) and all(log, function(t) return t.what == 'sale' and t.x == 13 end), #log)

    s, log = watchShift(straight(), rules('gold_standard'))
    check('Gold Standard stays quiet with no gold sold', #log == 0, #log)

    s, log = watchShift(straight(), rules('fools_gold'))
    check("Fool's Gold is credited the difference in type", near(s.ledger[U.fools_gold].delta, 60) and #log == 30, s.ledger[U.fools_gold].delta)

    -- Harmful triggers have a negative delta.
    s, log = watchShift(straight('copper_ore'), rules('embargo'))
    check('Embargo on copper registers as harmful',
      #log == 30 and all(log, function(t) return t.delta < 0 end) and s.total == 0 and near(s.ledger[U.embargo].delta, -30), s.total)
    s, log = watchShift(straight(), rules('embargo'))
    check('Embargo on iron registers as a gain', #log == 30 and all(log, function(t) return t.delta > 0 end) and s.total == 90, s.total)
    local tariff = boss('tariff', { mat = 'copper' })
    s, log = watchShift(straight('copper_ore'), Rules.new({ tariff }))
    check('Tariff is credited to the boss, and is harmful',
      #log == 30 and all(log, function(t) return t.mod == tariff and t.delta < 0 end) and near(s.ledger[tariff].delta, -15), #log)
    s, log = watchShift(straight('copper_ore'), Rules.new({ U.embargo, tariff }))
    check('a sale already worth $0 triggers nothing further', s.ledger[tariff].n == 0 and s.ledger[U.embargo].n == 30, s.ledger[tariff].n)

    -- Credit is marginal, in slot order.
    s = watchShift(straight(), rules('fools_gold', 'scrap_dealer'))
    check("slot order: Fool's Gold first", near(s.ledger[U.fools_gold].delta, 60) and near(s.ledger[U.scrap_dealer].delta, 180) and s.total == 270,
      s.ledger[U.fools_gold].delta .. ' / ' .. s.ledger[U.scrap_dealer].delta)
    s = watchShift(straight(), rules('scrap_dealer', 'fools_gold'))
    check('slot order: Scrap Dealer first', near(s.ledger[U.scrap_dealer].delta, 60) and near(s.ledger[U.fools_gold].delta, 180) and s.total == 270,
      s.ledger[U.scrap_dealer].delta .. ' / ' .. s.ledger[U.fools_gold].delta)

    -- The ledger always adds up, fractions and multipliers included.
    s = watchShift(straight(), rules('fools_gold', 'gold_standard', 'scenic_route', 'last_call'))
    check('ledger adds up to the revenue (fractional values)',
      near(ledgerSum(s), s.exact) and math.abs(s.total - s.exact) <= 0.5 and s.ledger[U.gold_standard].n > 0,
      ledgerSum(s) .. ' vs ' .. s.exact)
    s = watchShift(straight(), rules('fools_gold', 'gold_standard', 'monopoly', 'minimalist'))
    check('ledger adds up to the total (with two multipliers)', near(ledgerSum(s), s.exact) and near(s.mult, 2 * 1.48),
      ledgerSum(s) .. ' vs ' .. s.exact)

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
    local pressure = require('src.data.alternates').byId.pressure
    s, log = watchShift(layout({ 'K> p> E<' }), Rules.new({ pressure }))
    check('Pressure triggers on each diamond craft',
      #log >= s.sold.diamond.n and all(log, function(t) return t.mod == pressure and t.what == 'craft' and t.x == 1 end), #log)
    s, log = watchShift(layout({ 'I> s> p> E<' }), Rules.new({ pressure }))
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
