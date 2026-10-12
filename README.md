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
- Enable **Auto Locker** for detected world rushers. Auto Floor does **not** handle screen-only entity events, solve special puzzles, or complete scripted chase events.

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

## Dex Room_NUM mapping (v1.2.2)

The next-door detector accepts a literal `Room_NUM` object with an `A-###` text sign / number value, as well as numbered names such as `Room_212`. GUI markers resolve to their physical sign/door. `Room_###` room containers resolve to an entrance part instead of highlighting the entire room. Both ESP and navigation use this mapping.

## Locker ESP and actual door model (v1.3.0)

**Visual > ESP > Locker ESP** highlights loaded `Locker` models/parts with its own color picker; both settings persist in configs. Nested locker parts are deduplicated.

Next-door detection now recognizes the actual `DOORMODEL_REAL` model, pairs it with its `Room_NUM` sign (inside the model or directly beside it), and uses its Door / DoorMesh / MeshPart as the path target. ESP attaches to the real door model instead of the number sign when available. It still selects only the next numbered door.

## Pathfind / ESP performance (v1.3.1)

Door and ESP candidates are indexed when objects appear rather than rescanning all map parts each update. Next-door selection is cached for 0.3 seconds and invalidates on room changes and door streaming. Changing name settings or pressing Rescan rebuilds candidate membership. Auto Look now faces the route waypoint / crossing goal ahead, stops turning when there is no movement goal, and no longer locks onto the door behind the player. Disable **Floor > Auto Floor > Auto look** to keep manual camera control. Live performance still needs checking.

## Auto Floor performance and Auto Locker (v1.4.0)

- Room folder lookups are cached. When player room attributes are unavailable, geometry checks cover only the nearest three room pivots, at most once per 0.75 seconds.
- One path calculation worker runs at a time, tries at most three candidates per batch, and backs off for two seconds after blocked routes. Path visualization uses at most 65 points without shortening the navigation route. Generated path visuals are excluded from object indexing.
- **Floor > Auto Floor > Auto Locker (TP / Pathfind)** gives available lockers priority over loot and doors when a recognized world rusher is detected within 300 studs. It checks available prompts and occupancy, confirms hiding using character/player state or locker occupancy, and temporarily skips lockers whose entry is not confirmed.
- Hiding continues for two seconds after the last threat detection. Automatic exit requires a standard Exit/Leave prompt in the locker; if the game uses a custom exit action, the status asks you to leave manually. Detection does not cover screen-only A-90 or identify every possible mimic model.
- Mock tests cover forward camera aiming after passing a door, no repeated decoration scans, and confirmed hiding / threat-clear exit in both movement methods. Live game performance and locker state bindings remain unverified.

## Movement-based locker exit (v1.4.3)

After the existing threat-clear delay, Auto Locker sends a short camera-relative forward movement request when no Exit/Leave prompt exists. This uses Humanoid movement, shared by PC and mobile, rather than holding a virtual keyboard key. Auto Floor waits for hiding state to clear before resuming. Pulses stop when danger returns or automation is disabled; three unconfirmed attempts produce a status message instead of moving forever. Offline tests cover movement-based exits in both TP and Pathfind. Live input-handler compatibility remains unverified.
