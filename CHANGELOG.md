# Changelog

Notable changes to Ripen. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Statistics switches between the last 7 and 30 days. Total time, focus count and each project's time follow the range; projects are listed from most to least time with a rounded bar, and 30 days shows one square per day, darker on busier days.
- After your first completed focus, a one-time hint under the timer ring says it can be dragged out into a floating window.

### Changed

- Overtime no longer shares a hue with any project color: focus overtime is magenta and break overtime is a mustard yellow-green, replacing teal and orange.
- The main window's cycle dots mark the focus in progress with a ring, matching the "Focus · n/N" caption on the floating window and notch island.
- When the floating window is the only one on screen, its close button shows that it tucks Ripen into the notch, and its tooltip says the timer keeps running. The button that expands it into the main window now uses the same icon as the notch island's.
- Reset and Skip in the main window are plain icons beside the filled Start/Pause button, so the main action stands out; during overtime, Pause sits beside Done the same way.
- A project's "Today" line shows hours and minutes like its total, and today's label in the 7-day chart is bold.

## [0.2.2] - 2026-11-02

### Added

- Settings › Data: back up focus history and projects to a single file, restore from a backup, and export completed focuses as CSV for spreadsheets.
- Restoring merges by identifier: it only adds focuses and projects that are missing, shows a preview first, and keeps a copy of current data before writing. Unreadable, damaged, non-Ripen and newer-version files are rejected without changing anything.

## [0.2.1] - 2026-11-01

### Added

- Resume a closed or interrupted timer: reopening offers Continue or Discard with the last saved phase, progress and project. Time while Ripen is closed is excluded. Running timers save every five seconds and at key actions; interrupted progress is limited to the last successful save.

### Changed

- Quitting pauses the current phase instead of cancelling it or marking overtime Done. Previously pressed Done actions are still saved when quitting.
- Completed focuses are journaled with timer progress during the undo window, so reopening after interruption records each saved completion once without extending undo.

## [0.2.0] - 2026-10-30

Projects, per-project statistics and shareable recap cards.

### Added

- Projects: pick or add a project above the timer ring, each with a color from a preset palette; change it mid-focus to move the whole focus.
- Per-project statistics: a seven-day chart stacked by project color, project totals, and a detail page with every completed focus.
- A recap card per project in square or portrait layout; save it as PNG, copy the image, or share it through the macOS share menu.
- After **Done**, a short completion summary and a shortcut to the project's recap card in the main window, floating window and notch island.
- A capsule control to switch between the timer and statistics pages.
- Delete a project from its detail page; its focuses move to Uncategorized after you confirm.

### Changed

- The floating window and notch island are created when shown and released when hidden, and timers that are idle, paused or hidden no longer redraw on a schedule.
- Text and icons in phase, project and brand colors stay readable on every appearance: brighter on dark glass, darker on light backgrounds. Windows no longer fall back to the system accent color.

### Fixed

- **Skip** in the main window finishes the phase when the countdown has just passed zero, instead of doing nothing.

## [0.1.0] - 2026-10-29

The first release of Ripen, a native macOS Pomodoro timer in frosted glass.

### Added

- Focus, short break and long break with adjustable lengths; overtime keeps counting after zero until you press **Done**.
- Main window, an always-on-top floating window in three layouts, and a notch island.
- Black, White or Glass appearance.
- Undo skip, reset or Done for 5 seconds.
- A short gesture intro on first launch.
- Statistics for today and the last 7 days, stored only on your Mac.
- **Check for Updates…**, which only goes online when you ask.

[Unreleased]: https://github.com/latteine1217/ripen/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/latteine1217/ripen/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/latteine1217/ripen/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/latteine1217/ripen/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/latteine1217/ripen/releases/tag/v0.1.0
