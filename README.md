# QuestPlanner (WoW Forever)

Plan your questing without alt-tabbing. Look up any quest, see who gives it, what to do, where to go and what it rewards, follow the whole chain, and save a quest plan per character.

Built for **WoW Forever 1.60.1** (`## Interface: 16001`). Uses Questie's quest database, so it ships no data of its own and stays small (~2,500 lines of Lua, no libraries).

## Requirements

- **[Questie](https://www.curseforge.com/wow/addons/questie)** (QuestPlanner reads the QuestieDB database that comes with it)
- Optional: **Pawn** (green upgrade arrows on reward items), **TomTom** (waypoint arrow; without it QuestPlanner uses the game's map pin)

## Opening it

`/qp`, the minimap button (right-click opens My Plan), the addon compartment, or Alt-click a quest link in chat.

## Tabs

| Tab | What it shows |
|---|---|
| **Browse** | Search by quest name, quest ID or zone. Filters: level range (defaults to your level -3 / +2), For me (your race and class), Hide done, Gear rewards only, This zone |
| **Near Me** | Quests you can pick up now whose giver is in your zone, nearest first, with distance |
| **My Plan** | Your saved quests in order, with notes. Sort by zone or level, reorder with Up/Down, clear completed, and see the XP left at your level |

List rows show the quest level (coloured by difficulty), status, zone, a star for planned quests and the icon of any gear reward.

## Quest page

Shown on the quest-log parchment, in Blizzard's style:

- **Header**: quest level, required level, zone and status chips (completed, in log, available, level too low, locked with the missing prerequisite, or not for you)
- **Quest giver, Objectives, Turn in**: every NPC, object and item with zone, coordinates and spawn count. Click any row to set a waypoint
- **Objectives**: mob levels and elite rank, item drop sources, and live progress bars while the quest is in your log
- **Rewards**: XP (and what it's worth at your level, as a share of your current level bar), money, reputation, and reward items in Blizzard's reward tiles with quality borders and Pawn arrows
- **Requirements**: faction, class, profession skill, reputation, items, max level
- **Quest chain**: a timeline of every prerequisite and follow-up with its status. Click one to jump to it
- **Buttons**: Add to plan, Plan chain (adds every unfinished prerequisite too), Link, Go to start, Back

## Controls

| Action | Result |
|---|---|
| Click a quest | Show details |
| Right-click | Add to / remove from plan |
| Shift-click | Link in chat |
| Click a location | Set a waypoint |

## Slash commands

| Command | Action |
|---|---|
| `/qp` | Toggle the window |
| `/qp <text>` | Search |
| `/qp <questID>` | Open a quest |
| `/qp plan`, `/qp near` | Open a tab |
| `/qp add <questID>` | Add to plan |
| `/qp minimap` | Show/hide the minimap button |
| `/qp waypoints` | Toggle TomTom arrow vs game map pin |

## Notes

- The first time you open the window each session, a search index builds in the background (a few seconds, with a progress bar).
- Plans are saved per character and backed up account-wide at logout. If WoW Forever fails to load the character file, the plan is restored automatically.
- Item rewards from the database don't say which are choose-one. Exact choices and money show for quests in your log.
- XP at your level uses the Classic reduction table (full XP up to 5 levels above the quest, then 80/60/40/20/10%).

## Development

- `luacheck .` and `lua5.1 tests/run_tests.lua .` (mock WoW API) run on every push.
- Releases: bump `## Version:` in `QuestPlanner.toc` and push to `main`. The Release workflow tags `v<version>`, builds the zip with the BigWigs packager and uploads it to GitHub Releases and CurseForge.

## License

GPL-3.0-or-later. Quest data comes from Questie / QuestieDB (GPL-3.0) at runtime; none is bundled.
