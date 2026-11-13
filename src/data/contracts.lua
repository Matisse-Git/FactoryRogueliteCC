-- Run structure: sectors of 3 contracts. Every third contract is a boss.
-- Boss twists use the same hooks as upgrades (see src/data/upgrades.lua).

local Contracts = {}

-- Revenue quota per contract (summed over the contract's shifts): 12
-- contracts from $120 to $5M, about x2.63 each. After the last one the run
-- goes on in endless mode at x2.6 per contract.
Contracts.quotas = {
  120, 300, 800, 2200, 5800, 15000, 40000, 105000, 275000, 720000, 1900000, 5000000,
}
Contracts.endlessGrowth = 2.6

function Contracts.quota(index)
  local n = #Contracts.quotas
  if index <= n then return Contracts.quotas[index] end
  local q = Contracts.quotas[n] * Contracts.endlessGrowth ^ (index - n)
  local mag = 10 ^ (math.floor(math.log10(q)) - 1)      -- two significant digits
  return math.floor(q / mag + 0.5) * mag
end

Contracts.perSector = 3
Contracts.shifts = 3        -- shifts per contract
Contracts.shiftLen = 60     -- seconds (ticks) per shift
Contracts.basePower = 16    -- watts the run starts with
Contracts.powerStep = 8     -- watts per power purchase in the shop
Contracts.powerCost = 4     -- its first price; +1 per purchase

-- The plot a run starts on: the depot in the middle and these ports.
Contracts.startPlot = { items = { 'iron_ore', 'copper_ore' }, rocks = 0 }

-- New land, by sector: one plot is annexed for every contract after the
-- first. `ports` and `rocks` are { min, max }.
Contracts.land = {
  { resources = { 'iron_ore', 'copper_ore', 'coal', 'quartz' },   ports = { 1, 2 }, rocks = { 1, 3 } },
  { resources = { 'iron_ore', 'copper_ore', 'coal', 'quartz', 'gold_ore', 'crude' },
    ports = { 2, 2 }, rocks = { 2, 4 } },
  { resources = { 'iron_ore', 'copper_ore', 'coal', 'quartz', 'gold_ore', 'crude' },
    ports = { 2, 3 }, rocks = { 2, 5 } },
}
Contracts.specials = { 'pad', 'node', 'rich', 'premium' }
Contracts.specialChance = 60   -- percent of new plots that carry one

-- Payout in credits. Overshoot: beating the quota by each factor pays extra,
-- so optimising past "good enough" is worth something.
Contracts.reward = {
  normal = 5, boss = 8, perUnusedShift = 2, interestPer = 5, interestCap = 5,
  overshoot = { { 2, 2 }, { 4, 2 }, { 8, 2 } },     -- { times the quota, credits }
  perStretch = 2,     -- a contract whose demand needs a machine you lack pays this much more
}
Contracts.startCredits = 4
Contracts.startBlueprints = { 'smelter', 'press' }
Contracts.upgradeSlots = 5
Contracts.rerollCost = 2

-- Always-on rule of the site: a premium depot face pays extra. It takes
-- part in a sale like an upgrade does, so the ledger shows what it earned.
Contracts.premium = {
  id = 'premium', name = 'Premium Face', color = 'gold',
  value = function(s, ctx)
    if ctx.premium then ctx.value = ctx.value * ctx.premium end
  end,
}

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
    desc = 'Each depot tile accepts only 1 item every 2 seconds.',
    setup = function(r) r.exportPeriod = 2 end,
  },
  {
    id = 'rush', name = 'Rush Order',
    desc = 'Shifts are 20 seconds shorter.',
    setup = function(r) r.shiftLen = r.shiftLen - 20 end,
  },
  {
    id = 'inspection', name = 'Inspection',
    desc = 'Raw materials and dust sell for $0.',
    value = function(s, ctx)
      if ctx.tier == 1 then ctx.value = 0 end
    end,
  },
}

return Contracts
