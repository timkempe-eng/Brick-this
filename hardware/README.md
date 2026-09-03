# The puck

Brick charges $59 for a magnetic plastic square with a read-only NFC chip in
it. [The teardown](../docs/brick-teardown.md) establishes that the chip is a
30-cent sticker, which is true and is also not the whole story: what the money
buys is **heft and a place**. Something you can find by feel in the dark, that
stays where you put it, and that is annoying enough to walk to.

A sticker under a coaster does the job. This does it nicer, for about a
dollar.

| | |
|---|---|
| `puck.scad` | The model. Parametric; two parts; no supports. |
| Rendered STLs | Actions → **Hardware** → the latest run → Artifacts → `puck-stl` |

There is no local shell in this project, so the STLs are rendered by CI rather
than committed — same reason `Dad.xcodeproj` isn't in the repo. Editing
`puck.scad` and pushing gets you a fresh set.

## What it is

Two printed parts, 55mm across and 14mm tall.

- **cup** — prints open side up. Holds the ballast, and the magnet if you fit
  one. A shallow ring in the base takes a felt pad so it doesn't skate.
- **lid** — prints smooth face down, so the surface your phone meets comes off
  the bed glass-flat. The sticker goes *inside*, stuck to the ceiling of a
  well, with 1.8mm of plastic between it and the phone. Nothing is exposed to
  peel, scuff or get picked at.

Everything is a variable at the top of the file: diameter, height, tag size,
wall thickness, magnet, fit clearance. Three assertions fail the render rather
than let you print something that can't work — no room left for ballast, a lid
too thin not to show the sticker as a bump, a tag well that would eat the
lid's spigot.

## Two decisions worth reading before you print

### The magnet fights the tag

`magnet_diameter` is **0 by default**, and that is a recommendation, not a
placeholder.

A neodymium disc behind an ordinary NFC sticker detunes its antenna. The tap
does not fail cleanly — it gets less reliable, at a distance that varies with
the phone, which is the worst possible failure for the one interaction the
whole product consists of. [nfc-and-tags.md](../docs/nfc-and-tags.md) says
metal kills NFC; a magnet is metal that is also trying to be somewhere.

So:

- **On a desk, shelf or bedside table** — no magnet. The felt ring and 40-odd
  grams are enough, and the read is unconditional. This is the default.
- **On a fridge, radiator or steel door** — fit the magnet *and* buy an
  "on-metal" (ferrite-backed) NTAG215. The ferrite is what makes the tag
  survive being mounted to metal, and the magnet is metal. Do not fit one
  without the other and hope.

With a 20 × 3mm magnet the model automatically thickens the floor to hold it,
which costs 5ml of the ballast chamber. That is the trade, stated in
millilitres.

### Steel is the wrong ballast

The chamber is 15.0 ml with no magnet, 9.9 ml with one. What you put in it is
the difference between a printed disc and an object:

| Fill | Roughly | 15 ml weighs | Notes |
|---|---|---|---|
| Nothing | — | 0 g | A 19g plastic disc. Disappointing. |
| Dry sand | free | ~24 g | The cheap answer, and enough. |
| Glass beads | pennies | ~23 g | Cleaner to handle than sand. |
| Brass or bronze shot | ~$2 | ~75 g | The nice answer. Non-ferrous. |
| Lead shot | ~$1 | ~105 g | Densest common option. Sealed inside, but wash your hands. |
| **Steel shot** | ~$1 | ~72 g | **Don't.** |

Steel is the only common ballast that is also the thing that stops the tag
working. It sits 2.6mm below the sticker, which is close enough to matter.
Everything else in that table is non-ferrous and invisible to the tag.

Glue the fill down — a few drops of thin CA through sand, or epoxy over shot.
A puck that rattles reads as a toy.

Total with sand: about 43 g. With brass: about 94 g. For reference a hockey
puck is 160 g and a phone is around 200 g; somewhere near 90 g is where it
stops feeling printed.

## Bill of materials

| Part | Cost |
|---|---|
| NTAG215 sticker, 30mm ([which one](../docs/nfc-and-tags.md)) | ~$0.30 |
| ~19 g of PLA | ~$0.40 |
| Felt or silicone ring, 47mm outer | ~$0.05 |
| Ballast | $0–2 |
| *Optional* 20 × 3mm N35 disc magnet | ~$0.30 |

Under $1.50, and the expensive part is the filament.

## Printing

Nothing here is demanding. Both parts print flat on the bed with no supports
and no brim.

- **0.2mm layers, 0.4mm nozzle.** The 2.4mm wall is exactly six perimeters.
- **PLA is fine.** PETG if it will sit in a car or a sunny window — PLA sags
  around 60°C and a black puck on a dashboard gets there.
- **Print the cup at 100% infill.** You are trying to make it heavy; the extra
  plastic is a few grams of ballast you don't have to buy.
- **Print the lid smooth face down.** It is the face you will look at and the
  face your phone touches.
- The lid's spigot is 0.25mm under the cup's bore. If your printer runs tight,
  raise `fit_clearance` and re-render rather than sanding a round part round.

## Assembly

1. Test-fit the lid in the cup, empty. Adjust `fit_clearance` if it needs
   force or falls in.
2. Stick the tag to the **ceiling** of the lid's well, roughly centred.
3. **Tap your phone to the closed lid and check it reads — before any glue.**
   This is the one step that saves a reprint. Pair it in Dad (Settings → Pair
   a Dad tag), or scan it with any NFC reader app. If it doesn't read through
   1.8mm of plastic, it isn't going to start.
4. Magnet, if you're fitting one: press it into the base pocket, CA or epoxy,
   flush side out.
5. Fill the chamber and glue the fill down. Leave a millimetre of clearance
   under the lid's spigot.
6. Lid on, with a thin ring of CA around the spigot. Wipe the squeeze-out
   before it blooms.
7. Felt ring into the base recess.
8. Put it in another room. That was always the point.

## Rendering it yourself

If you have OpenSCAD locally:

```bash
openscad --export-format=binstl -D 'part="cup"' -o cup.stl hardware/puck.scad
openscad --export-format=binstl -D 'part="lid"' -o lid.stl hardware/puck.scad
python3 scripts/check_stl.py cup.stl lid.stl
```

`part="section"` cuts the assembly in half, which is the fastest way to see
what a parameter change did. `check_stl.py` asserts the two things a slicer
will not tell you: that every edge is shared by exactly two triangles, and
that the normals point outward. A model that renders and slices into a part
with one side missing is otherwise discovered four hours into the print.
