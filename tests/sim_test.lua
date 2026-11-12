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

  -- 1. A straight belt: 1 ore every 2s, 12 tiles to the export.
  do
    local F = Factory.new()
    F:place('port', 0, 2, 0, { item = 'iron_ore' })
    belts(F, 1, 12, 2)
    F:place('export', 13, 2, 2)
    local s = runShift(F)
    check('straight belt sells 24 ore for $24', s.total == 24, soldString(s))
  end

  -- 2. Smelter fed directly by a port: 4s per ingot.
  do
    local F = Factory.new()
    F:place('port', 0, 2, 0, { item = 'iron_ore' })
    F:place('smelter', 1, 2, 0)
    F:place('export', 2, 2, 2)
    local s = runShift(F)
    local n = s.sold.iron_ingot and s.sold.iron_ingot.n or 0
    check('one smelter makes 14 ingots in a shift', n == 14, soldString(s))
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
    check('splitter + 2 smelters make 26+ ingots', n >= 26 and n <= 30, soldString(s))
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
    check("Fool's Gold: iron ore sells as gold ore", s.total == 48 and s.sold.gold_ore ~= nil, soldString(s))
    s = runShift(straight(), rules('scrap_dealer'))
    check('Scrap Dealer: ore sells as ingot', s.total == 72, soldString(s))
    s = runShift(straight(), rules('fools_gold', 'scrap_dealer'))
    check('both: iron ore sells as gold ingot', s.total == 24 * 8, soldString(s))
    s = runShift(straight(), rules('monopoly'))
    check('Monopoly doubles a single-type shift', s.total == 48 and s.mult == 2, soldString(s))
    s = runShift(straight(), rules('scenic_route'))
    check('Scenic Route pays for distance', s.total == 24 * (1 + 3), soldString(s))
    s = runShift(straight(), rules('overtime'))
    check('Overtime lengthens the shift', s.total > 24, soldString(s))
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
    check('polisher doubles value (7 ore for $14)', count(s, 'iron_ore') == 7 and s.total == 14, soldString(s))

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
    check('Perfect Ratio: an idling press does not', s.mult == 1, soldString(s))

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

  -- 10c. Boss rubble comes and goes with the contract.
  do
    local run = Run.new(5)
    for _, b in ipairs(Contracts.bosses) do
      if b.id == 'rockfall' then run.bosses[1] = b end
    end
    run.index = 2
    run:advance()
    check('Rockfall buries 8 tiles', #run.factory.world:query('rubble') == 8)
    run:advance()
    check('rubble is cleared for the next contract', #run.factory.world:query('rubble') == 0)
    check('sector 2 adds a third port', #run.factory.world:query('port') == 3)
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

  -- 12. A run can be played start to finish through the Run API.
  do
    local run = Run.new(7)
    local F = run.factory
    local port, export
    for _, e in ipairs(F.world:query('building')) do
      if e.port and not port then port = e end
      if e.export then export = e end
    end
    -- Snake a belt from the first port to the export.
    local y = port.pos.y
    for x = 1, 12 do F:place('belt', x, y, 0) end
    local ey = export.pos.y
    if ey == y then
      -- already lined up
    else
      local step = ey > y and 1 or -1
      local dir = ey > y and 1 or 3
      F:remove(12, y)
      for yy = y, ey - step, step do
        if not F:at(12, yy) then F:place('belt', 12, yy, dir) end
      end
      F:place('belt', 12, ey, 0)
    end
    run:beginShift()
    while not F:finished() do F:step() end
    local s = run:endShift()
    check('run API: shift produces revenue', s.total > 0 and run.progress == s.total, s.total)
    check('run API: status is set', s.status == 'next' or s.status == 'cleared', s.status)
    check('quota table matches contract count', #Contracts.quotas == 9)
  end

  print(string.format('%d passed, %d failed', passed, failed))
  return failed == 0
end
