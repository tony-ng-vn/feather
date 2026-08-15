# Feather v2 -- editor, gallery, and page view design spec

Date: 2026-08-15
Status: proposed, ready to execute
Supersedes the editing and note-management parts of `2026-07-09-tony-note-design.md`.
The shell (menu bar item, floating panel, hotkey, theme) from that spec stays as-is.

## 1. Goal

Turn Feather from "a text box in a lovely floating window" into a frictionless note tool.
Three things must be true when this spec is done:

1. Typing feels like Bear or iA Writer: lists, indentation, checkboxes, headings, bold and italic just work from the keyboard, with markdown as the storage format.
2. Every note is findable and readable: a gallery shows all notes as paper cards, and opening one gives a big page view where the whole note can be read comfortably.
3. Nothing is ever lost: undo works, saves are debounced and atomic, deletes go to trash, and notes are plain files on disk.

Non-goals for this spec: sync, rich-text storage, tables, images, collaboration, iOS.

## 2. Product model

One store, three surfaces.

| Surface | Window | Purpose |
|---|---|---|
| Quick card | existing `FloatingPanel` | capture, always on top, small |
| Gallery | normal `NSWindow` | browse, search, open, trash |
| Page | one normal `NSWindow` per note | read and write a whole note comfortably |

A note has a `kind`:

- `quick`: created from the card, shown in the card's tab strip.
- `note`: promoted; lives in the gallery and opens as a page.

Promotion happens when the user opens a quick note from the gallery, presses `Cmd-Shift-K` ("Keep as note") on the card, or moves it from the gallery.
Promotion is one-way by default; "Send to card" (`Cmd-Shift-K` again on a page) demotes it back to `quick`.
The card's tab strip shows `quick` notes plus any note that is pinned, so the card stays small no matter how big the library grows.

## 3. Editor

### 3.1 Component

Replace SwiftUI `TextEditor` with `MarkdownTextView`, an `NSViewRepresentable` around a TextKit 2 `NSTextView` subclass.
Storage stays a plain `String` in markdown, so `Note.body` and the file format do not change shape.
One editor is used by both the card (compact skin) and the page (page skin); only paddings, max line width, and font sizes differ.

Guard rails:

- Never touch `layoutManager`; that silently downgrades to TextKit 1. Assert `textLayoutManager != nil` in debug builds.
- All syntax analysis lives in `FeatherCore/Markup.swift`, pure and unit tested. AppKit code only applies attributes and handles keys.
- Styling is incremental: on `NSTextStorageDelegate.processEditing`, restyle only the edited paragraphs plus their neighbors, and full-restyle only on load.

### 3.2 Block syntax and behavior

Recognized at line start (leading whitespace allowed for lists):

| Typed | Meaning | Rendered as |
|---|---|---|
| `# ` | title (H1) | 26 pt New York semibold, extra space below |
| `## ` | header 1 (H2) | 21 pt New York semibold |
| `### ` | header 2 (H3) | 17 pt New York semibold |
| `- `, `* `, `+ ` | bullet | round bullet glyph, hanging indent |
| `1. ` | ordered | number, hanging indent, renumbered automatically |
| `- [ ] `, `[] ` | checkbox | clickable box, hanging indent |
| `- [x] ` | done checkbox | filled box, text dimmed and struck through |
| `> ` | quote | left hairline bar, muted ink |
| ```` ``` ```` | code fence | monospace block on subtle background |
| `---` | rule | thin hairline |

The first non-empty line remains the note title in tabs and gallery, whether or not it has `#`.
Marker characters are hidden while the caret is not on that line and shown muted when it is (Bear / Obsidian Live Preview style).
Hidden markers still exist in the text; copy and export always produce the plain markdown.

Return:

