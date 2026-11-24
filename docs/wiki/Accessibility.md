# Accessibility

PaneKit uses the macOS **Accessibility** API to move and resize other apps’ windows. Without it, snaps and Layouts do nothing.

## Why

macOS blocks cross-app window control by default. PaneKit is not sandboxed; once trusted under Accessibility it can write window frames via AX.

> The Mac App Store sandbox cannot grant this level of control — PaneKit is distributed via GitHub Releases instead.

## Setup

1. Install to **`~/Applications/PaneKit.app`**  
2. Menu → **Open Accessibility Settings** (or System Settings → Privacy & Security → Accessibility)  
3. Enable **PaneKit**  
4. Remove duplicate / DerivedData / old FreeMagnet rows  
5. Quit and reopen PaneKit  

Menu status should show **Accessibility: OK ✓**.

## TCC tips

- Different **paths** or **signing identities** look like new apps to macOS  
- `./scripts/build-release.sh` installs a stable path + local signing identity so permission survives rebuilds better than Xcode Run from DerivedData  

## Related

- [Getting Started](Getting-Started) · [Troubleshooting](Troubleshooting)
