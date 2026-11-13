-- Player settings, kept in a small text file in the save folder.

local Settings = {
  crt = 50,            -- CRT filter strength, 0 (off) to 100 in steps of 10
  fullscreen = false,
  integer = true,      -- scale the picture by whole numbers only
  persist = true,      -- the screenshot script turns this off
}

local FILE = 'settings.txt'

function Settings.load()
  local text = love.filesystem.read(FILE)
  if not text then return end
  for key, value in text:gmatch('(%w+)=(%w+)') do
    if key == 'crt' then
      local n = tonumber(value)
      if n then Settings.crt = math.max(0, math.min(100, math.floor(n / 10 + 0.5) * 10)) end
    elseif key == 'fullscreen' or key == 'integer' then
      if value == 'true' or value == 'false' then Settings[key] = value == 'true' end
    end
  end
end

function Settings.save()
  if not Settings.persist then return end
  love.filesystem.write(FILE, string.format('crt=%d\nfullscreen=%s\ninteger=%s\n',
    Settings.crt, tostring(Settings.fullscreen), tostring(Settings.integer)))
end

-- Change one setting and write the file if it really changed.
function Settings.set(key, value)
  if Settings[key] == value then return end
  Settings[key] = value
  Settings.save()
end

return Settings
