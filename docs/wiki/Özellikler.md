# Özellikler

## Snap

Kısayol veya menü ile pencereyi work area’nın bir bölgesine oturtur.

- Yarılar, çeyrekler, thirds, fourths, sixths  
- Maximize / almost-maximize / maximize height  
- Smaller / Larger / Center / Restore  
- Aynı kısayola tekrar → **size cycle**, sonra diğer monitör  

Tam liste: [Kısayollar](Kısayollar)

## Drag-to-edge

Pencereyi **başlık çubuğundan** kenara sürükleyince dar magnet alanı snap bölgesi gösterir.

- Varsayılan magnet kalınlığı ~**6 px** (ekran görüntüsü / metin seçimini bozmamak için dar)  
- Menü → **Yapışma alanı / Snap zone…** ile 4–24 px arası  
- Menüden tamamen kapatılabilir  

## Ortak kenar sürükleme (split resize)

İki pencere kenar paylaşınca aradaki çizgiyi sürükleyerek birini büyütür, diğerini küçültürsün.

- Yalnızca **paylaşılan dikiş** üzerinde çalışır (her kenarda değil)  
- Window gap açıksa gap mesafesi “yapışık” sayılır  
- Menü → **Kenar sürükle (böl / birleştir)**  

## Tile (tüm pencereler)

| Kısayol | |
| --- | --- |
| `⌃⌥,` | Satır ızgarası |
| `⌃⌥.` | Sütun ızgarası |

Tekrar basınca ızgara düzeni döner. Pin uygulaması ve stash’li pencereler hariç tutulur.

## Cycle stacked

Aynı konumda üst üste binen pencerelerde `⌃⌥]` / `⌃⌥[` ile öne getir.

## Pin Mode

Bir uygulamayı ana ekranın **sağ şeridinde** sabitler; diğer snap’ler kalan work area’ya göre hesaplanır.

1. Hedef uygulamayı öne al  
2. Menü → **Pin app olarak kullan / Use “…“ as Pin App**  
3. **Pin Mode açık / Enable Pin Mode**  
4. Gerekirse **Pin’i yeniden yerleştir / Reflow Pin**  

Şerit genişliği Settings → General’dan (300 / 400 / 500 px).

## Workspaces

- Menü → **Workspaces…** — mevcut çerçeveleri kaydet, adlandır, yükle, sil  
- `⌃⌥P` — son kullanılan workspace  
- Settings’te: **Ekran bağlanınca workspace yükle**  

Stash’li pencereler kayda dahil edilmez.

## Stash

Pencereyi ekran kenarına kaydırır; küçük bir **peek** şeridi kalır.

| Kısayol | |
| --- | --- |
| `⌃⌥`` | Odak penceresini stash / geri al |
| `⌃⌥⇧`` | Tümünü aç |

İmleci peek şeridine getirince pencere geçici açılır; uzaklaşınca tekrar gizlenir (ayarlanabilir).

## Work area, gap, Stage Manager

Geometri şu sırayla hesaplanır:

1. Ekranın `visibleFrame`’i (menü / Dock dışı)  
2. Stage Manager açıksa (ve ayar açıksa) soldan şerit çıkar  
3. Pin açıksa sağdan şerit çıkar  
4. Snap karolarına **window gap / 2** inset uygulanır  

**Maximize** gap’i yok sayar — kenara yapışık dolar.

Gap: menü → **Pencere boşluğu** veya Settings (0 / 4 / 8 / 12 / 16 px).

## Yok sayılan uygulamalar

Menü → **Uygulamayı yok say / Ignore “…”** — o uygulama snap / tile / Layouts aday listesine girmez.
