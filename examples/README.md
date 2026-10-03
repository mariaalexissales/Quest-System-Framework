# Writing quests

Quests are .json files in `Zomboid/Lua/QuestFramework/`. On a server that's the server's folder,
not the players'. As many files as you like, as many quests per file as you like.

If the folder has no quests in it the first time a world starts, it gets created with a
`quests.json` holding one starter quest. On a host that runs the server with its own data folder,
it's in there instead, for example `server-data/Lua/QuestFramework/`. That only happens once per
world, so delete the starter and it stays deleted.

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
nails taken the second they pick the last one up. It's also forced off when the rewards have a
`choice`, since there's nobody to ask which one they wanted.

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

That's only for the file. Players are shown the character sheet's name, so `"Woodwork": 3` reads
as "Requires Carpentry 3" and an XP reward as "Carpentry +500 XP".

A name the game doesn't know gets named in the log and dropped, the same as an item.

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

## Teleport

```json
"teleport": { "x": 11651, "y": 9890, "z": 0, "cooldownHours": 12 }
```

Give a quest a `teleport` and a Teleport button appears next to Accept once the player has taken
it. They get a "You will be teleported to the event location, proceed?" prompt, and on yes they
go. It's meant for event quests, where walking somebody forty tiles to the start isn't the point.

The button only exists while the quest is in progress. It's not on Available and it's not on
Completed.

This can't be worked out from `location`, which is why it's written separately. A location can be
a town name or an `any` list, and neither of those is a spot to stand on.

`z` is the floor, default 0. That's different to `location`, where leaving `z` out means any floor
counts.

`cooldownHours` is in-game hours and defaults to 0, meaning they can use it as often as they like
while the quest is on. Set it if you'd rather it wasn't a free ride home and back. The button
stays visible while it's cooling down and shows the hours left.

The cooldown belongs to the quest, not to one run of it, so dropping the quest and taking it again
won't clear it. That's the only thing an abandoned quest leaves behind, and only if the player
actually teleported.

Point it at something off the map and it gets refused and logged. Check your coordinates against
the in-game map with the debug menu open.

## Rewards

```json
"rewards": {
  "items": [ { "item": "Base.Axe", "count": 1 } ],
  "xp": { "Woodwork": 500 }
}
```

Items go straight into the inventory and nothing checks the weight, so a big payout can leave
somebody overloaded.

### Letting them pick

```json
"rewards": {
  "items": [ { "item": "Base.Nails", "count": 20 } ],
  "choice": {
    "label": "Pick your tool",
    "options": [
      { "item": "Base.Axe", "count": 1 },
      { "item": "Base.Sledgehammer", "count": 1 }
    ]
  }
}
```

Give the rewards a `choice` and Turn In opens a picker instead of paying out straight away. The
player picks one option, hits Confirm, and gets that on top of everything in `items` and `xp`,
which are still paid in full. Cancel leaves the quest in progress and nothing is taken.

The options are listed in the quest's details on Available too, so people can see what's on offer
before they take it. The details show the first six, and the picker shows the lot.

`label` is the heading on both. Leave it out and you get "Choose your reward" on the picker and
"Choose one" in the details.

Options are written the same way as `items`. One the game doesn't recognise gets named in the log
and dropped, and the rest still stand. If every option is dropped, the choice goes with them and
the quest pays out like it never had one.

Past eight options the log warns you. They all still load, but the picker grows to fit rather than
scrolling, so a long enough list will run off the screen.

## NPCs

```json
{
  "npcs": [
    {
      "key": "old_joe",
      "name": "Old Joe",
      "x": 10629, "y": 9312, "z": 0,
      "outfit": "Farmer",
      "greeting": "You look like you can swing a hammer."
    }
  ]
}
```

An NPC stands on its tile and hands out quests. Players right-click on or beside it and pick
Talk. It can't be hurt, zombies walk straight past it, and it doesn't move. If something does shift
it, a car for instance, it's back on its tile a couple of seconds later.

They go in the same folder as quests, in any `.json`, under `npcs`. A file can hold both lists or
just one. `npcs.json` in this folder is one to copy.

`key`, `x` and `y` are the only things you have to write.

`key` is what a quest points at, so the same rules as a quest key. Renaming one cuts its quests
loose.

`name` is what players see. Leave it out and they see the key.

`z` is the floor, default 0.

`outfit` is a vanilla zombie outfit, default `Generic01`. A few that work for either sex: `Farmer`,
`Police`, `Doctor`, `Fireman`, `Ranger`, `Camper`, `Trader`, `Evacuee`, `Teacher`, `Chef`,
`Biker`, `Classy`, `Young`, `Retiree`. The debug menu's horde tool lists every one of them.

`female` is true or false, default false. Some outfits only exist for one sex: `Priest`,
`Mechanic` and `Hunter` are men's, `Generic_Skirt` and `OfficeWorkerSkirt` are women's. Ask for
one the wrong way round and the log tells you and the NPC gets `Generic01` instead.

`skin` is 1 to 5, light to dark, default 1.

`facing` is a compass point, `N` `NE` `E` `SE` `S` `SW` `W` `NW`. Default `SE`, which is toward
the camera.

