# thinkinghub

**Thinking Hub for ROOMS: Revisited — Mr H, Owner.**

Standalone client hub using [Obsidian](https://github.com/deividcomsono/Obsidian) and [MSESP](https://github.com/mstudio45/MSESP). It does not require mspaint or the DOORS addon.

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/KoSmoXD/thinkinghub/main/loader.lua"))()
```

The loader fetches the current `rooms_revisited.lua` with a fresh query parameter each time. Running it again unloads the previous Thinking Hub instance first. **Right Control** toggles the menu; Obsidian also provides mobile controls.

The client environment must provide `loadstring` and `game:HttpGet`. Automatic prompt interactions require `fireproximityprompt`; click interactions require `fireclickdetector`. The script is not a normal Roblox Studio LocalScript.

## Layout

| Section | Tabs / features |
| --- | --- |
| Credits | **Mr H - Owner** in yellow; library attribution |
| Home | General: Unload. Configs: name input, selection, Create, Load, Overwrite, Delete, Refresh |
| Main | Player: Loop speed toggle; speed slider **0–1000**; Instant interact; Auto interact for drawers and money |
| Visual | ESP: Doors, Bucks, Entities, each with its own color picker. Notify: entity toggle, Roblox sound ID input, Apply Notify Sound |
| Floor | Auto Floor toggle; **TP / Pathfind**; Auto loot; Auto look; Smooth camera; path color picker; editable detection settings |

Obsidian's main tabs serve as sections, with tabboxes inside them for the requested subtabs.

## Movement and interaction

- **Loop speed** writes the selected Humanoid WalkSpeed every Heartbeat, including after respawn. Disabling it restores the saved speed unless Auto Floor still owns movement.
- **Auto Floor** uses speed 40 unless Loop speed is enabled. Pathfind calculates a Roblox navigation route, draws it, and submits world-space movement after the normal controls. Blocked routes replan; old calculations are discarded when the method changes or automation stops.
- **TP** moves to the target approach point and then across a door threshold. It does not use tplay code. Server acceptance is not guaranteed.
- **Auto loot** prioritizes nearby drawers and bucks in the current room before the door. Without Auto Floor, it only interacts with nearby items. Pickup attempts are bounded; unconfirmed loot is temporarily skipped.
- **Auto look** faces Auto Floor's current target. Smooth camera interpolates that rotation.
- **Instant interact** sets prompt hold duration to zero and restores the original values when disabled or unloaded. It does not rewrite game remotes or extend interaction range.
- Auto Floor does **not** automatically hide, handle screen-only entity events, solve special puzzles, or complete scripted chase events.

## Configs

Files are saved as data-only JSON in `ThinkingHub/ROOMSRevisited/configs` within your client environment's filesystem. Enter a name to create; select an existing entry to load, overwrite, or delete. Names cannot contain path separators. Loading validates values before applying them and turns movement features on last.

Filesystem APIs are optional for the hub but required for configs. If unavailable, Home explains why saving is disabled.

## Detection and compatibility

**This version has not been tested inside a live ROOMS: Revisited session.** The linked community wiki describes the legacy game and does not expose the current Roblox instance hierarchy. Default names are configurable guesses, not verified game bindings.

The hub watches loaded Workspace objects and standard ProximityPrompts / ClickDetectors. Default aliases include:

- Door: `Door, ExitDoor, RoomDoor, RoomExit, Exit`
- Bucks: `Bucks, Buck, Money, Cash, MoneyPile, BucksPickup, CashPickup`
- Drawer: `Drawer, Drawers, DrawerContainer`
- Entity: `A60, A60b, A70, A90, A90b, A200, A25, MultiMonster, MultiBounder, Paralysis, Sensation`

Names ignore case, spaces and punctuation. Entity models marked `IsEntity = true` are also recognized. Player characters are excluded. ESP labels show up to the nearest 80 enabled targets and reuse the shared MSESP library without clearing other scripts' ESP.

Under **Floor > Detection**, enter the actual comma-separated object names if the game uses different names. Leave room folder blank for `CurrentRooms`, `Rooms`, `GeneratedRooms`, or `ActiveRooms`; otherwise enter a path relative to Workspace, for example `Map.CurrentRooms`. Press **Rescan** after changes.

If no path appears, check **Home > Status** for the detected object counts and controller message. A game using custom GUI interactions instead of standard prompts needs a game-specific adapter; changing names alone will not add that protocol. Entity notifications cover world models/parts, not purely GUI encounters. Audio playback depends on the selected asset's access permissions.

## Validation

Syntax checked with `texluac -p`. Offline mocked behavior tests cover startup, loop speed and restore, Pathfind steering, TP, cancelled path calculations, prompt interaction, ESP updates, notification deduplication, config CRUD / path validation, and idempotent unload cleanup.

```sh
texluac -p rooms_revisited.lua
texluac -p loader.lua
texlua tests/smoke.lua
```

Mocks cannot verify the live map, server behavior, game interactions, or rendering.

## Dependencies and references

- [Obsidian documentation](https://docs.mspaint.cc/obsidian) — pinned dependency commit `d62041eda54085a03259c789d4af2be76077379f`.
- [MSESP documentation](https://docs.mstudio45.com/esp-library/home) — pinned dependency commit `dbde68c85af504d58dac73a537fda21ca8fa626a` (an already-loaded shared MSESP instance is reused).
- [User-supplied game wiki](https://rooms-revisited.fandom.com/wiki/ROOMS:_Revisited_Wiki).

Dependency code stays in its upstream repositories; the hub loads the referenced versions.

## Camera controls (v1.1.0)

Visual > Camera adds **Loop FOV**, a **1–120 FOV slider**, and **No Camera Shake**. FOV runs independently of Auto Floor and restores saved values when disabled or unloaded, including for replacement cameras. Both settings are saved in configs.

No Camera Shake zeroes Humanoid camera offsets and removes effects applied after the standard camera update. It leaves Scriptable cameras / cutscenes alone. Shake applied within a custom game camera controller may require a game-specific adapter; live compatibility is unverified. Auto look is applied after shake suppression.

## Next door only (v1.2.0)

Door ESP and Auto Floor share one selector. It requires the current room number and a door destination equal to that number plus one (including `A-212` and `A-1000`). Destinations come from a numbered door name, a sign TextLabel/TextButton, or a DestinationRoom / NextRoom / DoorNumber / RoomNumber attribute. The candidate must belong to the current room when that room is resolved. Generic doors without a destination, previous doors, and later doors are excluded. If the next numbered door cannot be identified, ESP stays empty and navigation waits rather than targeting an arbitrary door. This mapping still needs live-game validation.

## Interaction detection (v1.2.1)

Money ESP also resolves pickup prompts labeled Bucks / Cash / Money or `$25`-style amounts, including anonymous pickup parts inside drawers. Numbered drawer names such as `Drawer_1` are recognized. If interactions still fail, stand beside a drawer or money pickup, choose **Floor > Detection > Copy interaction diagnostics**, and share the copied report. It includes nearby interaction classes, instance paths, labels, ranges and available interaction functions, so a custom game adapter can be written from actual evidence.
