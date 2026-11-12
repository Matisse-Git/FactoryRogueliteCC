# QUOTA — a factory roguelite (prototype)

Factorio-style throughput puzzles in a Balatro-style run. No exploration: one
screen, a kit of machines, and a revenue quota to beat.

Built with [LÖVE 11.5](https://love2d.org) and a small handwritten ECS.
320×180 internal resolution, scaled by whole numbers.

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

## How a run works

- A run is **9 contracts** in 3 sectors. Every third contract is a boss with a twist.
- Each contract gives you **3 shifts of 60 seconds** to earn its **revenue quota**.
- **Build** with time stopped, press **Run**, watch the shift, then rebuild before the next one.
  Items are cleared at the start of every shift; the same layout always earns the same amount.
- Raw items enter from **ports** on the left. Everything that reaches the **export** is sold.
- **Machines are owned pieces**: you place, move and rotate them for free. Belts are unlimited.
- **Power**: machines draw watts while crafting. Over the limit, every machine slows down in proportion.
- Clearing a contract pays **credits** (plus a bonus per unused shift and interest on savings).
  The **shop** offers 2 machines and 2 upgrades. You hold at most 5 upgrades.
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

Numbers worth knowing: a belt carries 1 item/s, a port supplies 1 item per 2 s,
a smelter takes 4 s, a press 3 s, an assembler 6 s. The recipe book (Tab) has the rest.

## Controls

| Input | Action |
|---|---|
| Left click | Place the selected piece; drag to lay belts; with nothing selected, pick a piece up |
| Right click | Remove (drag to erase); off the board, deselect |
| R / mouse wheel | Rotate the selected piece, or the piece under the cursor |
| 1–9 | Select a piece from the kit |
| Q / Esc | Deselect |
| X | Clear the board |
| Space / Enter | Run the shift; during a shift, Space pauses |
| 1 / 2 / 3 (during a shift) | Speed 1×, 2×, 4× |
| Tab | Recipe book |
| F11 | Fullscreen |

## Where things live

```
main.lua, conf.lua     entry point and window setup
src/ecs.lua            entities, component queries, systems
src/sim/               the simulation (no graphics): factory, belts, machines
src/rules.lua          hook dispatcher for upgrades and boss twists
src/run.lua            run state: kit, credits, contracts, shop
src/data/              ALL content and balance: items, recipes, machines,
                       upgrades, contracts (quotas, bosses, payouts)
src/gfx/               palette, pixel font, sprites (authored as text)
src/ui/                screens: title, game, shop, recipe book; fx.lua holds
                       the upgrade feedback (card pops, tile flashes)
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

Prototype. Quotas are tuned for the first sector only; later sectors are a
first guess. No audio, no saves, no meta-progression. Art is placeholder.
