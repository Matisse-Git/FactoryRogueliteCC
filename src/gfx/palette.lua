-- The whole game draws from this palette.
--
-- The look: mid-century factory paperwork on a sunlit site. Panels are cream
-- paper, text is brown-black ink, accents are the colours of inks and rubber
-- stamps, and the board is grass, earth and concrete seen from above.

local function hex(h)
  return {
    tonumber(h:sub(1, 2), 16) / 255,
    tonumber(h:sub(3, 4), 16) / 255,
    tonumber(h:sub(5, 6), 16) / 255,
    1,
  }
end

local raw = {
  -- Paper and ink: the UI.
  bg = 'e6dabb',                       -- tooltips, wells, empty slots
  dark = '2b2420',                     -- ink black: outlines, shadows
  panel = 'f1e8d0', panel2 = 'e2d5b3', line = '7d6c55',
  paper = 'f1e8d0', paperD = 'd8c9a4', paperL = 'fbf6e8',
  desk = '8a6a4a', deskD = '6a4f36', deskL = 'a3825d',
  clip = '9aa0a8', clipD = '5f646c', clipL = 'd4d8de',
  text = '2b2420', dim = '6b5d4b', faint = 'a3947a',

  -- Inks: accents that read on paper.
  green = '3d8b3d', red = 'c4453a', blue = '2e6da4', purple = '7b55b5',
  cyan = '23878a', orange = 'cc6a1f', amber = 'b07d12', money = '8f6a10',
  white = 'fffaf0',

  -- Dark partners (sprites and legacy fills).
  greenD = '2c6e3a', redD = '742a2e', blueD = '27618a', purpleD = '553a8e', cyanD = '2f7f8c',
  yellow = 'ffe060',

  -- Materials: items and their sprites.
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

  -- The site.
  grass = '6f9a4a', grassL = '8fb45e', grassD = '557d3a', grassDD = '3f6230',
  meadow = '7ea653', moss = '5e8a3e',
  soil = '8c6b47', soilL = 'a6845a', soilD = '6a4f33',
  concrete = 'c3baa3', concreteL = 'd3cbb6', concreteD = 'a69d86', seam = '8f8671',
  kerb = '7d7562',
  water = '4c8ea3', waterL = '79b8c4', waterD = '356b80', foam = 'd6eef0',
  sand = 'd8c290', sandD = 'b9a26f',
  road = '5d5a55', roadL = '726e67', roadD = '48453f', paint = 'e9d58a',
  bark = '5a3e28', leaf = '3f6b34', leafL = '5f8e45', leafD = '2b4c27', leafLL = '7fab55',
  crop = 'c9a64a', cropD = 'a2832f', cropL = 'e2c46a',
  flowerW = 'f4efe2', flowerY = 'f0cc4a', flowerR = 'd9604f', flowerB = '8aa8e0',
  stone = '9a958a', stoneL = 'bdb8ab', stoneD = '6e6a61',
  shadow = '2a2418',

  belt = '5b554d', beltL = '7a7367', rail = 'a9a397',
  pad = '7fa8b0', padL = 'a8ccd2',
  roof = 'a5493a', roofL = 'c4664f', roofD = '7a3328',
}

-- What the sprites were drawn with: they keep their own colours until they
-- are redrawn, whatever the UI inks become.
local sprite = {
  green = '6bd968', red = 'e0524a', blue = '4fb5e8', purple = 'b48cf0',
  cyan = '8ef0f0', orange = 'f08a30', yellow = 'ffe060', white = 'ffffff',
  panel2 = '2b2846',
}

local P = {}
for k, v in pairs(raw) do P[k] = hex(v) end
P.sprite = {}
for k, v in pairs(sprite) do P.sprite[k] = hex(v) end
P.hex = hex

-- Mix two colours: t = 0 gives a, 1 gives b.
function P.mix(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, 1 }
end

-- A light tint of an accent on paper (card faces, highlighted rows).
function P.tint(c, t)
  return P.mix(P.paperL, c, t or 0.22)
end

-- The ink for a named accent: gold is written in amber, which reads on paper.
local INK = { gold = 'amber', yellow = 'amber', white = 'text' }
function P.inkOf(name)
  if name == nil then return nil end
  return P[INK[name] or name]
end

-- Dark partner of an accent colour (legacy card backgrounds).
function P.darkOf(name)
  return P[name .. 'D'] or P.panel2
end

return P
