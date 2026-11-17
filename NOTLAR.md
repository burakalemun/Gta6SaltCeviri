# GTA 6 (PS5) Canlı Türkçe Altyazı — Kurulum ve Kullanım Notları

Bu uygulama **Apple Silicon (M1/M2/M3/M4)** MacBook'lar için sıfır kurulum gerektiren yerel (native) bir macOS uygulamasıdır. DMG'yi açıp **`GTA6 Türkçe Altyazı.app`** ikonunu **`Applications`** klasörüne sürükledikten sonra aşağıdaki adımları sırayla izleyin:

---

## Adım 1 — macOS Ekran Kaydı İzni
Uygulama ilk açıldığında karşınıza **Kurulum Rehberi (Onboarding)** penceresi gelir.
1. **"Sistem Ayarlarını Aç"** butonuna tıklayın (`Sistem Ayarları → Gizlilik ve Güvenlik → Ekran ve Sistem Ses Kaydı`).
2. Listeden **`GTA6 Türkçe Altyazı`** anahtarını **Açık** konuma getirin.
3. macOS *"Çık ve Yeniden Aç"* uyarısı gösterirse onaylayın.

> **Not:** Bu izin verilmezse macOS güvenlik nedeniyle diğer pencereleri gizler ve uygulama sadece boş masaüstü arka planını görür.

---

## Adım 2 — Çeviri Motorunu Seçin
Uygulama okuduğu cümleleri otomatik olarak yerel **SQLite veritabanına (`~/Library/Application Support/GTA6PS5Altyazi/data/cache.db`)** kaydeder; tekrar eden cümleler 0 ms'de gelir. İlk çeviriler için şu iki yoldan birini seçin:
- **Seçenek A — Yerel Yapay Zeka (Ollama, Ücretsiz & İnternetsiz):**
  `Yerel Ollama (M2) & AI` sekmesinden **"⚡ Tek Tıkla Otomatik Kur & Başlat"** butonuna basın. Sistem M2 çip için optimize edilmiş `qwen2.5:3b` modelini otomatik indirip arka planda başlatır.
- **Seçenek B — Bulut API (DeepL Free veya Google Gemini Flash):**
  `Yerel Ollama (M2) & AI` sekmesindeki ilgili kutuya **DeepL API Key** (ayda 500.000 karakter ücretsiz) veya **Gemini API Key** yapıştırıp **"Ayarları Kaydet"** butonuna basın.

---

## Adım 3 — Ev Ağı (PS5 + TV + MacBook Pro) Bağlantısı
MacBook Pro ile TV arasına HDMI kablosu çekmenize gerek yoktur:
1. **PS5** konsolunuz kendi HDMI kablosuyla doğrudan TV'ye bağlı kalsın (4K/HDR görüntü ve 0 ms kol gecikmesi korunur).
2. **`Ev Ağı (PS5 + TV + Mac)`** sekmesinden **"🎮 Tek Tıkla PS Remote Play İndir / Aç"** butonuyla Sony'nin resmi Remote Play uygulamasını açıp ev ağından PS5'e bağlanın.
3. Uygulamamız **"Oto Remote Play Penceresi"** modunda alt %14'lük altyazı şeridini otomatik yakalar.
4. İsterseniz **"Fareyle Bölge Seç (ROI)"** butonuyla ekrandaki herhangi bir İngilizce yazı veya video altyazı bölgesini seçip anında test edebilirsiniz.

---

## Adım 4 — Altyazı Konumu (Pixel Top) ve TV'de Gösterim
- Altyazı varsayılan olarak seçilen bölgenin **üstüne (`Pixel Top`)** yerleşir; okunan İngilizce yazının üstünü kapatmaz.
- **`Görünüm & Kalibrasyon`** sekmesinden konumu değiştirebilir (`Bölgenin Üstü`, `Bölgenin Altı`, `Ekran Alt Orta`, `Fareyle Taşı`) ve X/Y piksel sürgüleriyle milimetrik ayar yapabilirsiniz.
- Ev ağındaki TV tarayıcısı, telefon veya tabletten Dashboard'da yazan **`http://<mac-ip>:8765`** (veya canlı ekran + altyazı için **`/remote`**) adresine girerek altyazıyı kablosuz izleyebilirsiniz.
