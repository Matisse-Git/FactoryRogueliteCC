-- The contract board, between a cleared contract and the shop: two offers,
-- each a plot of land and a market. You see both in full before choosing,
-- and you shop knowing what you chose.

local P = require 'src.gfx.palette'
local Font = require 'src.gfx.font'
local Sprites = require 'src.gfx.sprites'
local UI = require 'src.ui.ui'
local Fmt = require 'src.fmt'
local Land = require 'src.ui.land'
local Map = require 'src.map'
local Market = require 'src.market'
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

-- The rows of a market: used here and in the game's intro panel.
-- Returns the y below the last row.
function Board.marketRows(run, market, plot, x, y, w)
  local resources, owned = run:resources(plot), run:kinds()
  for _, d in ipairs(market.demand) do
    UI.sprite(Sprites.item[d.item], x, y)
    UI.text(Items[d.item].name, x + 11, y + 2, P.text)
    UI.textRight('X' .. d.mult .. '  FIRST ' .. d.units, x + w, y + 2, P.green)
    y = y + 9
    local missing = Market.missing(d.item, resources, owned)
    if missing == nil then
      UI.text('NOTHING ON THIS SITE MAKES IT', x + 11, y, P.faint)
      y = y + 7
    elseif #missing > 0 then
      local names = {}
      for i, kind in ipairs(missing) do names[i] = Machines[kind].name end
      y = UI.paragraph('NEEDS ' .. table.concat(names, ', '), x + 11, y, math.floor((w - 11) / 4), P.faint)
    end
  end
  if market.slump then
    local s = market.slump
    UI.sprite(Sprites.item[s.item], x, y)
    UI.text(Items[s.item].name, x + 11, y + 2, P.text)
    UI.textRight('SLUMP X' .. Fmt.dec(s.mult), x + w, y + 2, P.red)
    y = y + 9
  end
  return y
end

local function drawCard(app, i, offer)
  local run = app.run
  local x, y, w, h = cardX(i), CARD.y, CARD.w, CARD.h
  local hot = UI.inside(x, y, w, h)
  UI.panel(x, y, w, h, P.panel, hot and P.text or P.line)

  -- The land.
  local plot = offer.plot
  UI.rect(x + 4, y + 4, Map.PW * 8 + 2, Map.PH * 8 + 2, P.bg)
  if plot then
    Land.draw(plot, x + 5, y + 5, 8, 1)
    local tx, ty = x + 75, y + 5
    UI.text('NEW LAND', tx, ty, P.cyan)
    ty = ty + 9
    for _, p in ipairs(plot.ports) do
      UI.sprite(Sprites.item[p.item], tx, ty - 1)
      UI.text(Fmt.perMin(p.period), tx + 11, ty + 1, p.rich and P.gold or P.text)
      ty = ty + 9
    end
    if plot.special then
      UI.paragraph(Map.SPECIAL_TEXT[plot.special], tx, ty + 1, 17, P.cyan)
    end
  else
    UI.textCenter('NO ROOM', x + 5 + Map.PW * 4, y + 22, P.faint)
    UI.text('THE SITE IS FULL.', x + 75, y + 5, P.faint)
  end

  -- The market.
  UI.text('IN DEMAND', x + 5, y + 58, P.green)
  Board.marketRows(run, offer.market, plot, x + 5, y + 66, w - 10)

  if offer.bonus > 0 then
    UI.text('+' .. offer.bonus .. ' CREDITS', x + 5, y + h - 12, P.gold)
  end
  if UI.button('TAKE ' .. i, x + w - 54, y + h - 17, 50, 13, { color = P.green }) then take(app, i) end
end

-- Beating a boss: one of three blueprints (or recipes), free.
local REWARD = { y = 44, w = 96, h = 96 }
local function rewardX(i, n) return 160 - (n * 100 - 4) / 2 + (i - 1) * 100 end

local function drawReward(app)
  local run = app.run
  local options = run.reward.options
  UI.rect(0, 0, 320, 180, P.bg)
  UI.textCenter('BOSS BEATEN', 160, 8, P.gold, 2)
  UI.textCenter('TAKE ONE. IT IS YOURS FOR THE REST OF THE RUN.', 160, 26, P.dim)
  for i, o in ipairs(options) do
    local x, y, w, h = rewardX(i, #options), REWARD.y, REWARD.w, REWARD.h
    local hot = UI.inside(x, y, w, h)
    UI.panel(x, y, w, h, P.panel, hot and P.text or P.line)
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
  UI.rect(0, 0, 320, 180, P.bg)
  UI.text('NEXT CONTRACT', 8, 5, P.text, 2)
  UI.textRight('QUOTA ' .. Fmt.money(c.quota), 312, 5, P.gold, 2)
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
    UI.textRight('CHOOSE ONE: ITS LAND AND ITS MARKET', 312, 20, P.faint)
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
