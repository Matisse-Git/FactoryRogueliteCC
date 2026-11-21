-- Build a factory from ASCII art, for tests and benchmarks.
-- Every tile is two characters: kind, then direction.
--   kinds: b belt   s smelter  p press     a assembler  c crusher
--          o polisher  g generator  y splitter  x bridge
--          w wire mill  f foundry  r refinery  m manufacturer  k packer
--          t filter (set its item with F:at(x, y).filter.item)
--          I iron port  C copper port  K coal port  G gold port
--          Q quartz port  O crude oil port  E export
--          # rock  * booster pad (floor only)
--          .  empty
--   dirs:  > v < ^   (or . for none)

local Factory = require 'src.sim.factory'

local KINDS = {
  b = 'belt', s = 'smelter', p = 'press', a = 'assembler', c = 'crusher',
  o = 'polisher', g = 'generator', y = 'splitter', x = 'bridge', E = 'export',
  w = 'wiremill', f = 'foundry', r = 'refinery', m = 'manufacturer', k = 'packer', t = 'filter',
}
local PORTS = { I = 'iron_ore', C = 'copper_ore', K = 'coal', G = 'gold_ore', Q = 'quartz', O = 'crude' }
local DIRS = { ['>'] = 0, ['v'] = 1, ['<'] = 2, ['^'] = 3, ['.'] = 0 }

return function(rows)
  local F = Factory.new()
  for y, row in ipairs(rows) do
    local x = 0
    for cell in row:gmatch('%S%S') do
      local k, d = cell:sub(1, 1), DIRS[cell:sub(2, 2)]
      if k == '#' then
        F:place('rock', x, y - 1, 0)
      elseif k == '*' then
        F:setFloor(x, y - 1, 'pad')
      elseif PORTS[k] then
        F:place('port', x, y - 1, d, { item = PORTS[k] })
      elseif KINDS[k] then
        F:place(KINDS[k], x, y - 1, d)
      end
      x = x + 1
    end
  end
  return F
end
