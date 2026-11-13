-- Shop between contracts: 2 blueprints, 2 upgrades, power, reroll, sell.

local P = require 'src.gfx.palette'
local Font = require 'src.gfx.font'
local Sprites = require 'src.gfx.sprites'
local UI = require 'src.ui.ui'
local Machines = require 'src.data.machines'
local Upgrades = require 'src.data.upgrades'
local Contracts = require 'src.data.contracts'
local Items = require 'src.data.items'
local Fmt = require 'src.fmt'

local Shop = {}

local function leave(app)
  app.run:advance()
  require('src.ui.game').enter(app)
  app.state = 'game'
end

function Shop.draw(app)
  local run = app.run
  local shop = run.shop
  local info

  UI.rect(0, 0, 320, 180, P.bg)
  UI.text('SHOP', 8, 6, P.text, 2)
  UI.textRight('$' .. run.credits, 312, 6, P.gold, 2)
  if UI.button('MENU', 146, 6, 27, 9) then app.openPause() end
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

  -- Offers.
  for i, o in ipairs(shop.offers) do
    local x, y, w, h = 8 + (i - 1) * 77, 31, 73, 58
    local def = o.type == 'blueprint' and Machines[o.id] or Upgrades.byId[o.id]
    local hot = UI.inside(x, y, w, h)
    if o.sold then
      UI.panel(x, y, w, h, P.bg, P.faint)
      UI.textCenter('SOLD', x + w / 2, y + 26, P.faint)
    else
      UI.panel(x, y, w, h, P.panel, hot and P.text or P.line)
      if o.type == 'blueprint' then
        UI.sprite(Sprites.machine[o.id], x + 5, y + 5)
      else
        UI.card(def, x + 5, y + 5)
      end
      UI.text(o.type, x + 25, y + 6, P.faint)
      if o.type == 'blueprint' then
        UI.text('BUILD ANY', x + 25, y + 13, P.faint)
        UI.text('NUMBER', x + 25, y + 20, P.faint)
      end
      local ny = y + (o.type == 'blueprint' and 29 or 25)
      for _, line in ipairs(Font.wrap(def.name, 16)) do
        UI.text(line, x + 5, ny, o.type == 'upgrade' and P[def.color] or P.text)
        ny = ny + 7
      end
      local blocked = run:buyBlocked(i)
      if UI.button('BUY $' .. o.cost, x + 4, y + h - 16, w - 8, 12, { disabled = blocked ~= nil, color = P.gold }) then
        run:buy(i)
      end
      if hot then
        info = { title = def.name, color = o.type == 'upgrade' and P[def.color] or P.text, text = def.desc }
        if o.type == 'blueprint' and def.time then
          info.text = info.text .. ' ' .. (math.floor(600 / def.time + 0.5) / 10) .. '/MIN, ' .. def.draw .. 'W.'
        end
        if blocked == 'slots full' then info.text = info.text .. ' (UPGRADE SLOTS FULL: SELL ONE FIRST.)' end
      end
    end
  end

  local cost = run:rerollCost()
  if UI.button('REROLL $' .. cost, 8, 93, 62, 12, { disabled = run.credits < cost }) then run:reroll() end
  local pcost = run:powerCost()
  if UI.button('POWER +' .. Contracts.powerStep .. 'W $' .. pcost, 76, 93, 86, 12,
      { disabled = run.credits < pcost, color = P.blue }) then
    run:buyPower()
  end
  UI.text('POWER ' .. run.power .. 'W', 168, 96, P.blue)

  -- Owned upgrades.
  UI.text('UPGRADES ' .. #run.upgrades .. '/' .. Contracts.upgradeSlots, 8, 111, P.dim)
  for i = 1, Contracts.upgradeSlots do
    local x, y = 8 + (i - 1) * 19, 119
    local id = run.upgrades[i]
    if id then
      local def = Upgrades.byId[id]
      UI.card(def, x, y)
      if UI.inside(x, y, 16, 16) then
        info = { title = def.name, color = P[def.color],
          text = def.desc .. ' RIGHT-CLICK TO SELL FOR $' .. math.floor(def.cost / 2) .. '.' }
      end
      if UI.clicked(x, y, 16, 16, 2) then run:sellUpgrade(i) end
    else
      UI.emptySlot(x, y)
    end
  end

  -- Blueprints.
  UI.text('BLUEPRINTS', 120, 111, P.dim)
  local n = 0
  for _, kind in ipairs(Machines.list) do
    if run.blueprints[kind] then
      local x, y = 120 + n * 19, 119
      n = n + 1
      UI.sprite(Sprites.machine[kind], x, y)
      if UI.inside(x, y, 18, 18) then
        local def = Machines[kind]
        info = { title = def.name, color = P.text, text = def.desc .. ' BUILD AS MANY AS POWER ALLOWS.' }
      end
    end
  end

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
        info = { title = Items[d.item].name, color = P.green,
          text = 'IN DEMAND NEXT CONTRACT: X' .. d.mult .. ' ON THE FIRST ' .. d.units .. ' SOLD EACH SHIFT.' }
      end
      nx = nx + 24
    end
    if chosen.market.slump then
      local s = chosen.market.slump
      UI.sprite(Sprites.item[s.item], nx, 166)
      UI.text('X' .. Fmt.dec(s.mult), nx + 10, 168, P.red)
      if UI.inside(nx, 165, 28, 10) then
        info = { title = Items[s.item].name, color = P.red, text = 'SLUMPS NEXT CONTRACT: SELLS FOR X' .. Fmt.dec(s.mult) .. '.' }
      end
      nx = nx + 30
    end
  end
  if nc.boss then UI.text('BOSS: ' .. nc.boss.name, nx, 168, P.red) end
  -- Info box.
  UI.panel(8, 140, 304, 22, P.panel, P.faint)
  if info then
    UI.text(info.title, 12, 143, info.color)
    UI.paragraph(info.text, 12 + Font.width(info.title) + 8, 143, 74 - #info.title - 2, P.dim)
  else
    UI.text('HOVER AN OFFER FOR DETAILS. CREDITS YOU KEEP EARN INTEREST: $1 PER $5, UP TO $5.', 12, 143, P.faint)
  end

  if UI.button('NEXT CONTRACT', 232, 165, 80, 13, { color = P.green }) then leave(app) end
end

function Shop.press(app, x, y, b)
  UI.click = { x = x, y = y, b = b }
end

function Shop.key(app, key)
  if key == 'return' then leave(app) end
end

return Shop
