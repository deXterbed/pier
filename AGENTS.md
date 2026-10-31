# AGENTS.md

Canary: begin your first response with "Pier: SwiftUI/AppKit dock app, done means ./build.sh."

Pier is a free, native macOS replacement for the system Dock: as many docks as you like, each
pinned to a display, each with its own items, position and look. This clone is a fork that a real
person runs as their daily driver, so a behaviour regression is noticed within minutes.

## Build and run

```bash
./install.sh   # build, reinstall into /Applications, relaunch (clears the stale TCC entry first)
./build.sh     # build only: release build, assembles Pier.app in the repo root, ad-hoc signs
```

- **Done means `./build.sh` succeeds and the installed app runs.** There is no other gate: no CI,
  no linter, no formatter step.
- **`swift test` does not work on this machine.** The test target imports `Testing` (swift-testing),
  which ships with Xcode, not with the Command Line Tools: `error: no such module 'Testing'`.
  `Tests/PierCoreTests` is therefore unrunnable here, not broken — don't rewrite the tests to "fix" it.
- **Every build invalidates the Accessibility grant.** Ad-hoc signing gives the binary a new cdhash,
  so macOS stops matching the TCC entry (`Failed to match existing code requirement ...
  kTCCServiceAccessibility`) and notification badges go blank. `install.sh` runs
  `tccutil reset Accessibility app.openware.pier` before copying, so the new build asks again
  instead of leaving a grant that no longer applies — but the toggle still has to be turned back on
  by hand. Check that first when badges disappear, before reading the badge code.
- **Never run the repo copy and the /Applications copy at once** — two instances, two sets of docks.

## Invariants

- **A hidden dock is a window parked off screen, not an ordered-out one.** Auto-hide moves the panel
  past its edge (`DockPlacement.hiddenFrame`, `peek: 0` deliberately: anything left on screen is a
  visible sliver). The window frame and `isRevealed` must always change together, so `relayout()`
  picks `frame(...)` or `hiddenFrame(...)` from `isRevealed`. Park the window without flipping the
  state and the dock looks open while believing it is hidden, until a pointer move resyncs them.
- **A panel that comes back after being ordered out must come back hidden** when the dock auto-hides
  (`DockWindowController.relayout`), or every display change pops it open.
- **Hit-testing uses `model.items`; persistence uses `dock.items`.** `model.items` is
  `dock.items + runningExtras` (running apps that aren't pinned). Index math that reads
  `model.items[index]` but looks up `dock.items[index]` targets the wrong item — that is how
  right-clicking a running extra used to lose its menu entirely.
- **Hiding is pointer-driven only.** `PointerWatcher` reads global mouse events (no permission
  needed) and nothing polls the cursor, so a revealed dock stays revealed until the pointer moves.
- **The transparent bleed around the card is not hit-testable** (26pt at default settings); clicks
  there pass through to whatever is underneath. Only the card receives events, which is why the
  dock's own actions live in a `Dock ▸` submenu on tile menus: a content-sized dock has almost no
  background to right-click.
- **Per-dock settings live on the `Dock`** (`appearance`, `behavior`, `placement`); app-wide settings
  live on `Preferences`. A `Preferences` write must go through `write(_:_:)` or it never posts
  `.pierPreferencesChanged` and nothing repaints.
- **`screen(for:)` returning nil is the "no screen" path, and it hides the panel.** Both an
  unplugged display and the optional single-display stand-down (`onlyWithMultipleDisplays`) use it.
  Reuse that path instead of special-casing visibility.
- **Display changes arrive as notifications, not polling:**
  `NSApplication.didChangeScreenParametersNotification` → `DockManager.rebuild()` → `relayout()`.
- **App identity is `bundleIdentifier ?? Bundle(path:)?.bundleIdentifier`.** Items built from a path
  (mirroring the system Dock, dragging an app in, a hand-edited config) carry no bundle identifier,
  so matching on that alone double-counts them.
- **Badges exist only in the real Dock's `AXStatusLabel`,** read via Accessibility and polled every
  2s because macOS announces no badge change. Empty when untrusted. One character (`•`, `3`) draws
  as a circle, anything longer as a capsule, sized by `Preferences.badgeSize`.

## Where the code is

`Sources/PierCore` is model and geometry with no window code: `Dock`, `DockItem`, `DockPlacement`
(all edge and hidden-frame math), `DockLayout`, `ScreenIdentity`, `Preferences`.
`Sources/Pier` is the app: `Dock/DockManager` owns controllers and the pointer watcher,
`Dock/DockWindowController` owns one panel and its menus, `Dock/DockPanel` is the non-activating
panel (`canBecomeKey` false), `Dock/DockTileView` draws a tile.
Language mode is Swift 5 (`.swiftLanguageMode(.v5)`) but the UI types are `@MainActor`.

State: docks in `~/Library/Application Support/Pier/docks.json`, preferences in the
`app.openware.pier` defaults domain. The bundle is `LSUIElement`, so there is no Dock icon — reach
settings and quit through the menu bar item.

## Working in this fork

- `origin` is `deXterbed/pier` (this fork); `upstream` is `openwarehq/pier`. Day-to-day work lands
  on `main` in the fork.
- **Do not open upstream PRs or push feature branches to `upstream` unless asked.** When asked,
  one branch per feature off `main`.
- Commit messages are single-line, sentence case, describing what changed, with no `feat:`/`fix:`
  prefix — match `git log`.
- Do not commit, and do not add co-author trailers, unless asked.
