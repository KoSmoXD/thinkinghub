# thinkinghub

## v0.10.6: observed Overhaul roles and diagnostic mouse fix

The shared detector now reads the live Character `Entity` string and
`Survivor=true` flag observed in an Overhaul diagnostic report with no Roblox
Teams. This fixes the missing role mapping used by ESP, Bigger Hitbox and Loop
Tp; selected player loadouts remain excluded. Regression fixtures cover Halt,
Guidance, survivors with entity loadouts, and round changes.

The standalone role report releases first-person mouse lock with a modal close
button and supports Right Shift to close. Reloading the hub closes an old role
report automatically. Tests are mocked; live gameplay still needs verification.

## v0.10.4: Auto Loop Tp

Exploits > Teleport now contains a red **Auto Loop Tp** toggle with description
`This is bannable,dont abuse this too much`. While enabled as a living entity,
it moves your HumanoidRootPart to the nearest living survivor every 0.2 seconds.
It pauses outside the entity role or without a valid target, follows respawns,
and stops on disable/unload. The setting survives UI style changes.
Client teleport behavior is not live-game verified.


## v0.10.3: removed features

Infinite Stamina and entity Auto Play have been removed, including their modules,
ability bindings, settings and background updates. The now-empty Player and
Entities tabs are gone. Bigger Hitbox remains in Exploits; ESP, visuals and the
fragment puzzle assistant remain available. Earlier release notes below are historical.

## v0.10.1: Bigger Hitbox

In v0.10.2, open the separate **Exploits** sidebar tab, then **Bigger Hitbox**.
The size slider accepts 2–20 studs
(default 8). Known living opponents with HumanoidRootPart rigs are expanded
locally; self, teammates and unknown roles are skipped. Expanded roots are
translucent, noncolliding and massless. Original properties restore on disable,
death, team change, respawn, player departure or unload (including End).
The toggle and size survive UI style switches. This does not change the server's
hit validation; increased hit registration is not confirmed in live gameplay.

Validation: 12 mocked Lua 5.4 suites and 23 Lua syntax checks, including hitbox
target filtering, size updates, lifecycle changes and exact property restoration.

## MAYHEM / Overhaul v0.10 reliability update

