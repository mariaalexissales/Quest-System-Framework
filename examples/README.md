# Writing quests

Quests are .json files in `Zomboid/Lua/QuestFramework/`. On a server that's the server's folder,
not the players'. As many files as you like, as many quests per file as you like.

To reload without restarting, open the quest log and hit Reload. Admins only. The console prints
what it found:

```
[QSF] 2 files, 6 quests loaded, 0 rejected, 1 warnings
```

A file that won't parse costs you that file and a line in the log. It never takes the server down.

Either shape works, so use whichever you like:

```json
[ { "key": "..." } ]
{ "quests": [ { "key": "..." } ] }
```

Notepad's byte-order mark, `//` comments and trailing commas are all fine.

## A quest

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

`key`, `title` and `objectives` are the only things you have to write. Everything else has a
default.

## The rest of it

`key` is unique, and it's what progress is saved against, so renaming one wipes anybody's progress
on it. Letters, digits, `_`, `.` and `-`.

`description` takes `<LINE>` for a break and `<RGB:r,g,b>` for colour.

`order` sorts the list, default 100.

`repeatable` is `false`, `true`, or `{ "cooldownHours": 72, "maxTurnins": 3 }`. Zero means no
limit either way.

`autoComplete` defaults to true. It's forced off when a quest consumes items, so nobody has their
nails taken the second they pick the last one up.

## Objectives

```json
{ "type": "kill",    "count": 25, "location": "Ekron", "label": "Cleared in Ekron" }
{ "type": "collect", "item": "Base.Nails", "count": 20, "consume": true }
```

All of them have to be done. There's no either/or yet.

Leave `location` out and the objective inherits the quest's. Write `false` and it can happen
anywhere. Write a value and it overrides.

`consume` defaults to true, so the items are taken on turn-in. Set it false for "just have this on
you". Items in a backpack count either way.

Skip `label` and you get the item's name, or "Zombies killed".

## Prereqs

```json
"prereqs": {
  "quests": ["intro_supplies"],
  "skills": { "Woodwork": 3, "Aiming": 2 },
  "kills": 100,
  "daysSurvived": 5,
  "hidden": false
}
```

Anything a player hasn't met shows greyed in Available with the reason written out. `hidden` keeps
it off the list entirely until it unlocks.

Perk names are the engine's, not the ones on the character sheet. These four catch everyone:

| Character sheet | What you write |
|---|---|
| Carpentry | `Woodwork` |
| Foraging | `PlantScavenging` |
| First Aid | `Doctor` |
| Lightfooted | `Lightfoot` |

There's no character level in this game, so `kills` and `daysSurvived` are the closest you'll get.

## Locations

```json
"location": "Louisville"
"location": { "x": 11651, "y": 9890, "radius": 120 }
"location": { "x": 10600, "y": 9700, "width": 400, "height": 400 }
"location": { "any": [ "Ekron", "FallasLake" ] }
"location": false
```

The game names these itself: `Muldraugh`, `WestPoint`, `Rosewood`, `Riverside`, `MarchRidge`,
`Louisville`, `ValleyStation`, `Jefferson`, `LAA`, and `General` for anywhere outside a region.

It doesn't name these, so we box them ourselves around the labels drawn on the in-game map:
`Ekron`, `FallasLake`, `Brandenburg`, `EchoCreek`, `Irvington`. The boxes are 300 to 400 tiles
across. If that's not the footprint you wanted, write your own box.

Named buildings work too, since every named zone at that spot gets checked. `CrossRoadsMall`,
`SunstarMotel`, `KnoxBank`, `RustyRifle`, `BinkysFarm` and the rest.

Boxes are measured from the top-left corner. Radius is in tiles. Add `"z": 0` to pin it to one
floor, otherwise any floor counts.

## Rewards

```json
"rewards": {
  "items": [ { "item": "Base.Axe", "count": 1 } ],
  "xp": { "Woodwork": 500 }
}
```

Items go straight into the inventory and nothing checks the weight, so a big payout can leave
somebody overloaded.

## Watch out for

Item types are full types. `Base.Nails`, not `Nails`. Anything the game doesn't recognise gets
named in the log and dropped.

Reordering the objectives on a live quest resets progress for anyone part-way through it, and says
so in the log. Progress is stored against objective position. Adding new quests is always safe.
Editing one people are already doing is not.

A prereq loop, where A needs B and B needs A, gets caught at load. Left alone it would make both
quests permanently unavailable and nothing would ever tell you why.

Kills count where the zombie died, not where the player was standing.
