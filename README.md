# iWords

iWords is a Swift/AppKit interface to William Whitaker’s WORDS Latin dictionary. This development branch targets **Apple silicon and macOS 14 or later**. The Ada engine and matching generated dictionary files are included; Rosetta and an Ada compiler are not needed to build or run the app.

## Build from a clean checkout

1. Clone this repository and open `iWords.xcodeproj` in Xcode. Use Xcode 16 or later for Swift Testing; this branch was verified in the current Xcode environment with the macOS 27 SDK.
2. Select the **iWords (macOS)** scheme and **My Mac** destination. Allow Swift Package Manager to resolve the checked-in package versions.
3. Build and run with Command-R. Signing defaults to local ad-hoc signing without a developer account. The minimum OS is set centrally in `Config/macOS.xcconfig`.
4. Run the parser and bundled-engine tests with Command-U.

Optional personal signing overrides belong in `Config/Local.xcconfig`, which is ignored by Git. For example, set `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY` there. Do not commit certificates or private keys. Local ad-hoc builds are for testing, not distribution.

For a fresh build after switching from an older branch, use Product → Clean Build Folder. No sibling DWUtils checkout or global Ada installation is needed. Initial package resolution requires network access.

## Architecture and dependencies

Swift AppKit controllers manage windows, settings and lookup history. `Dictionary` owns a long-running WORDS subprocess and its prompt protocol; `DictionaryParser` converts Pearse-coded output into structured results. An AppKit text view renders results directly as attributed text, with native selection, links, text scaling and printing. The Ada engine remains separate, so its linguistic behavior can be preserved and tested independently of the Swift UI.

| Dependency | Purpose | Version/source |
| --- | --- | --- |
| Sparkle | App updates | 2.10.0, Swift Package Manager |
| swift-collections | History collection support | 1.7.4, Swift Package Manager |
| WORDS | Latin morphology and dictionary | Pinned source, rebuilt ARM64; see [engine documentation](docs/ENGINE.md) |

DWUtils and Flow helpers have been replaced with standard Swift, Foundation and AppKit code. The unused Parsing and Difference dependencies and bundled Lodash were removed. Experimental parser/SwiftUI files are excluded from the shipping target; see [Experiments](Experiments/README.md). The existing AppKit UI remains native Swift code; this is not a wholesale SwiftUI rewrite.

See [build provenance and regression procedure](docs/ENGINE.md) and [release considerations](docs/RELEASING.md). Original project website: [iWords.org](https://iwords.org).
