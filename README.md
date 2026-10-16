# ShortLibrary

A different front end for your Shortcuts library. ShortLibrary reads the shortcuts you already
have, shows them as the same colored tiles Shortcuts draws, and lets you organize them the way
Shortcuts can't: nested folders, nested tags, favorites, smart lists, and sorting by name, date
added, last modified, last run or Shortcuts' own order. Run any shortcut from the grid. Your
organization syncs through your own iCloud to iPhone, iPad and Vision Pro.

The Mac is the reference implementation. iPhone, iPad and Vision Pro are sync-and-launch
clients of the same CloudKit store.

## What it does

- **Reads your library, nothing to re-create.** On the Mac, ShortLibrary asks the Shortcuts app
  for every shortcut (name, identifier, folder, color, icon, action count) through Shortcuts'
  scripting interface. All 2,500 shortcuts of a big library load in under a second.
- **Tiles that match Shortcuts.** Same proportions, gradient, glyph and order as the Shortcuts
  app. App-based shortcuts show their app's icon, exactly as Shortcuts does, once you grant
  access to the Shortcuts folder (File › Link Shortcuts Database for App Icons…).
- **Organize without touching Shortcuts.** Folders nest as deep as you like. Tags nest too, and
  a parent tag shows everything tagged beneath it. Favorites, notes, and smart lists built from
  rules (name, folder, tag, color, action count, dates, run count…). None of it changes anything
  inside the Shortcuts app.
- **Run from the grid.** Double-click a tile, press ⌘↩, or use the hover play button. On the Mac
  shortcuts run in the background through Shortcuts Events; on iPhone and iPad they run through
  the Shortcuts URL scheme and come back to ShortLibrary when done.
- **Sort and search.** Shortcuts order, name, date added, last modified, last run, action count,
  run count; search across names, tags and notes.
- **Sync.** Folders, tags, favorites, notes and smart lists live in a SwiftData store mirrored to
  your private CloudKit database. Devices see the same organization.

## How the data gets in

| Platform | Library source | Running |
| --- | --- | --- |
| Mac | `Shortcuts Events` scripting (sandboxed, via the `scripting-targets` entitlement), plus Shortcuts' own database for app icons and real dates when you link the folder | `run shortcut id` in the background |
| iPhone, iPad, Vision Pro | The bundled **Sync ShortLibrary** helper shortcut calls the app's intents (`BeginLibrarySyncIntent`, `ImportShortcutIntent` per shortcut, `FinishLibrarySyncIntent`) | `shortcuts://x-callback-url/run-shortcut`, returning through `shortlibrary://` |

iOS has no API to enumerate a user's shortcuts, which is why the helper shortcut exists. Its
source is in `Helper/Sync ShortLibrary.xml`; the signed copy ships in the app bundle and can be
installed from the app (File › Install Helper Shortcut… on the Mac, the Sync screen on iOS).

## Project notes

- Xcode 27 project for macOS, iOS, iPadOS and visionOS 26/27, SwiftUI and SwiftData, approachable
  concurrency with MainActor default isolation. Sources live in `ShortLibrary/` as a synchronized
  folder: `Models/` (SwiftData models, smart-list rules, sort), `Services/` (sync controller,
  importer, runner, icon processing, Shortcuts database reader), `Platform/` (Shortcuts Events
  bridge, App Intents, app-icon provider), `Views/`.
- CloudKit container `iCloud.fm.beard.ShortLibrary`. Every model property has a default and every
  relationship is optional, as CloudKit mirroring requires. Deploy the schema to Production in
  CloudKit Console before shipping a build that users will run.
- Sandbox notes that cost real time: `com.apple.security.automation.apple-events` alone gives
  error -600 from Shortcuts Events; the `com.apple.security.scripting-targets` entitlement with the
  `com.apple.shortcuts.run` and `com.apple.shortcuts.organize` access groups is what works. Under it,
  `folder id X` and folder references are rejected (-10004); index access and `shortcut id` work.
- Icons: Shortcuts hands back a finished 512 px tile per shortcut. `IconProcessing` extracts the
  white glyph as a mask and samples the gradient so tiles can be redrawn at any size. The Shortcuts
  database (`~/Library/Shortcuts/Shortcuts.sqlite`, read-only through a user-granted folder
  bookmark) supplies each shortcut's associated app, which `AppIconProvider` turns into the
  installed app's icon, App Store artwork, or a drawn stand-in for iOS-only Apple apps.
- Debug builds answer `shortlibrary://diagnostics?name=<shortcut>` (copies the record to the
  clipboard) and `shortlibrary://inspector?show=0|1`.
- App icon: `Design/Icons/A2-shelf-upright.svg` is the source; the asset set is rendered from it.

## Building and releasing

Open `ShortLibrary.xcodeproj` and run the ShortLibrary scheme. The first launch asks for
permission to control Shortcuts Events.

`Tools/release.sh --notarize --upload` archives the Mac app, exports it with Developer ID,
notarizes and staples it, packages `dist/ShortLibrary <version>.dmg`, and copies the DMG into the
beardfm.app site. The site is deployed separately.

## License

MIT. See `LICENSE`.
