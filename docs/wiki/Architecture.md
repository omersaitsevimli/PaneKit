# Architecture

Native **Swift + AppKit** menu-bar app (`LSUIElement`).

## Modules

- **App** — lifecycle, Info.plist, entitlements  
- **Core** — `WindowManager`, hotkeys, drag/split, stash, pin, workspaces, `ScreenHelper`  
- **Models** — `SnapAction`, preferences, layout templates  
- **UI** — menu, Layouts panels, Settings  

## Window control

Accessibility AX position/size writes with Cocoa ↔ AX coordinate conversion. Work area = visible frame − Stage Manager − Pin, then per-tile gap.

## Hotkeys

Carbon `RegisterEventHotKey`. Treat unbound shortcuts as `modifiers == 0` only — key code `0` is `kVK_ANSI_A`.

## Input

CGEvent taps (listenOnly) for drag-snap and shared-edge resize; mouse monitors for stash peek.

## Distribution

Unsigned-for-store / locally signed via `scripts/build-release.sh`. Not Mac App Store (sandbox).
