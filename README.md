<div align="center">

# Ripen

**A frosted-glass Pomodoro timer for macOS that lives where you need it: a window, a floating panel, or your notch.**

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](#install)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/latteine1217)

English · [繁體中文](README.zh-Hant.md)

<img src="docs/images/en/main.jpg" width="420" alt="Ripen main window counting down a focus session">

</div>

Ripen is a native Swift app for the classic focus-and-break rhythm. It stays small, stays on screen without getting in the way, and when a focus session runs long it keeps counting instead of cutting you off.

> Ripen is in active development. The first release will be published on [GitHub Releases](https://github.com/latteine1217/ripen/releases).

## Highlights

### Shrink it to a floating window

Click the yellow button, or drag the timer ring out of the main window, to get a small always-on-top panel. Drag any corner to switch between three layouts; Ripen remembers where you left it.

<p align="center">
  <img src="docs/images/en/floating-small.jpg" width="300" alt="Small floating window">
  <img src="docs/images/en/floating-medium.jpg" width="270" alt="Medium floating window">
  <img src="docs/images/en/floating-large.jpg" width="250" alt="Large floating window">
</p>

### Tuck it into the notch

Click the red button, or drag the main window up into the notch, and Ripen becomes a black island around the camera: progress on the left, time on the right. Hover to see the full controls; pull it down to bring the main window back. On a Mac without a notch, the island sits at the top center of the screen.

<p align="center">
  <img src="docs/images/en/notch.jpg" width="640" alt="Collapsed notch island">
  <img src="docs/images/en/notch-expanded.jpg" width="640" alt="Expanded notch island with controls">
</p>

### Overtime instead of interruption

When the countdown reaches zero, Ripen plays a sound and keeps counting as `+mm:ss` in a new color: teal for focus, orange for breaks. Press **Done** when you are ready, and the focus is recorded with its real length. Time you spend away from your Mac is not counted as overtime.

<p align="center">
  <img src="docs/images/en/overtime.jpg" width="380" alt="Focus session in overtime showing +03:17 and a Done button">
</p>

### See your week

The Statistics page shows today's focus count and minutes, plus a chart of the last seven days. Everything is stored locally on your Mac.

<p align="center">
  <img src="docs/images/en/stats.jpg" width="380" alt="Statistics page with today's totals and a seven-day chart">
</p>

## Features

- **Pomodoro cycle**: 25-minute focus, 5-minute short break, and a 15-minute long break after every 4 focuses. Every length (1–180 minutes) and the long-break interval (1–12) can be changed.
- **Global shortcut**: start or pause from any app with <kbd>⌥</kbd><kbd>⌘</kbd><kbd>P</kbd>, or record your own.
- **Keyboard control** in the main window: <kbd>⌘</kbd><kbd>S</kbd> to skip (or finish during overtime) and <kbd>⌘</kbd><kbd>R</kbd> to reset.
- **Menu bar item** with the remaining time, which can be hidden in Settings.
- **Reminder sound** chosen from the macOS system sounds, or turned off.
- **Optional auto-start** of the next phase, **open at login**, and a 12- or 24-hour clock for end times.
- **Adjustable glass**: change the tint opacity or turn off the background blur.
- **Fresh start after a break**: after two hours idle, the long-break count resets.
- **Private by design**: no account and no network access. Your focus history stays in `~/Library/Application Support/Ripen`.
- Available in **English** and **Traditional Chinese**.

## Install

1. Download `Ripen-<version>.dmg` from [GitHub Releases](https://github.com/latteine1217/ripen/releases). Ripen requires macOS 14 Sonoma or later.
2. Open the dmg and drag **Ripen** onto the **Applications** shortcut.
3. Ripen is ad-hoc signed and not notarized by Apple, so Gatekeeper blocks the first launch:
   - **macOS 14**: in the Applications folder, right-click (or Control-click) Ripen, choose **Open**, then click **Open** in the dialog.
   - **macOS 15 and later**: double-click Ripen so macOS blocks it, then open **System Settings › Privacy & Security**, find Ripen near the bottom, click **Open Anyway**, and confirm.

After that, Ripen opens normally.

## Roadmap

- Light appearance that follows the system setting
- Liquid Glass on macOS 26 and later
- Shortcuts app support

## Support

If Ripen helps you focus, you can support its development on [Ko-fi](https://ko-fi.com/latteine1217). Bug reports and ideas are welcome in [Issues](https://github.com/latteine1217/ripen/issues).

## Development

Building, testing, packaging, and the project layout are covered in [docs/development.md](docs/development.md).

## License

[MIT](LICENSE)
