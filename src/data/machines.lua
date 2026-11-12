-- Everything that can sit on a board tile.
--   time  = seconds (ticks) per craft        draw = watts while crafting
--   cost  = shop price                       weight = how often the shop offers it

local Machines = {
  belt = {
    name = 'Belt', free = true,
    desc = 'Carries 1 item per second. Free and unlimited.',
  },
  smelter = {
    name = 'Smelter', time = 4, draw = 3, cost = 4, weight = 3,
    desc = 'Ore or dust to ingot.',
  },
  press = {
    name = 'Press', time = 3, draw = 3, cost = 5, weight = 3,
    desc = 'Ingot to part: gear, wire x2 or foil.',
  },
  assembler = {
    name = 'Assembler', time = 6, draw = 5, cost = 7, weight = 3,
    desc = 'Two inputs to a product: steel, motor or circuit.',
  },
  crusher = {
    name = 'Crusher', time = 2, draw = 4, cost = 6, weight = 2,
    desc = '1 ore to 2 dust. Dust smelts like ore.',
  },
  polisher = {
    name = 'Polisher', time = 8, draw = 8, cost = 8, weight = 2, polish = true,
    desc = 'Polishes any item: sells for double.',
  },
  generator = {
    name = 'Generator', cost = 5, weight = 2,
    generator = { fuel = 'coal', burn = 6, watts = 8 },
    desc = 'Burns 1 coal per 6s for +8W.',
  },
  splitter = {
    name = 'Splitter', cost = 2, weight = 3,
    desc = 'In from the back. Alternates between front, left and right.',
  },
  bridge = {
    name = 'Bridge', cost = 2, weight = 2,
    desc = 'Lets two belts cross.',
  },

  -- Fixed board features (never in the kit).
  port   = { name = 'Port',   fixed = true, desc = 'Supplies 1 raw item every 2s.' },
  export = { name = 'Export', fixed = true, desc = 'Sells every item that enters.' },
  rubble = { name = 'Rubble', fixed = true, desc = 'Blocked tile.' },
}

for kind, def in pairs(Machines) do def.kind = kind end

-- Order in the build palette and the shop pool.
Machines.list = {
  'belt', 'smelter', 'press', 'assembler', 'crusher',
  'polisher', 'generator', 'splitter', 'bridge',
}

return Machines
