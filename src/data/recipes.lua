-- Recipes per machine kind. Craft time comes from the machine, not the recipe.
-- R({ {item, amount}, ... }, { {item, amount}, ... })

local Recipes = {}

function Recipes.make(inputs, outputs)
  local r = { inputs = inputs, outputs = outputs, need = {}, outN = 0 }
  for _, i in ipairs(inputs) do r.need[i[1]] = i[2] end
  for _, o in ipairs(outputs) do r.outN = r.outN + o[2] end
  return r
end
local R = Recipes.make

Recipes.smelter = {
  R({ { 'iron_ore', 1 } },    { { 'iron_ingot', 1 } }),
  R({ { 'copper_ore', 1 } },  { { 'copper_ingot', 1 } }),
  R({ { 'gold_ore', 1 } },    { { 'gold_ingot', 1 } }),
  R({ { 'iron_dust', 1 } },   { { 'iron_ingot', 1 } }),
  R({ { 'copper_dust', 1 } }, { { 'copper_ingot', 1 } }),
  R({ { 'gold_dust', 1 } },   { { 'gold_ingot', 1 } }),
}

Recipes.press = {
  R({ { 'iron_ingot', 1 } },   { { 'gear', 1 } }),
  R({ { 'copper_ingot', 1 } }, { { 'wire', 2 } }),
  R({ { 'gold_ingot', 1 } },   { { 'foil', 1 } }),
}

Recipes.assembler = {
  R({ { 'iron_ingot', 1 }, { 'coal', 1 } }, { { 'steel', 1 } }),
  R({ { 'gear', 1 }, { 'wire', 1 } },       { { 'motor', 1 } }),
  R({ { 'wire', 1 }, { 'foil', 1 } },       { { 'circuit', 1 } }),
}

Recipes.crusher = {
  R({ { 'iron_ore', 1 } },   { { 'iron_dust', 2 } }),
  R({ { 'copper_ore', 1 } }, { { 'copper_dust', 2 } }),
  R({ { 'gold_ore', 1 } },   { { 'gold_dust', 2 } }),
}

return Recipes
