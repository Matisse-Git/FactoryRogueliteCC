-- `lovec . --audio`: render the music and ambience, check them, and save each
-- as a WAV in the save folder to listen to.

local ffi = require 'ffi'

return function()
  local Audio = require 'src.audio'
  local t0 = love.timer.getTime()
  local buffers, toSound = Audio.render()
  print(string.format('rendered in %.2f s', love.timer.getTime() - t0))

  local ok = true
  local names = {}
  for name in pairs(buffers) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do
    local b = buffers[name]
    local peak, sum, bad = 0, 0, false
    for i = 0, b.n - 1 do
      local v = b.d[i]
      if v ~= v then bad = true end
      peak = math.max(peak, math.abs(v))
      sum = sum + v * v
    end
    local rms = math.sqrt(sum / b.n)
    local good = not bad and peak > 0.01
    ok = ok and good
    print(string.format('  %s %-12s %6.2f s  peak %.3f  rms %.3f', good and 'ok  ' or 'FAIL', name, b.n / 22050, peak, rms))

    -- A 16-bit mono WAV.
    local data = toSound(b, 0.9)
    local n = data:getSampleCount()
    local pcm = ffi.string(data:getFFIPointer(), n * 2)
    local function u32(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
    local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
    local header = 'RIFF' .. u32(36 + #pcm) .. 'WAVE' .. 'fmt ' .. u32(16) .. u16(1) .. u16(1)
      .. u32(22050) .. u32(22050 * 2) .. u16(2) .. u16(16) .. 'data' .. u32(#pcm)
    love.filesystem.write(name .. '.wav', header .. pcm)
  end
  print('saved to ' .. love.filesystem.getSaveDirectory())
  if math.abs(Audio.LENGTH - buffers.music_build.n / 22050) > 0.01 then
    print('FAIL the music loop is not the length of its bars')
    ok = false
  end
  return ok
end
