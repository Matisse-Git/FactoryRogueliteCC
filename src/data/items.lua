-- Every item that can exist on a belt.
--   mat   = primary material (drives colour and "counts as" rules)
--   form  = shape / processing stage (drives the sprite)
--   value = base sell price in $
--   mats  = every material the item contains (defaults to { mat })

local function item(name, mat, form, value, mats)
  return { name = name, mat = mat, form = form, value = value, mats = mats or { mat } }
end

local Items = {
  iron_ore     = item('Iron Ore',     'iron',   'ore',   1),
  copper_ore   = item('Copper Ore',   'copper', 'ore',   1),
  gold_ore     = item('Gold Ore',     'gold',   'ore',   2),
  coal         = item('Coal',         'coal',   'ore',   1),

  iron_dust    = item('Iron Dust',    'iron',   'dust',  1),
  copper_dust  = item('Copper Dust',  'copper', 'dust',  1),
  gold_dust    = item('Gold Dust',    'gold',   'dust',  2),

  iron_ingot   = item('Iron Ingot',   'iron',   'ingot', 3),
  copper_ingot = item('Copper Ingot', 'copper', 'ingot', 3),
  gold_ingot   = item('Gold Ingot',   'gold',   'ingot', 8),

  gear         = item('Gear',         'iron',   'gear',  7),
  wire         = item('Wire',         'copper', 'wire',  3),
  foil         = item('Foil',         'gold',   'foil',  18),

  steel        = item('Steel',        'steel',  'beam',    10, { 'iron', 'coal' }),
  motor        = item('Motor',        'iron',   'motor',   20, { 'iron', 'copper' }),
  circuit      = item('Circuit',      'gold',   'circuit', 40, { 'copper', 'gold' }),

  diamond      = item('Diamond',      'gem',    'gem',   15, { 'coal' }),
}

-- Display order for the recipe book.
Items.list = {
  'iron_ore', 'copper_ore', 'gold_ore', 'coal',
  'iron_dust', 'copper_dust', 'gold_dust',
  'iron_ingot', 'copper_ingot', 'gold_ingot',
  'gear', 'wire', 'foil',
  'steel', 'motor', 'circuit', 'diamond',
}

return Items
