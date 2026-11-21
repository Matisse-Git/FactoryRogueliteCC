-- Player settings, kept in a small text file in the save folder.

local Settings = {
  -- The last pass over the picture: 'print' (paper grain and a slightly
  -- misregistered ink, like a printed page), 'crt' (an old screen) or 'off'.
  filter = 'print',
  print = 50,          -- strength of the print filter

  -- CRT filter. Every strength is 0 (off) to 100 in steps of 10.
  crt = 50,            -- the one slider of the simple mode: drives every part
  custom = false,      -- true: each part has its own slider instead
  seeded = false,      -- the custom sliders have been given a starting value
  scanlines = 50, glow = 50, vignette = 50, fringe = 50, bulge = 50,

  sound = 70,          -- effects volume, 0 (off) to 100 in steps of 10
  music = 50,          -- music volume, likewise

  fullscreen = false,
  integer = true,      -- scale the picture by whole numbers only
  persist = true,      -- the screenshot script turns this off
}

-- The parts of the CRT filter, in the order the settings panel lists them.
Settings.PARTS = { 'scanlines', 'glow', 'vignette', 'fringe', 'bulge' }

local FILE = 'settings.txt'
local NUMBERS = { 'crt', 'scanlines', 'glow', 'vignette', 'fringe', 'bulge', 'sound', 'music', 'print' }
local SWITCHES = { 'custom', 'seeded', 'fullscreen', 'integer' }
local CHOICES = { filter = { 'print', 'crt', 'off' } }
Settings.FILTERS = CHOICES.filter
local kind = {}
for _, key in ipairs(NUMBERS) do kind[key] = 'number' end
for _, key in ipairs(SWITCHES) do kind[key] = 'switch' end
for key in pairs(CHOICES) do kind[key] = 'choice' end

function Settings.load()
  local text = love.filesystem.read(FILE)
  if not text then return end
  for key, value in text:gmatch('(%w+)=(%w+)') do
    if kind[key] == 'number' then
      local n = tonumber(value)
      if n then Settings[key] = math.max(0, math.min(100, math.floor(n / 10 + 0.5) * 10)) end
    elseif kind[key] == 'switch' then
      if value == 'true' or value == 'false' then Settings[key] = value == 'true' end
    elseif kind[key] == 'choice' then
      for _, v in ipairs(CHOICES[key]) do
        if v == value then Settings[key] = value end
      end
    end
  end
end

function Settings.save()
  if not Settings.persist then return end
  local lines = {}
  for _, key in ipairs(NUMBERS) do lines[#lines + 1] = key .. '=' .. Settings[key] end
  for _, key in ipairs(SWITCHES) do lines[#lines + 1] = key .. '=' .. tostring(Settings[key]) end
  for key in pairs(CHOICES) do lines[#lines + 1] = key .. '=' .. Settings[key] end
  love.filesystem.write(FILE, table.concat(lines, '\n') .. '\n')
end

-- Change one setting and write the file if it really changed.
function Settings.set(key, value)
  if Settings[key] == value then return end
  Settings[key] = value
  Settings.save()
end

-- Switch between the one slider and one slider per part. The first time,
-- the parts start from the one slider, so the picture does not jump; after
-- that the two keep their own values.
function Settings.setCustom(on)
  if on and not Settings.seeded then
    for _, part in ipairs(Settings.PARTS) do Settings[part] = Settings.crt end
    Settings.seeded = true
  end
  Settings.custom = on
  Settings.save()
end

-- The next filter in the list, after the current one.
function Settings.nextFilter()
  local list = CHOICES.filter
  for i, v in ipairs(list) do
    if v == Settings.filter then return list[i % #list + 1] end
  end
  return list[1]
end

-- Strength of each part of the CRT filter as 0..1, whichever mode is on;
-- all 0 when another filter is chosen.
local levels = {}
function Settings.levels()
  local on = Settings.filter == 'crt'
  for _, part in ipairs(Settings.PARTS) do
    levels[part] = on and (Settings.custom and Settings[part] or Settings.crt) / 100 or 0
  end
  return levels
end

return Settings
