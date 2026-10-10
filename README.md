# wow-addon-sim

Run a WoW addon headlessly and catch Lua errors without the game client.

Point it at any addon folder. It reads the TOC, loads every Lua file under a
real Lua VM (fengari) with a WoW API stub layer generated from actual client
captures, fires the lifecycle events (ADDON_LOADED, PLAYER_LOGIN,
PLAYER_ENTERING_WORLD), and reports every error. Syntax errors, nil references,
missing API calls — found at the terminal, not mid-raid.

## Usage

```bash
node wow-addon-sim.mjs <addon-dir>
```

Optional flags:
- `--surface <file.json>` — use a specific API surface (defaults to the bundled Forever capture)
- `--events PLAYER_REGEN_ENABLED,UNIT_HEALTH,...` — fire additional events after the standard lifecycle

## What it catches

- **Syntax errors** — the Lua parser rejects malformed code before it loads
- **Load-time errors** — nil globals, bad arguments during initialization
- **Event-time errors** — errors that only surface when the game fires an event
- **Missing API calls** — the stub layer is generated from a real client capture; calls to things not in the surface log visibly
- **Stub coverage gaps** — if the addon calls a frame method the stub doesn't implement, that's also an error (and a to-do for the stub layer)

## What it does NOT catch

- Visual bugs (positions, colors, animations)
- Logic errors that don't throw (wrong math, bad conditions)
- Timing-dependent bugs (race conditions, event ordering)
- Anything that depends on real game data (actual unit names, real spell IDs)

## The surface data

The default surface is a first-party capture of the WoW Forever beta client
(build 70245, interface 16001): 5,997 global functions, 271 C_ namespaces.
Every one of those gets a stub that logs when called and returns nil. Anything
your addon calls that isn't in that surface is either a beta-version difference
or a bug — both worth knowing about.

Swap in a retail capture for retail-specific testing:
```bash
node wow-addon-sim.mjs MyAddon --surface retail-surface.json
```

## License

MIT
