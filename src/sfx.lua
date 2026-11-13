-- Sound effects, synthesised at load time: no audio files. Every sound is a
-- few square or triangle notes with a decay, in keeping with the picture.
-- Volume is the `sound` setting (0 turns everything off).

local Settings = require 'src.settings'

local Sfx = { sources = {}, last = {}, mute = false, ok = false }

local RATE = 22050
local MASTER = 0.5

local function wave(kind, phase)
  phase = phase % 1
  if kind == 'square' then return phase < 0.5 and 1 or -1 end
  if kind == 'tri' then return phase < 0.5 and (4 * phase - 1) or (3 - 4 * phase) end
  if kind == 'noise' then return love.math.random() * 2 - 1 end
  return math.sin(phase * 2 * math.pi)
end

-- notes = { { freq, seconds, [freq at the end] }, ... } played one after the other.
local function build(kind, vol, notes)
  local total = 0
  for _, n in ipairs(notes) do total = total + n[2] end
  local count = math.max(1, math.floor(total * RATE))
  local data = love.sound.newSoundData(count, RATE, 16, 1)
  local i, phase = 0, 0
  for _, n in ipairs(notes) do
    local len = math.floor(n[2] * RATE)
    for k = 0, len - 1 do
      if i >= count then break end
      local u = k / len
      local freq = n[1] + ((n[3] or n[1]) - n[1]) * u
      phase = phase + freq / RATE
      -- A quick attack and a decay to nothing, so notes never click.
      local env = math.min(1, k / 40) * (1 - u) ^ 1.5
      data:setSample(i, wave(kind, phase) * env * vol)
      i = i + 1
    end
  end
  return love.audio.newSource(data, 'static')
end

local DEFS = {
  click  = { 'square', 0.20, { { 660, 0.035 } } },
  place  = { 'square', 0.22, { { 220, 0.05, 330 } } },
  remove = { 'noise',  0.16, { { 0, 0.06 } } },
  rotate = { 'square', 0.16, { { 440, 0.03 } } },
  sale   = { 'tri',    0.30, { { 880, 0.05, 990 } }, gap = 0.07 },
  bad    = { 'square', 0.22, { { 130, 0.16, 70 } }, gap = 0.15 },
  mod    = { 'tri',    0.26, { { 1320, 0.06 } }, gap = 0.1 },
  start  = { 'square', 0.22, { { 330, 0.06 }, { 440, 0.06 }, { 660, 0.1 } } },
  finish = { 'square', 0.22, { { 660, 0.07 }, { 440, 0.12 } } },
  clear  = { 'square', 0.24, { { 523, 0.07 }, { 659, 0.07 }, { 784, 0.07 }, { 1047, 0.2 } } },
  fail   = { 'square', 0.24, { { 220, 0.12 }, { 165, 0.12 }, { 110, 0.3 } } },
  buy    = { 'tri',    0.30, { { 784, 0.06 }, { 988, 0.1 } } },
  sell   = { 'tri',    0.28, { { 494, 0.06 }, { 370, 0.1 } } },
  land   = { 'tri',    0.30, { { 392, 0.07 }, { 523, 0.07 }, { 659, 0.14 } } },
  boss   = { 'square', 0.24, { { 98, 0.18 }, { 92, 0.18 }, { 87, 0.3 } } },
  error  = { 'square', 0.18, { { 150, 0.08 } }, gap = 0.1 },
}

function Sfx.load()
  if not (love.audio and love.sound) then return end
  local ok = pcall(function()
    for name, def in pairs(DEFS) do
      Sfx.sources[name] = build(def[1], def[2], def[3])
    end
  end)
  Sfx.ok = ok
end

-- pitch: 1 is the sound as built.
function Sfx.play(name, pitch)
  if not Sfx.ok or Sfx.mute or Settings.sound <= 0 then return end
  local src, def = Sfx.sources[name], DEFS[name]
  if not src then return end
  local now = love.timer.getTime()
  if def.gap and Sfx.last[name] and now - Sfx.last[name] < def.gap then return end
  Sfx.last[name] = now
  src:stop()
  src:setPitch(pitch or 1)
  src:setVolume(MASTER * Settings.sound / 100)
  src:play()
end

return Sfx
