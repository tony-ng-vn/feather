# TonyNote -- design spec

Date: 2026-07-09

Note: the project was renamed to Qnote shortly after this spec was written.
Left as-written below; treat "TonyNote" as "Qnote" throughout.

## What it is

A macOS menu-bar app (no Dock icon). One floating "paper" card hovers over any app,
even fullscreen ones. Summon it with a global hotkey or the menu-bar icon, type, dismiss.
A small tab strip switches between notes and makes new ones. Everything autosaves locally.

Design references, blended by zone:

- Writing surface = Apple Books: warm cream paper, body text in New York serif,
  generous margins, soft page shadow. Calm and literary.
- Chrome (tab strip, buttons) = event-distributor / Luma: SF Pro, fully-rounded pills,
  hairline borders, near-black accents, gentle `cubic-bezier(0.22, 1, 0.36, 1)` motion.

## Behavior

- Summon / dismiss: global hotkey, default Control-Option-N (changeable is future work;
  v1 ships this default). Toggles the panel. Escape also hides. On summon the panel
  activates and grabs focus so typing lands immediately (Spotlight-style). On hide,
  focus returns to the previous app.
- Notes: click a tab to switch; `+` makes a new note; trash deletes the current one.
  A note's tab label is its first non-empty line, or "New note".
- Saving: autosaves on every edit and on hide to
  `~/Library/Application Support/TonyNote/notes.json` (a `Codable` array). No accounts,
  no sync, no cloud.
- Window: ~360x440, draggable by its background, remembers its position across launches.
  First launch positions top-right, under the menu bar.

## Architecture

Swift Package Manager, two source targets plus tests:

- `TonyNoteCore` (library, pure logic, unit-tested):
  - `Note`: `Codable` struct (`id`, `body`, `createdAt`, `updatedAt`) with a `title`
    computed from the first non-empty line.
  - `NoteStore`: `ObservableObject` owning `[Note]` and the selected id. Create / select /
    delete / update, JSON persistence with an injectable file URL (temp dir in tests).
    Always keeps at least one note so there is always a surface to type on.
- `TonyNote` (executable, AppKit + SwiftUI):
  - `AppDelegate`: sets `.accessory` activation policy (menu-bar only), owns the
    `NSStatusItem`, the panel, the hotkey, and the store.
  - `FloatingPanel`: borderless `NSPanel`, `level = .floating`,
    `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, clear background so
    the rounded SwiftUI card and its native shadow show; `canBecomeKey = true` so the
    user can type.
  - `HotKey`: Carbon `RegisterEventHotKey` (system-wide, no Accessibility permission,
    swallows the keystroke) -- not `NSEvent` global monitors.
  - `NoteCardView` + `Theme`: the SwiftUI card, hosted via `NSHostingView`.
- `build.sh`: assembles a real `TonyNote.app` bundle (Info.plist with `LSUIElement`).
  Locally compiled and unsigned is fine; Gatekeeper only quarantines downloaded apps.

## Why these native choices

- `.accessory` policy -> menu-bar-only, no Dock icon, done in code (no fragile plist reliance).
- `.floating` panel + `.fullScreenAuxiliary` -> hovers even over fullscreen apps.
- Carbon hotkey -> true global summon with no permission prompt; the modern
  `NSEvent.addGlobalMonitorForEvents` would demand Accessibility and could not swallow the key.
- New York ships as the system serif (free Apple Books feel); SF Pro for chrome
  (Geist is not a system font and no font files are bundled).

## MVP scope (deliberately small)

Summon, switch / create / delete notes, type plain text, autosave, dismiss.
Out of scope for v1: markdown, rich text, search, sync, in-app hotkey editor,
per-note colors.

## Verification (honest for a GUI menu-bar app)

- `swift test` -> `NoteStore` logic (title derivation, seed-on-empty, create selects,
  update persists across reload, delete keeps at least one and selects a neighbor).
- `swift build` succeeds; `build.sh` produces `TonyNote.app`.
- An `ImageRenderer` snapshot of the card for the design check (palette, layout, type).
- Launch the app; user presses Control-Option-N over another app to confirm it
  summons, takes focus, and dismisses. No pretend "unit tests pass" for the GUI.
