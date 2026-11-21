-- Music and ambience, synthesised at load time like the sound effects: no
-- audio files.
--
-- The music is one jaunty swung theme in two arrangements of exactly the same
-- length, playing together from the start: a relaxed one while building and
-- on the paperwork screens, a driving one while a shift runs. Switching
-- between them is a crossfade, so they never lose their place.
--
-- The ambience is a few loops whose volumes follow the site: wind outdoors,
-- a machine hum that grows with the factory, belt clatter while a shift runs,
-- and now and then a bird (fewer as the factory grows).

local ffi = require 'ffi'
local Settings = require 'src.settings'

local Audio = { ok = false, mute = false }

local RATE = 22050
local MUSIC = 0.5          -- music volume at 100
local AMBIENT = 0.4        -- ambience volume at sound 100
local FADE = 0.8           -- volume units per second a loop moves towards its target

---------------------------------------------------------------- the score

local BPM = 128
local BEAT = 60 / BPM
local BARS = 16
local SWING = 0.6          -- where the off-beat eighth falls within its beat
Audio.LENGTH = BARS * 4 * BEAT

-- The chords, a bar each, as a root (MIDI) and a quality.
local CHORDS = {
  { 48, 'M' }, { 45, 'm' }, { 50, 'm' }, { 43, 'M' },
  { 48, 'M' }, { 45, 'm' }, { 50, 'm' }, { 43, 'M' },
  { 41, 'M' }, { 41, 'M' }, { 48, 'M' }, { 48, 'M' },
  { 50, 'm' }, { 43, 'M' }, { 48, 'M' }, { 43, 'M' },
}
local TRIAD = { M = { 0, 4, 7 }, m = { 0, 3, 7 } }

-- The tune: a bar each, { MIDI note (0 = rest), length in eighths }.
local TUNE = {
  { { 76, 1 }, { 79, 1 }, { 84, 2 }, { 79, 1 }, { 76, 1 }, { 79, 2 } },
  { { 81, 2 }, { 79, 1 }, { 76, 1 }, { 72, 3 }, { 0, 1 } },
  { { 74, 1 }, { 77, 1 }, { 81, 2 }, { 77, 1 }, { 74, 1 }, { 77, 2 } },
  { { 79, 3 }, { 77, 1 }, { 74, 2 }, { 71, 2 } },
  { { 76, 1 }, { 79, 1 }, { 84, 2 }, { 83, 1 }, { 84, 1 }, { 86, 2 } },
  { { 84, 2 }, { 81, 1 }, { 79, 1 }, { 76, 3 }, { 0, 1 } },
  { { 77, 1 }, { 76, 1 }, { 74, 1 }, { 77, 1 }, { 81, 2 }, { 79, 1 }, { 77, 1 } },
  { { 79, 4 }, { 0, 2 }, { 71, 1 }, { 74, 1 } },
  { { 77, 2 }, { 81, 1 }, { 84, 1 }, { 81, 2 }, { 77, 2 } },
  { { 79, 1 }, { 77, 1 }, { 76, 1 }, { 74, 1 }, { 72, 2 }, { 0, 2 } },
  { { 76, 2 }, { 79, 1 }, { 84, 1 }, { 88, 2 }, { 84, 2 } },
  { { 83, 1 }, { 84, 1 }, { 86, 1 }, { 84, 1 }, { 79, 4 } },
  { { 77, 1 }, { 81, 1 }, { 86, 2 }, { 84, 1 }, { 81, 1 }, { 77, 2 } },
  { { 79, 1 }, { 83, 1 }, { 86, 2 }, { 84, 1 }, { 83, 1 }, { 79, 2 } },
  { { 84, 3 }, { 79, 1 }, { 76, 2 }, { 72, 2 } },
  { { 74, 2 }, { 79, 2 }, { 83, 2 }, { 0, 2 } },
}

-- Seconds from the start to eighth number `e`, swung.
local function at(e)
  local beat = math.floor(e / 2)
  return beat * BEAT + (e % 2 == 1 and BEAT * SWING or 0)
end

local function hz(m) return 440 * 2 ^ ((m - 69) / 12) end

---------------------------------------------------------------- synthesis

-- A loop of `n` samples. Anything written past its end wraps to the start,
-- so tails ring over the seam and the loop is seamless.
local function buffer(seconds)
  local n = math.floor(seconds * RATE + 0.5)
  return { n = n, d = ffi.new('float[?]', n) }
end

local function put(b, i, v)
  local k = i % b.n
  b.d[k] = b.d[k] + v
