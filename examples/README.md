# Writing quests

Drop `.json` files into **`Zomboid/Lua/QuestFramework/`**. On a dedicated server that is the
*server's* folder — clients need nothing. Any number of files; each holds any number of quests.

Reload without restarting: open the quest log and press **Reload** (admins only). The console
prints a summary like `[QSF] 2 files, 6 quests loaded, 0 rejected, 1 warnings`. A broken file costs
you that file and a log line, never the server.

A file is either a bare array or an object with a `quests` key — both work. `//` comments, trailing
commas and a Notepad byte-order-mark are all tolerated.

## Minimal quest

```json
{
  "quests": [
    {
      "key": "first_nails",
      "title": "Something To Build With",
      "objectives": [
        { "type": "collect", "item": "Base.Nails", "count": 10 }
      ],
      "rewards": { "items": [ { "item": "Base.Hammer", "count": 1 } ] }
    }
  ]
}
```

## Every field

| Field | Required | Notes |
|---|---|---|
| `key` | yes | Unique. Letters, digits, `_`, `.`, `-`. This is the save key — renaming it loses progress. |
| `title` | yes | Shown in the list. |
| `description` | no | Supports `<LINE>` for a line break and `<RGB:r,g,b>` for colour. |
| `order` | no | Sort weight in the list, default `100`. |
| `location` | no | Default location for every objective. See below. |
| `prereqs` | no | See below. |
| `objectives` | yes | At least one. Always **all** required. |
| `rewards` | no | `items` and `xp`. |
| `repeatable` | no | `false` (default), `true`, or `{ "cooldownHours": n, "maxTurnins": n }`. `0` means no limit. |
| `autoComplete` | no | Default `true`. Forced to `false` when any objective consumes items. |

### Objectives

```json
{ "type": "kill",    "count": 25, "location": "Ekron", "label": "Cleared in Ekron" }
{ "type": "collect", "item": "Base.Nails", "count": 20, "consume": true, "location": false }
```

- `location` **omitted** inherits the quest's. `false` clears it (anywhere). A value overrides it.
- `consume` defaults to **true** — the items are taken at turn-in. Set `false` for "just have it".
- Items are counted recursively, so anything in a backpack counts.
- `label` is optional; without it the item's display name or "Zombies killed" is used.

### Prereqs

```json
"prereqs": {
  "quests": ["intro_supplies"],
  "skills": { "Woodwork": 3, "Aiming": 2 },
  "kills": 100,
  "daysSurvived": 5,
  "hidden": false
}
```

A quest whose prereqs are unmet shows **greyed out** in Available with the reason spelled out.
Set `hidden: true` to omit it entirely until it unlocks.

**Perk names are the engine's, not the UI's.** The four that catch people out:

| You'd write | The engine calls it |
|---|---|
| Carpentry | `Woodwork` |
| Foraging | `PlantScavenging` |
| First Aid | `Doctor` |
| Lightfooted | `Lightfoot` |

There is no overall character level in Project Zomboid — `kills` and `daysSurvived` are the
closest stand-ins.

### Locations

Five forms are accepted anywhere `location` appears:

```json
"location": "Louisville"
"location": { "x": 11651, "y": 9890, "radius": 120 }
"location": { "x": 10600, "y": 9700, "width": 400, "height": 400 }
"location": { "any": [ "Ekron", "FallasLake" ] }
"location": false
```

**Named regions the game defines:** `Muldraugh`, `WestPoint`, `Rosewood`, `Riverside`,
`MarchRidge`, `Louisville`, `ValleyStation`, `Jefferson`, `LAA`, and `General` for anywhere outside
a region.

**Towns the game does *not* define as regions** — these are ours, boxed around the game's own map
label positions, so they work anyway: `Ekron`, `FallasLake`, `Brandenburg`, `EchoCreek`,
`Irvington`. The default boxes are 300–400 tiles across and are a first pass; write a raw box if
you want a different footprint.

**Named buildings also work**, because the matcher checks every named zone at that spot — for
example `CrossRoadsMall`, `SunstarMotel`, `KnoxBank`, `RustyRifle`, `BinkysFarm`.

A box uses its **top-left corner** as `x`/`y`. A radius is in tiles. Add `"z": 0` to pin a floor;
without it any floor matches.

### Rewards

```json
"rewards": {
  "items": [ { "item": "Base.Axe", "count": 1 } ],
  "xp": { "Woodwork": 500 }
}
```

Items go straight into the player's inventory — they are **not** weight-checked, so a large reward
can leave the player over-encumbered.

## Things that will bite you

- **Item types are full types** — `Base.Nails`, not `Nails`. An unknown item is rejected at load
  with a log line naming it.
- **Reordering an objective resets that quest's progress** for anyone mid-way through it, with a
  warning in the log. Progress is stored per objective position. Adding a quest is always safe;
  editing a live one is not.
- **A prereq cycle** (A needs B, B needs A) is caught at load and logged. Without the check those
  quests would be permanently unavailable with no visible symptom.
- **Kills count where the zombie died**, not where the player stood.
