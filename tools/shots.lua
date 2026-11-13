-- Dev tool:  lovec . --shots
-- Drives the game through its screens with real mouse / keyboard events,
-- checks the results, and saves 3x screenshots to the LÖVE save directory
-- (printed on exit). Exit code 1 if any check fails.
-- The numbered shots are the bare canvas; the *_crt_* ones go through the
-- CRT filter. Saved settings are neither read nor written.

return function(App)
  local Game = require 'src.ui.game'
  local Factory = require 'src.sim.factory'
  local Settings = require 'src.settings'
  local Panel = require 'src.ui.settings'
  local Crt = require 'src.gfx.crt'
  local out = love.graphics.newCanvas(960, 540)
  out:setFilter('nearest', 'nearest')
  local failed = false

  -- The picture as the player sees it (CRT filter, scaling) in a w x h window.
  local function crtShot(name, w, h)
    local big = love.graphics.newCanvas(w, h)
    love.graphics.setCanvas(big)
    love.graphics.clear(0, 0, 0, 1)
    App.present(w, h)
    love.graphics.setCanvas()
    big:newImageData():encode('png', name .. '.png')
    big:release()
  end

  -- Window position at which the filter draws a canvas point: the inverse of
  -- Crt.warp, by iteration.
  local function screenOf(px, py)
    local s, ox, oy = App.layout()
    local k = Crt.K * App.crt()
    local dx, dy = px / App.W * 2 - 1, py / App.H * 2 - 1
    local cx, cy = dx, dy
    for _ = 1, 20 do cx, cy = dx / (1 + k * cy * cy), dy / (1 + k * cx * cx) end
    return math.floor(ox + (cx + 1) / 2 * App.W * s), math.floor(oy + (cy + 1) / 2 * App.H * s)
  end

  local function shot(name)
    love.graphics.setCanvas(out)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(App.canvas, 0, 0, 0, 3, 3)
    love.graphics.setCanvas()
    out:newImageData():encode('png', name .. '.png')
  end

  local function wait(n)
    for _ = 1, n or 1 do coroutine.yield() end
  end

  local function click(x, y, b)
    App.move(x, y)
    App.press(x, y, b or 1)
    wait(1)
    App.release(x, y, b or 1)
    wait(1)
  end

  local function expect(name, cond)
    print((cond and '  ok    ' or '  FAIL  ') .. name)
    if not cond then failed = true end
  end

  local function cellXY(cx, cy)
    return cx * 16 + 8, 20 + cy * 16 + 8
  end

  -- Belt every port to the export, with the starter machines on the way.
  local function autoBuild()
    local F = App.run.factory
    local ports, export = {}, nil
    for _, e in ipairs(F.world:query('building')) do
      if e.port then ports[#ports + 1] = e end
      if e.export then export = e end
    end
    local ey = export.pos.y
    for i, port in ipairs(ports) do
      local y = port.pos.y
      for x = 1, 11 do Game.placeAt(App, 'belt', x, y, 0) end
      if port.port.item ~= 'coal' then
        Game.placeAt(App, 'smelter', 3, y, 0)
        if i == 1 then Game.placeAt(App, 'press', 4, y, 0) end
      end
      local dir = (y == ey) and 0 or (ey > y and 1 or 3)
      Game.placeAt(App, 'belt', 12, y, dir)
      if y ~= ey then
        local step = ey > y and 1 or -1
        for yy = y + step, ey - step, step do
          if not F:at(12, yy) then Game.placeAt(App, 'belt', 12, yy, dir) end
        end
      end
    end
    Game.placeAt(App, 'belt', 12, ey, 0)
  end

  local co = coroutine.create(function()
    wait(3)
    shot('01_title')

    App.seed = 4242
    App.keypressed('return')
    wait(2)
    expect('title: Enter starts a run', App.state == 'game' and App.g.mode == 'intro')
    shot('02_intro')

    ---------------------------------------------------------- input checks
    local F = App.run.factory
    click(112, 142)
    expect('intro: START enters build mode', App.g.mode == 'build')

    click(238, 34)
    expect('palette: click selects the belt', App.g.tool == 'belt')

    local x, y = cellXY(2, 7)
    App.move(x, y)
    App.press(x, y, 1)
    for cx = 3, 5 do App.move(cellXY(cx, 7)) end
    for cy = 8, 9 do App.move(cellXY(5, cy)) end
    App.release(cellXY(5, 9))
    wait(1)
    expect('belt drag: lays a row heading east',
      F:at(2, 7) and F:at(2, 7).belt and F:at(2, 7).building.dir == 0 and F:at(4, 7) ~= nil)
    expect('belt drag: turns the corner south',
      F:at(5, 7) and F:at(5, 7).building.dir == 1 and F:at(5, 9) ~= nil)

    App.keypressed('2')
    expect('keys: 2 selects the smelter', App.g.tool == 'smelter')
    local before = App.g.dir
    App.keypressed('r')
    expect('keys: R rotates the tool', App.g.dir == (before + 1) % 4)
    click(cellXY(8, 7))
    expect('place: smelter lands on the board', F:at(8, 7) and F:at(8, 7).machine ~= nil)
    click(cellXY(9, 7))
    expect('place: tool clears when the kit runs out', App.g.tool == nil and App.run:available('smelter') == 0)
    click(cellXY(8, 7))
    expect('pick up: clicking a machine lifts it', App.g.tool == 'smelter' and F:at(8, 7) == nil)
    click(cellXY(8, 2))
    expect('pick up: and it can be put down elsewhere', F:at(8, 2) and F:at(8, 2).machine ~= nil)
    App.g.tool = nil
    local rx, ry = cellXY(4, 7)
    click(rx, ry, 2)
    expect('remove: right click deletes a belt', F:at(4, 7) == nil)
    local px, py = cellXY(0, F.world:query('port')[1].pos.y)
    click(px, py, 2)
    expect('remove: ports cannot be deleted', #F.world:query('port') == 2)
    App.keypressed('x')
    expect('keys: X clears the board', #F.world:query('belt') == 0 and #F.world:query('machine') == 0)
    App.keypressed('tab')
    wait(1)
    expect('keys: Tab opens the recipe book', App.g.book == true)
    App.keypressed('tab')

    ---------------------------------------------------------- belt shapes
    local demo = {
      -- a closed loop: four corners, both handednesses appear when reversed
      { 2, 6, 0 }, { 3, 6, 0 }, { 4, 6, 1 }, { 4, 7, 1 }, { 4, 8, 2 }, { 3, 8, 2 }, { 2, 8, 3 }, { 2, 7, 3 },
      -- a line with feeds from both sides, then an S-bend
      { 6, 6, 0 }, { 7, 6, 0 }, { 8, 6, 0 }, { 9, 6, 0 }, { 10, 6, 1 }, { 10, 7, 1 }, { 10, 8, 0 }, { 11, 8, 0 },
      { 7, 5, 1 }, { 7, 4, 1 }, { 8, 7, 3 }, { 8, 8, 3 },
      -- counter-clockwise turns
      { 6, 2, 2 }, { 5, 2, 2 }, { 4, 2, 3 }, { 4, 1, 3 }, { 4, 0, 0 }, { 5, 0, 0 }, { 6, 0, 1 }, { 6, 1, 1 },
    }
    for _, b in ipairs(demo) do Game.placeAt(App, 'belt', b[1], b[2], b[3]) end
    Game.placeAt(App, 'smelter', 9, 5, 1)
    App.move(300, 100)
    wait(2)
    shot('03a_belt_shapes')
    App.keypressed('x')

    ---------------------------------------------------------- contract 1
    autoBuild()
    App.g.tool, App.g.dir = 'splitter', 1
    App.move(cellXY(6, 5))
    wait(2)
    shot('03_build')
    App.g.tool = nil

    click(250, 170)
    expect('RUN SHIFT starts the shift', App.g.mode == 'run')
    App.g.acc = 30.4
    wait(1)
    App.g.paused = true
    App.move(cellXY(3, F.world:query('port')[1].pos.y))
    wait(2)
    shot('04_run')
    App.g.paused = false

    App.keypressed('return')
    App.keypressed('4')
    wait(1)
    expect('a running shift cannot be skipped', App.g.mode == 'run')
    click(300, 170)
    expect('4X button sets the speed', App.g.speed == 4 and App.g.mode == 'run')
    for _ = 1, 900 do
      if App.g.mode ~= 'run' then break end
      wait(1)
    end
    expect('the shift ends on its own', App.g.mode == 'summary')
    App.g.speed = 1
    shot('05_summary')
    local earned = App.run.progress
    expect('shift earned revenue', earned > 0)

    click(170, 157)
    expect('NEXT SHIFT returns to build mode', App.g.mode == 'build' and App.run.shiftsUsed == 1)

    App.run.progress = 9999          -- bank enough to clear the contract
    App.keypressed('space')
    expect('keys: Space runs the shift', App.g.mode == 'run')
    Game.fastForward(App)
    wait(1)
    expect('banked revenue clears the contract', App.g.mode == 'summary' and App.g.summary.status == 'cleared')
    click(170, 157)
    expect('COLLECT opens the shop', App.state == 'shop' and App.run.credits > 4)

    ---------------------------------------------------------- shop
    App.run.credits = 40
    App.move(8 + 2 * 77 + 20, 50)
    wait(2)
    shot('06_shop')
    local kitBefore = 0
    for _, n in pairs(App.run.kit) do kitBefore = kitBefore + n end
    click(44, 79)
    local kitAfter = 0
    for _, n in pairs(App.run.kit) do kitAfter = kitAfter + n end
    expect('shop: BUY adds a machine to the kit', kitAfter == kitBefore + 1 and App.run.shop.offers[1].sold)
    click(8 + 2 * 77 + 36, 79)
    expect('shop: BUY adds an upgrade', #App.run.upgrades == 1)
    click(30, 99)
    expect('shop: REROLL rolls new offers', App.run.shop.rerolls == 1 and not App.run.shop.offers[1].sold)
    for i = 3, 4 do App.run:buy(i) end
    App.run:reroll()
    for i = 3, 4 do App.run:buy(i) end
    App.run.credits = 99
    for i = 3, 4 do App.run:buy(i) end
    local owned, credits = #App.run.upgrades, App.run.credits
    click(16 + 19, 127, 2)
    expect('shop: right click sells an upgrade',
      #App.run.upgrades == owned - 1 and App.run.credits > credits)
    App.run.credits = 9
    App.move(16, 127)
    wait(2)
    shot('07_shop_bought')
    click(270, 171)
    expect('shop: NEXT CONTRACT moves on', App.state == 'game' and App.run.index == 2 and App.g.mode == 'intro')

    ---------------------------------------------------------- later screens
    App.run.index = 2
    App.run:advance()
    Game.enter(App)
    wait(2)
    shot('08_boss_intro')

    App.g.mode = 'build'
    App.g.book = true
    wait(2)
    shot('09_book')
    App.g.book = false

    App.run.index = 6
    App.run:advance()
    Game.enter(App)
    App.g.mode = 'build'
    for yy = 0, Factory.H - 1 do
      for xx = 0, Factory.W - 1 do App.run.factory:remove(xx, yy) end
    end
    App.run.kit.generator = 1
    App.run.kit.assembler = 1
    autoBuild()
    App.move(244, 104)
    wait(2)
    shot('10_sector3')

    Game.startShift(App)
    App.g.acc = 45.5
    wait(1)
    App.g.paused = true
    wait(2)
    shot('11_run_late')
    App.g.paused = false
    Game.fastForward(App)
    wait(2)
    shot('12_summary_late')

    ---------------------------------------------------------- upgrade feedback
    local Upgrades = require 'src.data.upgrades'
    local Contracts = require 'src.data.contracts'
    local U = Upgrades.byId
    local function clearBoard()
      for yy = 0, Factory.H - 1 do
        for xx = 0, Factory.W - 1 do App.run.factory:remove(xx, yy) end
      end
    end
    local function firstPortRow()
      for _, e in ipairs(App.run.factory.world:query('building')) do
        if e.port and e.port.item ~= 'coal' then return e.pos.y end
      end
    end
    -- Run single ticks until one has every wanted kind of trigger.
    local function stepUntil(limit, ...)
      local wanted = { ... }
      for _ = 1, limit do
        if App.g.mode ~= 'run' then return false end
        App.g.acc = 1
        wait(1)
        local seen = {}
        for _, ev in ipairs(App.run.factory.events) do
          if ev.kind == 'trigger' then seen[ev.what] = true end
        end
        local ok = true
        for _, what in ipairs(wanted) do ok = ok and seen[what] end
        if ok then return true end
        wait(14)                     -- about a tick at 1x, so popups spread out
      end
      return false
    end

    -- Build mode: machines changed by a static modifier carry pips.
    Game.afterSummary(App)
    clearBoard()
    App.run.kit = { smelter = 4, press = 2, splitter = 1, bridge = 1, generator = 1, assembler = 1 }
    App.run.upgrades = { 'assembly_line', 'direct_drive', 'isolation' }
    App.run:refreshRules()
    autoBuild()
    local py = firstPortRow()
    Game.placeAt(App, 'smelter', 3, py > 0 and py - 1 or py + 1, 0)
    App.move(224 + 3 + 8, 104)
    wait(3)
    expect('pips: static modifiers light their cards', App.g.lit[U.assembly_line] and App.g.lit[U.direct_drive])
    expect('pips: hovering a card picks its machines', App.g.hoverMod == U.assembly_line)
    shot('14_build_pips')

    -- A shift: cards pop, tiles flash, the ledger fills in.
    clearBoard()
    App.run.upgrades = { 'scenic_route', 'embargo', 'leaky_splitter', 'perfect_ratio', 'minimalist' }
    App.run:refreshRules()
    autoBuild()
    Game.placeAt(App, 'splitter', 7, py, 0)
    App.move(300, 90)                -- off every card, so the ledger shows
    Game.startShift(App)
    App.g.speed = 1
    App.g.acc = 20.5
    wait(40)
    local both = stepUntil(30, 'sale', 'dup') or stepUntil(8, 'sale')
    expect('triggers: a sale and a duplicate in one tick', both)
    expect('triggers: the card pops', next(App.g.fx.pops) ~= nil)
    local ledger = App.run.factory.shift.ledger
    expect('triggers: the ledger fills in', ledger[U.scenic_route].n > 0 and ledger[U.leaky_splitter].n > 0)
    shot('15_run_triggers')

    -- The summary plays out one end-of-shift line at a time.
    Game.fastForward(App)
    expect('reveal: one line per end-of-shift upgrade', App.g.mode == 'summary' and App.g.reveal.n == 2)
    App.g.reveal.t = 0.4 * 2 + 0.02
    wait(1)
    shot('16_summary_reveal')
    click(170, 157)
    expect('reveal: the first click only finishes it', App.g.mode == 'summary' and App.g.reveal.shown == 2)
    App.move(300, 90)
    wait(2)
    shot('17_summary_done')
    click(170, 157)
    expect('reveal: the second click moves on', App.g.mode == 'build')

    -- A boss twist that bites shakes the boss label.
    for _, b in ipairs(Contracts.bosses) do
      if b.id == 'tariff' then App.run.bosses[3] = b end
    end
    App.run.index = 8
    App.run:advance()
    Game.enter(App)
    App.g.mode = 'build'
    App.run.upgrades = { 'scenic_route' }
    App.run:refreshRules()
    clearBoard()
    autoBuild()
    App.move(300, 90)
    Game.startShift(App)
    App.g.acc = 20.5
    wait(40)
    local bitten = false
    for _ = 1, 30 do
      stepUntil(1, 'sale')
      if App.g.fx.pops[App.run:contract().boss] then bitten = true; break end
    end
    expect('boss: Tariff triggers on a copper sale', bitten)
    shot('18_boss_trigger')
    Game.fastForward(App)

    -- Lose on purpose: burn the remaining shifts with an empty board.
    for yy = 0, Factory.H - 1 do
      for xx = 0, Factory.W - 1 do App.run.factory:remove(xx, yy) end
    end
    for _ = 1, 4 do
      if App.g.mode == 'summary' then Game.afterSummary(App) end
      if App.g.mode == 'build' then
        Game.startShift(App)
        Game.fastForward(App)
      end
    end
    Game.afterSummary(App)
    wait(2)
    expect('missing the quota ends the run', App.g.mode == 'over' and App.run.lost)
    shot('13_run_over')
    click(112, 130)
    expect('TITLE returns to the title screen', App.state == 'title')

    ---------------------------------------------------------- settings panel
    expect('crt: the filter is available', Crt.ok)
    expect('settings: defaults', Settings.crt == 50 and Settings.integer)
    click(160, 160)
    expect('settings: the title button opens the panel', App.settingsOpen)
    local seed = App.seed
    App.keypressed('3')
    expect('settings: keys do not reach the screen underneath', App.seed == seed)
    App.move(300, 20)
    wait(2)
    shot('19_settings')

    click(Panel.stop(100))
    expect('slider: a click sets the strength', Settings.crt == 100)
    local sx, sy = Panel.stop(100)
    App.move(sx, sy)
    App.press(sx, sy, 1)
    App.move(Panel.stop(30), sy + 20)
    wait(1)
    App.release(Panel.stop(30), sy + 20, 1)
    expect('slider: dragging follows the mouse', Settings.crt == 30)
    App.move(Panel.stop(80), sy)
    expect('slider: and stops on release', Settings.crt == 30)
    App.keypressed('right')
    expect('slider: arrow keys step by 10', Settings.crt == 40)
    for _ = 1, 6 do App.keypressed('left') end
    expect('slider: 0 turns the filter off', Settings.crt == 0 and App.crt() == 0)

    expect('scaling: whole numbers by default', App.layout(1000, 700) == 3)
    click(219, 104)
    expect('scaling: the switch allows fractional sizes',
      not Settings.integer and App.layout(1000, 700) == 3.125)
    wait(2)
    crtShot('22_fractional_scaling', 1000, 700)
    click(219, 104)
    expect('scaling: and switches back', Settings.integer and App.layout(1000, 700) == 3)

    App.keypressed('escape')
    expect('settings: Esc closes the panel, not the game', not App.settingsOpen and App.state == 'title')

    ---------------------------------------------------------- CRT filter
    App.seed = 4242
    App.keypressed('return')
    wait(2)
    click(112, 142)
    App.keypressed('x')
    F = App.run.factory
    Settings.set('crt', 100)
    App.g.tool = 'belt'
    -- The inner corner of cell (1, 0): drawn far enough from where an
    -- unfiltered picture has it that an uncorrected mouse hits cell (2, 1).
    local wx, wy = screenOf(31.5, 35.5)
    local s, ox, oy = App.layout()
    local nx, ny = math.floor((wx - ox) / s / 16), math.floor(((wy - oy) / s - 20) / 16)
    expect('bulge: the picture really moves at this spot', nx == 2 and ny == 1)
    App.mousemoved(wx, wy)
    App.mousepressed(wx, wy, 1)
    wait(1)
    App.mousereleased(wx, wy, 1)
    wait(1)
    expect('bulge: a corner click lands on the tile under the cursor',
      F:at(1, 0) and F:at(1, 0).belt and F:at(2, 1) == nil)
    App.g.tool = nil
    App.keypressed('x')

    autoBuild()
    Game.startShift(App)
    App.g.acc = 30.4
    wait(3)
    App.keypressed('f10')
    expect('settings: F10 opens the panel during a shift', App.settingsOpen)
    local acc = App.g.acc
    wait(10)
    expect('settings: the shift waits while the panel is open', App.g.acc == acc)
    App.move(300, 20)
    wait(2)
    crtShot('23_crt_settings_100', 1280, 720)
    App.keypressed('f10')
    wait(3)
    expect('settings: closing it resumes the shift', not App.settingsOpen and App.g.acc ~= acc)

    App.g.paused = true
    App.move(cellXY(3, F.world:query('port')[1].pos.y))
    wait(2)
    crtShot('21_crt_100', 1280, 720)
    Settings.set('crt', 50)
    wait(2)
    crtShot('20_crt_50', 1280, 720)
    App.g.paused = false
    Game.fastForward(App)

    print('screenshots saved to ' .. love.filesystem.getSaveDirectory())
  end)

  return function()
    if coroutine.status(co) == 'dead' then
      love.event.quit(failed and 1 or 0)
      return
    end
    local ok, err = coroutine.resume(co)
    if not ok then
      print(debug.traceback(co, err))
      love.event.quit(1)
    end
  end
end
