-- The contract board, between a cleared contract and the shop: two offers,
-- each the plot of land it adds, and what that land would let the factory
-- make. You see both in full before choosing, and you shop knowing what you
-- chose.

local P = require 'src.gfx.palette'
local Font = require 'src.gfx.font'
local Sprites = require 'src.gfx.sprites'
local UI = require 'src.ui.ui'
local Fmt = require 'src.fmt'
local Land = require 'src.ui.land'
local Map = require 'src.map'
local Reach = require 'src.reach'
local Items = require 'src.data.items'
local Machines = require 'src.data.machines'
local Alternates = require 'src.data.alternates'

local Board = {}

local CARD = { y = 29, w = 148, h = 143 }
local function cardX(i) return 8 + (i - 1) * 156 end

local function take(app, i)
  local run = app.run
  if not run:choose(i) then return end
  run:openShop()
  app.state = 'shop'
  app.save()
end

-- What a plot would let the factory make that it cannot today: up to three
-- products now, best paying first, and what more blueprints would add.
local function opensRows(run, plot, x, y, w)
  local now, later = Reach.opens(run, plot)
  UI.text('OPENS UP', x, y, P.green)
  y = y + 8
  if #now == 0 then
    y = UI.paragraph('NOTHING NEW: MORE OF WHAT YOUR FACTORY RUNS ON.', x, y, math.floor(w / 4), P.dim) + 2
  end
  for i = 1, math.min(3, #now) do
    local id = now[i]
    UI.sprite(Sprites.item[id], x, y)
    UI.text(Items[id].name, x + 11, y + 2, P.text)
    UI.textRight(Fmt.money(Items[id].value), x + w, y + 2, P.money)
    y = y + 9
  end
  if #now > 3 then
    UI.text('AND ' .. (#now - 3) .. ' MORE', x + 11, y, P.dim)
    y = y + 8
  end
  if #later > 0 then
    local names = {}
    for i = 1, math.min(2, #later) do names[i] = Items[later[i]].name end
    if #later > 2 then names[#names + 1] = '...' end
    y = UI.paragraph('WITH MORE BLUEPRINTS: ' .. table.concat(names, ', '), x, y + 1, math.floor(w / 4), P.faint)
  end
  return y
end

local function drawCard(app, i, offer)
  local run = app.run
  local x, y, w, h = cardX(i), CARD.y, CARD.w, CARD.h
  local hot = UI.inside(x, y, w, h)
  UI.paper(x, y - (hot and 1 or 0), w, h)
  if hot then y = y - 1 end

  -- The land.
  local plot = offer.plot
  UI.rect(x + 4, y + 4, Map.PW * 8 + 2, Map.PH * 8 + 2, P.grass)
  UI.frame(x + 4, y + 4, Map.PW * 8 + 2, Map.PH * 8 + 2, P.dark)
  if plot then
    Land.draw(plot, x + 5, y + 5, 8, 1)
    local tx, ty = x + 75, y + 5
    UI.text('NEW LAND', tx, ty, P.cyan)
    ty = ty + 9
    for _, p in ipairs(plot.ports) do
      UI.sprite(Sprites.item[p.item], tx, ty - 1)
      UI.text(Fmt.perMin(p.period), tx + 11, ty + 1, p.rich and P.money or P.text)
      ty = ty + 9
    end
    if plot.special then
      UI.paragraph(Map.SPECIAL_TEXT[plot.special], tx, ty + 1, 17, P.cyan)
    end
  else
    UI.textCenter('NO ROOM', x + 5 + Map.PW * 4, y + 22, P.faint)
    UI.text('THE SITE IS FULL.', x + 75, y + 5, P.faint)
  end

  -- What the land would let the factory make.
  if plot then opensRows(run, plot, x + 5, y + 58, w - 10) end
  -- Signed at the bottom.
  UI.text('SIGNED', x + 5, y + h - 10, P.faint)
  UI.rect(x + 31, y + h - 5, w - 92, 1, P.dark)
  if hot then
    -- A signature, scrawled.
    UI.color(P.blue)
    local sx, sy = x + 33, y + h - 7
    for k = 0, w - 98, 2 do love.graphics.points(sx + k + 0.5, sy + math.floor(math.sin(k * 0.7 + i) * 2) + 0.5) end
  end
  if UI.button('SIGN ' .. i, x + w - 54, y + h - 17, 50, 13, { color = P.green }) then take(app, i) end
end

-- Beating a boss: one of three blueprints (or recipes), free.
local REWARD = { y = 44, w = 96, h = 96 }
local function rewardX(i, n) return 160 - (n * 100 - 4) / 2 + (i - 1) * 100 end

local function drawReward(app)
  local run = app.run
  local options = run.reward.options
  UI.desk(0, 0, 320, 180)
  UI.paper(40, 3, 240, 33)
  UI.textCenter('BOSS BEATEN', 160, 8, P.text, 2)
  UI.textCenter('TAKE ONE. IT IS YOURS FOR THE REST OF THE RUN.', 160, 26, P.dim)
  for i, o in ipairs(options) do
    local x, y, w, h = rewardX(i, #options), REWARD.y, REWARD.w, REWARD.h
    local hot = UI.inside(x, y, w, h)
    UI.paper(x, y - (hot and 1 or 0), w, h)
    if hot then y = y - 1 end
    local name, desc, kind
    if o.type == 'blueprint' then
      local def = Machines[o.id]
      name, kind = def.name, o.id
      desc = def.desc .. ' ' .. Fmt.perMin(def.time) .. ', ' .. def.draw .. 'W.'
    else
      local alt = Alternates.byId[o.id]
      name, desc, kind = alt.name, alt.desc, alt.kind
    end
    UI.sprite(Sprites.machine[kind], x + 5, y + 5)
    UI.text(o.type == 'blueprint' and 'BLUEPRINT' or 'RECIPE', x + 25, y + 5, P.cyan)
    UI.text(name, x + 25, y + 13, P.text)
    UI.paragraph(desc, x + 5, y + 26, 21, P.dim)
    if UI.button('TAKE ' .. i, x + 5, y + h - 17, w - 10, 13, { color = P.green }) then
      run:takeReward(i)
      require('src.sfx').play('buy')
      app.save()
      return
    end
  end
end

function Board.draw(app)
  local run = app.run
  if run.reward then
    drawReward(app)
    return
  end
  local c = run:contract(run.index + 1)
  UI.desk(0, 0, 320, 180)
  UI.paper(3, 2, 314, 25)
  UI.text('NEXT CONTRACT', 8, 5, P.text, 2)
  UI.textRight('QUOTA ' .. Fmt.money(c.quota), 312, 5, P.money, 2)
  if UI.button('MENU', 146, 5, 27, 9) then app.openPause() end
  local sub = 'CONTRACT ' .. c.index .. (c.index <= run:total() and (' OF ' .. run:total()) or ' (ENDLESS)')
  UI.text(sub, 8, 20, P.dim)
  if c.boss then
    local bx = 8 + Font.width(sub) + 8
    UI.text('BOSS: ' .. c.boss.name, bx, 20, P.red)
    if UI.inside(bx, 18, 200, 9) then
      UI.tip = { title = c.boss.name, color = P.red, lines = { c.boss.desc } }
    end
  else
    UI.textRight('CHOOSE ONE: THE LAND IT ADDS TO YOUR SITE', 312, 20, P.faint)
  end
  for i, offer in ipairs(run.offers) do drawCard(app, i, offer) end
  if UI.tip then UI.drawTip(UI.tip, UI.mx, UI.my) end
end

-- Canvas position of an offer's TAKE button (for the screenshot script).
function Board.at(i)
  return cardX(i) + CARD.w - 29, CARD.y + CARD.h - 10
end

-- And of a boss reward's.
function Board.rewardAt(i, n)
  return rewardX(i, n) + REWARD.w / 2, REWARD.y + REWARD.h - 10
end

function Board.press(app, x, y, b)
  UI.click = { x = x, y = y, b = b }
end

function Board.key(app, key)
  local n = tonumber(key)
  if app.run.reward then
    if n and app.run:takeReward(n) then app.save() end
  elseif n == 1 or n == 2 then
    take(app, n)
  end
end

return Board
