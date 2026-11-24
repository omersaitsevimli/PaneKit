# Sorun Giderme

## Pencere hiç hareket etmiyor

1. Menüde **Accessibility: OK ✓** mi? Değilse [Erişilebilirlik](Erişilebilirlik)  
2. Doğru kopya: `~/Applications/PaneKit.app`  
3. PaneKit’i Quit → yeniden aç  
4. Hedef uygulama “yok sayılanlar”da mı? Menüden kontrol et  

## Her rebuild’de Accessibility istiyor

DerivedData yolundan çalışıyorsundur. `./scripts/build-release.sh` ile `~/Applications` kullan.

## `⌃⌥A` çalışmıyordu (düzeltildi)

Eski sürümlerde `A` tuşu (key code 0) yanlışlıkla “kısayol kapalı” sayılıyordu. **2.0.0+** / güncel `main` ile düzeldi. Hâlâ oluyorsa release’i yenile.

## Aralık açılıp kapanıyor gibi

- **Pencere boşluğu** ayarı 0 mı? (Menü → Window gap)  
- Aynı kısayola tekrar basınca **size cycle** boyutu değiştirir — bu normal  
- Eski sürümlerde stubborn uygulamalarda −40px nudge flicker vardı; güncel sürümde azaltıldı  

## Gatekeeper / “geliştirici doğrulanamadı”

Finder’da **sağ tık → Aç**. Uygulama yerel imzalıdır; notarize App Store dağıtımı değildir.

## Layouts boş / aday yok

- Accessibility kapalı olabilir  
- Tüm pencereler minimize / yok sayılmış olabilir  
- Başka Space’teki pencereler listelenmeyebilir  

## Stash geri gelmiyor

`⌃⌥`` tekrar veya `⌃⌥⇧`` (tümünü aç). Peek şeridine imleç getir.

## Pin diğer snap’leri bozuyor

Pin Mode açıkken work area daralır — beklenen davranış. Menüden Pin Mode’u kapat.

## İki PaneKit aynı anda

Eski kopyayı Quit et; tek `~/Applications/PaneKit.app` bırak. Accessibility listesini temizle.

## Log / teşhis

```bash
pgrep -lf PaneKit
codesign -dv --verbose=2 ~/Applications/PaneKit.app
```

Menü → Accessibility satırı ve **Yol (kopyala)** ile kurulum yolunu doğrula.
