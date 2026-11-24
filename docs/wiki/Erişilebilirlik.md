# Erişilebilirlik (Accessibility)

PaneKit, diğer uygulamaların pencerelerini taşımak için macOS **Erişilebilirlik API**’sini kullanır. Bu izin olmadan kısayollar/Layouts çalışmaz.

## Neden gerekli?

macOS, uygulamaların birbirinin penceresini boyutlandırmasını varsayılan olarak engeller. PaneKit sandboxed değildir; Accessibility güvenilir süreç listesine eklenince pencere geometrisi yazılabilir.

> Mac App Store sandbox’ı Accessibility ile tam pencere kontrolüne izin vermez — bu yüzden PaneKit App Store’da yayınlanamaz.

## Adım adım

1. PaneKit’i **`~/Applications/PaneKit.app`** olarak kur  
2. Menü → **Erişilebilirlik Ayarlarını Aç**  
   veya: Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik  
3. Listede **PaneKit** satırını aç  
4. Birden fazla PaneKit satırı varsa (DerivedData, eski FreeMagnet, Downloads kopyası) hepsini sil; yalnızca `~/Applications/PaneKit.app` kalsın  
5. PaneKit’i **Quit** edip yeniden aç  

Menü çubuğunda **Accessibility: OK ✓** görünmelidir. **⚠ Required** ise izin yoktur veya yanlış kopyaya verilmiştir.

## TCC / imza notları

- Her **farklı binary yolu** veya **farklı code-sign kimliği** macOS’a “yeni uygulama” gibi görünür → izin yeniden istenir  
- `./scripts/build-release.sh` sabit yola (`~/Applications`) kurar ve **PaneKit Local Signing** / FreeMagnet Local Signing ile imzalar; rebuild’lerde TCC daha az sıfırlanır  
- Xcode’dan doğrudan Run → DerivedData yolu her seferinde değişebilir → izni tekrar açman gerekebilir  

## Sık hatalar

| Belirti | Çözüm |
| --- | --- |
| Kısayol basıyorum, pencere kıpırdamıyor | Accessibility’te doğru yolu aç; uygulamayı yeniden başlat |
| Her rebuild’de izin istiyor | Release script ile `~/Applications` kullan |
| Birden fazla PaneKit satırı | Eski satırları sil; tek kopya bırak |
| Gatekeeper engeli | Sağ tık → Aç; Sistem Ayarları → Gizlilik’den de izin verilebilir |

## İlgili

- [Başlangıç ve Kurulum](Başlangıç-ve-Kurulum)  
- [Sorun Giderme](Sorun-Giderme)  
