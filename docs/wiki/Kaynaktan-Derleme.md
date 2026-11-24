# Kaynaktan Derleme

## Gereksinimler

- [Xcode](https://developer.apple.com/xcode/) 15+  
- (İsteğe bağlı) [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`  

## Önerilen: release script

```bash
git clone https://github.com/omersaitsevimli/PaneKit.git
cd PaneKit
./scripts/build-release.sh
open ~/Applications/PaneKit.app
```

Bu script:

1. Release yapılandırmasında derler  
2. `~/Applications/PaneKit.app` altına kurar  
3. Sabit yerel imza kimliği ile codesign eder (TCC için)  

## Xcode

```bash
# proje dosyası yoksa / güncellemek için
xcodegen generate
open PaneKit.xcodeproj
```

Product → Run. Mümkünse aynı local signing identity’yi kullan; aksi halde her DerivedData yolunda Accessibility yeniden istenebilir.

## Proje yapısı

```
PaneKit/
├── PaneKit.xcodeproj
├── project.yml              # XcodeGen
├── scripts/
│   ├── build-release.sh
│   └── ensure-local-signing-identity.sh
├── LICENSE
└── PaneKit/
    ├── App/                 # AppDelegate, Info.plist, entitlements
    ├── Core/                # WindowManager, hotkeys, drag, stash, pin…
    ├── Models/              # SnapAction, preferences, templates
    ├── UI/                  # Menu, Layouts, Settings
    └── Assets.xcassets
```

## Bundle ID

`com.panekit.PaneKit` — Accessibility kaydı bu kimliğe bağlıdır.

## Intel Mac

Release binary şu an **arm64**. Intel için:

```bash
./scripts/build-release.sh
```

kendi mimarinde derler (`ONLY_ACTIVE_ARCH=YES`). Universal binary için `project.yml` / xcodebuild ayarlarını genişletmen gerekir.