`greeting` is what they say when the conversation opens. `<LINE>` and `<RGB:r,g,b>` work here too.

Whatever an NPC says in the conversation also appears over its head, as plain text and once per
conversation. Only the player talking sees it. A long line is cut short up there and is in full in
the window.

An NPC keeps the same clothes for good, across restarts and for every player. Changing its
`outfit` or `female` re-rolls them. Moving it doesn't.

### Giving quests

```json
{
  "key": "intro_supplies",
  "title": "Something To Build With",
  "giver": "old_joe",
  "dialogue": {
    "offer": "Bring me nails and planks and we'll talk about the work that pays.",
    "progress": "Still short. Nails and planks.",
    "complete": "That'll do. Here."
  },
  "objectives": [ { "type": "collect", "item": "Base.Nails", "count": 10 } ]
}
```

Give a quest a `giver` and it belongs to that NPC. It leaves the Available tab, and the only way to
take it or hand it in is to stand within three tiles of the NPC, on the same floor, and talk. The
server checks that itself. Once taken it's in the log under In Progress like any other, and it can
be abandoned from there.

`autoComplete` is off for these whatever you write, since handing it in is the point.

`dialogue` is what the NPC says about that quest. `offer` before it's taken, `progress` while it's
underway, `complete` when it's ready to hand in. All three are optional. With no `offer` they say
the quest's `description`, and the other two have stock lines.

Everything else about the quest works as it did. Prereqs still lock it, and a locked quest shows
in the conversation greyed with the reason, unless it's `hidden`.

A `giver` that names nobody gets a warning in the log, and the quest goes back to being an
ordinary one in the log rather than being stuck where nobody can reach it.

### Placeholders

```json
"greeting": "Morning, {player}. I'm {npc}.",
"dialogue": { "offer": "{quest} won't do itself, {player}." }
```

Three names in curly braces are swapped for the real thing when a player reads the line:

| You write | They see |
|---|---|
| `{player}` | their character's first name |
| `{npc}` | the name of the NPC giving the quest |
| `{quest}` | the quest's title |

They work in a `greeting`, in the three `dialogue` lines and in a quest's `description`, so a
description reads the same in the log as it does when the NPC says it.

One with nothing to fill it is shown as written. That's `{quest}` in a greeting, or `{npc}` on a
quest nobody gives. Anything else in braces, a typo like `{plyer}`, is shown as written too and
named in the log.

### The marker

A gold `!` over an NPC's head means they have something new for you. A gold `?` means something of
theirs is ready to hand in. A grey `?` means you're part-way through one. Nothing means nothing.

Each player sees their own.

### Placing one in game

Right-click a tile and pick Place quest NPC here. Fill in a name, pick an outfit, confirm. They
appear on the spot. Leave the key empty and it's made from the name, so "Old Joe" becomes
`old_joe`.

On a server that's admins only. In singleplayer it needs debug mode on, so it isn't sitting in
everybody's right-click menu.

These are written to `npcs_placed.json` in the quest folder. That file belongs to the game: it
rewrites the whole thing every time one is placed or removed. You can edit it by hand and the
edits are kept, but your own files are never touched, so anything you want comments in belongs in
one of those.

An NPC placed this way can be removed by right-clicking it. One you wrote into a file yourself
comes out of that file.

To make a placed NPC hand out quests, put its key in a quest's `giver` and hit Reload.

## What players are told

A line appears over the player's head when they take a quest, when they finish one, and when
something they asked for is refused. A refusal says why: too far from the giver, or the same
reason the log greys a row with. A quest that completes itself says so too.

Admins get one when a reload finishes.

## Watch out for


Item types are full types. `Base.Nails`, not `Nails`. Anything the game doesn't recognise gets
named in the log and dropped.

Reordering the objectives on a live quest resets progress for anyone part-way through it, and says
so in the log. Progress is stored against objective position. Adding new quests is always safe.
Editing one people are already doing is not.

A prereq loop, where A needs B and B needs A, gets caught at load. Left alone it would make both
quests permanently unavailable and nothing would ever tell you why.

Kills count where the zombie died, not where the player was standing.

An NPC is a zombie underneath, dressed up and held still. Anything that acts on every zombie acts
on it too. Clearing zombies with an admin command takes the NPCs with them, and they're back in a
few seconds. Another mod's armed survivors will shoot at one, and waste the bullets. Hitting one
never counts toward a kill objective.

An NPC's tile has to be loaded for it to exist, so the first player into an area sees it appear a
moment after they arrive. Chunks load well ahead of where anyone can see, so in practice it's there
by the time they get to it.

A conversation lists the first ten things an NPC has for a player. Past that the rest don't fit.
Give the eleventh to somebody else.

A file with a syntax error in it costs you that file and one line in the log, naming the file and
the line the mistake is on:

```
[QSF] WARN: QuestFramework/quests.json: line 14: expected a comma or a closing brace in object
```

Every other file still loads, and the summary line counts the bad one under rejected. Fix it and
hit Reload. The warning comes back on every reload until you do, and placing or removing an NPC in
game is a reload.
