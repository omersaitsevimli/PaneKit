# Getting Started

## Requirements

- **macOS 13** (Ventura) or later  
- Prebuilt binary for **Apple Silicon**; **Intel** Macs: build from source  
- **Accessibility** permission to move other apps’ windows  

## Install from Release (Apple Silicon)

1. Open [Releases](https://github.com/omersaitsevimli/PaneKit/releases/latest)  
2. Download **`PaneKit-*-macos-arm64.zip`**  
3. Unzip and move `PaneKit.app` to **`~/Applications/`**  
4. First launch: right-click → **Open** (local signing; Gatekeeper may warn once)  
5. PaneKit appears in the menu bar only (no Dock icon)  

## Accessibility

1. System Settings → Privacy & Security → Accessibility  
2. Enable **only** `~/Applications/PaneKit.app`  
3. Remove DerivedData / old PaneKit entries  
4. Quit and reopen PaneKit  

Menu → **Open Accessibility Settings** jumps to the right pane.

More: [Accessibility](Accessibility)

## First try

| Action | Shortcut |
| --- | --- |
| Left half | `⌃⌥←` |
| Right half | `⌃⌥→` |
| Layouts | `⌃⌥L` |
| Maximize | `⌃⌥↩` |

## Build from source

```bash
git clone https://github.com/omersaitsevimli/PaneKit.git
cd PaneKit
./scripts/build-release.sh
open ~/Applications/PaneKit.app
```

See [Building from Source](Building-from-Source).

## Next

- [Shortcuts](Shortcuts) · [Layouts (EN)](Layouts-EN) · [Features](Features) · [Settings](Settings) · [Troubleshooting](Troubleshooting)
