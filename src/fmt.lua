-- Number formatting shared by every screen.

local Fmt = {}

local UNITS = { { 1e12, 'T' }, { 1e9, 'B' }, { 1e6, 'M' }, { 1e3, 'K' } }

-- 950 -> "950", 12345 -> "12.3K", 4995000 -> "5M", 1234567 -> "1.23M".
-- Numbers under 10,000 are written out; above that, three significant digits.
function Fmt.num(n)
  n = math.floor(n + 0.5)
  local neg = n < 0
  if neg then n = -n end
  local s
  if n < 10000 then
    s = tostring(n)
  else
    for _, u in ipairs(UNITS) do
      if n >= u[1] then
        local v = n / u[1]
        local digits = v >= 100 and 0 or (v >= 10 and 1 or 2)
        s = string.format('%.' .. digits .. 'f', v)
        if digits > 0 then s = s:gsub('0+$', ''):gsub('%.$', '') end
        s = s .. u[2]
        break
      end
    end
  end
  return (neg and '-' or '') .. s
end

function Fmt.money(n)
  if n < 0 then return '-$' .. Fmt.num(-n) end
  return '$' .. Fmt.num(n)
end

-- A rate or a multiplier: whole numbers plain, otherwise one decimal.
function Fmt.dec(n)
  if n == math.floor(n) then return tostring(n) end
  return string.format('%.1f', n)
end

-- Items per minute from seconds per item.
function Fmt.perMin(seconds)
  return Fmt.dec(math.floor(600 / seconds + 0.5) / 10) .. '/MIN'
end

return Fmt
