-- Recipes per machine kind. Craft time comes from the machine, not the recipe.
-- R({ {item, amount}, ... }, { {item, amount}, ... })
-- The polisher and the packer take any item and have no recipes here.

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
  R({ { 'quartz', 1 } },      { { 'glass', 1 } }),
  R({ { 'iron_dust', 1 } },   { { 'iron_ingot', 1 } }),
  R({ { 'copper_dust', 1 } }, { { 'copper_ingot', 1 } }),
  R({ { 'gold_dust', 1 } },   { { 'gold_ingot', 1 } }),
  R({ { 'sand', 1 } },        { { 'glass', 1 } }),
}

Recipes.crusher = {
  R({ { 'iron_ore', 1 } },   { { 'iron_dust', 2 } }),
  R({ { 'copper_ore', 1 } }, { { 'copper_dust', 2 } }),
  R({ { 'gold_ore', 1 } },   { { 'gold_dust', 2 } }),
  R({ { 'quartz', 1 } },     { { 'sand', 2 } }),
}

Recipes.press = {
  R({ { 'iron_ingot', 1 } },   { { 'gear', 1 } }),
  R({ { 'copper_ingot', 1 } }, { { 'plate', 1 } }),
  R({ { 'gold_ingot', 1 } },   { { 'foil', 1 } }),
  R({ { 'glass', 1 } },        { { 'lens', 1 } }),
  R({ { 'steel', 1 } },        { { 'beam', 1 } }),
}

Recipes.wiremill = {
  R({ { 'copper_ingot', 1 } }, { { 'wire', 2 } }),
  R({ { 'gold_ingot', 1 } },   { { 'gold_wire', 2 } }),
  R({ { 'glass', 1 } },        { { 'fibre', 2 } }),
}

Recipes.foundry = {
  R({ { 'iron_ingot', 1 }, { 'coal', 1 } },         { { 'steel', 1 } }),
  R({ { 'glass', 1 }, { 'coal', 1 } },              { { 'silicon', 1 } }),
  R({ { 'copper_ingot', 1 }, { 'gold_ingot', 1 } }, { { 'electrum', 1 } }),
}

Recipes.refinery = {
  R({ { 'crude', 1 } }, { { 'plastic', 1 }, { 'tar', 1 } }),
}

Recipes.assembler = {
  R({ { 'gear', 1 }, { 'wire', 1 } },         { { 'motor', 1 } }),
  R({ { 'wire', 1 }, { 'foil', 1 } },         { { 'circuit', 1 } }),
  R({ { 'plastic', 1 }, { 'wire', 1 } },      { { 'cable', 1 } }),
  R({ { 'silicon', 1 }, { 'gold_wire', 1 } }, { { 'chip', 1 } }),
  R({ { 'lens', 1 }, { 'plate', 1 } },        { { 'lamp', 1 } }),
}

Recipes.manufacturer = {
  R({ { 'motor', 1 }, { 'beam', 1 }, { 'cable', 1 } },    { { 'engine', 1 } }),
  R({ { 'lens', 1 }, { 'chip', 1 }, { 'plastic', 1 } },   { { 'camera', 1 } }),
  R({ { 'motor', 1 }, { 'circuit', 1 }, { 'beam', 1 } },  { { 'robot', 1 } }),
  R({ { 'circuit', 1 }, { 'chip', 1 }, { 'cable', 1 } },  { { 'computer', 1 } }),
}

return Recipes
