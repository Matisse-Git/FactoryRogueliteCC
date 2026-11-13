-- App shell: 320x180 canvas put on screen through the CRT filter, screen
-- switching, the pause menu and settings panel on top, input.

local P = require 'src.gfx.palette'
local Font = require 'src.gfx.font'
local Sprites = require 'src.gfx.sprites'
local Crt = require 'src.gfx.crt'
local UI = require 'src.ui.ui'
local Run = require 'src.run'
local Settings = require 'src.settings'
local Panel = require 'src.ui.settings'
local Pause = require 'src.ui.pause'
local Save = require 'src.save'
local Records = require 'src.records'
local Sfx = require 'src.sfx'

-- App.overlay is nil, 'pause', 'settings' or 'records': what sits on top of
-- the screen.
local App = { W = 320, H = 180, state = 'title', time = 0, seed = 1 }

local screens = {
  title = require 'src.ui.title',
  game = require 'src.ui.game',
  shop = require 'src.ui.shop',
  board = require 'src.ui.board',
}

local overlays = { pause = Pause, settings = Panel, records = require 'src.ui.records' }
local NO_FILTER = { scanlines = 0, glow = 0, vignette = 0, fringe = 0, bulge = 0 }

local function randomSeed()
  return os.time() % 90000 + 10000
end

function App.load(flags)
  love.graphics.setDefaultFilter('nearest', 'nearest')
  love.graphics.setLineStyle('rough')
  App.canvas = love.graphics.newCanvas(App.W, App.H)
  App.canvas:setFilter('nearest', 'nearest')
  Font.load()
  Sprites.load()
  Crt.load()
  App.seed = randomSeed()
  Sfx.load()
  if flags['--shots'] then
    -- The script neither reads nor writes anything saved, and makes no noise.
    Settings.persist, Records.persist = false, false
    Save.FILE = 'shots-run.lua'    -- its own save file, removed when it is done
    Save.delete()
    Sfx.mute = true
    App.script = require('tools.shots')(App)
  else
    Settings.load()
    Records.load()
    if Settings.fullscreen then love.window.setFullscreen(true, 'desktop') end
  end
end

function App.newRun()
  Save.delete()
  App.run = Run.new(App.seed)
  Records.runStarted()
  screens.game.enter(App)
  App.state = 'game'
  App.save()
end

-- The run is over, won or lost: nothing left to resume.
function App.toTitle()
  Save.delete()
  App.run = nil
  App.state = 'title'
  App.seed = randomSeed()
end

---------------------------------------------------------------- saving

-- Where a saved run picks up, from where the game is now. Nil: the run is
-- over and there is nothing to save.
local function resumePoint()
  if App.state == 'shop' or App.state == 'board' then return App.state end
  local g = App.g
  if g.mode == 'summary' then
    local status = g.summary.status
    if status == 'failed' then return nil end
    return status == 'cleared' and 'cleared' or 'build'
  elseif g.mode == 'over' then
    return nil
  elseif g.mode == 'run' then
    return 'build'                 -- a shift cut short is simply run again
  end
  return g.mode                    -- annex, intro, build, win
end

-- Write the run in progress to disk. Called wherever something was decided.
function App.save()
  if not App.run or App.state == 'title' or not Save.persist then return end
  local resume = resumePoint()
  if not resume then
    Save.delete()
    return
  end
  local data = { run = App.run:snapshot(), resume = resume }
  -- A shift in progress has not happened yet as far as the save goes.
  if App.state == 'game' and App.g.mode == 'run' then data.run.shiftsUsed = data.run.shiftsUsed - 1 end
  Save.write(data)
end

function App.hasSave()
  return Save.exists()
end

-- Pick up the saved run. Returns false if there is none (or it is damaged).
function App.continueRun()
  local data = Save.read()
  local ok, run = pcall(function() return data and Run.restore(data.run) end)
  if not ok or not run then
    Save.delete()
    return false
  end
  App.run = run
  App.seed = run.seed
  screens.game.enter(App)
  App.state = 'game'
  local g, resume = App.g, data.resume
  if resume == 'board' or resume == 'shop' then
    App.state = resume
  elseif resume == 'cleared' then
    -- Saved on the summary of a contract that was cleared: collect it now.
    run:payout()
    if run.index == run:total() then
      run.won = true
      g.mode = 'win'
    else
      screens.game.goOn(App)
    end
  elseif resume == 'build' or resume == 'win' then
    g.mode = resume
  end
  return true
end

-- Leave a run without ending it: it stays saved.
function App.saveAndQuit()
  App.save()
  App.overlay = nil
  App.run = nil
  App.state = 'title'
  App.seed = randomSeed()
end

function App.quit()
  App.save()
end

-- Strength of each part of the CRT filter, 0..1; all 0 when the filter
-- could not be built.
function App.levels()
  return Crt.ok and Settings.levels() or NO_FILTER
end

