-- Dev tool:  lovec . --shots
-- Drives the game through its screens with real mouse / keyboard events,
-- checks the results, and saves 3x screenshots to the LÖVE save directory
-- (printed on exit). Exit code 1 if any check fails.
-- The numbered shots are the bare canvas; the *_crt_* ones go through the
-- CRT filter. Saved settings are neither read nor written.

return function(App)
  local Game = require 'src.ui.game'
  local Map = require 'src.map'
  local Route = require 'tests.route'
  local Settings = require 'src.settings'
  local Panel = require 'src.ui.settings'
  local Pause = require 'src.ui.pause'
  local Board = require 'src.ui.board'
  local Shop = require 'src.ui.shop'
  local Title = require 'src.ui.title'
  local Save = require 'src.save'
  local Records = require 'src.records'
  local Crt = require 'src.gfx.crt'
  local Contracts = require 'src.data.contracts'
  local Upgrades = require 'src.data.upgrades'
  local Bosses = require 'src.data.bosses'
  local U = Upgrades.byId
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
    local k = Crt.K * App.levels().bulge
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
    if type(x) == 'table' then x, y, b = x[1], x[2], y end
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

  -- Canvas position of the middle of a tile.
  local function cell(cx, cy)
    return Game.cellXY(App, cx, cy)
  end

  local function rclick(cx, cy)
    local x, y = Game.cellXY(App, cx, cy)
    click(x, y, 2)
  end

  local function F() return App.run.factory end

  -- Top-left tile of the plot the run started on.
  local function home()
    local d = App.run.map.depot[1]
    local sx, sy = Map.slotOf(d[1], d[2])
    return sx * Map.PW, sy * Map.PH
  end

  local function clearBoard()
    local f = F()
    for y = 0, f.H - 1 do
      for x = 0, f.W - 1 do f:remove(x, y) end
    end
  end

  -- Belt every port to the depot: a smelter on each ore line, and a press on
  -- the first. Returns the paths.
  local function autoBuild()
    local paths = {}
    for i, port in ipairs(Route.ports(App.run)) do
      local machines = {}
      if port.port.item ~= 'coal' then
        machines = (i == 1) and { 'smelter', 'press' } or { 'smelter' }
      end
      paths[i] = Route.belt(App.run, port, machines)
    end
    return paths
  end

  -- Place every pending plot in the first free slot.
  local function takeLand()
    if App.g.mode ~= 'annex' then return end
    local s = App.run.map:free()[1]
    click(cell(s[1] * Map.PW + 4, s[2] * Map.PH + 3))
  end

  -- Run single ticks until one has every wanted kind of trigger.
  local function stepUntil(limit, ...)
    local wanted = { ... }
    for _ = 1, limit do
      if App.g.mode ~= 'run' then return false end
      App.g.acc = 1
      wait(1)
      local seen = {}
      for _, ev in ipairs(F().events) do
        if ev.kind == 'trigger' then seen[ev.what] = true end
      end
      local ok = true
      for _, what in ipairs(wanted) do ok = ok and seen[what] end
      if ok then return true end
      wait(14)                     -- about a tick at 1x, so popups spread out
    end
    return false
  end

  local co = coroutine.create(function()
    wait(3)
    shot('01_title')
    expect('sound: the effects were built (and are muted here)', require('src.sfx').ok)

    App.seed = 4242
    App.keypressed('return')
    wait(2)
    expect('title: Enter starts a run', App.state == 'game' and App.g.mode == 'intro')
    shot('02_intro')

    ---------------------------------------------------------- building
    click(Game.at.intro)
    expect('intro: START enters build mode', App.g.mode == 'build')
    expect('the run opens on the depot, close up', App.g.cam.T == 16 and Game.cellAt(App.g, cell(App.run.map.depot[1][1], App.run.map.depot[1][2])) ~= nil)

    local ox, oy = home()
    click(Game.paletteXY(App, 'belt'))
    expect('palette: click selects the belt', App.g.tool == 'belt')

    local x, y = cell(ox + 1, oy + 1)
    App.move(x, y)
    App.press(x, y, 1)
    for cx = ox + 2, ox + 5 do App.move(cell(cx, oy + 1)) end
    for cy = oy + 2, oy + 3 do App.move(cell(ox + 5, cy)) end
    App.release(cell(ox + 5, oy + 3))
    wait(1)
    local f = F()
    expect('belt drag: lays a row heading east',
      f:at(ox + 1, oy + 1) and f:at(ox + 1, oy + 1).belt and f:at(ox + 1, oy + 1).building.dir == 0 and f:at(ox + 4, oy + 1) ~= nil)
    expect('belt drag: turns the corner south',
      f:at(ox + 5, oy + 1) and f:at(ox + 5, oy + 1).building.dir == 1 and f:at(ox + 5, oy + 3) ~= nil)

    App.keypressed('6')
    expect('keys: 6 selects the smelter', App.g.tool == 'smelter')
    local before = App.g.dir
    App.keypressed('r')
    expect('keys: R rotates the tool', App.g.dir == (before + 1) % 4)
    click(cell(ox + 1, oy + 4))
    click(cell(ox + 2, oy + 4))
    click(cell(ox + 3, oy + 4))
    expect('place: a blueprint builds any number', App.g.tool == 'smelter' and #f.world:query('machine') == 3)
    local edge = (ox == 8) and (ox - 1) or (ox + 8)        -- a tile next to the plot, not owned
    click(cell(edge, oy + 4))
    expect('place: not on land you do not own', f:at(edge, oy + 4) == nil)
    App.keypressed('q')
    expect('keys: Q puts the tool away', App.g.tool == nil)
    click(cell(ox + 1, oy + 4))
    expect('pick up: clicking a machine lifts it', App.g.tool == 'smelter' and f:at(ox + 1, oy + 4) == nil)
    click(cell(ox + 6, oy + 4))
    expect('pick up: and it can be put down elsewhere', f:at(ox + 6, oy + 4) and f:at(ox + 6, oy + 4).machine ~= nil)
    App.keypressed('q')
    rclick(ox + 3, oy + 1)
    expect('remove: right click deletes a belt', f:at(ox + 3, oy + 1) == nil)
    local port = f.world:query('port')[1]
    rclick(port.pos.x, port.pos.y)
    expect('remove: ports cannot be deleted', #f.world:query('port') == 2)
    local d = App.run.map.depot[1]
    rclick(d[1], d[2])
    expect('remove: nor can the depot', #f.world:query('export') == 4)

    ---------------------------------------------------------- select, copy, paste
    App.keypressed('v')
    expect('keys: V picks the select tool', App.g.tool == 'select')
    x, y = cell(ox + 2, oy + 4)
    App.move(x, y)
    App.press(x, y, 1)
    App.move(cell(ox + 3, oy + 4))
    App.release(cell(ox + 3, oy + 4))
    wait(1)
    local sel = App.g.sel
    expect('select: dragging marks a box', sel and sel.x1 == ox + 2 and sel.x2 == ox + 3 and sel.y1 == oy + 4)
    App.move(cell(ox + 2, oy + 3))
    wait(2)
    shot('03b_select')
    App.keypressed('c')
    expect('select: C copies it onto the stamp', App.g.tool == 'stamp' and #App.g.clip.items == 2 and App.g.clip.w == 2)
    App.keypressed('r')
    expect('stamp: R turns it', App.g.clip.w == 1 and App.g.clip.h == 2)
    App.move(cell(ox + 6, oy + 1))
    wait(2)
    shot('03c_stamp')
    click(cell(ox + 6, oy + 1))
    expect('stamp: a click pastes the pieces',
      f:at(ox + 6, oy + 1) and f:at(ox + 6, oy + 1).machine and f:at(ox + 6, oy + 2) and f:at(ox + 6, oy + 2).machine)
    click(cell(d[1], d[2]))
    expect('stamp: it will not paste over the depot', #f.world:query('export') == 4 and #f.world:query('machine') == 5)
    App.keypressed('q')
    App.keypressed('v')
    x, y = cell(ox + 6, oy + 1)
    App.move(x, y)
    App.press(x, y, 1)
    App.move(cell(ox + 6, oy + 2))
    App.release(cell(ox + 6, oy + 2))
    App.keypressed('x')
    expect('select: X cuts', f:at(ox + 6, oy + 1) == nil and App.g.tool == 'stamp')
    App.keypressed('q')
    App.keypressed('v')
    x, y = cell(ox + 1, oy + 4)
    App.move(x, y)
    App.press(x, y, 1)
    App.move(cell(ox + 6, oy + 4))
    App.release(cell(ox + 6, oy + 4))
    App.keypressed('delete')
    expect('select: Delete removes the pieces', #f.world:query('machine') == 0 and App.g.sel == nil)
    App.keypressed('q')

    ---------------------------------------------------------- filter
    click(Game.paletteXY(App, 'filter'))
    click(cell(ox + 1, oy + 4))
    local filter = f:at(ox + 1, oy + 4)
    expect('filter: placing one opens the item chooser', filter and filter.filter and App.g.picker ~= nil)
    App.move(128 - 74 + 4 + 3 * 14 + 7, 16 + (144 - 90) / 2 + 13 + 7)
    wait(2)
    shot('03e_filter_items')
    click(128 - 74 + 4 + 3 * 14 + 7, 16 + (144 - 90) / 2 + 13 + 7)      -- the 4th item: quartz
    expect('filter: a click sets the item', filter.filter.item == 'quartz' and App.g.picker == nil)
    click(cell(ox + 2, oy + 4))
    expect('filter: the next one keeps that item', f:at(ox + 2, oy + 4).filter.item == 'quartz' and App.g.picker == nil)
    App.keypressed('q')
    App.move(cell(ox + 1, oy + 4))
    App.keypressed('f')
    expect('filter: F reopens the chooser', App.g.picker ~= nil and App.g.picker.e == filter)
    App.keypressed('escape')
    expect('filter: Esc closes it', App.g.picker == nil and App.overlay == nil)
    wait(2)
    shot('03f_filter_set')
    rclick(ox + 1, oy + 4)
    rclick(ox + 2, oy + 4)

    ---------------------------------------------------------- camera
    App.move(cell(ox + 2, oy + 2))
    App.wheelmoved(0, -1)
    wait(2)
    expect('wheel down: the whole site', App.g.cam.T == 8 and App.g.cam.x == 0 and App.g.cam.y == 0)
    shot('03d_overview')
    App.keypressed('1')
    click(cell(ox + 2, oy + 4))
    expect('the overview is fully playable', f:at(ox + 2, oy + 4) and f:at(ox + 2, oy + 4).belt)
    App.keypressed('q')
    App.move(cell(ox + 2, oy + 2))
    App.wheelmoved(0, 1)
    wait(1)
    expect('wheel up: back in, on the tile under the mouse',
      App.g.cam.T == 16 and Game.cellAt(App.g, 128, 88) == ox + 2)
    local camx = App.g.cam.x
    Game.pan(App, -40, 0)
    expect('the camera moves', App.g.cam.x == camx - 40)
    Game.pan(App, -4000, -4000)
    expect('and stops at the edge of the site', App.g.cam.x == 0 and App.g.cam.y == 0)
    App.keypressed('z')
    App.keypressed('z')
    Game.setZoom(App.g, 16, d[1] + 1, d[2] + 1)
    App.keypressed('tab')
    wait(1)
    expect('keys: Tab opens the recipe book', App.g.book == true)
    App.keypressed('tab')

    ---------------------------------------------------------- contract 1
    clearBoard()
    local quota1 = Contracts.quotas[1]
    Contracts.quotas[1] = 99999      -- out of reach, so the first shift cannot clear it
    local paths = autoBuild()
    expect('both ports reach the depot', paths[1] ~= nil and paths[2] ~= nil)
    App.g.tool, App.g.dir = 'splitter', 1
    App.move(cell(ox + 6, oy + 4))
    wait(2)
    shot('03_build')
    App.g.tool = nil

    click(Game.at.run)
    expect('RUN starts the shift', App.g.mode == 'run')
    App.g.acc = 30.4
    wait(1)
    App.g.paused = true
    local smelter
    for _, e in ipairs(f.world:query('machine')) do
      if e.building.kind == 'smelter' then smelter = e end
    end
    App.move(cell(smelter.pos.x, smelter.pos.y))
    wait(2)
    shot('04_run')
    App.g.paused = false

    App.keypressed('return')
    App.keypressed('4')
    wait(1)
    expect('a running shift cannot be skipped', App.g.mode == 'run')
    click(Game.at.speed[3])
    expect('4X button sets the speed', App.g.speed == 4 and App.g.mode == 'run')
    local t0 = love.timer.getTime()     -- by the clock: frames may run unthrottled
    while App.g.mode == 'run' and love.timer.getTime() - t0 < 30 do wait(1) end
    expect('the shift ends on its own', App.g.mode == 'summary')
    App.g.speed = 1
    App.move(300, 100)
    wait(2)
    shot('05_summary')
    expect('warm start: the smelter worked the whole shift', f:utilisation(smelter) == 1)
    local earned = App.run.progress
    expect('shift earned revenue', earned > 0)

    click(Game.at.summary)
    expect('NEXT SHIFT returns to build mode', App.g.mode == 'build' and App.run.shiftsUsed == 1)
    App.keypressed('u')
    App.move(cell(smelter.pos.x, smelter.pos.y))
    wait(2)
    expect('keys: U shows how busy each machine was', App.g.stats == true)
    shot('05a_utilisation')
    App.wheelmoved(0, -1)
    wait(2)
    shot('05b_utilisation_overview')
    App.wheelmoved(0, 1)
    App.keypressed('u')

    Contracts.quotas[1] = quota1
    App.run.progress = quota1        -- bank enough to clear the contract
    App.keypressed('space')
    expect('keys: Space runs the shift', App.g.mode == 'run')
    Game.fastForward(App)
    wait(1)
    expect('banked revenue clears the contract', App.g.mode == 'summary' and App.g.summary.status == 'cleared')
    click(Game.at.summary)
    expect('COLLECT opens the contract board', App.state == 'board' and #App.run.offers == 2 and App.run.credits > 4)
    App.move(160, 100)
    wait(2)
    shot('05c_board')
    click(Board.at(2))
    expect('board: TAKE picks that contract and opens the shop',
      App.state == 'shop' and App.run.chosen == App.run.offers[2])
    click(Shop.at.menu)
    expect('shop: MENU opens the pause menu', App.overlay == 'pause')
    App.keypressed('escape')
    expect('shop: Esc closes it again', App.overlay == nil and App.state == 'shop')

    ---------------------------------------------------------- shop
    local run = App.run
    run.credits = 60
    local offers = run.shop.offers
    expect('shop: a blueprint or recipe, two modules, three investments',
      #offers == 6 and (offers[1].type == 'blueprint' or offers[1].type == 'recipe')
      and offers[2].type == 'upgrade' and offers[3].type == 'upgrade' and offers[6].type == 'invest')
    App.move(Shop.offerXY(App, 2))
    wait(2)
    shot('06_shop')
    local first = offers[1]
    click(Shop.offerXY(App, 1))
    expect('shop: BUY takes the blueprint or recipe',
      first.sold and (run:unlocked(first.id) or run:hasRecipe(first.id)))
    click(Shop.offerXY(App, 2))
    expect('shop: BUY adds a module', #run.upgrades == 1 and run.upgrades[1] == offers[2].id)
    local inv = offers[4].id
    click(Shop.offerXY(App, 4))
    expect('shop: BUY raises an investment a level', run.levels[inv] == 1 and offers[4].sold)
    click(Shop.at.reroll)
    expect('shop: REROLL rolls all six again', run.shop.rerolls == 1 and not run.shop.offers[1].sold
      and not run.shop.offers[4].sold)

    -- Selling, and replacing once the five slots are full.
    local credits = run.credits
    click(Shop.sellXY(1))
    expect('shop: SELL pays back half', #run.upgrades == 0 and run.credits > credits)
    run.upgrades = { 'bullion', 'middleman', 'monopoly', 'embargo', 'last_call' }
    run:refreshRules()
    run.credits = 30
    local wanted = run.shop.offers[2].id
    click(Shop.offerXY(App, 2))
    expect('shop: with five modules, buying asks which one goes',
      run.shop.replace == 2 and #run.upgrades == 5 and run.credits == 30)
    App.move(Shop.slotXY(3))
    wait(2)
    shot('07_shop_replace')
    App.keypressed('escape')
    expect('shop: Esc takes the question back', run.shop.replace == nil and App.overlay == nil)
    click(Shop.offerXY(App, 2))
    click(Shop.slotXY(3))
    expect('shop: clicking a module swaps it out, in place',
      run.upgrades[3] == wanted and #run.upgrades == 5 and run.shop.replace == nil and run.credits < 30)
    App.move(200, 158)
    wait(2)
    shot('07_shop_bought')
    click(Shop.at.next)
    expect('shop: NEXT CONTRACT moves on', App.state == 'game' and App.run.index == 2)

    ---------------------------------------------------------- new land
    expect('land: the next contract starts by placing a plot',
      App.g.mode == 'annex' and App.run.pendingPlot ~= nil and App.g.cam.T == 8)
    local free = App.run.map:free()
    App.move(cell(free[2][1] * Map.PW + 4, free[2][2] * Map.PH + 3))
    wait(2)
    shot('08a_new_land')
    click(cell(ox + 2, oy + 2))
    expect('land: clicking your own plot does nothing', App.g.mode == 'annex')
    local ports = #f.world:query('port')
    local plot = App.run.pendingPlot
    expect('land: it is the plot of the contract you took', plot ~= nil and App.run.market ~= nil)
    click(cell(free[2][1] * Map.PW + 4, free[2][2] * Map.PH + 3))
    expect('land: clicking a free slot places it',
      App.g.mode == 'intro' and App.run.map.count == 2 and App.run.map:has(free[2][1], free[2][2]))
    expect('land: its ports are on the board', #f.world:query('port') == ports + #plot.ports)
    click(Game.at.intro)
    App.wheelmoved(0, -1)
    App.move(300, 100)
    wait(2)
    shot('08b_two_plots')
    App.wheelmoved(0, 1)
    local c2 = App.run:contract()
    expect('boss: announced ahead, in the top bar', c2.boss == nil and c2.sectorBoss ~= nil and c2.bossIn == 1)

    ---------------------------------------------------------- later screens
    -- A boss that cuts off the plot the run started on.
    local hx, hy = Map.slotOf(ox, oy)
    App.run.bosses[1] = Bosses.make(Bosses.byId.blackout, { plots = { { hx, hy } } })
    App.run.index = 2
    App.run:advance()
    Game.enter(App)
    takeLand()
    wait(2)
    expect('a boss contract announces its twist', App.g.mode == 'intro' and App.run:contract().boss ~= nil)
    shot('08_boss_intro')
    click(Game.at.intro)
    Game.setZoom(App.g, 8, 0, 0)
    Game.startShift(App)
    App.g.acc = 10.5
    wait(2)
    App.g.paused = true
    local off = 0
    for _, e in ipairs(f.world:query('machine')) do
      if e.machine.status == 'off' then off = off + 1 end
    end
    expect('boss: Blackout stops the machines on the marked plot', off > 0)
    App.move(300, 120)
    wait(2)
    shot('08c_blackout')
    App.g.paused = false
    Game.fastForward(App)
    App.g.summary.status = 'next'
    Game.afterSummary(App)

    App.g.mode = 'build'
    App.keypressed('tab')
    wait(2)
    shot('09_book')
    for page = 2, 4 do
      App.keypressed('right')
      wait(2)
      shot('09_book_' .. page)
    end
    expect('book: arrows turn the pages', App.g.bookPage == 4)
    click(9 + 28, 10)
    expect('book: a tab click turns to that page', App.g.book and App.g.bookPage == 1)
    click(160, 100)
    expect('book: a click elsewhere closes it', not App.g.book)

    App.run.index = 6
    App.run:advance()
    Game.enter(App)
    takeLand()
    App.g.mode = 'build'
    clearBoard()
    for _, kind in ipairs(require('src.data.machines').list) do App.run.blueprints[kind] = true end
    autoBuild()
    Game.setZoom(App.g, 8, 0, 0)
    App.move(300, 100)
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
    -- Build mode: machines changed by a static modifier carry pips.
    Game.afterSummary(App)
    if App.state ~= 'game' then          -- the late layout may clear the contract
      App.state = 'game'
      App.g.mode = 'build'
    end
    clearBoard()
    App.run.upgrades = { 'assembly_line', 'direct_drive', 'isolation' }
    App.run:refreshRules()
    paths = autoBuild()
    Game.setZoom(App.g, 16, paths[1][2][1], paths[1][2][2])
    App.move(256 + 3 + 8, 46)
    wait(3)
    expect('pips: a static modifier lights its card', App.g.lit[U.direct_drive] ~= nil or App.g.lit[U.isolation] ~= nil)
    expect('pips: hovering a card picks its machines', App.g.hoverMod == U.assembly_line)
    shot('14_build_pips')

    -- A shift: cards pop, tiles flash, the ledger fills in.
    clearBoard()
    App.run.upgrades = { 'scenic_route', 'embargo', 'leaky_splitter', 'perfect_ratio', 'minimalist' }
    App.run:refreshRules()
    paths = autoBuild()
    local mid = paths[1][#paths[1] - 1]
    f:remove(mid[1], mid[2])
    f:place('splitter', mid[1], mid[2], mid[3])
    Game.setZoom(App.g, 16, mid[1], mid[2])
    App.move(300, 120)               -- off every card
    Game.startShift(App)
    App.g.speed = 1
    App.g.acc = 20.5
    wait(40)
    local both = stepUntil(30, 'sale', 'dup') or stepUntil(8, 'sale')
    expect('triggers: a sale and a duplicate in one tick', both)
    expect('triggers: the card pops', next(App.g.fx.pops) ~= nil)
    local ledger = f.shift.ledger
    expect('triggers: the ledger fills in', ledger[U.scenic_route].n > 0 and ledger[U.leaky_splitter].n > 0)
    shot('15_run_triggers')

    -- The summary plays out one end-of-shift line at a time.
    Game.fastForward(App)
    expect('reveal: one line per end-of-shift upgrade', App.g.mode == 'summary' and App.g.reveal.n == 2)
    App.g.reveal.t = 0.4 * 2 + 0.02
    wait(1)
    shot('16_summary_reveal')
    click(Game.at.summary)
    expect('reveal: the first click only finishes it', App.g.mode == 'summary' and App.g.reveal.shown == 2)
    App.move(300, 120)
    wait(2)
    shot('17_summary_done')
    App.g.summary.status = 'next'
    click(Game.at.summary)
    expect('reveal: the second click moves on', App.g.mode == 'build')

    -- A boss twist that bites shakes the boss label.
    App.run.bosses[3] = Bosses.make(Bosses.byId.tariff, { mat = 'copper' })
    App.run.index = 8
    App.run:advance()
    Game.enter(App)
    takeLand()
    App.g.mode = 'build'
    App.run.upgrades = { 'scenic_route' }
    App.run:refreshRules()
    clearBoard()
    autoBuild()
    App.move(300, 120)
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

    -- Win the run, then keep going.
    App.g.summary.status = 'next'
    Game.afterSummary(App)
    App.run.index = 12
    App.run:startContract()
    Game.enter(App)
    App.g.mode = 'build'
    App.run.progress = App.run:contract().quota
    Game.startShift(App)
    Game.fastForward(App)
    wait(1)
    click(Game.at.summary)
    expect('clearing contract 12 wins the run', App.g.mode == 'win' and App.run.won)
    App.move(300, 120)
    wait(2)
    shot('13a_win')
    click(Game.at.keepGoing)
    expect('KEEP GOING: endless mode, and the boss reward first',
      App.state == 'board' and App.run.endless and App.run.reward ~= nil)
    App.move(300, 170)
    wait(2)
    shot('13b_boss_reward')
    local nopts = #App.run.reward.options
    local first = App.run.reward.options[1]
    click(Board.rewardAt(1, nopts))
    expect('reward: TAKE unlocks it and shows the next contracts',
      App.run.reward == nil and #App.run.offers == 2 and (App.run:unlocked(first.id) or App.run:hasRecipe(first.id)))
    click(Board.at(1))
    click(Shop.at.next)
    expect('endless: on to contract 13', App.state == 'game' and App.run.index == 13)
    takeLand()
    wait(2)
    shot('13c_endless_intro')
    click(Game.at.intro)

    -- Lose on purpose: burn the remaining shifts with an empty board.
    clearBoard()
    App.run.progress = 0
    for _ = 1, 4 do
      if App.g.mode == 'summary' then
        App.run.progress = 0
        App.g.summary.status = App.run:shiftsLeft() > 0 and 'next' or 'failed'
        Game.afterSummary(App)
      end
      if App.g.mode == 'build' then
        Game.startShift(App)
        Game.fastForward(App)
      end
    end
    if App.g.mode == 'summary' then Game.afterSummary(App) end
    wait(2)
    expect('missing the quota ends the run', App.g.mode == 'over')
    shot('13_run_over')
    click(Game.at.finish)
    expect('TITLE returns to the title screen', App.state == 'title')

    ---------------------------------------------------------- settings panel
    expect('crt: the filter is available', Crt.ok)
    expect('settings: defaults', Settings.crt == 50 and Settings.integer)
    expect('a run that ended leaves nothing to continue', not App.hasSave())
    click(Title.at.records)
    expect('title: RECORDS opens the records', App.overlay == 'records' and Records.contract >= 12 and Records.wins == 1)
    App.move(300, 20)
    wait(2)
    shot('19a_records')
    App.keypressed('escape')
    expect('records: Esc closes them', App.overlay == nil and App.state == 'title')
    click(Title.at.settings)
    expect('settings: the title button opens the panel', App.overlay == 'settings')
    click(Panel.stop(30, 'sound'))
    expect('settings: the sound slider sets the volume', Settings.sound == 30)
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

    -- One slider per part.
    click(Panel.at('mode'))
    expect('custom: the switch shows a slider per part', Settings.custom and Panel.stop(0, 'bulge') ~= nil)
    expect('custom: the parts start from the one slider',
      Settings.scanlines == 40 and Settings.glow == 40 and Settings.bulge == 40)
    click(Panel.stop(100, 'bulge'))
    expect('custom: a slider moves only its own part',
      App.levels().bulge == 1 and App.levels().glow == 0.4 and Settings.crt == 40)
    App.keypressed('up')
    App.keypressed('left')
    expect('custom: Up / Down pick the slider the arrows move', Settings.fringe == 30 and Settings.bulge == 100)
    click(Panel.stop(0, 'scanlines'))
    App.move(300, 20)
    wait(2)
    shot('24_settings_custom')
    click(Panel.at('mode'))
    expect('custom: switching back keeps the one slider',
      not Settings.custom and Settings.crt == 40 and App.levels().bulge == 0.4)
    click(Panel.at('mode'))
    expect('custom: and the parts keep their own values',
      Settings.custom and Settings.bulge == 100 and Settings.scanlines == 0)
    for _, part in ipairs(Settings.PARTS) do click(Panel.stop(0, part)) end
    expect('custom: every part at 0 turns the filter off', Crt.off(App.levels()))
    click(Panel.at('mode'))

    for _ = 1, 6 do App.keypressed('left') end
    expect('slider: 0 turns the filter off', Settings.crt == 0 and Crt.off(App.levels()))

    expect('scaling: whole numbers by default', App.layout(1000, 700) == 3)
    click(Panel.at('integer'))
    expect('scaling: the switch allows fractional sizes',
      not Settings.integer and App.layout(1000, 700) == 3.125)
    wait(2)
    crtShot('22_fractional_scaling', 1000, 700)
    click(Panel.at('integer'))
    expect('scaling: and switches back', Settings.integer and App.layout(1000, 700) == 3)

    App.keypressed('escape')
    expect('settings: Esc closes the panel, not the game', App.overlay == nil and App.state == 'title')

    ---------------------------------------------------------- pause menu
    App.seed = 4242
    App.keypressed('return')
    wait(2)
    click(Game.at.intro)
    f = F()
    ox, oy = home()
    App.g.tool = 'belt'
    App.keypressed('escape')
    expect('pause: Esc first drops the piece in hand', App.g.tool == nil and App.overlay == nil)
    App.keypressed('escape')
    expect('pause: then opens the pause menu', App.overlay == 'pause')
    App.move(300, 20)
    wait(2)
    shot('25_pause')
    App.keypressed('escape')
    expect('pause: Esc resumes', App.overlay == nil and App.state == 'game')
    click(Game.at.menu)
    expect('pause: the MENU button opens it', App.overlay == 'pause')
    click(Pause.at('settings'))
    expect('pause: SETTINGS opens the settings', App.overlay == 'settings')
    click(Panel.at('close'))
    expect('pause: closing them returns to the pause menu', App.overlay == 'pause')
    App.keypressed('f10')
    App.keypressed('f10')
    expect('pause: so does F10', App.overlay == 'pause')
    click(Pause.at('resume'))
    expect('pause: RESUME returns to the run', App.overlay == nil and App.state == 'game')

    ---------------------------------------------------------- CRT filter
    Settings.set('crt', 100)
    App.g.tool = 'belt'
    -- Put a free tile of the home plot in the top-left corner of the view,
    -- where the bulge moves the picture most, and click near its far corner.
    local cam = App.g.cam
    cam.x, cam.y = (ox + 1) * 16 - 16, (oy + 1) * 16 - 16
    local px, py = 31.5, 47.5
    local wantX, wantY = Game.cellAt(App.g, math.floor(px), math.floor(py))
    local wx, wy = screenOf(px, py)
    local s, lox, loy = App.layout()
    local rawX, rawY = Game.cellAt(App.g, math.floor((wx - lox) / s), math.floor((wy - loy) / s))
    expect('bulge: the picture really moves at this spot',
      wantX == ox + 1 and wantY == oy + 1 and (rawX ~= wantX or rawY ~= wantY))
    App.mousemoved(wx, wy)
    App.mousepressed(wx, wy, 1)
    wait(1)
    App.mousereleased(wx, wy, 1)
    wait(1)
    expect('bulge: a corner click lands on the tile under the cursor',
      f:at(wantX, wantY) and f:at(wantX, wantY).belt and #f.world:query('belt') == 1)
    App.g.tool = nil
    clearBoard()

    Game.setZoom(App.g, 16, ox + 4, oy + 3)
    autoBuild()
    Game.startShift(App)
    App.g.acc = 30.4
    wait(3)
    App.keypressed('f10')
    expect('settings: F10 opens the panel during a shift', App.overlay == 'settings')
    local acc = App.g.acc
    wait(10)
    expect('settings: the shift waits while the panel is open', App.g.acc == acc)
    App.move(300, 20)
    wait(2)
    crtShot('23_crt_settings_100', 1280, 720)
    App.keypressed('f10')
    wait(3)
    expect('settings: closing it resumes the shift', App.overlay == nil and App.g.acc ~= acc)
    App.keypressed('escape')
    acc = App.g.acc
    wait(10)
    expect('pause: the shift waits behind the pause menu', App.overlay == 'pause' and App.g.acc == acc)
    App.keypressed('escape')

    App.g.paused = true
    App.move(cell(ox + 2, oy + 2))
    wait(2)
    crtShot('21_crt_100', 1280, 720)
    Settings.set('crt', 50)
    wait(2)
    crtShot('20_crt_50', 1280, 720)
    Settings.setCustom(true)
    for _, part in ipairs(Settings.PARTS) do Settings[part] = 0 end
    Settings.scanlines = 100
    wait(2)
    crtShot('26_crt_custom_scanlines_only', 1280, 720)
    Settings.setCustom(false)
    App.g.paused = false
    Game.fastForward(App)

    ---------------------------------------------------------- save and continue
    App.g.summary.status = 'next'
    Game.afterSummary(App)
    Game.setZoom(App.g, 16, ox + 4, oy + 3)
    App.g.tool, App.g.dir = 'filter', 2
    click(cell(ox + 1, oy + 4))
    App.g.picker.e.filter.item = 'gear'
    App.g.picker = nil
    App.keypressed('q')
    local pieces, used, credits = #f.world:query('building'), App.run.shiftsUsed, App.run.credits
    App.keypressed('escape')
    expect('pause: opening the menu saves the run', App.overlay == 'pause' and App.hasSave())
    click(Pause.at('quit'))
    expect('pause: SAVE AND QUIT returns to the title, run kept',
      App.state == 'title' and App.overlay == nil and App.run == nil and App.hasSave())
    App.move(300, 20)
    wait(2)
    shot('27_title_continue')
    click(Title.at.continue)
    f = F()
    local filter = f:at(ox + 1, oy + 4)
    expect('title: CONTINUE picks the run up where it was',
      App.state == 'game' and App.g.mode == 'build' and App.run.seed == 4242
      and #f.world:query('building') == pieces and App.run.shiftsUsed == used and App.run.credits == credits)
    expect('continue: pieces keep their direction and filters their item',
      filter and filter.filter and filter.filter.item == 'gear' and filter.building.dir == 2)

    -- Closing the game mid-shift: the shift has not happened.
    local banked = App.run.progress
    Game.startShift(App)
    App.g.acc = 20.5
    wait(2)
    App.quit()
    App.saveAndQuit()
    App.continueRun()
    expect('continue: a shift cut short is simply run again',
      App.g.mode == 'build' and App.run.shiftsUsed == used and App.run.progress == banked)

    -- In the shop.
    App.run.progress = App.run:contract().quota
    Game.startShift(App)
    Game.fastForward(App)
    App.save()
    App.saveAndQuit()
    App.continueRun()
    expect('continue: a cleared contract is collected on return', App.state == 'board' and #App.run.offers == 2)
    click(Board.at(1))
    App.run.credits = 30
    click(Shop.offerXY(App, 4))
    local level = App.run.levels[App.run.shop.offers[4].id]
    App.saveAndQuit()
    App.continueRun()
    expect('continue: the shop is as you left it',
      App.state == 'shop' and App.run.shop.offers[4].sold and App.run.levels[App.run.shop.offers[4].id] == level
      and App.run.chosen == App.run.offers[1])
    click(Shop.at.next)
    expect('continue: and the run goes on', App.state == 'game' and App.run.index == 2 and App.g.mode == 'annex')
    takeLand()
    click(Game.at.intro)

    ---------------------------------------------------------- abandoning
    App.keypressed('escape')
    click(Pause.at('abandon'))
    expect('abandon: one click only asks', App.overlay == 'pause' and App.state == 'game')
    App.move(300, 20)
    wait(2)
    click(Pause.at('abandon'))
    expect('abandon: moving away takes the question back', App.overlay == 'pause' and App.state == 'game')
    click(Pause.at('abandon'))
    expect('abandon: a second click ends the run', App.overlay == nil and App.state == 'title')
    expect('abandon: and removes its save', not App.hasSave())
    Save.delete()

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
