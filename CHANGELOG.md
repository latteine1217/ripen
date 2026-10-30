# Changelog

Notable changes to Ripen. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/latteine1217/ripen/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/latteine1217/ripen/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/latteine1217/ripen/releases/tag/v0.1.0
