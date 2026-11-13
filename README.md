# QUOTA — a factory roguelite (prototype)

Factorio-style throughput puzzles in a Balatro-style run. No exploration: one
screen, a kit of machines, and a revenue quota to beat.

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

- `--test` runs the headless simulation tests.
- `--bench` prints what reference layouts earn per shift, with and without each upgrade (for tuning quotas).
- `--shots` drives the real game with mouse and keyboard events, checks the results, and saves screenshots to the LÖVE save directory.
  The numbered shots are the bare canvas; the `*_crt_*` ones go through the CRT filter. It ignores your saved settings.

## How a run works

- A run is **9 contracts** in 3 sectors. Every third contract is a boss with a twist.
- Each contract gives you **3 shifts of 60 seconds** to earn its **revenue quota**.
- **Build** with time stopped, press **Run**, watch the shift, then rebuild before the next one.
  The same layout always earns the same amount.
- **Shifts start warm**: the factory runs until it is flowing before the clock starts, so a shift
  earns exactly its steady rates times 60 seconds. A port at 30/min sells 30 items, however long the belt.
- Raw items enter from **ports** on the left. Everything that reaches the **export** is sold.
- **Blueprints**: a machine you have the blueprint for can be placed any number of times, for free.
  Belts, splitters, bridges and generators need no blueprint.
- **Power is the budget**: machines draw watts while crafting. Over the limit, every machine slows
  down in proportion, so the question is always which machines the watts are best spent on.
- Clearing a contract pays **credits** (plus a bonus per unused shift and interest on savings).
  The **shop** offers 2 blueprints, 2 upgrades and more power. You hold at most 5 upgrades.
- Miss a quota and the run is over. Runs are seeded.

### Reading your upgrades

- An upgrade's **card pops** whenever it changes something: a sale, a machine, the shift total.
  A harmful change (a sale zeroed by Embargo or a boss twist) flashes red and shakes instead;
  a boss twist does this on the `BOSS:` label.
- The **ledger** fills the box under the cards during a shift: what each upgrade earned or cost,
  or how often it triggered. Hover a card to read its description instead.
- The **sale popup** at the export is red for a `$0` sale, and otherwise takes the colour of the
  upgrade that added the most.
- **Tiles flash** where an upgrade acts on the board (a duplicated item, an oven smelt, a diamond).
- Machines changed by a placement upgrade (Assembly Line, Direct Drive, Hand Crank) carry a
  **pip** in its colour, while building too. Hover the card to outline them.
- The **shift summary** plays end-of-shift upgrades one line at a time, met or not.

### Reading your factory

The game states every rate per minute and measures what actually happened; it never plans for you.

- Hover a machine, a port or a palette entry for its rate and watts. A belt carries 60/min, a port
  supplies 30/min, a smelter makes 15/min, a press 20/min, an assembler 10/min.
- During a shift the top bar shows what the factory earns per second.
- Hover a machine during or after a shift for the share of the shift it spent working; hover a belt
  for how full it ran. **U** prints that share on every machine at once (green from 90%).
- The recipe book (Tab) has every recipe and sell value.

## Controls

| Input | Action |
|---|---|
| Left click | Place the selected piece; drag to lay belts; with nothing selected, pick a piece up |
| Right click | Remove (drag to erase); off the board, deselect |
| R / mouse wheel | Rotate the selected piece, or the piece under the cursor |
| 1–9 | Select a piece from the palette |
| U | Show how busy each machine was |
| Q / Esc | Deselect |
| Esc (nothing selected) / MENU button | Pause menu: resume, settings, abandon run |
| X | Clear the board |
| Space / Enter | Run the shift; during a shift, Space pauses |
| 1 / 2 / 3 (during a shift) | Speed 1×, 2×, 4× |
| Tab | Recipe book |
| F10 | Settings, from anywhere |
| F11 | Fullscreen |

### Settings

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

Settings are saved to `settings.txt` in the LÖVE save directory. A running shift waits while
the pause menu or the settings are open.

## Where things live

```
main.lua, conf.lua     entry point and window setup
src/ecs.lua            entities, component queries, systems
src/sim/               the simulation (no graphics): factory, belts, machines
src/rules.lua          hook dispatcher for upgrades and boss twists
src/run.lua            run state: blueprints, credits, contracts, shop
src/settings.lua       player settings and their file
src/data/              ALL content and balance: items, recipes, machines,
                       upgrades, contracts (quotas, bosses, payouts)
src/gfx/               palette, pixel font, sprites (authored as text);
                       crt.lua is the CRT filter and its mouse correction
src/ui/                screens: title, game, shop, recipe book; pause.lua and
                       settings.lua are the pause menu and settings panel;
                       fx.lua holds the upgrade feedback (card pops, tile
                       flashes)
tests/                 headless tests, ASCII layout loader, benchmark
tools/shots.lua        scripted play-through with screenshots
```

### Adding an upgrade

Upgrades are tables of hooks in `src/data/upgrades.lua`; the header of that
file lists every hook. For example, "iron counts as gold":

```lua
{
  id = 'fools_gold', name = "Fool's Gold", code = 'FG', color = 'gold', cost = 7,
  desc = 'Iron items count as gold when sold.',
  sellAs = function(s, ctx)
    if ctx.mats.iron then
      ctx.mats.gold = true
      ctx.type = GOLD_EQUIVALENT[ctx.type] or ctx.type
    end
  end,
},
```

Hooks run in slot order, left to right, so the order of your upgrades matters.

An upgrade never declares when it triggers. `src/rules.lua` compares the sale,
the shift multiplier or the machine before and after each hook, and remembers
which upgrade set each rule field or added each recipe, so the card pop, the
ledger entry and the board markers come for free. Each upgrade is credited
with its own change in slot order, and the credits add up to the shift total.

## Status

Version 1.0 is being built on the `v1-overhaul` branch, one milestone at a time.
Done so far: blueprints, power as the budget, warm-start shifts, rates and
utilisation on screen; one persistent site of 4x3 plots around a central depot,
new land every contract, a camera with two zoom levels (wheel or Z, WASD or
middle-drag to move), and select / copy / cut / paste (V, then C, X, Delete);
ten production machines, 37 items in five tiers where every step is worth about
2.7x what went in, a filter (F sets its item), a tar byproduct that generators
burn, and crates.
Quotas are not yet retuned for any of it, and the rest of this file still
describes the single-board prototype in places. No audio, no saved runs. Art is
placeholder.
