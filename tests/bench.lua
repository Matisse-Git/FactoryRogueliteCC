-- Reference layouts for tuning quotas. Run with:  lovec . --bench
-- Prints what each layout earns in one 60 s shift under various upgrades.

local layout = require 'tests.layout'
local Rules = require 'src.rules'
local Upgrades = require 'src.data.upgrades'
local Contracts = require 'src.data.contracts'

local function rules(ids)
  local mods = {}
  for _, id in ipairs(ids) do mods[#mods + 1] = Upgrades.byId[id] end
  return Rules.new(mods)
end

local function shift(F, ids)
  F:beginShift(rules(ids or {}))
  while not F:finished() do F:step() end
  return F:endShift()
end

local function report(name, rows, ids)
  local s = shift(layout(rows), ids)
  local parts = {}
  for _, t in ipairs(s.order) do parts[#parts + 1] = t .. ' x' .. s.sold[t].n end
  print(string.format('%-34s $%-5d  %s', name, s.total, table.concat(parts, ', ')))
  return s.total
end

-- Starting kit only: 2 smelters, 1 press, 1 splitter (bridge unused).
local STARTER = {
  '.. .. .. .. .. .. .. .. .. .. .. .. .. ..',
  'I> b> y> s> p> b> b> b> b> b> b> b> bv ..',
  '.. .. s> b> b> b> b> b> b> b> b> b> bv ..',
  '.. .. .. .. .. .. .. .. .. .. .. .. b> E<',
  '.. .. .. .. .. .. .. .. .. .. .. .. b^ ..',
  'C> b> b> b> b> b> b> b> b> b> b> b> b^ ..',
}

-- Lazy starter: one belt per port, machines dropped in line.
local NAIVE = {
  '.. .. .. .. .. .. .. .. .. .. .. .. .. ..',
  'I> b> b> s> p> b> b> b> b> b> b> b> bv ..',
  '.. .. .. .. .. .. .. .. .. .. .. .. bv ..',
  '.. .. .. .. .. .. .. .. .. .. .. .. b> E<',
  '.. .. .. .. .. .. .. .. .. .. .. .. b^ ..',
  'C> b> b> s> b> b> b> b> b> b> b> b> b^ ..',
}

-- A mid-run kit: 2 smelters, 2 presses, 1 assembler making motors
-- (gear from the top line, wire from the bottom line).
local MOTORS = {
  '.. .. .. .. .. .. .. .. .. .. .. .. .. ..',
  'I> s> p> b> bv .. .. .. .. .. .. .. .. ..',
  '.. .. .. .. a> b> b> b> b> b> b> b> bv ..',
  'C> s> p> b> b^ .. .. .. .. .. .. .. b> E<',
}

-- Same, with the assembler parked next to the export to cut travel time.
local MOTORS_SHORT = {
  '.. .. .. .. .. .. .. .. .. .. .. .. .. ..',
  'I> s> p> b> b> b> b> b> b> b> b> b> bv ..',
  '.. .. .. .. .. .. .. .. .. .. .. .. a> E<',
  'C> s> p> b> b> b> b> b> b> b> b> b> b^ ..',
}

return function()
  print('one shift, base rules')
  local naive = report('naive starter', NAIVE)
  local best = report('tuned starter', STARTER)
  report('motors, assembler near ports', MOTORS)
  report('motors, assembler near export', MOTORS_SHORT)
  print('')
  print('tuned starter with one upgrade')
  for _, u in ipairs(Upgrades.list) do
    report('  + ' .. u.name, STARTER, { u.id })
  end
  print('')
  print('quotas (3 shifts each): ' .. table.concat(Contracts.quotas, ', '))
  print(string.format('starter kit over 3 shifts: naive $%d, tuned $%d', naive * 3, best * 3))
  return true
end