end

local TAU = 2 * math.pi

local function osc(kind, phase, duty)
  phase = phase % 1
  if kind == 'square' then return phase < (duty or 0.5) and 0.8 or -0.8 end
  if kind == 'tri' then return phase < 0.5 and (4 * phase - 1) or (3 - 4 * phase) end
  if kind == 'epiano' then
    return math.sin(phase * TAU) * 0.8 + math.sin(phase * 2 * TAU) * 0.25 + math.sin(phase * 3 * TAU) * 0.06
  end
  return math.sin(phase * TAU)
end

-- One note. opts: kind, vol, decay (per second; 0 holds), release (seconds),
-- duty, vib (vibrato depth as a fraction of the pitch).
local function note(b, t0, dur, freq, o)
  local start = math.floor(t0 * RATE)
  local release = o.release or 0.03
  local len = math.floor((dur + release) * RATE)
  local hold = dur * RATE
  local phase, decay, vol = 0, o.decay or 0, o.vol
  for i = 0, len - 1 do
    local t = i / RATE
    local f = freq
    if o.vib then f = freq * (1 + o.vib * math.sin(t * TAU * 5.5) * math.min(1, t * 4)) end
    phase = phase + f / RATE
    local env = math.min(1, i / 60) * math.exp(-decay * t)
    if i > hold then env = env * (1 - (i - hold) / (len - hold)) end
    put(b, start + i, osc(o.kind, phase, o.duty) * env * vol)
  end
end

local function kick(b, t0, vol)
  local start, len, phase = math.floor(t0 * RATE), math.floor(0.22 * RATE), 0
  for i = 0, len - 1 do
    local t = i / RATE
    phase = phase + (45 + 90 * math.exp(-t * 28)) / RATE
    put(b, start + i, math.sin(phase * TAU) * math.exp(-t * 14) * math.min(1, i / 20) * vol)
  end
end

local function snare(b, t0, vol)
  local start, len, phase = math.floor(t0 * RATE), math.floor(0.16 * RATE), 0
  for i = 0, len - 1 do
    local t = i / RATE
    phase = phase + 190 / RATE
    local v = (love.math.random() * 2 - 1) * math.exp(-t * 24) + math.sin(phase * TAU) * 0.5 * math.exp(-t * 35)
    put(b, start + i, v * vol)
  end
end

local function hat(b, t0, vol)
  local start, len, prev = math.floor(t0 * RATE), math.floor(0.045 * RATE), 0
  for i = 0, len - 1 do
    local w = love.math.random() * 2 - 1
    put(b, start + i, (w - prev) * 0.5 * math.exp(-i / RATE * 70) * vol)
    prev = w
  end
end

-- A gentle one-pole low-pass over the whole buffer (k near 1: darker).
local function soften(b, k)
  local y = b.d[b.n - 1]
  for i = 0, b.n - 1 do
    y = y * k + b.d[i] * (1 - k)
    b.d[i] = y
  end
end

local function peakOf(b)
  local top = 1e-6
  for i = 0, b.n - 1 do top = math.max(top, math.abs(b.d[i])) end
  return top
end

-- The buffer as 16-bit SoundData, scaled so its loudest sample (or `top`,
-- to scale several buffers alike) comes to `peak`.
local function toSound(b, peak, top)
  local k = peak / (top or peakOf(b))
  local data = love.sound.newSoundData(b.n, RATE, 16, 1)
  local ok, ptr = pcall(function() return ffi.cast('int16_t*', data:getFFIPointer()) end)
  if ok and ptr ~= nil then
    for i = 0, b.n - 1 do ptr[i] = math.floor(b.d[i] * k * 32767 + 0.5) end
  else
    for i = 0, b.n - 1 do data:setSample(i, b.d[i] * k) end
  end
  return data
end

---------------------------------------------------------------- arrangements

