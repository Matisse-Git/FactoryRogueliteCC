-- Records across runs, kept in a small text file in the save folder.
-- No unlocks and no permanent upgrades: just what you have managed so far.

local Records = {
  runs = 0,            -- runs started
  wins = 0,            -- runs that cleared all 12 contracts
  contract = 0,        -- most contracts cleared in one run
  shift = 0,           -- most revenue from one shift
  seed = 0,            -- seed of the run that cleared the most contracts
  persist = true,      -- the screenshot script turns this off
}

local FILE = 'records.txt'
local KEYS = { 'runs', 'wins', 'contract', 'shift', 'seed' }

function Records.load()
  if not Records.persist then return end
  local text = love.filesystem.read(FILE)
  if not text then return end
  for k, v in text:gmatch('(%w+)=([%d%.e%+]+)') do
    local n = tonumber(v)
    if n and Records[k] ~= nil and type(Records[k]) == 'number' then Records[k] = n end
  end
end

function Records.save()
  if not Records.persist then return end
  local lines = {}
  for _, k in ipairs(KEYS) do lines[#lines + 1] = k .. '=' .. string.format('%.0f', Records[k]) end
  love.filesystem.write(FILE, table.concat(lines, '\n') .. '\n')
end

function Records.runStarted()
  Records.runs = Records.runs + 1
  Records.save()
end

-- A shift ended with this total. Returns true if it is a new record.
function Records.shiftEnded(total)
  if total <= Records.shift then return false end
  Records.shift = total
  Records.save()
  return true
end

-- A contract was cleared. `cleared` is how many the run has cleared now.
-- Returns true if it is a new record.
function Records.contractCleared(cleared, total, seed)
  local best = cleared > Records.contract
  if best then Records.contract, Records.seed = cleared, seed end
  if cleared == total then Records.wins = Records.wins + 1 end
  if best or cleared == total then Records.save() end
  return best
end

return Records
