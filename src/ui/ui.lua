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

-- rot = quarter turns clockwise; flip mirrors the sprite top-to-bottom
-- before it is rotated.
function UI.sprite(img, x, y, rot, alpha, flip)
  love.graphics.setColor(1, 1, 1, alpha or 1)
  if (rot and rot ~= 0) or flip then
    local w, h = img:getDimensions()
    love.graphics.draw(img, x + w / 2, y + h / 2, (rot or 0) * math.pi / 2,
      1, flip and -1 or 1, w / 2, h / 2)
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
--   pop   1 = it just triggered, fading to 0: the card inverts and hops
--   bad   the trigger hurt: it turns red and shakes instead
--   lit   it is changing a machine on the board right now: a lamp in the corner
function UI.card(def, x, y, pop, bad, lit)
  local accent = P[def.color] or P.purple
  local fill, ink, edge = P.darkOf(def.color), accent, accent
  pop = pop or 0
  if pop > 0 and bad then
    x = x + ((math.floor(pop * 8) % 2 == 0) and 1 or -1)
    fill, ink, edge = P.red, P.dark, pop > 0.5 and P.white or P.red
  elseif pop > 0 then
    y = y - (pop > 0.5 and 2 or 1)
    fill, ink, edge = accent, P.dark, pop > 0.5 and P.white or accent
  end
  UI.rect(x, y, 16, 16, fill)
  UI.frame(x, y, 16, 16, edge)
  UI.textCenter(def.code:sub(1, 2), x + 8, y + 6, ink)
  UI.rect(x + 2, y + 2, 2, 1, ink)
  UI.rect(x + 12, y + 13, 2, 1, ink)
  if lit then
    UI.rect(x + 11, y + 1, 4, 4, P.dark)
    UI.rect(x + 12, y + 2, 2, 2, P.white)
  end
end

function UI.emptySlot(x, y)
  UI.rect(x, y, 16, 16, P.bg)
  UI.frame(x, y, 16, 16, P.faint)
end

return UI