-- The relaxed one: a walking triangle bass on the beat, soft electric-piano
-- chords on the swung off-beats of 2 and 4, the tune on the same piano and
-- the lightest brushed hat.
local function relaxed()
  local b = buffer(Audio.LENGTH)
  for bar = 1, BARS do
    local root, q = CHORDS[bar][1], CHORDS[bar][2]
    local e0 = (bar - 1) * 8
    note(b, at(e0), at(e0 + 3) - at(e0), hz(root), { kind = 'tri', vol = 0.34, decay = 2.5, release = 0.05 })
    note(b, at(e0 + 4), at(e0 + 7) - at(e0 + 4), hz(root + 7), { kind = 'tri', vol = 0.3, decay = 2.5, release = 0.05 })
    for _, e in ipairs({ 3, 7 }) do
      for _, iv in ipairs(TRIAD[q]) do
        note(b, at(e0 + e), at(e0 + e + 1) - at(e0 + e), hz(root + 12 + iv),
          { kind = 'epiano', vol = 0.07, decay = 7, release = 0.06 })
      end
    end
    for e = 1, 7, 2 do hat(b, at(e0 + e), 0.05) end
    local e = e0
    for _, n in ipairs(TUNE[bar]) do
      if n[1] > 0 then
        note(b, at(e), at(e + n[2]) - at(e), hz(n[1]), { kind = 'epiano', vol = 0.22, decay = 2.2, release = 0.08 })
      end
      e = e + n[2]
    end
  end
  soften(b, 0.35)
  return b
end

-- The driving one: kick on every beat, snare on 2 and 4, hats on every
-- eighth, a square bass walking in eighths, off-beat stabs and a square lead
-- with a little vibrato, doubled an octave down.
local function driving()
  local b = buffer(Audio.LENGTH)
  local WALK = { 0, 12, 7, 12, 0, 12, 7, 10 }
  for bar = 1, BARS do
    local root, q = CHORDS[bar][1], CHORDS[bar][2]
    local e0 = (bar - 1) * 8
    for beat = 0, 3 do
      kick(b, at(e0 + beat * 2), 0.55)
      if beat % 2 == 1 then snare(b, at(e0 + beat * 2), 0.18) end
    end
    for e = 0, 7 do
      hat(b, at(e0 + e), e % 2 == 1 and 0.1 or 0.06)
      local len = (at(e0 + e + 1) - at(e0 + e)) * 0.85
      note(b, at(e0 + e), len, hz(root - 12 + WALK[e + 1]), { kind = 'square', duty = 0.5, vol = 0.12, decay = 5 })
      if e % 2 == 1 then
        for _, iv in ipairs(TRIAD[q]) do
          note(b, at(e0 + e), len * 0.6, hz(root + 12 + iv), { kind = 'square', duty = 0.25, vol = 0.03, decay = 12 })
        end
      end
    end
    local e = e0
    for _, n in ipairs(TUNE[bar]) do
      if n[1] > 0 then
        local len = at(e + n[2]) - at(e)
        note(b, at(e), len * 0.92, hz(n[1]), { kind = 'square', duty = 0.25, vol = 0.12, decay = 1.2, vib = 0.004 })
        note(b, at(e), len * 0.92, hz(n[1] - 12), { kind = 'tri', vol = 0.1, decay = 1.2 })
      end
      e = e + n[2]
    end
  end
  soften(b, 0.45)
  return b
end

---------------------------------------------------------------- ambience

-- Wind: brown noise rising and falling in slow gusts, crossfaded over its
-- own seam.
local function wind()
  local seconds, fade = 8, 0.5
  local n, f = math.floor(seconds * RATE), math.floor(fade * RATE)
  local raw = ffi.new('float[?]', n + f)
  local brown, low = 0, 0
  for i = 0, n + f - 1 do
    brown = brown * 0.997 + (love.math.random() * 2 - 1) * 0.05
    low = low * 0.9995 + brown * 0.0005
    raw[i] = brown - low
  end
  local b = buffer(seconds)
  for i = 0, n - 1 do
    local v = raw[i]
    if i < f then v = raw[i] * (i / f) + raw[n + i] * (1 - i / f) end
    local t = i / RATE
    local gust = 0.55 + 0.25 * math.sin(TAU * t / seconds) + 0.2 * math.sin(TAU * 3 * t / seconds + 1)
    b.d[i] = v * gust
  end
  return b
end

-- Machine hum: a low drone with a slow mechanical throb. Every partial and
-- the throb fit the loop a whole number of times.
local function hum()
  local b = buffer(2)
  for i = 0, b.n - 1 do
    local t = i / RATE
    local v = math.sin(TAU * 55 * t) + 0.5 * math.sin(TAU * 110 * t) + 0.25 * math.sin(TAU * 165 * t)
      + 0.08 * math.sin(TAU * 440 * t)
    b.d[i] = v * (0.85 + 0.15 * math.sin(TAU * 3 * t))
  end
  soften(b, 0.6)
  return b
end

