# QUOTA — a factory roguelite

Factorio-style throughput puzzles in a Balatro-style run. No exploration: one
site, a factory you keep building for the whole run, and a revenue quota that
grows from $120 to $5,000,000.

Built with [LÖVE 11.5](https://love2d.org) and a small handwritten ECS.
320×180 internal resolution, scaled by whole numbers and shown through a
CRT filter (both adjustable in the settings, F10).

## Run it

```bash
love .
```

```bash
lovec . --test
```

```bash
lovec . --bench
```

```bash
lovec . --shots
```

- `--test` runs the headless tests: the simulation, the rules, the run, saving.
- `--bench` prints what reference factories earn against every quota (see Balance).
- `--shots` drives the real game with mouse and keyboard events, checks the results, and saves
  screenshots to the LÖVE save directory. The numbered shots are the bare canvas; the `*_crt_*`
  ones go through the CRT filter. It ignores your saved settings, records and run, and is silent.

## How a run works

- A run is **12 contracts** in 4 sectors. Every third contract is a boss. After the twelfth the
  run is won, and can go on in **endless mode** until a quota is missed.
- Each contract gives you **3 shifts of 60 seconds** to earn its **revenue quota**.
- **Build** with time stopped, press **Run**, watch the shift, then rebuild before the next one.
  The same layout always earns the same amount.
- **Shifts start warm**: the factory runs until it is flowing before the clock starts, so a shift
  earns exactly its steady rates times 60 seconds. What you calculated is what you get.
- Miss a quota and the run is over. Runs are seeded.

### The site

- One **site** for the whole run: 4×3 plots of 8×6 tiles. You start on one plot with the **depot**
  in its middle. The depot never moves and sells whatever enters it, from any of its 8 faces.
- Every contract after the first brings a **plot** of new land, which you place in any free slot
  touching land you own. A plot has 1–3 **ports** (a raw resource at 30 items per minute), some
  rock, and sometimes a special: booster pads (a machine on one runs 50% faster), a power node
  (+12 W), a rich port (60/min) or a premium depot face (items entering through it sell for +50%).
- Nothing is ever wiped. Moving and rotating pieces is free.

### The factory

- **Blueprints**: a machine you have the blueprint for can be placed any number of times, for free.
  You start with the smelter and the press. Belts, splitters, bridges, filters and generators need
  no blueprint.
- **Power is the budget**: machines draw watts while crafting. Over the limit, every machine slows
  down in proportion, so the question is always which machines the watts are best spent on.
- **Depth pays**: every recipe is worth about 2.7× what goes into it. Ore is $1; a computer, five
  steps later, is $437.

| Machine | Shape | Rate | Watts | Makes |
|---|---|---|---|---|
| Smelter | 1 → 1 | 15/min | 3 | ingots from ore or dust, glass from quartz or sand |
| Crusher | 1 → 2 | 30/min | 4 | 2 dust from 1 ore: the ore goes twice as far |
| Press | 1 → 1 | 20/min | 3 | gear, copper plate, gold foil, lens, steel beam |
| Wire mill | 1 → 2 | 30/min | 3 | 2 wire, gold wire or glass fibre |
| Foundry | 2 → 1 | 12/min | 6 | steel, silicon, electrum |
| Refinery | 1 → 2 different | 15/min | 6 | plastic and tar from crude oil |
| Assembler | 2 → 1 | 10/min | 5 | motor, circuit, cable, chip, lamp |
| Manufacturer | 3 → 1 | 6/min | 12 | engine, camera, robot, computer |
| Polisher | any → same | 30/min | 10 | the item sells for double |
| Packer | 4 → 1 | 30/min | 2 | a crate: 4 identical items in one belt slot, worth 10% more |

- A **filter** sends its chosen item straight on and everything else out of its sides (F sets the item).
- The refinery's **tar** has to go somewhere, or the refinery stops. Sell it, or burn it: a
  **generator** burns coal or tar for +10 W.
- A belt carries 60 items per minute. So does each depot face.

### Contracts and markets

- Every contract has a **market**: 2 products **in demand** (3 from the third sector on) sell for
  ×3, but only on the first N units of each per shift. Filling every demand means splitting the
  factory, not building one line. From the second sector on, one product also **slumps** to half
  price, and on one of the two offers it is the product you sold most of.
- After a contract you choose between **two offers**, each a plot and a market, seen in full.
  At least one demand is something you can already make; the other may need a machine you lack,
  in which case the contract pays extra credits. You shop after choosing.
- **Bosses** attack the factory that is standing: a plot loses power, a resource's ports run dry,
  a machine kind runs at half speed, depot faces close, belt length is taxed. The boss of a sector
  is announced on its first contract, three contracts ahead, with its target; a plot it will cut
  off is hatched in red on the board from then on. Beating a boss gives a free pick of one from
  three blueprints.

### The shop

Clearing a contract pays **credits**: 5 (8 for a boss), 2 per unused shift, interest on what you
kept ($1 per $5, up to $5), 2 for each of 2×, 4× and 8× the quota, and 2 for a hard market. The
shop offers six things, and one reroll replaces all six:

- **One blueprint or alternate recipe.** Alternate recipes are permanent and take no slot: 2 gears
  from one ingot, steel straight from ore, plastic from tar.
- **Two modules**, the rule-benders: 40 of them in three rarities. You hold 5, in order, and the
  order matters. Each one you hold has a SELL button (half price back); buying a sixth asks which
  one it replaces, and the refund counts towards the price.
- **Three investments**, bought a level at a time at rising prices: power (+10 W), a resource's
  port rate (+25%, up to a full belt), a machine kind's speed (+20%), or the value of everything
  containing a raw material (+20%). An item made of several materials gets every bonus, multiplied.

### Reading your factory

The game states every rate per minute and measures what actually happened; it never plans for you.

- Hover a machine, a port or a palette entry for its rate and watts.
- During a shift the top bar shows what the factory earns per second, and the sidebar how much
  of each demand is filled.
- Hover a machine during or after a shift for the share of the shift it spent working; hover a belt
  for how full it ran. **U** prints that share on every machine at once (green from 90%). The shift
  summary names the machine that worked least.
- The recipe book (Tab) has every machine, recipe and sell value, including machines you have
  not unlocked.

### Reading your upgrades

- A module's **card pops** whenever it changes something: a sale, a machine, the shift total.
  A harmful change flashes red and shakes instead; a boss twist does this on the `BOSS:` label.
- The **ledger** fills the sidebar during a shift: what the market, each module, your investments
  and the boss earned or cost. Their credits add up to the shift total.
- The **sale popup** at the depot is red for a `$0` sale, and otherwise takes the colour of
  whatever added the most.
- **Tiles flash** where a module acts on the board. Machines changed by a placement module
  (Assembly Line, Direct Drive, Hand Crank...) carry a **pip** in its colour, while building too.
  Hover the card to outline them.
- The **shift summary** plays end-of-shift modules one line at a time, met or not.

## Controls

| Input | Action |
|---|---|
| Left click | Place the selected piece; drag to lay belts; with nothing selected, pick a piece up |
| Right click | Remove (drag to erase); off the board, put the tool away |
| R | Rotate the selected piece, the stamp, or the piece under the cursor |
| 1–9, 0 | Select a piece from the palette |
| V | Select tool: drag a box, then C copies, X cuts, Delete removes |
| F | Choose the item of the filter under the cursor |
| Q / Esc | Put the tool or selection away |
| Mouse wheel / Z | Zoom: close up, or the whole site. Both are fully playable |
| WASD / arrows / middle drag | Move the camera |
| Space / Enter | Run the shift; during a shift, Space pauses |
| 1 / 2 / 3 (during a shift) | Speed 1×, 2×, 4× |
| U | Show how busy each machine was |
| Tab | Recipe book (arrows or 1–4 turn the pages) |
| Esc (nothing in hand) / MENU | Pause menu: resume, settings, save and quit, abandon run |
| F10 | Settings, from anywhere |
| F11 | Fullscreen |

### Saving

The run in progress is saved on its own: when a shift starts, after every purchase and choice,
when the pause menu opens and when the game closes. **Continue** on the title screen picks it up.
A shift that was cut short is simply run again. The save is removed when the run ends.

### Settings

- **Sound**: effects volume, 0 to 100. 0 is silent.
- **CRT filter**: scanlines, a soft glow, darker corners, a faint colour fringe near the edges
  and a slight bulge. Nothing in it moves or flickers. Scanlines fade out when the picture is
  shown at less than 3×.
  - **Simple**: one strength slider for the whole filter, 0 to 100. 50 is the default, 0 turns it off.
  - **Custom**: one slider per part. The first time, they start from the simple slider; after
    that the two modes keep their own values.
  - Sliders take a click, a drag, or Left / Right; Up / Down pick which slider the keys move.
- **Fullscreen**: same as F11.
- **Integer scaling**: on, the picture is scaled by whole numbers with black bars around it.
  Off, it fills the window as far as its 16:9 shape allows.

Settings, records and the saved run live in the LÖVE save directory (`settings.txt`,
`records.txt`, `run.lua`).

## Where things live

```
main.lua, conf.lua     entry point and window setup
src/ecs.lua            entities, component queries, systems
src/sim/               the simulation (no graphics): factory, belts, machines
src/rules.lua          hook dispatcher for everything that changes the rules
src/map.lua            the site: plot slots, annexing, plot generation
src/market.lua         demand, slumps, what a site can make
src/run.lua            run state: blueprints, modules, credits, contracts, shop
src/save.lua           the run in progress, as a data-only Lua file
src/records.lua        records across runs
src/settings.lua       player settings and their file
src/sfx.lua            sound effects, synthesised at load time
src/data/              ALL content and balance: items, recipes, machines,
                       upgrades (modules), investments, alternates, bosses,
                       contracts (quotas, land, payouts)
src/gfx/               palette, pixel font, sprites (authored as text, at two
                       sizes); crt.lua is the CRT filter and its mouse correction
src/ui/                screens: title, game, board (contract choice), shop,
                       recipe book; pause, settings and records panels; fx.lua
                       holds the upgrade feedback (card pops, tile flashes)
tests/                 headless tests, ASCII layout loader, belt router, benchmark
tools/shots.lua        scripted play-through with screenshots
```

### How the rules fit together

Everything that changes a sale, a machine or a shift is a table of hooks, and they all go
through `src/rules.lua` in one fixed order: the site's own rules, investments, the market,
alternate recipes, modules left to right, then the boss. So a product in demand is tripled
after its material bonuses, and a module's multiplier lands on top of both.

### Adding a module

Modules are tables of hooks in `src/data/upgrades.lua`; the header of that file lists every
hook. For example, "tier 2 items sell for triple":

```lua
{
  id = 'bullion', name = 'Bullion', code = 'BU', color = 'gold', rarity = 'common',
  desc = 'Tier 2 items (ingots, glass, plastic) sell for triple.',
  value = function(s, ctx)
    if ctx.tier == 2 then ctx.value = ctx.value * 3 end
  end,
},
```

A module never declares when it triggers. `src/rules.lua` compares the sale, the shift
multiplier or the machine before and after each hook, and remembers which mod set each rule
field or added each recipe, so the card pop, the ledger entry and the board markers come for
free. Each mod is credited with its own change in order, and the credits add up to the shift
total. Bosses, investments, alternate recipes and the market are written the same way.

## Balance

The quota curve is a first pass and has not been measured against reference factories yet.

## Status

Version 1.0, on the `v1-overhaul` branch. No music, no difficulty levels, no alternative
starting setups and no permanent unlocks: those are for after 1.0. Art is placeholder.
