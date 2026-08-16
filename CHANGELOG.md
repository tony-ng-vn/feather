# Changelog

## v2.1.0

2026-08-16

**App**

- The app is now called Qnote. The menu-bar item, the built app, and the bundle identifier all use the new name.
- Notes written under the old name are moved across automatically on first launch, from `Application Support/Feather` to `Application Support/Qnote`. If both folders somehow exist, the new one is used and the old one is left untouched so nothing can be lost.

---

## v2.0.0

2026-08-15

**Editor**

- Notes are written in markdown with live styling: headings, bullets, numbered lists, checkboxes, quotes, code fences, and inline bold, italic, code, strikethrough, and highlight.
- Return continues the list you are in, Tab indents it, and Cmd-Enter ticks a checkbox; every one of these is a single undo step.
- Each note keeps its own undo history, so switching tabs or opening it as a page never loses it.
- References like `leetcode 1`, `lc 1`, or `LC-1` are styled as links, name the problem on hover, open it on Cmd-click, and turn into a real markdown link with Cmd-Shift-L.

**Card**

- The tab strip now holds quick notes plus anything pinned, so the card stays small however many notes you keep.
- A grid button in the strip opens the gallery.
- The trash button moves a note to the trash and offers Undo for five seconds instead of deleting it outright.
- Cmd-Shift-K keeps the current note for the gallery, Cmd-Shift-P pins it, and Cmd-Option-[ / Cmd-Option-] step through the strip.

**Gallery**

- A new window shows every note as a paper card, grouped into Pinned, Notes, Quick notes, and Trash, with search that filters as you type.
- Open a card by clicking it, pressing Return, or pressing Cmd-1 to Cmd-9; opening a quick note keeps it as a real note.
- Right-click a card to pin it, keep it as a note or send it back to the card, export it as Markdown, or move it to the trash.
- Trashed notes can be restored one by one, deleted for good, or cleared together with Empty Trash.

**Page**

- Any note can open in its own window with larger type, a comfortable text column, and its own remembered size and position.
- A quiet footer shows the word count and when the note was last edited, above it a pin toggle and a menu for export, send to card, and trash.
- Cmd-Shift-F turns on focus mode, which hides the chrome and keeps the line you are typing in the middle of the window.
- Opening a note from the gallery grows its card into the window, unless Reduce Motion is on.

**Storage**

- Notes are now one markdown file per note in `~/Library/Application Support/Qnote/notes/`, so what is on disk is exactly what you typed; an existing `notes.json` is imported once.
- Saves are coalesced while you type and written out when the card hides, a window closes, the app loses focus, or you quit.
- Deleting is reversible: trashed notes stay on disk and are cleared for good after 30 days.

**App**

- The menu-bar menu gained Open Gallery and New Note.
- Cmd-P opens a quick switcher that searches every note, with arrow keys, Return, and Cmd-1 to Cmd-9 to open one.
- Reduce Motion is respected everywhere motion was added.
- The app bundle now carries the LeetCode snapshot, so references resolve offline from the first launch.

---
