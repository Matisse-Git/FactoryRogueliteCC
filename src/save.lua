-- The run in progress, saved to one file in the LÖVE save directory so a
-- 60-minute run survives closing the game. Written at every point where
-- something was decided (a shift started, a purchase, a contract chosen)
-- and on quit; deleted when the run ends.
--
-- The file is a Lua table literal. It is loaded with no environment, so it
-- can hold data and nothing else.

local Save = { FILE = 'run.lua', VERSION = 1, persist = true }

local function key(k)
  if type(k) == 'number' then return '[' .. k .. ']' end
  if k:match('^[%a_][%w_]*$') then return k end
  return '[' .. string.format('%q', k) .. ']'
end

local function ser(v, out, depth)
  local t = type(v)
  if t == 'number' then
    out[#out + 1] = (v == math.floor(v) and math.abs(v) < 1e15) and string.format('%d', v) or string.format('%.17g', v)
  elseif t == 'boolean' then
    out[#out + 1] = tostring(v)
  elseif t == 'string' then
    out[#out + 1] = string.format('%q', v)
  elseif t == 'table' then
    assert(depth < 20, 'save: table too deep (a cycle?)')
    -- Sorted keys, so the same run always writes the same file.
    local keys = {}
    for k, val in pairs(v) do
      local kt, vt = type(k), type(val)
      -- Functions are rules, not state, and `mod` is a cache of them.
      if (kt == 'string' or kt == 'number') and vt ~= 'function' and vt ~= 'userdata' and k ~= 'mod' then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys, function(a, b)
      if type(a) == type(b) then return a < b end
      return type(a) == 'number'
    end)
    out[#out + 1] = '{'
    for i, k in ipairs(keys) do
      if i > 1 then out[#out + 1] = ',' end
      out[#out + 1] = key(k) .. '='
      ser(v[k], out, depth + 1)
    end
    out[#out + 1] = '}'
  else
    out[#out + 1] = 'nil'
  end
end

-- A value (tables of numbers, strings and booleans) as Lua source.
function Save.encode(value)
  local out = { 'return ' }
  ser(value, out, 0)
  return table.concat(out)
end

-- The value back, or nil if the text is not a clean table literal.
function Save.decode(text)
  if type(text) ~= 'string' then return nil end
  local chunk = loadstring(text, 'save')
  if not chunk then return nil end
  setfenv(chunk, {})
  local ok, value = pcall(chunk)
  if not ok or type(value) ~= 'table' then return nil end
  return value
end

function Save.exists()
  return Save.persist and love.filesystem.getInfo(Save.FILE) ~= nil
end

function Save.delete()
  if Save.persist and love.filesystem.getInfo(Save.FILE) then love.filesystem.remove(Save.FILE) end
end

-- data = { run = Run:snapshot(), resume = where to pick up }
function Save.write(data)
  if not Save.persist then return end
  data.version = Save.VERSION
  love.filesystem.write(Save.FILE, Save.encode(data))
end

function Save.read()
  if not Save.exists() then return nil end
  local data = Save.decode(love.filesystem.read(Save.FILE))
  if not data or data.version ~= Save.VERSION or type(data.run) ~= 'table' then return nil end
  return data
end

return Save
