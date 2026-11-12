-- Headless mode (`lovec . --test`) runs the simulation tests without a window.
local headless = false
for _, a in ipairs(arg or {}) do
  if a == '--test' or a == '--bench' then headless = true end
end

function love.conf(t)
  t.identity = 'factory-roguelite'
  t.version = '11.5'
  t.modules.joystick = false
  t.modules.physics = false
  t.modules.video = false
  if headless then
    t.modules.window = false
    t.modules.graphics = false
    t.modules.audio = false
    t.modules.sound = false
  else
    t.window.title = 'QUOTA - a factory roguelite'
    t.window.width = 1280
    t.window.height = 720
    t.window.minwidth = 320
    t.window.minheight = 180
    t.window.resizable = true
    t.window.vsync = 1
  end
end