The Mayhem adapter lives on `feat/doors-mayhem-support` (PR #1).
Start it inside the Overhaul testing portal with:

```lua
getgenv().ZincMayhemForceOverhaul = true
loadstring(game:HttpGet("https://raw.githubusercontent.com/KoSmoXD/thinkinghub/feat/doors-mayhem-support/doors_mayhem.lua"))()
```

- **Emergency stop:** press **End**, or use Home > Unload, to stop automation,
  release native prompt holds, and restore camera/lighting. End ignores text entry.
- **Path recovery:** six-second path-request timeout, stale-result rejection,
  proper stop on reaching a target, character hiding/death checks, and no stuck
  replans while a path is still computing. Status includes timeout counts.
- **Fragment assistant:** separate debounce for same-name answer buttons,
  inactive-button exclusion, and at most three unconfirmed prompt attempts,
  spaced at least eight seconds apart (long holds extend this delay).
- **Respawn handling:** immediately discard old-character stamina sources and
  reject sources moved outside the local player/current character.
- **Visuals and UI:** preserve original FOV/fullbright settings across repeated
  toggles and camera changes; prevent overlapping UI switches and late downloads
  reopening an unloaded window. Periodic ESP scans discover late metadata even
  when that category already has other indexed objects.
- **Fault reporting:** a failing controller stops once while the other controllers
  continue. Details appear in F9 and `getgenv().ZincMayhem.Errors`; reload to retry.

Validation: 11 offline Lua 5.4 mocked test suites and syntax checks for all 21 Lua
files. These checks do **not** establish live Roblox compatibility. Actual map
navigation, game-specific ability bindings, fragment GUI mapping, streaming and
server-authoritative stamina still require an in-game test. Unknown puzzle
answers remain manual. No claim that every live-game issue is resolved.

Suggested live check: enable autoplay as an entity, approach a survivor, respawn,
then try the fragment assistant as a survivor. Toggle FOV/fullbright twice,
switch UI styles, and press End during movement or a held prompt; confirm motion
and holds stop and visuals restore. Capture F9 errors if any step fails.

**Zinc Hub for ROOMS: Revisited.**

Standalone client hub using selectable [Obsidian](https://github.com/deividcomsono/Obsidian) or **ZincUI** (our own library), plus [MSESP](https://github.com/mstudio45/MSESP). It does not require mspaint or the DOORS addon.

## Run

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/KoSmoXD/thinkinghub/main/loader.lua"))()
```

The loader fetches the current `rooms_revisited.lua` with a fresh query parameter each time. Running it again unloads the previous Thinking Hub instance first. **Right Control** toggles the menu in both UI styles; ZincUI supports mouse and touch.

The client environment must provide `loadstring` and `game:HttpGet`. Automatic prompt interactions require `fireproximityprompt`; click interactions require `fireclickdetector`. The script is not a normal Roblox Studio LocalScript.

## Layout

| Section | Tabs / features |
| --- | --- |
| Home | General: Unload and UI style **Obsidian / Zinc**. Configs: Create, Load, Overwrite, Delete, Refresh |
| Main | Player: Loop speed toggle; speed slider **0–1000**; Instant interact; Auto interact for drawers and money |
| Visual | ESP: Doors, Bucks, Entities, each with its own color picker. Notify: entity toggle, Roblox sound ID input, Apply Notify Sound |
| Floor | Auto Floor toggle; **TP / Pathfind**; Auto loot; Auto look; Smooth camera; path color picker; editable detection settings |

When Obsidian is selected, its main tabs serve as sections with tabboxes for subtabs. ZincUI uses its own left navigation and stacked sections.

## ZincUI style (Windows XP layout, ZincUI v0.2.1)

Choose **Home > General > UI style > Zinc** to replace Obsidian with the public [ZincUI library](https://github.com/KoSmoXD/ZincUI). The adapter tries the public source first and falls back to the in-repository `lib/ZincUI.lua` mirror if it is unavailable. Choose **Obsidian** to switch back. Both styles use the same game features; `lib/ZincAdapter.lua` maps controls without duplicating game logic.

Switching styles rebuilds the client hub, preserves currently selected feature values (including colors, method, speed and toggles), and restores movement-related toggles last. The chosen style remains selected during the current client environment session. A fresh client session defaults to Obsidian; saved config files remain unchanged. If ZincUI fails to download or initialize, the hub attempts Obsidian fallback.

The custom ZincUI style is a single Windows XP-inspired application window, with a blue title bar, left navigation, square beveled controls and bottom status bar. Drag the window using the title bar, the bottom status bar, or the narrow lower edge with mouse or touch. It supports mouse/touch, sections, dropdowns, buttons, sliders, color pickers, notifications and Right Control to show/hide the menu. Live ROOMS: Revisited rendering and interaction are not yet verified.

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

Earlier versions were syntax checked with `texluac -p`. Offline mocked behavior tests cover startup, loop speed and restore, Pathfind steering, TP, cancelled path calculations, prompt interaction, ESP updates, notification deduplication, config CRUD / path validation, and idempotent unload cleanup.

```sh
texluac -p rooms_revisited.lua
texluac -p loader.lua
texlua tests/smoke.lua
```

Mocks cannot verify the live map, server behavior, game interactions, or rendering.

## Dependencies and references

- Public standalone library: [KoSmoXD/ZincUI](https://github.com/KoSmoXD/ZincUI) (MIT). Hub fallback mirror: [`lib/ZincUI.lua`](lib/ZincUI.lua). Adapter: [`lib/ZincAdapter.lua`](lib/ZincAdapter.lua).
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

## Stable door routes and locker key input (v1.4.4)

The toggle is now **Door ESP**, with labels such as **Door A-212** for both upcoming doors. An acquired door route no longer gets cancelled just because the number-sign / ESP lookup temporarily returns no result. Crossing attempts expire after three seconds if the player's room progress has not advanced, instead of permanently excluding that door.

Locker exit also sends a short W key event through VirtualInputManager when supported, alongside the existing movement request. Key-up is sent on pulse completion, route reset, confirmed exit, disable and unload. No key is pressed while a text box has focus. Availability depends on the client; live exit compatibility remains unverified.

## DOORS: MAYHEM + OVERHAUL TESTING (beta v0.2)

Zinc Hub routes the original [DOORS: MAYHEM](https://www.roblox.com/games/119040856156269/DOORS-MAYHEM) place `119040856156269` to the separate [doors_mayhem.lua](doors_mayhem.lua) adapter. The same adapter also supports **DM: OVERHAUL TESTING**, the public-test place linked from the original game's portal.

**The Overhaul testing Place ID is not yet independently verified.** The loader checks Roblox's own asset metadata for the exact experience titles `DM: OVERHAUL TESTING`, `DOORS: MAYHEM OVERHAUL TESTING`, or `DOORS: MAYHEM TESTING` and verifies creator `MISTICHISKII` (or original MAYHEM universe `6537995571`). If metadata cannot be read, unrecognized places retain the old ROOMS fallback. This title/creator check is a beta compatibility path, not proof of live runtime compatibility.

Mayhem and Overhaul are team-based asymmetric survival games, not linear next-door games. The UI uses the standalone XP-style ZincUI with Right Control to toggle.

- **Home**: Mayhem classic vs Overhaul build label, player role/team (when exposed through client-visible attributes), counts, console diagnostics, Unload.
- **ESP**: Player highlights with team filtering; objectives (yellow); exits (green); world entity models (pink).
- **Glitch Fragment ESP**: dedicated toggle independent from ordinary objectives. Pink highlights and floating `GLITCH FRAGMENT [NN studs]` text. Detects names such as `GlitchFragment`, `GlitchShard`, named attributes, and `ProximityPrompt` text; ignores plain `Glitch` to avoid confusing a monster with a fragment.
- **Visual**: local FOV, fullbright, spectating, XP/Dark/Midnight themes.
- **Cleanup**: destroys highlights and billboards, disconnects listeners, restores client camera and visual values.

Real object trees and naming in Overhaul remain unverified. Since object detection is client-visible and name-based, some objectives/fragments will not appear without a live diagnostic sample. ESP counts are bounded, and the adapter does not fire game remotes, solve objectives, or copy ROOMS Auto Floor.

**Glitch Fragment ESP usage:** open **ESP > Map objectives**, enable **Glitch Fragment ESP** to see pink highlights and distance labels. If Overhaul uses different pickup names, enter them under **ESP > Glitch Fragment detection > Extra fragment aliases**, then press **Apply aliases and rescan**. Existing objective ESP works independently.

**Manual Overhaul override:** when the testing portal uses an unknown Place ID or Roblox blocks metadata lookup, run the two-line loader below. The override is intentionally opt-in; the normal dispatcher still requires a verified name/creator combination. The fragment scanner only inspects client-visible objects and does not manufacture pickups.

**Direct testing loader for either Mayhem or Overhaul (feature branch):**

```lua
getgenv().ZincMayhemForceOverhaul = true
loadstring(game:HttpGet("https://raw.githubusercontent.com/KoSmoXD/thinkinghub/feat/doors-mayhem-support/doors_mayhem.lua"))()
```

After merging the PR, use the main `loader.lua` in Run. The client must support `game:HttpGet` and `loadstring`. Live Roblox gameplay is not yet tested.

The offline CI suite parses `doors_mayhem.lua` and runs `tests/mayhem_dispatch.lua` for classic/testing routes and false positives plus `tests/mayhem_fragments.lua` for real classification code and fake instance fixtures, and `tests/mayhem_guard.lua` for testing metadata/override behavior.


### Mayhem UI/ESP bug fixes (v0.3 beta)

When using Mayhem in Obsidian mode, its adapter also provides a draggable bottom-left footer grip, while leaving Obsidian's lower-right resize control intact.


- The pink color previously used for generic world entities is now orange. Player ESP defaults to **green** for confirmed opponents, **blue** for same-team players, and **cyan** when team/role information is missing. The **Player ESP color** dropdown changes the confirmed-opponent color (Green/Blue/Cyan/Yellow/Red).
- The Mayhem module now supports **Home / Visual > Interface > UI library > Zinc or Obsidian**, using the shared Obsidian library with a compatibility facade in [lib/MayhemObsidian.lua](lib/MayhemObsidian.lua). Selecting a new UI style reruns the game module, copies feature settings and fragment aliases, and unloads the old window. This is not the XP theme selector.
- Fragment detection now recognizes eligible names, text on pickup prompts, common item attributes, CollectionService tags, and fragment containers. With fragment ESP enabled and no candidates detected, a throttled, incremental rescan runs periodically. **Overhaul may still use undisclosed runtime names**, so Home has a **Scan pickup names to console** diagnostic button, which prints the nearest 40 standard ProximityPrompts with their paths, labels and likely fragment matches. The game's own guide describes glitch fragments as a second-stage Hotel objective, so none may be loaded in the lobby.
- The user-uploaded short clip shows the pre-round lobby and a ZincUI window; no spawned fragment is visible in that clip. Obsidian and actual pickup mapping require a live round test.
- New `tests/mayhem_ui.lua` validates the Obsidian facade control contract in a mocked Lua environment. GitHub CI continues compiling the Mayhem module and testing the loader and classifiers.

**Development-branch loader:**

```lua
getgenv().ZincMayhemForceOverhaul = true
loadstring(game:HttpGet("https://raw.githubusercontent.com/KoSmoXD/thinkinghub/feat/doors-mayhem-support/doors_mayhem.lua"))()
```

### Library glitch book and Cellar lever ESP (v0.4 beta)

The MAYHEM map guide documents the **Library** as a code-book collection objective and **Cellar** as a lever-pulling objective. The in-game object instance hierarchy in the public Overhaul build is not yet confirmed, so the matcher uses known aliases, standard interaction prompts, attributes, CollectionService tags, and optional user-defined names. No gameplay remotes are called.

Under **ESP > Map objectives**:
- **Glitch Book ESP (Library, blue)** highlights matching interactable books in light blue and displays `GLITCH BOOK [distance in studs]`.
- **Lever ESP (Cellar, gold)** highlights matching levers in gold with `LEVER [distance in studs]`.
- Both are separate from regular Objective ESP and the original **pink Glitch Fragment ESP**.

Use **ESP > Library / Cellar detection** to enter comma-separated custom book/lever names and click **Apply aliases and rescan objectives** when Overhaul changes object names. Aliases and toggles carry over when switching between ZincUI and Obsidian. Home > Scan pickup names to console reports classified prompts if expected pickups do not appear.

Detection excludes objects nested inside player characters, and it does not automatically solve puzzles or interact with objects. Offline tests include named/numbered objects, prompt labels, attributes, tags, alias overrides, decorations, character inventory exclusion, and regressions for previously implemented ESP types. **Live game verification remains pending**.

### MSESP rendering and Key ESP (Mayhem v0.5 beta)

- The client now uses **mstudio45/MSESP v2.1.4** (the pinned version already used by the ROOMS module). It creates MSESP **Highlight** markers, color-coded billboards and distance text for players, entities, fragments, books, levers, keys and exits. It no longer creates Zinc-owned Highlight/BillboardGui instances. The shared MSESP library is never cleared or destroyed when MAYHEM unloads; only its own markers are removed. If MSESP fails to load, startup reports an error rather than silently switching to a different renderer.
- Under **ESP > Map objectives**, **Key ESP (yellow)** detects known keys (Key, HotelKey, RoomKey, ExitKey, GoldenKey and numbered key variants). It recognizes client-visible pickup prompts, object names, attributes and CollectionService tags. It is independent of other ESP toggles and excludes player-held items and door prompts labeled "Use Key".
- Under **ESP > Key detection**, provide custom comma-separated key object names and press **Apply key aliases and rescan** for Overhaul Testing map variants. The aliases and key toggle survive switching between ZincUI and Obsidian.
- The player/objective/fragment/book/lever/exit ESPs all use MSESP after this change. Book highlights remain blue, levers gold, keys yellow, and glitch fragments pink. MSESP's default GlobalConfig.Distance setting supplies distance indicators.
- `tests/mayhem_msesp.lua` covers the MSESP API options, caching, recoloring, category changes and per-marker teardown. `tests/mayhem_fragments.lua` now includes key classifier cases, avoiding false positives from keyboard/keyhole and door prompts.
- **Live Roblox gameplay not yet tested:** the exact Key model names and MSESP rendering behavior can differ by Overhaul version. The Home pickup diagnostic scanner can reveal names if the Key ESP finds zero items.

### Obsidian window toggle (v0.5)

In **DOORS: MAYHEM / Overhaul Testing**, press **Right Shift** to hide or show the **Obsidian** interface. This calls Obsidian's native toggle and does not unload the hub or reset ESP settings. The **ZincUI** interface retains **Right Control**. The keybind applies when the UI style is selected under **Visual > Interface > UI library**.

### Experimental infinite stamina (MAYHEM v0.6)

New **Player > Movement > Infinite stamina (experimental)** toggle for DOORS: MAYHEM and Overhaul Testing. This is a best-effort **local-only refill**, not a proven bypass of the game's authoritative stamina mechanics. It searches the local player, character, and their descendant **NumberValue/IntValue** objects or numeric attributes named `Stamina`, `CurrentStamina`, `SprintStamina` and similar. It tries to refill them to the locally exposed `MaxStamina` (or a 100 fallback) every 0.1 seconds and discovers newly spawned sources periodically.

**Player > Inspect local stamina sources** prints candidate paths to the F9 console. The live status label distinguishes "No accessible stamina source found" from client writes; even a successful client write does **not** confirm server-authoritative stamina will stay full. If MAYHEM computes stamina inside a private Lua closure or on the server, this toggle will not bypass it. No arbitrary closures, game remotes, or other players' data are touched.

The stamina controller does not write to PlayerGui stamina bars, does not persist changes when disabled, and stops on unload or UI reload. The toggle is preserved during ZincUI/Obsidian style changes. This feature has **not been verified in a live MAYHEM round**.


### All entity Auto Play (MAYHEM v0.8 beta)

The former Rush-only Auto Play has moved to **Entities > Entity Auto Play**. It now auto-detects **Rush, Figure, Bramble, Seek, Halt, Eyes**, and **Jeff the Killer** (special/admin), with a **Generic** fallback when the player is on an entity team with an unrecognized role. The roster follows the community's MAYHEM character listing, not the standard DOORS game roster.

- **Movement:** nearest living survivor (excluding same-team/entity teammates, inactive/dead players and publicly marked hiding players), Roblox PathfindingService navigation, target movement repathing, blocked-path rescan, and stall-based restart. Uses Humanoid:MoveTo and cannot control special rigs without a Humanoid.
- **Role detection:** character/player role attributes and team name. A survivor team overrides stale selected entity attributes. Select a manual role in the dropdown only when auto detection fails.
- **Abilities:** optional per-entity bindings. In **Entities > Per-entity ability bindings**, enter four comma-separated Roblox keys in *Primary, Ability 1, Ability 2, Ability 3* order, e.g. `Q,E,R,F`. Default `None,None,None,None` does not press anything. Each profile has separate conservative distance and cooldown rules; **Jeff's admin Ultra Attack is never auto-fired**. Exact game bindings and individual ability behavior are unverified and require user configuration.
- **Persistence:** entity auto toggle, ability enabled toggle, manual role, and all profile key mappings survive switching ZincUI/Obsidian.
- **Diagnostics:** status text reports active role/target, planned paths, stuck recoveries and issued ability inputs. If the game uses a client movement controller instead of Humanoid:MoveTo, no functional movement can be guaranteed.
- **Checks:** `tests/mayhem_entities.lua` tests all profile names, role/team detection, nearest survivor, blocked path replan, movement, independent ability bindings, reset/unload and special ability restriction. Existing ROOMS module is unchanged.

This is an experimental **client-side** navigation and input integration. Real in-game movement and ability use have **not** been verified on the live Overhaul test place, and additional entity variants may need specific adapters.

### Fix: Player ESP when playing as an entity (v0.8 patch)

The **ESP > Teams > Player highlights** filter now checks the actual Teams service team first and uses role attributes only as fallback. A survivor remains classified as Survivor even if a stale `SelectedEntity` or character attribute says Rush/Figure from a previous round. When **Opponents only** is enabled, survivors are visible to entity players; same-team players and known other entities are excluded. Unknown-role players on other teams appear cyan instead of being silently discarded. The ESP uses `HumanoidRootPart`, `PrimaryPart` or another actual `BasePart` and can display custom entity/character rigs without a Humanoid if they are not explicitly dead. The ESP origin also uses a custom rig root when needed. Use **ESP > Teams > Inspect player ESP filter (F9)** to print the observed team, role, rig type, and candidate visibility for every player. Live behavior needs validation in the game.


### Auto Glitch Fragment Game (Mayhem v0.9 experimental)

The Hotel map's second objective uses Glitch Fragments: after the first objective, players solve them to obtain the Hotel key. **Auto Glitch Fragment Game (beta)** is in **ESP > Hotel Fragment Game (experimental)**, separate from the pink Glitch Fragment ESP.

- While playing as a survivor, the assistant attempts to activate recognized Glitch Fragment ProximityPrompts only when inside their activation radius. It tries `fireproximityprompt` if the executor supports that function, then falls back to `InputHoldBegin/InputHoldEnd` for normal prompts.
- When a visibly named fragment puzzle GUI opens, the assistant only clicks a button if the puzzle exposes a **single, unambiguous explicit answer** (such as `IsCorrect=true` on a button or `CorrectAnswer`/`Solution` on a parent GUI). Clicking is throttled and debounced by puzzle stage so it does not repeatedly guess.
- If the puzzle is driven by private script state, graphics, or an unexposed sequence, it will show **"Puzzle visible: no explicit answer"** rather than blindly clicking random buttons. Therefore the full Glitch Fragment puzzle is **not confirmed automated** for the current Overhaul build.
- Press **Inspect visible fragment puzzle (F9)** with the puzzle open to print active ScreenGui names, recognized puzzle controls, explicit-answer flags and nearby fragment prompts. If the puzzle uses an unknown ScreenGui/Frame name, enter it in **Puzzle GUI name (optional alias)**. This provides diagnostics for implementing the actual minigame logic later.
- Uses no game remotes or teleporting, ignores unrelated ZincUI controls, does not activate while on an entity team, and unloads cleanly. Auto-interaction and GUI input depend on the executor / game input APIs.
- The `tests/mayhem_fragment_game.lua` mocks proximity range, puzzle explicit-answer cases, repeated clicks, disabling, unknown answers, and entity-only exclusion. **In-game verification remains pending.**

### v0.9 follow-up: prompt positioning and asynchronous paths

- Fragment prompts now use BasePart position, Attachment world position, or a Model's PrimaryPart position. Prompts with missing required positions are skipped. Reach respects configured distances below three studs, including zero; the existing 15-stud cap remains.
- Entity autoplay waits for an asynchronous path computation before issuing movement toward the new route. Failed computations release their allocated Path before using the existing direct fallback. Results arriving after disable are discarded and destroyed.
- Validation: all 20 repository Lua files parsed and all 10 mocked suites passed locally using Lua 5.4 through Lupa. Added regressions cover model/attachment prompts, short/zero ranges, waiting for asynchronous routes, failed-path cleanup and cancellation after disable. These are offline mocks; live Roblox pathfinding, prompt interaction, GUI solving and ESP rendering remain unverified.
