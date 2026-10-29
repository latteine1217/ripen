# Contributing to Ripen

Thanks for your interest in Ripen. Bug reports, ideas and pull requests are all welcome, in English or 繁體中文.

## Reporting bugs and ideas

Open an [issue](https://github.com/latteine1217/ripen/issues/new/choose) and pick a template. For bugs, include your Ripen and macOS versions and the steps to reproduce; a screenshot or a short recording helps a lot.

Security issues should be reported privately; see [SECURITY.md](SECURITY.md).

## Before you write code

For anything larger than a small fix, open an issue first so we can agree on the approach. Ripen keeps a deliberately small feature set, and design decisions are recorded in [docs/adr/](docs/adr/); a change that goes against one of them should start as a discussion.

## Building and testing

You need macOS 14 or later, Xcode with Swift 6, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). `Ripen.xcodeproj` is generated from `project.yml` and is not checked in.

```sh
brew install xcodegen
xcodegen generate
xcodebuild test -project Ripen.xcodeproj -scheme Ripen -destination 'platform=macOS'
```

More on the project layout, frame-by-frame UI checks and packaging is in [docs/development.md](docs/development.md) (Traditional Chinese). Domain terms are defined in [GLOSSARY.md](GLOSSARY.md).

## Pull requests

- Keep each pull request focused on one change, and describe what and why.
- Add or update tests for timer, presentation and storage logic. Visual changes should include before/after screenshots.
- User-facing text goes into `Ripen/Resources/Localizable.xcstrings` with both English and Traditional Chinese.
- CI must pass before a pull request is merged.

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
