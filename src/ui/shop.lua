-- Shop between contracts.
--   top row     a blueprint or alternate recipe, and two modules
--   second row  three investments
--   below       reroll (all six), the modules you hold with a SELL under
--               each, and what else the run owns
-- Buying a module with all five slots full asks which one it replaces; the
-- refund for the old one counts towards the price.

local P = require 'src.gfx.palette'
local Font = require 'src.gfx.font'
local Sprites = require 'src.gfx.sprites'
local UI = require 'src.ui.ui'
local Fmt = require 'src.fmt'
local Machines = require 'src.data.machines'
local Upgrades = require 'src.data.upgrades'
local Investments = require 'src.data.investments'
local Alternates = require 'src.data.alternates'
local Items = require 'src.data.items'

local Shop = {}

local ROW1 = { y = 29, h = 46 }
local ROW2 = { y = 77, h = 44 }
local CARDW, PITCH = 100, 104
local OWNED = { x = 8, y = 137, pitch = 32 }

local function leave(app)
  app.run:advance()
  require('src.ui.game').enter(app)
  app.state = 'game'
end

-- Where offer i sits: investments on the second row, the rest on the first.
local function place(shop, i)
  local top, bottom = 0, 0
  for k = 1, i do
    if shop.offers[k].type == 'invest' then bottom = bottom + 1 else top = top + 1 end
  end
  if shop.offers[i].type == 'invest' then
    return 8 + (bottom - 1) * PITCH, ROW2.y, CARDW, ROW2.h
  end
  return 8 + (top - 1) * PITCH, ROW1.y, CARDW, ROW1.h
end

-- A 16x16 picture for an investment.
local function investIcon(def, x, y)
  local icon = def.icon
  if icon.machine then
    UI.sprite(Sprites.machine[icon.machine], x, y)
    if icon.item then UI.sprite(Sprites.item[icon.item], x + 4, y + 4) end
  else
    UI.rect(x, y, 16, 16, P.bg)
    UI.frame(x, y, 16, 16, P.goldD)
    UI.sprite(Sprites.item[icon.item], x + 2, y + 6)
  end
  if icon.money then UI.text('$', x + 11, y + 2, P.gold) end
end

local function rate(def)
  return Fmt.perMin(def.time) .. ', ' .. def.draw .. 'W'
end

-- Everything a card shows for an offer.
local function describe(run, o)
  if o.type == 'blueprint' then
    local def = Machines[o.id]
    return {
      label = 'BLUEPRINT', labelColor = P.cyan, name = def.name, nameColor = P.text,
      tip = { title = def.name, color = P.text, lines = { def.desc, rate(def), 'BUILD AS MANY AS YOUR POWER ALLOWS.' } },
      icon = function(x, y) UI.sprite(Sprites.machine[o.id], x, y) end,
    }
  elseif o.type == 'recipe' then
    local alt = Alternates.byId[o.id]
    return {
      label = 'RECIPE', labelColor = P.cyan, name = alt.name, nameColor = P.cyan,
      tip = { title = alt.name, color = P.cyan, lines = { alt.desc, 'A NEW RECIPE FOR THE ' .. Machines[alt.kind].name .. '. TAKES NO MODULE SLOT.' } },
      icon = function(x, y)
        UI.sprite(Sprites.machine[alt.kind], x, y)
        UI.rect(x + 10, y + 10, 6, 6, P.dark)
        UI.text('+', x + 11, y + 10, P.cyan)
      end,
    }
  elseif o.type == 'upgrade' then
    local def = Upgrades.byId[o.id]
    return {
      label = def.rarity, labelColor = P[Upgrades.RARITY_COLOR[def.rarity]], name = def.name, nameColor = P[def.color],
      tip = { title = def.name, color = P[def.color], lines = { def.desc } },
      icon = function(x, y) UI.card(def, x, y) end,
    }
  end
  local def = Investments.byId[o.id]
  local level = run.levels[o.id] or 0
  -- A sold offer shows the level it took you to.
  local from, to = level, level + 1
  if o.sold then from, to = level - 1, level end
  return {
    name = def.name, nameColor = P.text,
    effect = 'LEVEL ' .. to .. ': ' .. (from > 0 and (def.effect(from) .. ' > ') or '') .. def.effect(to),
    tip = { title = def.name, color = P.green, lines = { def.desc, 'LEVEL ' .. to .. ': ' .. def.effect(to) } },
    icon = function(x, y) investIcon(def, x, y) end,
  }
end

local function anyReplace(run, i)
  for slot = 1, #run.upgrades do
    if run:canReplace(slot, i) then return true end
  end
  return false
end

