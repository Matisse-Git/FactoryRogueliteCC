-- Everything that can sit on a board tile.
--   time  = seconds (ticks) per craft        draw = watts while crafting
--   cost  = shop price of the blueprint      weight = how often the shop offers it
--   free  = no blueprint needed              needs = blueprint that must come first
-- A blueprint unlocks a kind for the rest of the run: place as many as the
-- power and the floor allow.
--
-- Machines differ in shape, so each brings its own ratio problem:
--   1 -> 1   smelter, press, polisher        1 -> 2   crusher, wire mill
--   2 -> 1   foundry, assembler              3 -> 1   manufacturer
--   1 -> 2 different   refinery              4 -> 1   packer

local Machines = {
  belt = {
    name = 'Belt', free = true,
    desc = 'Carries 60 items per minute.',
  },
  splitter = {
    name = 'Splitter', free = true,
    desc = 'In from the back. Alternates between front, left and right.',
  },
  bridge = {
    name = 'Bridge', free = true,
    desc = 'Lets two belts cross.',
  },
  filter = {
    name = 'Filter', free = true,
    desc = 'In from the back. The chosen item goes straight on; everything else leaves through the sides. F sets the item.',
  },
  generator = {
    name = 'Generator', free = true,
    generator = { fuel = { coal = 6, tar = 4 }, order = { 'coal', 'tar' }, watts = 10 },
    desc = 'Burns coal (10/min) or tar (15/min) for +10W.',
  },

  smelter = {
    name = 'Smelter', time = 4, draw = 3, cost = 5, weight = 3,
    desc = 'Ore or dust to ingot, quartz or sand to glass.',
  },
  crusher = {
    name = 'Crusher', time = 2, draw = 4, cost = 6, weight = 3,
    desc = '1 ore to 2 dust. Dust smelts like ore, so the ore goes twice as far.',
  },
  press = {
    name = 'Press', time = 3, draw = 3, cost = 5, weight = 3,
    desc = 'Shapes one ingot or pane: gear, plate, foil, beam, lens.',
  },
  wiremill = {
    name = 'Wire Mill', time = 2, draw = 3, cost = 6, weight = 3,
    desc = 'Draws one ingot or pane into 2 wires or fibres.',
  },
  foundry = {
    name = 'Foundry', time = 5, draw = 6, cost = 7, weight = 3,
    desc = 'Two inputs to an alloy: steel, silicon, electrum.',
  },
  refinery = {
    name = 'Refinery', time = 4, draw = 6, cost = 7, weight = 2,
    desc = 'Crude oil to plastic and tar. The tar has to go somewhere, or the refinery stops.',
  },
  assembler = {
    name = 'Assembler', time = 6, draw = 5, cost = 8, weight = 4,
    desc = 'Two parts to a component: motor, circuit, cable, chip, lamp.',
  },
  manufacturer = {
    name = 'Manufacturer', time = 10, draw = 12, cost = 12, weight = 3, needs = 'assembler',
    desc = 'Three components to a product: engine, robot, camera, computer.',
  },
  polisher = {
    name = 'Polisher', time = 2, draw = 10, cost = 8, weight = 2, polish = true,
    desc = 'Polishes any item: it sells for double. Hungry for power.',
  },
  packer = {
    name = 'Packer', time = 2, draw = 2, cost = 5, weight = 2, pack = 4,
    desc = 'Packs 4 identical items into a crate worth 10% more than the four. A crate takes one belt slot.',
  },

  -- Fixed board features (never built by the player).
  port   = { name = 'Port',   fixed = true, desc = 'Supplies a raw item.' },
  export = { name = 'Depot',  fixed = true, desc = 'Sells every item that enters, from any side.' },
  rubble = { name = 'Rubble', fixed = true, desc = 'Blocked for this contract.' },
  rock   = { name = 'Rock',   fixed = true, desc = 'Nothing can be built here.' },
  node   = { name = 'Power Node', fixed = true, desc = 'Adds 12W while you own this plot.' },
}

for kind, def in pairs(Machines) do def.kind = kind end

-- Order in the build palette, the shop pool and the recipe book.
Machines.list = {
  'belt', 'splitter', 'bridge', 'filter', 'generator',
  'smelter', 'crusher', 'press', 'wiremill', 'foundry', 'refinery',
  'assembler', 'manufacturer', 'polisher', 'packer',
}

return Machines
