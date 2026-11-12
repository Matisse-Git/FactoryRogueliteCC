-- Run structure: 3 sectors x 3 contracts. Every third contract is a boss.
-- Boss twists use the same hooks as upgrades (see src/data/upgrades.lua).

local Contracts = {}

-- Revenue quota per contract (summed over the contract's shifts).
-- Untuned beyond the first sector: `lovec . --bench` prints reference numbers.
Contracts.quotas = { 120, 220, 340, 550, 850, 1200, 1800, 2600, 3600 }

Contracts.perSector = 3
Contracts.shifts = 3        -- shifts per contract
Contracts.shiftLen = 60     -- seconds (ticks) per shift
Contracts.basePower = 16    -- watts supplied by the board itself (starter kit draws 9)

-- Raw resources on the input ports of each sector.
-- A nested list means "pick one of these with the run's seed".
-- Coal arrives in sector 2 so generators are never a dead purchase.
Contracts.sectorPorts = {
  { 'iron_ore', 'copper_ore' },
  { 'iron_ore', 'copper_ore', 'coal' },
  { 'iron_ore', 'copper_ore', 'coal', 'gold_ore' },
}

-- Payout in credits.
Contracts.reward = { normal = 5, boss = 8, perUnusedShift = 2, interestPer = 5, interestCap = 5 }
Contracts.startCredits = 4
Contracts.startKit = { smelter = 2, press = 1, splitter = 1, bridge = 1 }
Contracts.upgradeSlots = 5
Contracts.rerollCost = 2

Contracts.bosses = {
  {
    id = 'tariff', name = 'Tariff',
    desc = 'Items containing copper sell for $0.',
    value = function(s, ctx) if ctx.mats.copper then ctx.value = 0 end end,
  },
  {
    id = 'brownout', name = 'Brownout',
    desc = 'Base power is halved.',
    setup = function(r) r.basePower = math.floor(r.basePower / 2) end,
  },
  {
    id = 'rockfall', name = 'Rockfall', rubble = 8,
    desc = '8 tiles are buried under rubble.',
  },
  {
    id = 'narrow_dock', name = 'Narrow Dock',
    desc = 'The export accepts only 1 item every 2 seconds.',
    setup = function(r) r.exportPeriod = 2 end,
  },
  {
    id = 'rush', name = 'Rush Order',
    desc = 'Shifts are 20 seconds shorter.',
    setup = function(r) r.shiftLen = r.shiftLen - 20 end,
  },
  {
    id = 'inspection', name = 'Inspection',
    desc = 'Raw ore and dust sell for $0.',
    value = function(s, ctx)
      if ctx.form == 'ore' or ctx.form == 'dust' then ctx.value = 0 end
    end,
  },
}

return Contracts