local function drawOffer(app, i, o)
  local run, shop = app.run, app.run.shop
  local x, y, w, h = place(shop, i)
  local d = describe(run, o)
  local hot = UI.inside(x, y, w, h)
  local picking = shop.replace == i
  UI.panel(x, y, w, h, o.sold and P.bg or P.panel, picking and P.yellow or (hot and P.text or (o.sold and P.faint or P.line)))
  d.icon(x + 4, y + 4)
  local ny = y + 4
  if d.label then
    UI.text(d.label, x + 24, ny, o.sold and P.faint or d.labelColor)
    ny = ny + 8
  end
  for _, line in ipairs(Font.wrap(d.name, 18)) do
    UI.text(line, x + 24, ny, o.sold and P.faint or d.nameColor)
    ny = ny + 7
  end
  if d.effect then UI.text(d.effect, x + 4, y + 22, o.sold and P.faint or P.green) end

  local by = y + h - 15
  local blocked = run:buyBlocked(i)
  if o.sold then
    UI.textCenter('BOUGHT', x + w / 2, by + 4, P.faint)
  elseif blocked == 'slots full' then
    -- All five slots are taken: this one has to replace another.
    local label = picking and 'CANCEL' or ('REPLACE $' .. o.cost)
    if UI.button(label, x + 4, by, w - 8, 12, { disabled = not anyReplace(run, i), color = P.yellow, active = picking }) then
      shop.replace = (not picking) and i or nil
    end
  elseif UI.button('BUY $' .. o.cost, x + 4, by, w - 8, 12, { disabled = blocked ~= nil, color = P.gold }) then
    run:buy(i)
    shop.replace = nil
  end
  if hot then
    local tip = d.tip
    if blocked == 'slots full' and not o.sold then
      tip.lines[#tip.lines + 1] = 'YOUR 5 SLOTS ARE FULL: REPLACE, THEN CLICK THE MODULE TO SWAP OUT. ITS REFUND COUNTS TOWARDS THE PRICE.'
    end
    UI.tip = tip
  end
end

local function drawOwned(app)
  local run, shop = app.run, app.run.shop
  local picking = shop.replace
  UI.text('MODULES ' .. #run.upgrades .. '/' .. Upgrades.slots, 84, 126, picking and P.yellow or P.dim)
  if picking then UI.text('WHICH ONE GOES?', 136, 126, P.yellow) end
  for i = 1, Upgrades.slots do
    local x, y = OWNED.x + (i - 1) * OWNED.pitch, OWNED.y
    local id = run.upgrades[i]
    if id then
      local def = Upgrades.byId[id]
      local refund = Upgrades.refund(def)
      UI.card(def, x + 7, y, picking and (math.floor(app.time * 4) % 2) * 0.6 or 0)
      if UI.inside(x, y, 30, 16) then
        UI.tip = { title = def.name, color = P[def.color], lines = { def.desc, 'SELLS FOR $' .. refund .. '.' } }
      end
      if picking then
        local ok = run:canReplace(i, picking)
        if UI.button('SWAP', x, y + 17, 30, 9, { disabled = not ok, color = P.yellow })
            or (ok and UI.clicked(x, y, 30, 16)) then
          run:replaceUpgrade(i, picking)
          shop.replace = nil
        end
      elseif UI.button('SELL ' .. refund, x, y + 17, 30, 9) or UI.clicked(x, y, 30, 16, 2) then
        run:sellUpgrade(i)
      end
    else
      UI.emptySlot(x + 7, y)
    end
  end
end

-- What else the run owns: blueprints, recipes, investment levels.
local function drawAssets(app)
  local run = app.run
  local x = 176
  UI.text('BLUEPRINTS', x, 126, P.dim)
  local n = 0
  for _, kind in ipairs(Machines.list) do
    if run.blueprints[kind] then
      local ix = x + n * 10
      UI.sprite(Sprites.set[8].machine[kind], ix, 134)
      if UI.inside(ix, 134, 9, 9) then
        local def = Machines[kind]
        UI.tip = { title = def.name, color = P.text, lines = { def.desc, rate(def) } }
      end
      n = n + 1
    end
  end
  UI.text('RECIPES', x, 146, #run.recipes > 0 and P.dim or P.faint)
  for i, id in ipairs(run.recipes) do
    local alt = Alternates.byId[id]
    local ix = x + 34 + (i - 1) * 10
    UI.sprite(Sprites.set[8].machine[alt.kind], ix, 144)
    if UI.inside(ix, 144, 9, 9) then
      UI.tip = { title = alt.name, color = P.cyan, lines = { alt.desc } }
    end
  end
  local total, lines = 0, {}
  for _, def in ipairs(Investments.list) do
    local level = run.levels[def.id] or 0
    if level > 0 then
      total = total + level
      lines[#lines + 1] = def.name .. ' ' .. level .. ': ' .. def.effect(level)
    end
  end
  UI.text('INVESTED: ' .. total .. (total == 1 and ' LEVEL' or ' LEVELS'), x, 156, total > 0 and P.green or P.faint)
  if total > 0 and UI.inside(x, 154, 136, 9) then
    UI.tip = { title = 'INVESTMENTS', color = P.green, lines = lines }
  end
  UI.textRight('POWER ' .. run:basePower() .. 'W', 312, 126, P.blue)
end

function Shop.draw(app)
  local run = app.run
  local shop = run.shop

  UI.rect(0, 0, 320, 180, P.bg)
  UI.text('SHOP', 8, 5, P.text, 2)
  UI.textRight('$' .. run.credits, 312, 5, P.gold, 2)
  if UI.button('MENU', 146, 5, 27, 9) then app.openPause() end
  local p = run.lastPayout
  if p then
    -- Only the parts that paid.
    local parts = { 'CONTRACT ' .. p.base }
    if p.unused > 0 then parts[#parts + 1] = 'SHIFTS LEFT ' .. p.unused end
    if p.interest > 0 then parts[#parts + 1] = 'INTEREST ' .. p.interest end
    if p.overshoot > 0 then parts[#parts + 1] = Fmt.dec(math.floor(p.times * 10) / 10) .. 'X QUOTA ' .. p.overshoot end
    if p.stretch > 0 then parts[#parts + 1] = 'HARD MARKET ' .. p.stretch end
    UI.text('PAID $' .. p.total .. ':  ' .. table.concat(parts, ' + '), 8, 21, P.dim)
  end

  for i, o in ipairs(shop.offers) do drawOffer(app, i, o) end

  local cost = run:rerollCost()
  if UI.button('REROLL $' .. cost, 8, 123, 70, 12, { disabled = run.credits < cost }) then
    run:reroll()
    shop.replace = nil
  end
  if UI.inside(8, 123, 70, 12) then
    UI.tip = { title = 'REROLL', color = P.text, lines = {
      'NEW OFFERS IN ALL SIX SLOTS. COSTS $1 MORE EACH TIME THIS SHOP.',
      'CREDITS YOU KEEP EARN INTEREST: $1 PER $5, UP TO $5.' } }
  end
  drawOwned(app)
  drawAssets(app)

  -- What comes next: the contract you chose, and what it wants.
  local nc = run:contract(run.index + 1)
  local nextLabel = 'NEXT: ' .. Fmt.money(nc.quota)
  UI.text(nextLabel, 8, 168, P.dim)
  local nx = 8 + Font.width(nextLabel) + 6
  local chosen = run.chosen or (run.offers and run.offers[1])
  if chosen then
    for _, d in ipairs(chosen.market.demand) do
      UI.sprite(Sprites.item[d.item], nx, 166)
      UI.text('X' .. d.mult, nx + 10, 168, P.green)
      if UI.inside(nx, 165, 22, 10) then
        UI.tip = { title = Items[d.item].name, color = P.green, lines = {
          'IN DEMAND NEXT CONTRACT: X' .. d.mult .. ' ON THE FIRST ' .. d.units .. ' SOLD EACH SHIFT.' } }
      end
      nx = nx + 24
    end
    if chosen.market.slump then
      local s = chosen.market.slump
      UI.sprite(Sprites.item[s.item], nx, 166)
      UI.text('X' .. Fmt.dec(s.mult), nx + 10, 168, P.red)
      if UI.inside(nx, 165, 28, 10) then
        UI.tip = { title = Items[s.item].name, color = P.red, lines = {
          'SLUMPS NEXT CONTRACT: SELLS FOR X' .. Fmt.dec(s.mult) .. '.' } }
      end
      nx = nx + 30
    end
  end
  if nc.boss then
    UI.text('BOSS: ' .. nc.boss.name, nx, 168, P.red)
    if UI.inside(nx, 165, 80, 10) then
      UI.tip = { title = nc.boss.name, color = P.red, lines = { nc.boss.desc } }
    end
  end
  if UI.button('NEXT CONTRACT', 232, 165, 80, 13, { color = P.green }) then leave(app) end
  if UI.tip then UI.drawTip(UI.tip, UI.mx, UI.my) end
end

function Shop.press(app, x, y, b)
  UI.click = { x = x, y = y, b = b }
end

function Shop.key(app, key)
  if key == 'return' then leave(app) end
end

-- Esc: stop choosing a module to replace. False if there was nothing to cancel.
function Shop.cancel(app)
  local shop = app.run.shop
  if shop and shop.replace then
    shop.replace = nil
    return true
  end
  return false
end

---------------------------------------------------------------- for scripts

-- Canvas position of the button of offer i.
function Shop.offerXY(app, i)
  local x, y, w, h = place(app.run.shop, i)
  return x + w / 2, y + h - 9
end

-- Canvas position of the card of owned module `slot`, and of its button.
function Shop.slotXY(slot)
  local x = OWNED.x + (slot - 1) * OWNED.pitch
  return x + 15, OWNED.y + 8
end

function Shop.sellXY(slot)
  local x = OWNED.x + (slot - 1) * OWNED.pitch
  return x + 15, OWNED.y + 21
end

Shop.at = { reroll = { 43, 129 }, next = { 272, 171 }, menu = { 159, 9 } }

return Shop
