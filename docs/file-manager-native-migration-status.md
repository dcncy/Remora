# File Manager Native Migration Status

## Goal

Replace the old SwiftUI-based file browser with a Finder-style native macOS file manager window, centered on AppKit controls:

- `NSToolbar`
- `NSPathControl`
- `NSOutlineView`
- `NSTableView`

The end state is a single primary file-manager path opened from terminal sessions as an independent window.

## What Was Wrong Before

The original file manager had several structural issues:

1. The main browsing UI lived inside a large SwiftUI view (`FileManagerPanelView`) with too many responsibilities:
   - left sidebar
   - right file list
   - quick paths
   - search
   - upload/download actions
   - archive actions
   - editor/log windows
   - transfer queue overlay

2. The UI direction changed mid-flight:
   - from embedded panel
   - to standalone window
   - then further toward Finder-style native controls

3. Multiple implementations coexisted:
   - old embedded SwiftUI browser
   - newer standalone SwiftUI browser
   - later AppKit-first browser work

4. Running-state verification was confusing because local debugging often launched:
   - the source-built binary under `.build/.../RemoraApp`
   - while Computer Use or other UI tooling still attached to `/Applications/Remora.app`

## Root Problems Identified During This Work

### 1. Old main-path ambiguity

The old SwiftUI browser remained visible in some flows, making it unclear which path was authoritative.

### 2. File manager startup path was hard to verify

We confirmed that:

- the source-built binary was running
- the installed app bundle was also present
- accessibility tooling did not reliably attach to the debug binary

This meant runtime screenshots could not always be trusted unless the target app instance was explicitly controlled.

### 3. Sidebar tree model was wrong

This is the most important unresolved structural issue.

The current AppKit sidebar is **not a real tree** yet.

What it currently does:

- `Section.quickPaths`
- `Section.folders`
- where `folders` is fed by the **current directory’s direct subdirectories**

That means the sidebar behaves like:

- a flat directory list for the current path
- not a root-anchored expandable tree

This explains the observed problems:

- no real nested expansion
- directory list changes when current path changes
- no stable tree model across navigation

### 4. Selection loop bug

We found and fixed a concrete loop in the AppKit sidebar:

- reload sidebar
- programmatically select root row
- `selectionDidChange`
- navigate to `/`
- reload again

That produced repeated logs and a frozen-feeling UI.

The fix added:

- a programmatic-selection guard
- same-path reselect guards

## Architecture Direction Chosen

The chosen architecture is:

1. Main entry from terminal session remains in SwiftUI session UI
2. File manager opens in an independent window
3. That window is managed through AppKit window infrastructure
4. The browser core is implemented through AppKit-first controllers
5. Existing business logic continues to reuse `FileTransferViewModel`

## Current Main Path

These files are now the primary file manager path:

- `Sources/RemoraApp/FileManagerWorkspaceWindow.swift`
- `Sources/RemoraApp/FileManagerWindowToolbar.swift`
- `Sources/RemoraApp/FileManagerWindowSplitController.swift`

## Completed Work

### Window and entry routing

- Terminal header button opens the file manager workspace window
- File manager window is independently managed
- Main browsing path no longer depends on the old SwiftUI browser

### Native toolbar

Implemented a native window toolbar with:

- back
- forward
- refresh
- path control
- search field

### Native left sidebar

Implemented an AppKit `NSOutlineView`-based left panel with:

- quick paths section
- root entry
- current directory list section

Important note:

This is still **not a true lazy tree**, only a native sidebar shell.

### Native right detail list

Implemented an AppKit `NSTableView`-based detail list with:

- columns
- sorting
- local filtering from toolbar search
- double-click open behavior
- context menu selection behavior

### Action bridges migrated to native detail table

The AppKit detail table now bridges these actions:

- create folder
- create file
- rename
- delete
- copy path
- upload
- properties
- permissions
- text edit
- live log view
- compress
- extract

### Legacy browser removal

The old SwiftUI browser rendering files were removed from the main build path:

- `Sources/RemoraApp/FileManagerPanelView.swift`
- `Sources/RemoraApp/FileManagerPanelComponents.swift`
- `Sources/RemoraApp/FileManagerPanelRemoteView.swift`

Only a small formatting helper remains:

- `Sources/RemoraApp/FileManagerLegacyFormatting.swift`

### Compile verification

`swift build` passed after the convergence work.

## Current Status

### Completed

- standalone file-manager window path
- native toolbar
- native detail table
- native action bridge for high-frequency file operations
- compile-path convergence away from the old SwiftUI browser

### Not fully completed

The remaining major gap is:

#### Left sidebar tree model rewrite

The left sidebar still needs to be rewritten from:

- “current directory’s child folders”

to:

- a real root-anchored lazy directory tree

That rewrite should include:

- a `DirectoryNode` model
- children caching
- expand-on-demand loading
- path-to-node expansion
- stable selection synchronization

## Verified Evidence

### Code-path evidence

- Main path routes to native controllers
- Old SwiftUI browser files are removed from the main path
- Action bridges are connected in `FileManagerWorkspaceWindow.swift`

### Build evidence

- `swift build` succeeds

### Runtime evidence

Partial only.

We confirmed:

- source-built binaries were running
- debug app instances could be launched
- installed app and debug app can coexist

But accessibility-based runtime verification of the debug app window was unreliable, so runtime UI verification is incomplete.

## Commits Produced During This Migration

- `e298d37` Polish file manager sidebar navigation
- `b0a9529` Add tree navigation to file manager
- `cd1a65c` Speed up file manager directory browsing
- `5254890` Inline file manager quick path management
- `649d3cc` Refine file manager sidebar interactions
- `9c0a140` Support drag sorting for quick paths
- `668fce3` Start native file manager browser
- `a94fcc4` Replace SwiftUI file browser with native window browser

## Recommended Next Step

Do **not** continue adding polish on top of the current fake tree.

The next task should be explicitly scoped as:

`Rewrite FileManagerOutlineSidebarController into a real lazy directory tree`

Suggested acceptance criteria for that task:

1. Root is stable and always present
2. Child folders load lazily per expanded node
3. Switching current path does not replace the whole sidebar with a new flat list
4. Already-selected paths do not trigger navigation loops
5. Expand/collapse affordances are present for real branch nodes
6. `swift build` passes

## Summary

This migration is **substantially complete at the architecture level**:

- native window
- native toolbar
- native detail table
- native action bridge
- old main-path SwiftUI browser removed

But the **sidebar tree is not yet a true tree**.

That is the main remaining implementation task.
