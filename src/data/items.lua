-- Every item that can exist on a belt.
--   mat   = what it looks like it is made of (drives the colour)
--   form  = shape / processing stage (drives the sprite)
--   value = base sell price in $
--   tier  = how deep in the chain it sits: 1 raw, 2 refined, 3 parts and
--           alloys, 4 components, 5 products
--   mats  = the raw materials it contains: iron, copper, gold, coal, quartz,
--           oil. "Counts as" rules and material bonuses go by these.
--
-- Depth pays: every step is worth roughly 2.7x the sum of what went in, so a
-- product sells for a few hundred times its ore.

local function item(name, mat, form, value, tier, mats)
  return { name = name, mat = mat, form = form, value = value, tier = tier, mats = mats or { mat } }
end

local Items = {
  -- Tier 1: what the ports supply, and what a crusher makes of it.
  iron_ore     = item('Iron Ore',     'iron',   'ore',    1, 1),
  copper_ore   = item('Copper Ore',   'copper', 'ore',    1, 1),
  coal         = item('Coal',         'coal',   'ore',    1, 1),
  quartz       = item('Quartz',       'quartz', 'ore',    1, 1),
  gold_ore     = item('Gold Ore',     'gold',   'ore',    3, 1),
  crude        = item('Crude Oil',    'oil',    'barrel', 2, 1),

  iron_dust    = item('Iron Dust',    'iron',   'dust',   1, 1),
  copper_dust  = item('Copper Dust',  'copper', 'dust',   1, 1),
  gold_dust    = item('Gold Dust',    'gold',   'dust',   2, 1),
  sand         = item('Sand',         'quartz', 'dust',   1, 1),

  -- Tier 2: smelted or refined.
  iron_ingot   = item('Iron Ingot',   'iron',    'ingot', 3, 2),
  copper_ingot = item('Copper Ingot', 'copper',  'ingot', 3, 2),
  gold_ingot   = item('Gold Ingot',   'gold',    'ingot', 9, 2),
  glass        = item('Glass',        'glass',   'pane',  3, 2, { 'quartz' }),
  plastic      = item('Plastic',      'plastic', 'brick', 5, 2, { 'oil' }),
  tar          = item('Tar',          'tar',     'blob',  1, 2, { 'oil' }),
  diamond      = item('Diamond',      'gem',     'gem',   8, 2, { 'coal' }),

  -- Tier 3: parts and alloys.
  gear         = item('Gear',         'iron',     'gear',  8, 3),
  plate        = item('Copper Plate', 'copper',   'plate', 8, 3),
  foil         = item('Gold Foil',    'gold',     'foil',  24, 3),
  lens         = item('Lens',         'glass',    'lens',  8, 3, { 'quartz' }),
  wire         = item('Wire',         'copper',   'wire',  4, 3),
  gold_wire    = item('Gold Wire',    'gold',     'wire',  12, 3),
  fibre        = item('Glass Fibre',  'glass',    'wire',  4, 3, { 'quartz' }),
  steel        = item('Steel',        'steel',    'ingot', 11, 3, { 'iron', 'coal' }),
  silicon      = item('Silicon',      'silicon',  'wafer', 11, 3, { 'quartz', 'coal' }),
  electrum     = item('Electrum',     'electrum', 'ingot', 32, 3, { 'copper', 'gold' }),

  -- Tier 4: components.
  beam         = item('Steel Beam',   'steel',   'beam',    30, 4, { 'iron', 'coal' }),
  motor        = item('Motor',        'iron',    'motor',   32, 4, { 'iron', 'copper' }),
  circuit      = item('Circuit',      'gold',    'circuit', 76, 4, { 'copper', 'gold' }),
  cable        = item('Cable',        'plastic', 'cable',   24, 4, { 'oil', 'copper' }),
  chip         = item('Chip',         'silicon', 'chip',    62, 4, { 'quartz', 'coal', 'gold' }),
  lamp         = item('Lamp',         'glass',   'lamp',    43, 4, { 'quartz', 'copper' }),

  -- Tier 5: products.
  engine       = item('Engine',       'steel',   'engine',   232, 5, { 'iron', 'coal', 'copper', 'oil' }),
  camera       = item('Camera',       'silicon', 'camera',   203, 5, { 'quartz', 'coal', 'gold', 'oil' }),
  robot        = item('Robot',        'iron',    'robot',    373, 5, { 'iron', 'coal', 'copper', 'gold' }),
  computer     = item('Computer',     'plastic', 'computer', 437, 5, { 'copper', 'gold', 'quartz', 'coal', 'oil' }),
}

-- Display order for the recipe book, tier by tier.
Items.list = {
  'iron_ore', 'copper_ore', 'coal', 'quartz', 'gold_ore', 'crude',
  'iron_dust', 'copper_dust', 'gold_dust', 'sand',
  'iron_ingot', 'copper_ingot', 'gold_ingot', 'glass', 'plastic', 'tar', 'diamond',
  'gear', 'plate', 'foil', 'lens', 'wire', 'gold_wire', 'fibre', 'steel', 'silicon', 'electrum',
  'beam', 'motor', 'circuit', 'cable', 'chip', 'lamp',
  'engine', 'camera', 'robot', 'computer',
}

-- The six raw materials, for rules and bonuses that go by material.
Items.materials = { 'iron', 'copper', 'gold', 'coal', 'quartz', 'oil' }
Items.materialName = {
  iron = 'IRON', copper = 'COPPER', gold = 'GOLD', coal = 'COAL', quartz = 'QUARTZ', oil = 'OIL',
}

-- A packed crate of 4 sells for this much more than its contents.
Items.CRATE_BONUS = 1.1

return Items