-- The largest picture that fits a w x h area (the window by default),
-- centred with black bars. Whole-number scales only, unless the player
-- turned that off.
function App.layout(w, h)
  if not w then w, h = love.graphics.getDimensions() end
  local s = math.min(w / App.W, h / App.H)
  if Settings.integer then s = math.max(1, math.floor(s)) end
  return s, math.floor((w - App.W * s) / 2), math.floor((h - App.H * s) / 2)
end

-- Window position to canvas pixel, through the same bulge the filter draws.
function App.toCanvas(x, y)
  local s, ox, oy = App.layout()
  local u, v = Crt.warp((x + 0.5 - ox) / (App.W * s), (y + 0.5 - oy) / (App.H * s), App.levels())
  return math.floor(u * App.W), math.floor(v * App.H)
end

function App.setFullscreen(on)
  love.window.setFullscreen(on, 'desktop')
  Settings.set('fullscreen', on)
end

-- An overlay sits on top of the current screen, which stops updating (so a
-- running shift waits) and stops receiving input.
local function show(name)
  if not App.overlay then
    local scr = screens[App.state]
    if scr.release then scr.release(App, UI.mx, UI.my, 1) end   -- end any drag
  end
  UI.click = nil
  App.overlay = name
end

-- Settings open from anywhere (F10), and close back to where they came
-- from: the pause menu or the screen.
function App.openSettings()
  if App.overlay == 'settings' then return end
  App.settingsFrom = App.overlay
  show('settings')
end

function App.closeSettings()
  Panel.release()
  if App.settingsFrom == 'pause' then Pause.open() end
  show(App.settingsFrom)
  App.settingsFrom = nil
end

-- The pause menu exists only during a run. Opening it saves the run.
function App.openPause()
  if App.overlay or App.state == 'title' then return end
  App.save()
  Pause.open()
  show('pause')
end

function App.closePause()
  show(nil)
end

function App.abandonRun()
  show(nil)
  App.toTitle()
end

function App.openRecords()
  if not App.overlay then show('records') end
end

function App.closeRecords()
  show(nil)
end

function App.update(dt)
  dt = math.min(dt, 0.1)
  App.time = App.time + dt
  if App.overlay then return end
  local scr = screens[App.state]
  if scr.update then scr.update(App, dt) end
end

-- Put the canvas on the current render target, sized for a w x h area.
function App.present(w, h)
  local s, ox, oy = App.layout(w, h)
  local levels = App.levels()
  love.graphics.setColor(1, 1, 1, 1)
  if Crt.ok and (s ~= math.floor(s) or not Crt.off(levels)) then
    Crt.draw(App.canvas, ox, oy, s, levels)
  else
    love.graphics.draw(App.canvas, ox, oy, 0, s, s)
  end
end

function App.draw()
  love.graphics.setCanvas(App.canvas)
  love.graphics.clear(P.bg[1], P.bg[2], P.bg[3], 1)
  UI.beginFrame()
  local over = overlays[App.overlay]
  if over then
    -- The screen underneath is drawn with no mouse and no click.
    local mx, my, click = UI.mx, UI.my, UI.click
    UI.mx, UI.my, UI.click = -1, -1, nil
    screens[App.state].draw(App)
    UI.mx, UI.my, UI.click, UI.tip = mx, my, click, nil
    over.draw(App)
  else
    screens[App.state].draw(App)
  end
  UI.endFrame()
  love.graphics.setCanvas()

  love.graphics.clear(0, 0, 0, 1)
  App.present()

  if App.script then App.script() end
end

-- Whatever takes input right now: the overlay or the screen.
local function target()
  return overlays[App.overlay] or screens[App.state]
end

-- Canvas-space input (also used by the screenshot script).
function App.press(x, y, b)
  UI.mx, UI.my = x, y
  local t = target()
  if t.press then t.press(App, x, y, b) end
end

function App.release(x, y, b)
  local t = target()
  if t.release then t.release(App, x, y, b) end
end

function App.move(x, y)
  UI.mx, UI.my = x, y
  local t = target()
  if t.moved then t.moved(App, x, y) end
end

function App.mousepressed(x, y, b)
  local cx, cy = App.toCanvas(x, y)
  App.press(cx, cy, b)
end

function App.mousereleased(x, y, b)
  local cx, cy = App.toCanvas(x, y)
  App.release(cx, cy, b)
end

function App.mousemoved(x, y)
  local cx, cy = App.toCanvas(x, y)
  App.move(cx, cy)
end

function App.wheelmoved(dx, dy)
  local t = target()
  if t.wheel and dy ~= 0 then t.wheel(App, dy) end
end

function App.keypressed(key)
  if key == 'f11' then
    App.setFullscreen(not love.window.getFullscreen())
    return
  end
  if key == 'f10' then
    if App.overlay == 'settings' then App.closeSettings() else App.openSettings() end
    return
  end
  -- In a run, Esc first cancels whatever the screen has open or in hand;
  -- with nothing to cancel it opens the pause menu.
  if key == 'escape' and not App.overlay and App.state ~= 'title' then
    local scr = screens[App.state]
    if not (scr.cancel and scr.cancel(App)) then App.openPause() end
    return
  end
  local t = target()
  if t.key then t.key(App, key) end
end

return App