-- Belt clatter: rollers ticking, eight to the second, no two quite alike.
local function clatter()
  local b = buffer(1)
  for k = 0, 15 do
    local start = math.floor((k / 16 + love.math.random() * 0.01) * b.n)
    local vol = (k % 2 == 0 and 1 or 0.55) * (0.8 + love.math.random() * 0.4)
    local prev = 0
    for i = 0, math.floor(0.012 * RATE) do
      local w = love.math.random() * 2 - 1
      put(b, start + i, (w - prev * 0.6) * math.exp(-i / RATE * 260) * vol)
      prev = w
    end
  end
  return b
end

-- A bird: two to four quick rising chirps.
local function bird(variant)
  local b = buffer(0.6)
  local count = 2 + variant % 3
  local base = 2600 + variant * 350
  for c = 0, count - 1 do
    local start, len, phase = math.floor(c * 0.11 * RATE), math.floor(0.06 * RATE), 0
    for i = 0, len - 1 do
      local u = i / len
      phase = phase + (base + 1400 * u * u) / RATE
      local env = math.sin(math.pi * u)
      put(b, start + i, math.sin(phase * TAU) * env * (1 - c * 0.15))
    end
  end
  return b
end

---------------------------------------------------------------- playing

local loops = {}       -- name -> { src, vol }
local birds = {}
local birdIn = 4

local function loop(name, b, peak, top)
  local src = love.audio.newSource(toSound(b, peak, top), 'static')
  src:setLooping(true)
  src:setVolume(0)
  loops[name] = { src = src, vol = 0 }
end

-- Every buffer, by name, for the WAV dump (`lovec . --audio`).
function Audio.render()
  return {
    music_build = relaxed(), music_shift = driving(),
    wind = wind(), hum = hum(), clatter = clatter(),
    bird1 = bird(1), bird2 = bird(2), bird3 = bird(3),
  }, toSound
end

function Audio.load()
  if not (love.audio and love.sound) then return end
  local ok, err = pcall(function()
    -- One scale for both arrangements, so the driving one is the louder.
    local calm, drive = relaxed(), driving()
    local top = math.max(peakOf(calm), peakOf(drive))
    loop('build', calm, 0.9, top)
    loop('shift', drive, 0.9, top)
    loop('wind', wind(), 0.8)
    loop('hum', hum(), 0.8)
    loop('clatter', clatter(), 0.8)
    for v = 1, 3 do birds[v] = love.audio.newSource(toSound(bird(v), 0.8), 'static') end
  end)
  Audio.ok = ok
  if not ok then print('music unavailable: ' .. tostring(err)) return end
  -- The two arrangements start together, so they stay in step.
  for _, name in ipairs({ 'build', 'shift', 'wind', 'hum', 'clatter' }) do loops[name].src:play() end
end

-- How loud each loop should be right now, 0..1 (before the volume settings).
local function targets(app)
  local t = { build = 1, shift = 0, wind = 0.25, hum = 0, clatter = 0 }
  local g = app.g
  if app.state == 'game' and g and app.run then
    local running = g.mode == 'run' and not g.paused and not app.overlay
    if running then t.build, t.shift = 0, 1 end
    t.wind = 0.6
    local world = app.run.factory.world
    local machines, belts = #world:query('machine'), #world:query('belt')
    t.hum = math.min(1, machines / 14) * (running and 0.4 or 0.15)
    t.clatter = running and math.min(1, belts / 40) * 0.5 or 0
    t.birds = math.max(0.15, 1 - machines / 25)
  end
  return t
end

Audio.targets = targets

local acc = 0
local want = nil

function Audio.update(app, dt)
  if not Audio.ok or Audio.mute then return end
  -- The site is counted a few times a second, not every frame.
  acc = acc - dt
  if acc <= 0 or not want then
    want = targets(app)
    acc = 0.25
  end
  local music, sound = MUSIC * Settings.music / 100, AMBIENT * Settings.sound / 100
  for name, l in pairs(loops) do
    local target = want[name] or 0
    if l.vol < target then l.vol = math.min(target, l.vol + FADE * dt)
    else l.vol = math.max(target, l.vol - FADE * dt) end
    local level = (name == 'build' or name == 'shift') and music or sound
    l.src:setVolume(l.vol * level)
  end
  -- Now and then a bird, out on the site.
  if want.birds and sound > 0 then
    birdIn = birdIn - dt
    if birdIn <= 0 then
      birdIn = 3 + love.math.random() * 8
      if love.math.random() < want.birds then
        local src = birds[love.math.random(#birds)]
        src:stop()
        src:setPitch(0.9 + love.math.random() * 0.25)
        src:setVolume(sound * 0.35 * (0.5 + love.math.random() * 0.5))
        src:play()
      end
    end
  end
end

return Audio
