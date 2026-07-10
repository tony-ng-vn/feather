# Feather

A floating sticky-note that hovers over any app on macOS. Summon it with a global
hotkey, jot anything, dismiss. Lives in the menu bar, not the Dock.

Warm Apple Books paper (New York serif) for the writing surface; clean Luma-style
neutral chrome (SF Pro, rounded pills) for the tabs and buttons. Native Swift, so it
stays light -- no Electron/Chromium runtime along for the ride.

## Use

- Summon / hide: press **Control-Option-J** anywhere, or click the menu-bar note icon.
  (Not N: Option-N is the US-layout dead key for combining tilde, which can collide
  with accent input methods like Vietnamese IM.)
- Escape hides it too. On summon it grabs focus so you can type immediately.
- Tabs: click a tab to switch notes, `+` makes a new one, trash deletes the current one.
- A tab's label is the note's first line. Everything autosaves.
- Drag the card by its top strip; it remembers where you left it.
- Right-click the menu-bar icon for New Note / Show-Hide / Quit.

Notes are stored locally at `~/Library/Application Support/Feather/notes.json`.
No accounts, no sync, no cloud.

## Build

Needs the Xcode command-line tools (Swift 5.9+).

```sh
./build.sh         # produces Feather.app
open Feather.app   # run it
```

To keep it around and always available:

```sh
cp -r Feather.app /Applications/
```

Then add it to System Settings -> General -> Login Items so it starts with your Mac.
It is locally compiled and unsigned, which is fine for an app you build yourself
(Gatekeeper only quarantines apps downloaded from the internet).

## Develop

```sh
swift test    # NoteStore logic (persistence, tab titles, create/select/delete)
swift build   # debug build at .build/debug/Feather
```

Layout:

- `Sources/FeatherCore` -- `Note` + `NoteStore` (pure, unit-tested logic).
- `Sources/Feather` -- AppKit shell (`AppDelegate`, `FloatingPanel`, `HotKey`) plus
  the SwiftUI card (`NoteCardView`, `Theme`).
- `docs/superpowers/specs/` -- the design spec.
