-- Seeded Park-Miller generator. Kept separate from love.math so a seed
-- reproduces the same run everywhere, including the headless tests.

local Rng = {}
Rng.__index = Rng

function Rng.new(seed)
  local s = math.floor(math.abs(seed or 1)) % 2147483646 + 1
  local r = setmetatable({ s = s }, Rng)
  for _ = 1, 4 do r:next() end
  return r
end

function Rng:next()
  self.s = (self.s * 48271) % 2147483647
  return self.s
end

-- Integer in [lo, hi].
function Rng:int(lo, hi)
  return lo + self:next() % (hi - lo + 1)
end

function Rng:pick(list)
  return list[self:int(1, #list)]
end

function Rng:shuffle(list)
  for i = #list, 2, -1 do
    local j = self:int(1, i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

-- entries = { {value, weight}, ... }
function Rng:weighted(entries)
  local total = 0
  for i = 1, #entries do total = total + entries[i][2] end
  local roll = self:int(1, total)
  for i = 1, #entries do
    roll = roll - entries[i][2]
    if roll <= 0 then return entries[i][1] end
  end
  return entries[#entries][1]
end

return Rng
