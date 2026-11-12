-- QUOTA - a factory roguelite.
--   love .            play
--   lovec . --test    run the headless simulation tests
--   lovec . --bench   print revenue of reference layouts (for tuning quotas)

local flags = {}
for _, a in ipairs(arg or {}) do flags[a] = true end

if flags['--test'] or flags['--bench'] then
  function love.load()
    local mod = flags['--test'] and 'tests.sim_test' or 'tests.bench'
    local ok, result = xpcall(function() return require(mod)() end, debug.traceback)
    if not ok then print(result) end
    love.event.quit((ok and result) and 0 or 1)
  end
  return
end

local App = require 'src.app'

function love.load() App.load(flags) end
function love.update(dt) App.update(dt) end
function love.draw() App.draw() end
function love.mousepressed(x, y, b) App.mousepressed(x, y, b) end
function love.mousereleased(x, y, b) App.mousereleased(x, y, b) end
function love.mousemoved(x, y) App.mousemoved(x, y) end
function love.wheelmoved(dx, dy) App.wheelmoved(dx, dy) end
function love.keypressed(key) App.keypressed(key) end
