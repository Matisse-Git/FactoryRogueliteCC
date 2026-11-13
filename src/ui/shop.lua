-- Shop between contracts: 2 machines, 2 upgrades, reroll, sell.

local P = require 'src.gfx.palette'
local Font = require 'src.gfx.font'
local Sprites = require 'src.gfx.sprites'
local UI = require 'src.ui.ui'
local Machines = require 'src.data.machines'
local Upgrades = require 'src.data.upgrades'
local Contracts = require 'src.data.contracts'

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
    UI.text('PAYOUT  CONTRACT +$' .. p.base .. '   UNUSED SHIFTS +$' .. p.unused ..
      '   INTEREST +$' .. p.interest, 8, 21, P.dim)
  end

  -- Offers.
  for i, o in ipairs(shop.offers) do
    local x, y, w, h = 8 + (i - 1) * 77, 31, 73, 58
    local def = o.type == 'machine' and Machines[o.id] or Upgrades.byId[o.id]
    local hot = UI.inside(x, y, w, h)
    if o.sold then
      UI.panel(x, y, w, h, P.bg, P.faint)
      UI.textCenter('SOLD', x + w / 2, y + 26, P.faint)
    else
      UI.panel(x, y, w, h, P.panel, hot and P.text or P.line)
      if o.type == 'machine' then
        UI.sprite(Sprites.machine[o.id], x + 5, y + 5)
      else
        UI.card(def, x + 5, y + 5)
      end
      UI.text(o.type, x + 25, y + 6, P.faint)
      if o.type == 'machine' then
        UI.text('OWNED ' .. (run.kit[o.id] or 0), x + 25, y + 13, P.faint)
      end
      local ny = y + 25
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
        if blocked == 'slots full' then info.text = info.text .. ' (UPGRADE SLOTS FULL: SELL ONE FIRST.)' end
      end
    end
  end

  local cost = run:rerollCost()
  if UI.button('REROLL $' .. cost, 8, 93, 62, 12, { disabled = run.credits < cost }) then run:reroll() end

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

  -- Kit.
  UI.text('KIT', 120, 111, P.dim)
  local n = 0
  for _, kind in ipairs(Machines.list) do
    local owned = run.kit[kind] or 0
    if owned > 0 then
      local x, y = 120 + n * 22, 119
      n = n + 1
      UI.sprite(Sprites.machine[kind], x, y)
      local label = tostring(owned)
      local w = Font.width(label)
      UI.rect(x + 14 - w, y + 10, w + 2, 7, P.dark)
      UI.text(label, x + 15 - w, y + 11, P.text)
      if UI.inside(x, y, 18, 18) then
        local def = Machines[kind]
        info = { title = def.name, color = P.text,
          text = def.desc .. ' RIGHT-CLICK TO SELL ONE FOR $' .. math.floor(def.cost / 2) .. '.' }
      end
      if UI.clicked(x, y, 18, 18, 2) then run:sellMachine(kind) end
    end
  end

  -- Info box.
  UI.panel(8, 140, 304, 22, P.panel, P.faint)
  if info then
    UI.text(info.title, 12, 143, info.color)
    UI.paragraph(info.text, 12 + Font.width(info.title) + 8, 143, 74 - #info.title - 2, P.dim)
  else
    UI.text('HOVER AN OFFER FOR DETAILS. CREDITS YOU KEEP EARN INTEREST: $1 PER $5, UP TO $5.', 12, 143, P.faint)
  end

  -- What comes next.
  local nc = run:contract(run.index + 1)
  local nextLabel = 'NEXT: CONTRACT ' .. nc.index .. ', QUOTA $' .. nc.quota
  UI.text(nextLabel, 8, 168, P.dim)
  local nx = 8 + Font.width(nextLabel) + 8
  if nc.boss then
    UI.text('BOSS: ' .. nc.boss.name, nx, 168, P.red)
  elseif nc.newSector then
    UI.text('NEW SECTOR', nx, 168, P.cyan)
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
