-- Alternate recipes: permanent unlocks from the shop that take no module
-- slot. Each adds one recipe to a machine. Where it uses the same input as a
-- standard recipe it is simply the better one and replaces it; otherwise it
-- is a new way to reach an item, and usually a reason to recalculate a line.

local Recipes = require 'src.data.recipes'

local R = Recipes.make

local list = {
  {
    id = 'pressure', name = 'Pressure', kind = 'press', cost = 6,
    recipe = R({ { 'coal', 1 } }, { { 'diamond', 1 } }),
    desc = 'A press turns coal into a diamond worth $8.',
  },
  {
    id = 'twin_dies', name = 'Twin Dies', kind = 'press', cost = 8,
    recipe = R({ { 'iron_ingot', 1 } }, { { 'gear', 2 } }),
    desc = 'A press stamps 2 gears out of one iron ingot.',
  },
  {
    id = 'float_glass', name = 'Float Glass', kind = 'smelter', cost = 7,
    recipe = R({ { 'sand', 1 } }, { { 'glass', 2 } }),
    desc = 'A smelter makes 2 panes of glass from one sand. With a crusher, quartz goes four times as far.',
  },
  {
    id = 'blast_furnace', name = 'Blast Furnace', kind = 'foundry', cost = 7,
    recipe = R({ { 'iron_ore', 1 }, { 'coal', 1 } }, { { 'steel', 1 } }),
    desc = 'A foundry makes steel straight from iron ore and coal: no smelter needed.',
  },
  {
    id = 'iron_wire', name = 'Iron Wire', kind = 'wiremill', cost = 6,
    recipe = R({ { 'iron_ingot', 1 } }, { { 'wire', 2 } }),
    desc = 'A wire mill draws wire from iron ingots too.',
  },
  {
    id = 'cracking', name = 'Cracking', kind = 'refinery', cost = 8,
    recipe = R({ { 'tar', 1 } }, { { 'plastic', 1 } }),
    desc = 'A refinery turns tar into plastic, with nothing left over.',
  },
  {
    id = 'compact_engine', name = 'Compact Engine', kind = 'manufacturer', cost = 9,
    recipe = R({ { 'motor', 1 }, { 'beam', 1 }, { 'plate', 1 } }, { { 'engine', 1 } }),
    desc = 'A manufacturer builds an engine with a copper plate in place of the cable: no oil needed.',
  },
}

local Alternates = { list = list, byId = {} }

-- An alternate takes part in the rules like a quiet mod: its setup adds the
-- recipe, and the simulation credits it whenever that recipe is crafted.
for _, alt in ipairs(list) do
  Alternates.byId[alt.id] = alt
  alt.color = 'cyan'
  alt.quiet = true
  alt.setup = function(r) r:addRecipe(alt.kind, alt.recipe) end
end

return Alternates
