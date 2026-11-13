-- The whole game draws from this palette.

local function hex(h)
  return {
    tonumber(h:sub(1, 2), 16) / 255,
    tonumber(h:sub(3, 4), 16) / 255,
    tonumber(h:sub(5, 6), 16) / 255,
    1,
  }
end

local raw = {
  bg = '0f0e17', dark = '08070d',
  floor = '191726', floor2 = '22203a', pad = '1b2a3c',
  panel = '1c1a2e', panel2 = '2b2846', line = '47436e',
  text = 'e8e4d8', dim = '8884aa', faint = '57547a',

  iron = '9aa3b2', ironL = 'd3dbe6', ironD = '596273',
  copper = 'd9773a', copperL = 'f7b070', copperD = '8a4122',
  gold = 'f2c53d', goldL = 'fff3a0', goldD = 'a67a1a',
  coal = '3f3f52', coalL = '6a6a84', coalD = '1d1d2a',
  steel = '6f8fb8', steelL = 'a8c4e8', steelD = '3e5578',
  gem = '8ef0f0', gemL = 'e6ffff', gemD = '3a9aa8',
  quartz = 'e8c8e0', quartzL = 'fff0fa', quartzD = '9a7890',
  glass = '9fd8ee', glassL = 'e0f6ff', glassD = '4f8fa8',
  oil = '3a5a50', oilL = '5e8a7c', oilD = '1c2e28',
  plastic = 'e868b0', plasticL = 'ffb0dc', plasticD = '8e2e68',
  tar = '3a2c44', tarL = '5a4868', tarD = '181020',
  silicon = '5a6a9a', siliconL = '8ea0d0', siliconD = '2e3a60',
  electrum = 'd8e078', electrumL = 'f6ffb8', electrumD = '8a9238',

  green = '6bd968', greenD = '2c6e3a',
  red = 'e0524a', redD = '742a2e',
  blue = '4fb5e8', blueD = '27618a',
  purple = 'b48cf0', purpleD = '553a8e',
  cyan = '8ef0f0', cyanD = '2f7f8c',
  orange = 'f08a30', yellow = 'ffe060', white = 'ffffff',

  belt = '2a2839', beltL = '4d4975', rail = '6c6898',
}

local P = {}
for k, v in pairs(raw) do P[k] = hex(v) end
P.hex = hex

-- Dark partner of an accent colour (for card backgrounds).
function P.darkOf(name)
  return P[name .. 'D'] or P.panel2
end

return P
