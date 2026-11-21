-- Small immediate-mode UI toolkit: drawing helpers, hover, clicks, tooltips.
-- Coordinates are canvas pixels (320x180).

local P = require 'src.gfx.palette'
local Font = require 'src.gfx.font'
local Sfx = require 'src.sfx'

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
-- A paper tab with an ink border and a drop shadow; pressed in while hot.
function UI.button(label, x, y, w, h, opts)
  opts = opts or {}
  local hot = not opts.disabled and UI.inside(x, y, w, h)
  local accent = opts.color or P.dark
  local down = opts.active or (hot and love.mouse and love.mouse.isDown and love.mouse.isDown(1))
  local fill = opts.active and accent or (hot and P.paperL or P.panel2)
  if not opts.disabled and not down then UI.rect(x + 1, y + 1, w, h, P.dark, 0.35) end
  if down then x, y = x + 1, y + 1 end
  UI.rect(x, y, w, h, fill)
  UI.frame(x, y, w, h, opts.disabled and P.faint or accent)
  local tc = opts.disabled and P.faint or (opts.active and P.paperL or (opts.color or P.text))
  UI.textCenter(label, x + w / 2, y + math.floor((h - 5) / 2), tc)
  local clicked = not opts.disabled and UI.clicked(x - (down and 1 or 0), y - (down and 1 or 0), w, h)
  if clicked then Sfx.play('click') end
  return clicked
end

-- Upgrade card: a 16x16 punch card in its accent's ink, with a folded
-- corner, a row of punched holes and the two-letter code.
--   pop   1 = it just triggered, fading to 0: the card inks over and hops
--   bad   the trigger hurt: it turns red and shakes instead
--   lit   it is changing a machine on the board right now: a lamp in the corner
local function holes(code)
  local h = 0
  for i = 1, #code do h = (h * 31 + code:byte(i)) % 997 end
  return h
end

function UI.card(def, x, y, pop, bad, lit)
  local ink = P.inkOf(def.color) or P.purple
  local face, text, edge = P.tint(ink, 0.2), ink, ink
  pop = pop or 0
  if pop > 0 and bad then
    x = x + ((math.floor(pop * 8) % 2 == 0) and 1 or -1)
    face, text, edge = P.red, P.paperL, P.dark
  elseif pop > 0 then
    y = y - (pop > 0.5 and 2 or 1)
    face, text, edge = ink, P.paperL, P.dark
  end
  UI.rect(x + 1, y + 1, 16, 16, P.dark, 0.3)
  UI.rect(x, y, 16, 16, face)
  UI.frame(x, y, 16, 16, edge)
  -- The folded corner.
  local fold = P.mix(face, P.dark, 0.25)
  UI.rect(x + 13, y + 1, 2, 1, fold); UI.rect(x + 14, y + 2, 1, 1, fold)
  UI.rect(x + 12, y + 1, 1, 1, edge); UI.rect(x + 13, y + 2, 1, 1, edge); UI.rect(x + 14, y + 3, 1, 1, edge)
  -- Punched holes, a pattern of its own per card.
  local h, hole = holes(def.code or def.id or '?'), P.mix(face, P.dark, 0.45)
  for k = 0, 4 do
    if math.floor(h / 2 ^ k) % 2 == 1 then UI.rect(x + 2 + k * 2 + (k > 2 and 1 or 0), y + 12, 1, 2, hole) end
  end
  UI.textCenter((def.code or '?'):sub(1, 2), x + 8, y + 5, text)
  if lit then
    UI.rect(x + 1, y + 1, 4, 4, P.dark)
    UI.rect(x + 2, y + 2, 2, 2, P.amber)
  end
end

-- A tooltip floating next to the mouse, kept on the canvas.
-- tip = { title, color, lines = { ... } }; long lines wrap.
function UI.drawTip(tip, mx, my)
  local lines = {}
  for _, s in ipairs(tip.lines or {}) do
    if s then
      for _, line in ipairs(Font.wrap(s, 34)) do lines[#lines + 1] = line end
    end
  end
  local w = Font.width(tip.title)
  for _, line in ipairs(lines) do w = math.max(w, Font.width(line)) end
  w = w + 8
  local h = 11 + #lines * 7 + (#lines > 0 and 2 or 0)
  local x, y = mx + 10, my + 8
  if x + w > 319 then x = mx - w - 6 end
  if y + h > 179 then y = my - h - 4 end
  x, y = math.max(1, math.min(x, 319 - w)), math.max(1, y)
  UI.rect(x + 2, y + 2, w, h, P.dark, 0.3)
  UI.panel(x, y, w, h, P.paperL, P.dark)
  UI.text(tip.title, x + 4, y + 3, tip.color or P.text)
  for i, line in ipairs(lines) do
    UI.text(line, x + 4, y + 4 + i * 7, P.dim)
  end
end

-- An empty card slot: a dashed outline pencilled on the paper.
function UI.emptySlot(x, y)
  UI.rect(x, y, 16, 16, P.bg, 0.6)
  for k = 0, 15, 3 do
    UI.rect(x + k, y, 2, 1, P.faint); UI.rect(x + k, y + 15, 2, 1, P.faint)
    UI.rect(x, y + k, 1, 2, P.faint); UI.rect(x + 15, y + k, 1, 2, P.faint)
  end
end

return UI
