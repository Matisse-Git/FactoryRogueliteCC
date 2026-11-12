-- App shell: 320x180 canvas scaled by whole numbers, screen switching, input.

local P = require 'src.gfx.palette'
local Font = require 'src.gfx.font'
local Sprites = require 'src.gfx.sprites'
local UI = require 'src.ui.ui'
local Run = require 'src.run'

local App = { W = 320, H = 180, state = 'title', time = 0, seed = 1 }

local screens = {
  title = require 'src.ui.title',
  game = require 'src.ui.game',
  shop = require 'src.ui.shop',
}

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
  App.seed = randomSeed()
  if flags['--shots'] then App.script = require('tools.shots')(App) end
end

function App.newRun()
  App.run = Run.new(App.seed)
  screens.game.enter(App)
  App.state = 'game'
end

function App.toTitle()
  App.state = 'title'
  App.seed = randomSeed()
end

-- Largest whole-number scale that fits, centred (letterboxed).
function App.layout()
  local w, h = love.graphics.getDimensions()
  local s = math.max(1, math.floor(math.min(w / App.W, h / App.H)))
  return s, math.floor((w - App.W * s) / 2), math.floor((h - App.H * s) / 2)
end

function App.toCanvas(x, y)
  local s, ox, oy = App.layout()
  return math.floor((x - ox) / s), math.floor((y - oy) / s)
end

function App.update(dt)
  dt = math.min(dt, 0.1)
  App.time = App.time + dt
  local scr = screens[App.state]
  if scr.update then scr.update(App, dt) end
end

function App.draw()
  love.graphics.setCanvas(App.canvas)
  love.graphics.clear(P.bg[1], P.bg[2], P.bg[3], 1)
  UI.beginFrame()
  screens[App.state].draw(App)
  UI.endFrame()
  love.graphics.setCanvas()

  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
  local s, ox, oy = App.layout()
  love.graphics.draw(App.canvas, ox, oy, 0, s, s)

  if App.script then App.script() end
end

-- Canvas-space input (also used by the screenshot script).
function App.press(x, y, b)
  UI.mx, UI.my = x, y
  local scr = screens[App.state]
  if scr.press then scr.press(App, x, y, b) end
end

function App.release(x, y, b)
  local scr = screens[App.state]
  if scr.release then scr.release(App, x, y, b) end
end

function App.move(x, y)
  UI.mx, UI.my = x, y
  local scr = screens[App.state]
  if scr.moved then scr.moved(App, x, y) end
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
  local scr = screens[App.state]
  if scr.wheel and dy ~= 0 then scr.wheel(App, dy) end
end

function App.keypressed(key)
  if key == 'f11' then
    love.window.setFullscreen(not love.window.getFullscreen(), 'desktop')
    return
  end
  local scr = screens[App.state]
  if scr.key then scr.key(App, key) end
end

return App
