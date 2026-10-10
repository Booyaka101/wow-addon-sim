# Engineering Gap Analysis — WoW DevKit

## What's built and working
- ✅ Static analysis (wow-secret-lint): secret-value risks, removed APIs, flavour gates
- ✅ Unit testing (fengari harnesses): 305+ assertions across all addons
- ✅ Runtime simulation (wow-addon-sim): lifecycle events, API surface stubs
- ✅ Layout validation: structural correctness after events
- ✅ CI/CD: GitHub Actions with cross-repo integration
- ✅ Release pipeline: one command from code to GitHub release

## What needs engineering (the real gaps)

### 1. Event data injection — sim tests structure, not data
Events fire but return nil. ClearCombatText's COMBAT_TEXT_UPDATE handler gets
nil from GetCurrentEventInfo() and renders nothing. The sim proves the code
doesn't crash, but doesn't prove it WORKS. We have real event data from the
Beacon captures — we should replay it.

### 2. Dynamic element capture — visual layer is blind
Font strings created during execution (combat text, tooltip lines) aren't
captured by the layout walker due to closure scoping in the stub CreateFontString.
The visual renderer shows frames but not their content.

### 3. Performance envelope — nothing tests lag
WoW addons run at 60fps with strict memory limits. An addon that creates
unbounded font strings per combat event will lag the game. No tool measures
allocation rates, handler invocation frequency, or memory growth.

### 4. CurseForge API — browser automation for what should be REST
CurseForge has an author API. We're driving a web browser with OCR and
keyboard tricks. The API exists, is documented, and eliminates all of it.

### 5. Addon dependency resolution — no library support
Addons that use Ace3, LibStub, CallbackHandler or other libraries fail in
the sim because those libraries don't exist. No mechanism to load them.

### 6. Golden-file regression — no visual baselines
The visual renderer can screenshot but can't compare against a saved baseline
for automated regression detection.