- Continues the current list type with the same depth. Ordered lists get the next number.
- On an empty nested item: outdent one level.
- On an empty top-level item: remove the marker, plain paragraph.
- On a plain line indented with tabs or spaces: keep that indentation.
- `Shift-Return`: soft line break, no new marker.
- Inside a code fence: plain newline, keep leading whitespace.
- After typing ```` ``` ```` on its own line: insert the closing fence and place the caret between.

Tab / Shift-Tab (and `Cmd-]` / `Cmd-[`):

- On a list line: indent or outdent one level; ordered siblings renumber.
- With a multi-line selection: apply to every selected line.
- On a plain line: insert or remove one indent unit (4 spaces, stored as spaces).
- Inside a code fence: literal tab.
- Depth is capped at 6.

Hanging indent: `headIndent > firstLineHeadIndent` with a tab stop at `headIndent`, so wrapped lines align with the text, not the marker.
The marker hangs into the left margin so prose and list text share the same left edge (iA style).

Checkboxes:

- The box is a real hit target drawn in place of `- [ ]`; clicking toggles state without moving the caret and registers one undo step.
- `Cmd-Enter` toggles the checkbox on the caret line or on every selected line.
- Done items render dimmed and struck through.
- Optional setting "move completed to bottom" (off by default).

Move and duplicate:

- `Cmd-Option-Up/Down`: move the current line (with its nested children for lists) up or down.
- `Cmd-D`: duplicate the current line or selection.
- `Cmd-Shift-Backspace`: delete the current line or selected lines. (`Cmd-Shift-K` is reserved for "Keep as note", see section 6.)

### 3.3 Inline syntax and behavior

| Typed | Rendered |
|---|---|
| `**bold**` | New York bold |
| `*italic*` or `_italic_` | New York italic |
| `` `code` `` | monospace on subtle pill |
| `~~strike~~` | strikethrough, muted |
| `==mark==` | warm yellow highlight |
| `[text](url)` | accent colored text |
| bare `https://...` | accent colored, opens on Cmd-click |

Rules:

- `Cmd-B`, `Cmd-I`, `Cmd-E` (code), `Cmd-Shift-X` (strike), `Cmd-Shift-H` (highlight) wrap the selection; with no selection they insert the pair and put the caret inside; pressing again with the caret inside an empty pair removes it.
- `Cmd-K`: with a selection, wrap as `[selection](url)` using the clipboard if it holds a URL, otherwise leave the caret in the parentheses; with no selection insert `[](url)`.
- Pasting a URL over a selection produces `[selection](url)`.
- Typing `*`, `_`, `` ` ``, `[`, `(`, `"` while text is selected wraps the selection.
- Auto-pair `()`, `[]`, `""`, and backticks; type-over the closer; Backspace right after an auto-pair removes both. Asterisks and underscores are not auto-paired.
- `Cmd-1`, `Cmd-2`, `Cmd-3`: set the current line to H1, H2, H3; pressing the same again returns it to body. `Cmd-0`: body.
- `Cmd-Shift-7` ordered, `Cmd-Shift-8` bullet, `Cmd-Shift-9` checkbox: convert the current line or selection.
- Smart quotes and dashes follow the system setting, are always off inside code, and default off in Feather.
- Cmd-click opens links; plain click edits.
- Inline markers hide when the caret is off the span, show muted when the caret is inside it.

### 3.4 Typography and layout

- Body: New York 16 pt on the card, 18 pt on the page; line height 1.5; paragraph spacing 0.5 em; list items 0.2 em apart.
- Max text column: 68 characters on the page; on the card it is the width minus margins.
- Code: SF Mono at 0.9 em.
- Colors come from `Theme`; add `accent link`, `highlight`, `codeBackground`, `quoteBar` tokens for light and dark.
- `Cmd-+`, `Cmd--` zoom text 14..24 pt, `Cmd-Shift-0` resets; persisted.

### 3.5 Undo

- One `NSUndoManager` per note, held by the store's per-note editing session, so switching tabs and reopening a page keeps the history.
- Typing groups by run as AppKit does; every programmatic edit (list continue, toggle checkbox, indent, move line, wrap) is registered as its own undo step through `shouldChangeText(in:replacementString:)` plus `didChangeText()`.
- `Cmd-Z` and `Cmd-Shift-Z` work in card and page.
- Undo history is discarded only when the note is deleted.

### 3.6 Copy and paste

- Paste is plain text (already true); `Cmd-Shift-V` pastes as-is including tabs.
- `Cmd-C` with no selection copies the whole note as markdown.
- Drop of text, URL, or `.md`/`.txt` file onto the editor inserts the text or a link.

### 3.7 Problem references (LeetCode)

Typing a reference such as `leetcode 1`, `leetcode #1`, `lc 1`, `lc1`, or `LC-1` (case-insensitive) is detected by the inline scanner as `InlineKind.problemRef(site: .leetcode, number:)`.
The typed text is never rewritten; the file on disk stays exactly what the user typed.

Resolution is deterministic, no AI:

- A bundled `leetcode-problems.json` (snapshot of the public `https://leetcode.com/api/problems/all/` list: number, title, slug, difficulty) ships with the app.
- A `ProblemIndex` in `FeatherCore` loads it and refreshes it in the background at most once a week into `Application Support/Feather/leetcode.json`; the app works offline after first launch.
- Known number: link to `https://leetcode.com/problems/<slug>/`; unknown number: link to `https://leetcode.com/problemset/?search=<number>` so a link is never dead.

Rendering and interaction:

- The reference is styled like a link. If the index knows the problem, a muted suffix with title and difficulty is drawn after it (a rendering attribute only, no inserted characters).
- Cmd-click or `Cmd-Enter` opens the problem page; plain click edits.
- `Cmd-Shift-L` on the caret line rewrites the reference into a real markdown link `[1. Two Sum](https://leetcode.com/problems/two-sum/)` for copying into other tools.

The resolver table is per site so Codeforces or GitHub-issue style references can be added later without touching the scanner.

## 4. Gallery

Window `GalleryWindow`, single instance, standard titled window with a hidden toolbar and the paper background.
Open with `Cmd-Shift-O` from the card, the menu bar item ("Open Gallery"), or a small grid icon in the card's tab strip.

Layout:

- Search field at the top; typing filters cards live by title and body; `Escape` clears, then closes.
- Sections in order: Pinned, Notes, Quick notes, Trash (collapsed by default).
- Cards: 16 pt continuous corners, hairline border, title in New York 15 pt semibold, three preview lines in New York 13 pt with markers stripped, relative date muted, small dot showing quick or note.
- Grid is adaptive, minimum card width 220 pt.
- Hover lifts the card 2 pt with a soft shadow; no motion under Reduce Motion.

Actions:

- Click or `Return` opens the note as a page and promotes a quick note to `note`.
- Arrow keys move focus; `Cmd-1..9` open the nth visible card.
- `Cmd-N` new note (opens a page); `Cmd-Delete` moves to trash; `Cmd-P` pins; drag reorders within Pinned.
- Trash items show a Restore button; "Empty trash" is behind a confirmation; auto-purge after 30 days.
- Right-click menu: Open, Pin, Keep as note or Send to card, Export as Markdown, Move to Trash.

## 5. Page

Window `NoteWindow`, one per open note, kept in a `[UUID: NoteWindow]` map by a `WindowController`.
Default 720 x 900 pt, minimum 520 x 480, frame remembered per note.
Standard window level so it behaves like a document window; the card stays floating above it.

Layout:

- Paper background with a slightly darker cream frame around a page area whose text column is capped at 68 characters, margins growing on wide windows.
- Top margin of 56 pt so the first line reads as a page title.
- Quiet footer: word count and last edited date, muted; hidden in focus mode.
- Top-left "Gallery" back button and top-right pin and overflow menu (Export as Markdown, Send to card, Move to Trash).

Behavior:

- Same `MarkdownTextView` and shortcuts as the card.
- `Cmd-Shift-F`: focus mode, hides chrome and keeps the caret line vertically centered (typewriter). No animation under Reduce Motion.
- Opening from the gallery: 250 ms scale-and-fade from the card to the window using `cubic-bezier(0.22, 1, 0.36, 1)`; skipped under Reduce Motion.
- Closing returns focus to the gallery if it is open.

## 6. Navigation and shortcuts

Global (unchanged): `Ctrl-Option-J` show or hide the card, `Escape` hides it.

Card and page:

| Keys | Action |
|---|---|
| `Cmd-N` | new note |
| `Cmd-W` | close page, or move card note to trash with undo toast |
| `Cmd-P` | quick switcher over all notes (fuzzy title and body), `Return` opens |
| `Cmd-[` / `Cmd-]` | previous or next note in the strip |
| `Cmd-1..9` | in the switcher and gallery only, to avoid clashing with heading keys |
| `Cmd-Shift-O` | open gallery |
| `Cmd-Shift-K` | keep as note or send to card |
| `Cmd-Shift-P` | pin or unpin |
| `Cmd-F` | find in note (`Cmd-Shift-F` is focus mode on the page) |

The tab strip drag-reorders; overflow scrolls as today.

## 7. Storage

Move from one JSON blob to one markdown file per note.

- Folder: `~/Library/Application Support/Feather/notes/`.
- File name: `<uuid>.md`. Contents: the body only, so the file is what the user typed.
- Metadata: `notes/index.json` maps id to `kind`, `pinned`, `order`, `createdAt`, `updatedAt`, `deletedAt`, plus `selectedID`. The index is rebuilt from the folder if missing, using file dates.
- Migration: on first launch, if the legacy `notes.json` exists, import every note, write the files, rename the legacy file to `notes.legacy.json`.
- Saves are debounced 300 ms per note and flushed on hide, on window close, on quit, and on losing app focus. Writes are atomic.
- Snapshots: every 5 minutes, if anything changed, copy changed notes into `snapshots/<yyyy-mm-dd-hhmm>/`; keep 7 days. Gallery overflow menu offers "Restore from snapshot".
- Trash: `deletedAt` set; file stays in place; purge after 30 days.
- Export: single note or all notes as `.md`, plain copy of the file.

## 8. Architecture

FeatherCore (pure, tested):

- `Note`: add `kind`, `pinned`, `deletedAt`, keep `title` derived from the first non-empty line with `#` stripped.
- `Markup`: line classifier (`LineKind`, depth, marker range, checkbox state), inline span scanner (`InlineSpan` with kind and marker ranges), and edit helpers: `continueList`, `indent`, `outdent`, `toggleCheckbox`, `setHeading`, `wrap`, `renumber`, `moveLine`. All operate on `String` plus ranges and return the new string and caret.
- `NoteStore`: notes, selection, create/select/update/delete/restore/pin/promote/demote/reorder, search, and persistence through a `NoteRepository` protocol with `FileRepository` (real) and `MemoryRepository` (tests). Debounce lives in the store; the repository is synchronous.
- `Calc` is out of scope for this spec but the line classifier reserves a `.math` kind so it can slot in later.

Feather (AppKit + SwiftUI):

- `MarkdownTextView`: `NSTextView` subclass plus `NSViewRepresentable`; key handling, attribute application, checkbox hit testing, link clicks, undo registration.
- `EditorStyle`: compact and page skins.
- `NoteCardView`: swaps `TextEditor` for `MarkdownTextView`; filters the strip; adds grid icon.
- `GalleryView`, `GalleryWindow`, `NoteWindow`, `PageView`, `QuickSwitcher`.
- `WindowController`: owns the panel, the gallery, and open pages; routes menu and shortcut actions.
- `AppDelegate`: shrinks to app lifecycle and status item; hands the rest to `WindowController`.

## 9. Accessibility and polish

- Every icon button gets an accessibility label and `.help`.
- Reduce Motion disables the card hover lift, the open animation, and typewriter scrolling animation.
- Reduce Transparency is respected if translucency is ever added; not part of this spec.
- Checkbox and heading state are exposed to VoiceOver through the attributed string.
- Keyboard-only use covers everything: no action is mouse-only.

## 10. Execution plan

Each step is a PR; each PR is several small commits (failing test, implementation, wiring, docs).

1. Storage: `NoteRepository`, file-per-note, migration, debounce, trash, snapshots. Tests for migration and repository.
2. `Markup` core: classifier, inline scanner, edit helpers. Exhaustive unit tests, including empty input, deep nesting, mixed lists, fences, unterminated markers.
3. `MarkdownTextView`: replace `TextEditor`, block styling, Return and Tab logic, hanging indent, per-note undo. Manual end-to-end check in the running app.
4. Inline styling and shortcuts: bold, italic, code, strike, highlight, links, headings, list conversion, auto-pair, wrap-on-type, paste URL over selection.
   4b. Problem references: `ProblemIndex` with bundled snapshot and weekly refresh, `problemRef` scanning, link rendering with title suffix, `Cmd-Shift-L` rewrite.
5. Checkboxes: hit-testable box, `Cmd-Enter`, done styling, sort-completed option.
6. Model and store: `kind`, `pinned`, promote and demote, search, reorder; card strip filtering; quick switcher.
7. Gallery window.
8. Page window, focus mode, open animation, `WindowController` refactor.
9. Polish: zoom, word count, move and duplicate line, drop targets, accessibility pass, README and CHANGELOG.

## 11. Verification

- `swift test` covers all of `FeatherCore` including `Markup` and repository migration.
- Each editor behavior in section 3 gets a checklist entry exercised in the running app before its PR is opened, including: nested list exit, ordered renumber, fence tab, undo across tab switch, checkbox click does not move caret, wrap-on-type with a selection, paste URL over selection.
- Gallery and page: open, promote, pin, trash, restore, search, and keyboard-only navigation, verified by hand in the built app.
- Reduce Motion enabled and disabled during the manual pass.

## 12. Open decisions

- Whether `Cmd-1..9` in the card should switch notes (Antinote, Stickies) or set headings (Bear, iA). This spec chooses headings and moves note jumping to the switcher and gallery.
- Marker visibility: hidden-until-caret is the target; if TextKit 2 makes it costly, ship muted-always-visible (iA style) first and hide markers in a follow-up.
- Inline math and a `/` command picker are attractive follow-ups and are intentionally not in this spec.
