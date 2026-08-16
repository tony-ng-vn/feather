# Qnote

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
- The card is for capture. Its tab strip holds quick notes plus anything pinned, so
  it stays small however many notes you keep. A tab's label is the note's first line.
- Text is markdown: `#` headings, `-` bullets, `1.` lists, `- [ ]` checkboxes, quotes,
  code fences, and inline `**bold**` / `*italic*` / `` `code` `` / `==highlight==`.
- The trash button moves the note to trash and offers **Undo** for five seconds.
  Trash is emptied for good after 30 days, or from the gallery.
- **Gallery** (grid icon, `Cmd-Shift-O`, or the menu-bar item): every note as a paper
  card, grouped into Pinned, Notes, Quick notes, and Trash, with live search.
  Opening a quick note from here keeps it as a real note. Right-click a card for
  pin, keep as note / send to card, export as Markdown, and move to trash.
- **Pages**: opening a note gives it its own window with room to read and write.
  It has a pin toggle, an overflow menu, a word count, and `Cmd-Shift-F` focus mode,
  which hides the chrome and keeps the line you are typing centered.
- **Quick switcher** (`Cmd-P`): search every note, arrow keys to move, Return to open.
- Drag the card by its top strip; it remembers where you left it, as pages do.
- Type `leetcode 1`, `lc 1`, or `LC-1` and the reference is styled as a link:
  Cmd-click opens the problem, `Cmd-Shift-L` rewrites it as a real markdown link.
  The problem list ships with the app and refreshes itself weekly.

### Shortcuts

| Keys | Action |
|---|---|
| `Ctrl-Option-J` | show or hide the card |
| `Cmd-N` | new note |
| `Cmd-W` | close a page, or move the card's note to trash |
| `Cmd-P` | quick switcher |
| `Cmd-Option-[` / `Cmd-Option-]` | previous or next note in the strip |
| `Cmd-Shift-O` | open the gallery |
| `Cmd-Shift-K` | keep as note (card) or send to card (page) |
| `Cmd-Shift-P` | pin or unpin |
| `Cmd-Shift-F` | focus mode, on a page |
| `Cmd-1`..`Cmd-9` | pick the nth row in the switcher or gallery |
| `Cmd-Delete` | move to trash, in the gallery |
| `Cmd-Shift-L` | rewrite a LeetCode reference as a markdown link |

Editing keys (`Cmd-B`, `Cmd-I`, `Cmd-K`, `Cmd-]` / `Cmd-[` to indent, `Cmd-Enter` to
tick a checkbox, and the rest) are listed in the design spec, section 3.

Notes are stored locally as one markdown file per note at
`~/Library/Application Support/Qnote/notes/*.md`, with an `index.json` alongside
them for pins, order, and trash. No accounts, no sync, no cloud.
Notes written under the app's former name (Feather) move across automatically on
first launch.

## Build

Needs the Xcode command-line tools (Swift 5.9+).

```sh
./build.sh         # produces Qnote.app
open Qnote.app   # run it
```

To keep it around and always available:

```sh
cp -r Qnote.app /Applications/
```

Then add it to System Settings -> General -> Login Items so it starts with your Mac.
It is locally compiled and unsigned, which is fine for an app you build yourself
(Gatekeeper only quarantines apps downloaded from the internet).

## Develop

```sh
swift test    # NoteStore logic (persistence, tab titles, create/select/delete)
swift build   # debug build at .build/debug/Qnote
```

Layout:

- `Sources/QnoteCore` -- `Note` + `NoteStore` (pure, unit-tested logic).
- `Sources/Qnote` -- AppKit shell (`AppDelegate`, `WindowController`, `FloatingPanel`,
  `GalleryWindow`, `NoteWindow`, `HotKey`) plus the SwiftUI surfaces (`NoteCardView`,
  `GalleryView`, `PageView`, `QuickSwitcher`, the `MarkdownTextView` editor, `Theme`).
- `docs/superpowers/specs/` -- the design spec.

### Changelog categories

`CHANGELOG.md` groups every release by the area a change touched.
Use these names, in this order: **Editor**, **Card**, **Gallery**, **Page**, **Storage**, **App**.

### Regenerating the LeetCode problem snapshot

`Sources/QnoteCore/Resources/leetcode-problems.json` is a compact snapshot of
LeetCode's public problem list, used offline to resolve `leetcode 1` / `lc 1`
style references (see spec section 3.7). To refresh it:

```sh
curl -s https://leetcode.com/api/problems/all/ -o /tmp/lc.json
python3 -c '
import json
d = json.load(open("/tmp/lc.json"))
out = [
    {"n": p["stat"]["frontend_question_id"],
     "t": p["stat"]["question__title"],
     "s": p["stat"]["question__title_slug"],
     "d": p["difficulty"]["level"]}
    for p in d["stat_status_pairs"]
]
out.sort(key=lambda x: x["n"])
json.dump(out, open("Sources/QnoteCore/Resources/leetcode-problems.json", "w"), separators=(",", ":"))
'
rm /tmp/lc.json
```

Do not commit the raw API dump, only the compact snapshot it produces.
