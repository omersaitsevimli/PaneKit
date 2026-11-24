# Başlangıç ve Kurulum

## Gereksinimler

- **macOS 13** (Ventura) veya üzeri  
- Apple Silicon için hazır binary; **Intel Mac** için kaynaktan derleme gerekir  
- Diğer uygulamaların pencerelerini taşımak için **Erişilebilirlik** izni  

## 1) İndirerek kurulum (önerilen — Apple Silicon)

1. [Releases](https://github.com/omersaitsevimli/PaneKit/releases/latest) sayfasını aç  
2. **`PaneKit-2.0.0-macos-arm64.zip`** (veya daha yeni) dosyasını indir  
3. Zip’i aç  
4. `PaneKit.app` dosyasını **`~/Applications/`** klasörüne taşı  
   - `/Applications` da olur; Accessibility / TCC için `~/Applications` daha stabil bir yol  
5. İlk açılışta Finder’da uygulamaya **sağ tık → Aç**  
   - Yerel imza kullanıldığı için Gatekeeper bir kez uyarı gösterebilir  
6. PaneKit menü çubuğunda görünür (Dock’ta yok — `LSUIElement`)  

## 2) Erişilebilirlik izni

PaneKit çalışır ama pencereler hareket etmezse izin eksiktir.

1. **Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik**  
2. Yalnızca **`~/Applications/PaneKit.app`** açık olsun  
3. DerivedData / eski “PaneKit” / “FreeMagnet” satırlarını (−) ile sil  
4. PaneKit’i tamamen kapatıp yeniden aç  

Menü çubuğu → PaneKit → **Erişilebilirlik Ayarlarını Aç** doğrudan doğru paneli açar.

Ayrıntı: [Erişilebilirlik](Erişilebilirlik)

## 3) İlk kullanım

| Deneme | Kısayol |
| --- | --- |
| Sol yarı | `⌃⌥←` |
| Sağ yarı | `⌃⌥→` |
| Layouts | `⌃⌥L` |
| Maximize | `⌃⌥↩` |

Menü çubuğundaki ikondan da tüm snap’lere, Layouts’a, Settings’e ulaşabilirsin.

## Kaynaktan kurulum

Geliştirme veya Intel Mac için:

```bash
git clone https://github.com/omersaitsevimli/PaneKit.git
cd PaneKit
./scripts/build-release.sh
open ~/Applications/PaneKit.app
```

Detay: [Kaynaktan Derleme](Kaynaktan-Derleme)

## Güncelleme

1. Yeni release zip’ini indir  
2. Eski `~/Applications/PaneKit.app` üzerine yaz (veya silip kopyala)  
3. Aynı yoldaki Accessibility satırını koru — yol değişmezse izin genelde kalır  

## Sonraki adımlar

- [Kısayollar](Kısayollar)  
- [Layouts](Layouts)  
- [Özellikler](Özellikler)  
- [Ayarlar](Ayarlar)  
