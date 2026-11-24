# Mimari

PaneKit yerel **Swift + AppKit** menü çubuğu uygulamasıdır (`LSUIElement`). Electron yok.

## Katmanlar

| Klasör | Rol |
| --- | --- |
| `App/` | `AppDelegate`, Info.plist, entitlements |
| `Core/` | Pencere taşıma, hotkey, drag, split resize, stash, pin, workspace, screen helper |
| `Models/` | `SnapAction`, `UserPreferences`, Layout şablonları, hotkey tanımları |
| `UI/` | Menü çubuğu, Layouts panelleri, Settings |

## Pencere kontrolü

- **Accessibility (AX)** ile `kAXPosition` / `kAXSize` yazılır  
- Kordinat dönüşümü: Cocoa (sol-alt) ↔ AX (sol-üst) — `ScreenHelper`  
- Stubborn uygulamalar için yeniden deneme / hafif nudge  

## Hotkey

Carbon `RegisterEventHotKey` — global, uygulamanın odaklanmasına gerek yok.

> Not: `kVK_ANSI_A == 0`. “Kısayol kapalı” kontrolü yalnızca `modifiers == 0` ile yapılmalı; aksi halde `⌃⌥A` kaydolmaz.

## Work area

```
visibleFrame
  − Stage Manager strip (opsiyonel, ana ekran)
  − Pin sidebar (opsiyonel, ana ekran)
→ workArea
→ tile rect (+ window gap/2 inset; maximize hariç)
```

## Event tap’ler

- **DragSnapManager** — kenara sürükleme (listenOnly CGEvent)  
- **SplitResizeManager** — ortak kenar  
- **GreenButtonLayoutsTrigger** — yeşil düğme + Option  
- **StashController** — peek şeridi mouse monitor  

## Tercihler

`UserDefaults` (`com.panekit.PaneKit`): gap, pin, shortcuts, workspaces, ignore list, feature toggles.

## Dağıtım

- Sandbox **kapalı** (AX için zorunlu)  
- GitHub Releases; App Store değil  
- Release script: sabit yol + yerel codesign  
