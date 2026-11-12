-- Small immediate-mode UI toolkit: drawing helpers, hover, clicks, tooltips.
-- Coordinates are canvas pixels (320x180).

local P = require 'src.gfx.palette'
local Font = require 'src.gfx.font'

local UI = {
  mx = -1, my = -1,   -- mouse position on the canvas
  click = nil,        -- { x, y, b } for the frame after a press
  tip = nil,          -- { title, color, lines = {...} } set by whatever is hovered
}

function UI.beginFrame()
  UI.tip = nil
end

function UI.endFrame()
  UI.click = nil
end

function UI.color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

function UI.rect(x, y, w, h, c, a)
  UI.color(c, a)
  love.graphics.rectangle('fill', x, y, w, h)
end

function UI.frame(x, y, w, h, c, a)
  UI.color(c, a)
  love.graphics.rectangle('fill', x, y, w, 1)
  love.graphics.rectangle('fill', x, y + h - 1, w, 1)
  love.graphics.rectangle('fill', x, y, 1, h)
  love.graphics.rectangle('fill', x + w - 1, y, 1, h)
end

function UI.panel(x, y, w, h, fill, border)
  UI.rect(x, y, w, h, fill or P.panel)
  UI.frame(x, y, w, h, border or P.line)
end

function UI.text(s, x, y, c, scale)
  UI.color(c or P.text)
  Font.print(s, x, y, scale)
end

function UI.textRight(s, xr, y, c, scale)
  UI.text(s, xr - Font.width(s, scale), y, c, scale)
end

function UI.textCenter(s, cx, y, c, scale)
  UI.text(s, math.floor(cx - Font.width(s, scale) / 2), y, c, scale)
end

-- Wrapped paragraph; returns the y below the last line.
function UI.paragraph(s, x, y, maxChars, c, lineH)
  lineH = lineH or 7
  for _, line in ipairs(Font.wrap(s, maxChars)) do
    UI.text(line, x, y, c)
    y = y + lineH
  end
  return y
end

function UI.sprite(img, x, y, rot, alpha)
  love.graphics.setColor(1, 1, 1, alpha or 1)
  if rot and rot ~= 0 then
    local w, h = img:getDimensions()
    love.graphics.draw(img, x + w / 2, y + h / 2, rot * math.pi / 2, 1, 1, w / 2, h / 2)
  else
    love.graphics.draw(img, x, y)
  end
end

function UI.inside(x, y, w, h)
  return UI.mx >= x and UI.mx < x + w and UI.my >= y and UI.my < y + h
end

function UI.clicked(x, y, w, h, button)
  local c = UI.click
  return c ~= nil and c.b == (button or 1)
    and c.x >= x and c.x < x + w and c.y >= y and c.y < y + h
end

-- opts: disabled, color (accent), active (drawn pressed-in)
function UI.button(label, x, y, w, h, opts)
  opts = opts or {}
  local hot = not opts.disabled and UI.inside(x, y, w, h)
  local accent = opts.color or P.line
  local fill = opts.active and accent or (hot and P.line or P.panel2)
  UI.rect(x, y, w, h, fill)
  UI.frame(x, y, w, h, opts.disabled and P.faint or accent)
  local tc = opts.disabled and P.faint or (opts.active and P.dark or P.text)
  UI.textCenter(label, x + w / 2, y + math.floor((h - 5) / 2), tc)
  return not opts.disabled and UI.clicked(x, y, w, h)
end

-- Upgrade card icon: 16x16, accent border, two-letter code.
function UI.card(def, x, y)
  local accent = P[def.color] or P.purple
  UI.rect(x, y, 16, 16, P.darkOf(def.color))
  UI.frame(x, y, 16, 16, accent)
  UI.textCenter(def.code:sub(1, 2), x + 8, y + 6, accent)
  UI.rect(x + 2, y + 2, 2, 1, accent)
  UI.rect(x + 12, y + 13, 2, 1, accent)
end

function UI.emptySlot(x, y)
  UI.rect(x, y, 16, 16, P.bg)
  UI.frame(x, y, 16, 16, P.faint)
end

return UI
