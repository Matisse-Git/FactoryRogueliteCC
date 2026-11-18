-- Run structure: sectors of 3 contracts. Every third contract is a boss
-- (see src/data/bosses.lua).

local Contracts = {}

-- Revenue quota per contract (summed over the contract's shifts): 12
-- contracts from $120 to $2.2M. The steps are steep while blueprints are
-- still being unlocked (x3 to x4) and ease to under x2 once growth has to
-- come from investments and modules. After the last one the run goes on in
-- endless mode at x2 per contract, faster than any factory grows.
-- Fitted with `lovec . --bench`: see the Balance section of the README.
Contracts.quotas = {
  120, 500, 1500, 4500, 12000, 30000, 75000, 180000, 400000, 750000, 1300000, 2200000,
}
Contracts.endlessGrowth = 2

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
  -- A contract pays `normal`, plus `perSector` for every sector after the
  -- first, plus `boss` if it was one: later shops have more to spend.
  normal = 5, perSector = 3, boss = 3, perUnusedShift = 2, interestPer = 5, interestCap = 5,
  overshoot = { { 2, 2 }, { 4, 2 }, { 8, 2 } },     -- { times the quota, credits }
  perStretch = 2,     -- a contract whose demand needs a machine you lack pays this much more
  noBlueprint = 5,    -- beating a boss with nothing left to unlock pays this instead
}
Contracts.startCredits = 4
Contracts.startBlueprints = { 'smelter', 'press' }
Contracts.rerollCost = 2

-- Always-on rule of the site: a premium depot face pays extra. It takes
-- part in a sale like an upgrade does, so the ledger shows what it earned.
Contracts.premium = {
  id = 'premium', name = 'Premium Face', color = 'gold',
  value = function(s, ctx)
    if ctx.premium then ctx.value = ctx.value * ctx.premium end
  end,
}

return Contracts
