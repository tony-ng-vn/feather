# TonyNote

A floating sticky-note that hovers over any app on macOS. Summon it with a global
hotkey, jot anything, dismiss. Lives in the menu bar, not the Dock.

Warm Apple Books paper (New York serif) for the writing surface; clean Luma-style
neutral chrome (SF Pro, rounded pills) for the tabs and buttons.

## Use

- Summon / hide: press **Control-Option-N** anywhere, or click the menu-bar note icon.
- Escape hides it too. On summon it grabs focus so you can type immediately.
- Tabs: click a tab to switch notes, `+` makes a new one, trash deletes the current one.
- A tab's label is the note's first line. Everything autosaves.
- Drag the card by its top strip; it remembers where you left it.
- Right-click the menu-bar icon for New Note / Show-Hide / Quit.

Notes are stored locally at `~/Library/Application Support/TonyNote/notes.json`.
No accounts, no sync, no cloud.

## Build

Needs the Xcode command-line tools (Swift 5.9+).

```sh
./build.sh          # produces TonyNote.app
open TonyNote.app   # run it
```

To keep it around and always available:

```sh
cp -r TonyNote.app /Applications/
```

Then add it to System Settings -> General -> Login Items so it starts with your Mac.
It is locally compiled and unsigned, which is fine for an app you build yourself
(Gatekeeper only quarantines apps downloaded from the internet).

## Develop

```sh
swift test    # NoteStore logic (persistence, tab titles, create/select/delete)
swift build   # debug build at .build/debug/TonyNote
```

Layout:

- `Sources/TonyNoteCore` -- `Note` + `NoteStore` (pure, unit-tested logic).
- `Sources/TonyNote` -- AppKit shell (`AppDelegate`, `FloatingPanel`, `HotKey`) plus
  the SwiftUI card (`NoteCardView`, `Theme`).
- `docs/superpowers/specs/` -- the design spec.
