# Building from Source

## Requirements

- Xcode 15+  
- Optional: `brew install xcodegen`  

## Recommended

```bash
git clone https://github.com/omersaitsevimli/PaneKit.git
cd PaneKit
./scripts/build-release.sh
open ~/Applications/PaneKit.app
```

Installs a signed copy to `~/Applications/PaneKit.app` for stable Accessibility TCC.

## Xcode

```bash
xcodegen generate   # if needed
open PaneKit.xcodeproj
```

Prefer the same local signing identity as the release script so TCC does not reset every rebuild.

## Layout

`PaneKit/App`, `Core`, `Models`, `UI`, `Assets.xcassets` — see repo README.

Bundle ID: `com.panekit.PaneKit`.
