# WoW Addon DevKit

Everything you need to build, test, and ship WoW addons for the Forever and
Midnight clients — without opening the game.

## The Tools

| Tool | What it does |
|---|---|
| **wow-secret-lint** | Static analysis: which calls go dark under the secret-value API |
| **wow-addon-sim** | Runtime simulation: load any addon headlessly, fire events, catch errors |
| **wow-addon-release** | One command from code to CurseForge: test → bump → zip → tag → release |

## Quick Start

```bash
# Test any addon
node wow-addon-sim/wow-addon-sim.mjs path/to/YourAddon

# Test with a combat scenario
node wow-addon-sim/wow-addon-sim.mjs path/to/YourAddon --scenario combat

# Release (dry run first, always)
node wow-addon-sim/wow-addon-release.mjs path/to/YourAddon --dry
node wow-addon-sim/wow-addon-release.mjs path/to/YourAddon --patch
```

## The Quality Stack

```
Layer 1: Syntax       → luaparse rejects malformed Lua
Layer 2: Static       → wow-secret-lint: secret-value risks, removed APIs, flavour gates
Layer 3: Unit         → fengari harnesses: assertions under a real Lua VM
Layer 4: Simulation   → wow-addon-sim: full lifecycle + scenarios under real API stubs
Layer 5: Integration  → CI cross-checks: sim runs against sibling repos
Layer 6: Distribution → GitHub releases with provenance + CurseForge moderation
```

## Scenarios

wow-addon-sim ships with named event sequences that simulate real gameplay:

- `login` — the standard lifecycle (ADDON_LOADED → PLAYER_LOGIN → PLAYER_ENTERING_WORLD)
- `combat` — enter combat, take damage, power changes
- `arena` — zone change into an arena, combat starts
- `target` — target and mouseover changes
- `zone` — zone transitions
- `group` — party formation and unit updates
- `logout` — the full lifecycle then logout

Chain them: `--scenario combat,arena,logout`

## The Data Advantage

The sim's stub layer is generated from a **first-party capture of the live
Forever client** — 5,997 global functions, 271 C_ namespaces, captured from
build 70245. When your addon calls something, the sim knows whether it actually
exists on the client. Nobody else in the Forever scene has this.

## Addons Built With This Stack

- [WhyHidden](https://github.com/Booyaka101/whyhidden) — explains what the client is hiding
- [ClearCombatText](https://github.com/Booyaka101/clearcombattext) — readable combat text under restrictions
- [wow-secret-lint](https://github.com/Booyaka101/wow-secret-lint) — the linter that started it all

## License

MIT
