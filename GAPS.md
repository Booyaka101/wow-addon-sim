# Engineering Gap Analysis — WoW DevKit

## What's built and working
- ✅ Static analysis (wow-secret-lint): secret-value risks, removed APIs, flavour gates,
      tostring marker propagation, pcall taint, WSL023 removed tooltip scripts
- ✅ Unit testing (fengari harnesses): 305+ assertions across all addons
- ✅ Runtime simulation (wow-addon-sim): lifecycle events, API surface stubs
- ✅ Secret-value emulation (2026-10-11): the `secrets` scenario feeds marked payloads
      through COMBAT_TEXT_UPDATE; arithmetic on secrets errors exactly like the live
      client, tostring keeps the marker, tonumber launders, SetText is the display sink.
      Caught two real bugs on day one: the stub font-string SetPoint global-capture bug
      (GAPS item 2 below) and ClearCombatText's nil-mtype `table index is nil`.
- ✅ Layout validation: structural correctness after events, now including pooled
      font strings created at runtime (fixed with the SetPoint scoping bug)
- ✅ CI/CD: GitHub Actions with cross-repo integration
- ✅ Release pipeline: one command from code to GitHub release

## What needs engineering (the real gaps)

### 1. Event data injection — PARTLY CLOSED
The secrets scenario injects marked payloads through C_CombatText, keyed to the live
client's verified semantics. Still open: replaying REAL captured event data from the
ForeverBeacon captures across other event types.

### 2. Dynamic element capture — CLOSED 2026-10-11
Root cause was never the layout walker: the stub CreateFontString built its table with
self-referencing closures inside a `local fs = {...}` initializer, which capture the
GLOBAL fs in Lua. Font strings now construct first and attach methods after, so pooled
strings are tracked and layout-validated.

### 3. Performance envelope — nothing tests lag
WoW addons run at 60fps with strict memory limits. An addon that creates unbounded
font strings per combat event will lag the game. No tool measures allocation rates,
handler invocation frequency, or memory growth.

### 4. CurseForge API — browser automation for what should be REST
CurseForge has an author API. We're driving a web browser with OCR and
keyboard tricks. The API exists, is documented, and eliminates all of it.

### 5. Addon dependency resolution — no library support
Addons that use Ace3, LibStub, CallbackHandler or other libraries fail in
the sim because those libraries don't exist. No mechanism to load them.

### 6. Golden-file regression — no visual baselines
The visual renderer can screenshot but can't compare against a saved baseline
for automated regression detection.
