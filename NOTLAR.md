# SaltÇeviri — Kurulum ve Kullanım Notları

**SaltÇeviri**, Apple Silicon (**M1/M2/M3/M4**) MacBook'lar için geliştirilmiş, **PS5 (GTA 6)** ve ekrandaki herhangi bir İngilizce içeriği **Apple Vision (Neural Engine)** ile okuyup anlık Türkçeye çeviren yerel macOS uygulamasıdır.

`SaltCeviri-macOS-M2.dmg` dosyasını açıp **`SaltÇeviri.app`** ikonunu **`Applications`** klasörüne sürükledikten sonra aşağıdaki adımları sırayla uygulayın:

---

## Adım 1 — macOS Ekran Kaydı İzni
Uygulama ilk açıldığında karşınıza **Kurulum Rehberi (Onboarding)** penceresi gelir.
1. **"Sistem Ayarlarını Aç"** butonuna tıklayın (`Sistem Ayarları → Gizlilik ve Güvenlik → Ekran ve Sistem Ses Kaydı`).
2. Listeden **`SaltÇeviri`** anahtarını **Açık** konuma getirin.
3. macOS *"Çık ve Yeniden Aç"* uyarısı gösterirse onaylayın.

> **Önemli:** İzin verilmezse macOS güvenlik nedeniyle diğer pencereleri gizler ve uygulama sadece masaüstü arka planını görür.

---

## Adım 2 — Çeviri Motoru ve API Anahtarları (Ücretsiz Seçenekler)
SaltÇeviri okuduğu her cümleyi otomatik olarak yerel **SQLite önbelleğine** kaydeder; tekrar eden replikler **0 ms**'de ve ücretsiz gelir. İlk çeviriler için şu seçeneklerden birini kullanabilirsiniz:

| Seçenek | Kota / Maliyet | Nereden Alınır / Nasıl Kurulur? |
|---|---|---|
| **1. Yerel Ollama (M2 Çip)** | **%100 Ücretsiz & İnternetsiz** | Dashboard'daki **"Yerel Ollama (M2) & AI"** sekmesinden **"⚡ Tek Tıkla Otomatik Kur & Başlat"** butonuna basın (`qwen2.5:3b` modelini otomatik kurar). Manuel indirme: [ollama.com/download](https://ollama.com/download) |
| **2. DeepL API Free** | **Ayda 500.000 Karakter Ücretsiz** | [deepl.com/en/pro-api](https://www.deepl.com/en/pro-api) adresinden ücretsiz hesap açıp `:fx` ile biten API anahtarını kopyalayın ve uygulama içine yapıştırın. |
| **3. Google Gemini Flash** | **Ücretsiz Katman / Çok Düşük Maliyet** | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) adresinden "Create API Key" ile anahtar oluşturup uygulama içine yapıştırın. |

> **Güvenlik Notu:** API anahtarlarınız sadece kendi bilgisayarınızda (`~/Library/Application Support/SaltCeviri/.env` veya yerel `.env`) saklanır, asla GitHub'a veya başka bir sunucuya gönderilmez.

---

## Adım 3 — Ev Ağı (PS5 + TV + MacBook Pro) Bağlantısı
MacBook Pro ile TV arasına HDMI kablosu çekmenize gerek yoktur:
1. **PS5** konsolunuz kendi HDMI kablosuyla doğrudan TV'ye bağlı kalsın (**4K/HDR görüntü ve 0 ms kol gecikmesi** korunur).
2. **`Ev Ağı (PS5 + TV + Mac)`** sekmesinden **"🎮 Tek Tıkla PS Remote Play İndir / Aç"** butonuyla Sony'nin resmi Remote Play uygulamasını açıp ev ağından PS5'e bağlanın.
3. SaltÇeviri **"Oto Remote Play Penceresi"** modunda alt şeridi otomatik yakalar.
4. İsterseniz **"Fareyle Bölge Seç (ROI)"** butonuyla ekrandaki herhangi bir İngilizce yazı veya video altyazı alanını seçip anında test edebilirsiniz.

---

## Adım 4 — Altyazı Konumu (`Pixel Top`) ve TV'de Gösterim
- Altyazı varsayılan olarak seçilen bölgenin **üstüne (`Pixel Top`)** yerleşir; okunan İngilizce yazının üstünü kapatmaz.
- **`Görünüm & Kalibrasyon`** sekmesinden konumu değiştirebilir (`Bölgenin Üstü`, `Bölgenin Altı`, `Ekran Alt Orta`, `Fareyle Taşı`) ve X/Y piksel sürgüleriyle milimetrik ayar yapabilirsiniz.
- Ev ağındaki TV tarayıcısı, telefon veya tabletten Dashboard'da yazan **`http://<mac-ip>:8765`** (veya canlı ekran + altyazı için **`/remote`**) adresine girerek altyazıyı kablosuz izleyebilirsiniz.

---

## Lisans
Bu proje **MIT Lisansı** (`LICENSE`) ile açık kaynaklı olarak sunulmaktadır.
