-- Build a factory from ASCII art, for tests and benchmarks.
-- Every tile is two characters: kind, then direction.
--   kinds: b belt   s smelter  p press     a assembler  c crusher
--          o polisher  g generator  y splitter  x bridge
--          I iron port  C copper port  K coal port  G gold port  E export
--          .  empty
--   dirs:  > v < ^   (or . for none)

local Factory = require 'src.sim.factory'

local KINDS = {
  b = 'belt', s = 'smelter', p = 'press', a = 'assembler', c = 'crusher',
  o = 'polisher', g = 'generator', y = 'splitter', x = 'bridge', E = 'export',
}
local PORTS = { I = 'iron_ore', C = 'copper_ore', K = 'coal', G = 'gold_ore' }
local DIRS = { ['>'] = 0, ['v'] = 1, ['<'] = 2, ['^'] = 3, ['.'] = 0 }

return function(rows)
  local F = Factory.new()
  for y, row in ipairs(rows) do
    local x = 0
    for cell in row:gmatch('%S%S') do
      local k, d = cell:sub(1, 1), DIRS[cell:sub(2, 2)]
      if PORTS[k] then
        F:place('port', x, y - 1, d, { item = PORTS[k] })
      elseif KINDS[k] then
        F:place(KINDS[k], x, y - 1, d)
      end
      x = x + 1
    end
  end
  return F
end
