# SaltÇeviri — GTA 6 (PS5) Canlı Türkçe Altyazı Sistemi (macOS Apple Silicon)

> **⬇️ TEK TIKLA İNDİR (macOS M1/M2/M3/M4):**
> **[SaltCeviri-macOS-M2.dmg İndir (Doğrudan Kurulum Paketi)](https://github.com/burakalemun/Gta6SaltCeviri/raw/main/dist/SaltCeviri-macOS-M2.dmg)** · [Tüm Sürümler (Releases)](https://github.com/burakalemun/Gta6SaltCeviri/releases) · [Kurulum & API Rehberi (NOTLAR.md)](NOTLAR.md)

**Kurulum:** Yukarıdaki `.dmg` dosyasını indirip açın, **`SaltÇeviri.app`** ikonunu **`Applications`** klasörüne sürükleyin ve açın. İlk açılışta **Kurulum Rehberi (Onboarding)** sizi 4 adımda yönlendirecektir.

**Lisans:** MIT License ([LICENSE](LICENSE)) · **Yöntem:** PS Remote Play (Ev Ağı) + Apple Vision OCR + Yerel Ollama / DeepL / Gemini + Tıklama Geçirgen Katman
**Temel Kısıtlar:**
- Harici capture card veya ek fiziksel donanım kullanılmayacak
- Konsol modlanmayacak (jailbreak yok, PSN ban riski sıfır)
- Altyazı doğrudan TV / Mac ekranında görünecek

---

## 1. Proje Tanımı ve Amacı

PlayStation 5 üzerinde resmi Türkçe dil desteği bulunmayan **Grand Theft Auto VI (GTA 6)** oyununun İngilizce altyazılarını, harici bir yakalama kartı (capture card) veya konsol modifikasyonu olmadan **gerçek zamanlı olarak Türkçeye çevirip TV ekranında göstermek.**

### Nasıl Çalışır?
PS5'in TV'ye giden HDMI sinyaline doğrudan müdahale etmek fiziksel bir cihaz olmadan imkansızdır. Bu projede görüntü, Sony'nin resmi **PS Remote Play** (veya açık kaynaklı `chiaki-ng`) yazılımı ile ev ağı üzerinden bilgisayara aktarılır. Bilgisayarda çalışan Python tabanlı yazılımımız:
1. Remote Play penceresinin sadece altyazı bölgesini (ROI) saniyede 8–10 kez yakalar.
2. Görüntüde yeni bir altyazı belirdiğini algılar ve **OCR** ile İngilizce metni okur.
3. Metni, oyun argosuna ve karakter bağlamına uygun şekilde **DeepL / Gemini Flash API** ile Türkçeye çevirir (veya daha önce çevrildiyse yerel SQLite önbellekten anında çeker).
4. Orijinal İngilizce altyazının tam üzerine oturan şeffaf/opak bir **ekran üstü katman (overlay)** ile Türkçe altyazıyı yazar.
5. Bilgisayar ekranı **AirPlay 2 / Miracast** (veya B planı olarak HDMI) ile TV'ye yansıtılır.

### Temel Hedef Ölçütler
| Ölçüt | Hedef Değer |
|---|---|
| Altyazı çeviri gecikmesi | ~0,6 – 1,5 saniye (replik ekrana geldikten sonra) |
| Oyun kontrol gecikmesi | ~120 – 250 ms (kablosuz yansıtma) / ~50 – 100 ms (HDMI ile) |
| Ek donanım | Yok (sadece PS5 için Ethernet kablosu önerilir) |
| Ban / Güvenlik riski | Yok (tamamen resmi Remote Play akışı üzerinden okuma) |

---

## 2. Proje Dizin Yapısı

Proje bu klasör (`gta6-ps5-altyazi`) içerisine aşağıdaki mimariyle kurulacaktır:

```
gta6-ps5-altyazi/
├── README.md                 # Proje tanımı, teknoloji yığını ve kurulum rehberi
├── requirements.txt          # Python bağımlılıkları
├── .env.example              # API anahtarları şablonu (DEEPL_API_KEY, GEMINI_API_KEY)
├── config.json               # ROI koordinatları, kısayollar ve görünüm ayarları
├── run.sh                    # Tek komutla kurulum ve başlatma betiği
├── build_dmg.sh              # macOS .app ve .dmg kurulum imajı üretici betik
├── dist/
│   ├── GTA6 Türkçe Altyazı.app          # Çift tıklanabilir macOS uygulaması
│   └── GTA6-PS5-Altyazi-macOS-M2.dmg    # Sürükle-bırak macOS kurulum imajı
├── data/
│   ├── glossary.json         # GTA 6 özel isimler ve argo sözlüğü
│   └── cache.db              # SQLite çeviri önbelleği (çalışırken oluşur)
└── src/
    ├── __init__.py
    ├── main.py               # Uygulama başlatıcı ve ana döngü
    ├── dashboard.py          # Görsel Kontrol Merkezi (API anahtarları, canlı log, görünüm ayarları)
    ├── capture.py            # Pencere yakalama ve ROI kırpma (macOS Quartz / ScreenCaptureKit)
    ├── ocr.py                # Metin okuma ve pHash değişim algılama (Apple Vision — M2 Neural Engine)
    ├── stabilizer.py         # Levenshtein metin sabitleme ve konuşmacı ayrıştırma
    ├── translator.py         # SQLite önbellek + DeepL Free + Gemini Flash çeviri motoru
    └── overlay.py            # PyQt6 tıklama geçirgen ekran üstü altyazı katmanı ve ROI seçici
```

---

## 3. Sistem Mimarisi ve Veri Akışı (Ev Ağı: PS5 + TV + M2 MacBook Pro)

MacBook Pro ile TV arasına HDMI kablosu çekmeye gerek kalmadan her şey **Ev Ağı (Wi-Fi / LAN)** üzerinden yürür:

```
[PS5 Konsol] ══════(Konsolun Kendi HDMI Kablosu: 4K / HDR / 0 ms Gecikme)══════► [Akıllı TV Ekranı]
     │                                                                                  ▲
     │ 1. Ev Ağı (Remote Play Akışı)                                                    │ 8. Ev Ağı Wi-Fi (:8765)
     ▼                                                                                  │    Türkçe Altyazı Katmanı
[M2 MacBook Pro — Native Swift Stüdyosu (GTA6 Türkçe Altyazı.app)] ─────────────────────┘
     ├──► 2. Pencere Yakalama (CoreGraphics / Quartz — Alt %20 ROI)
     ├──► 3. Değişiklik Algılama (64-bit dHash fark kontrolü)
     ├──► 4. OCR ile Metin Okuma (Apple Vision — M2 16 Çekirdekli Neural Engine)
     ├──► 5. Metin Sabitleme & Konuşmacı Ayrıştırma (Levenshtein + LUCIA/JASON rozeti)
     ├──► 6. Çeviri Motoru (SQLite Önbellek ➔ Gemini Flash / DeepL Free / Ollama)
     └──► 7. Çift Çıktı: Yerel Ağ TV Sunucusu + Mac Ekran Üstü Katman
```

### Ev Ağı Üzerinden TV'de Gösterim Seçenekleri
1. **Mimari 1 — Doğrudan Ev Ağı TV Katmanı (Önerilen):** PS5 kendi HDMI kablosuyla doğrudan TV'ye bağlıdır (4K/HDR ve sıfır kol gecikmesi). M2 MacBook Pro ev ağından Remote Play ile altyazıyı okur ve çevrilen Türkçe metni `http://<macbook-ip>:8765` (`/api/subtitle`) üzerinden kablosuz olarak TV'ye (Android TV ADB katmanı, LG webOS, Samsung Tizen veya TV Multi-View tarayıcısına) basar.
2. **Mimari 2 — Kablosuz AirPlay 2 Ekran Yansıtma:** MacBook Pro üzerindeki Remote Play + Türkçe Altyazı katmanı **AirPlay 2** ile kablosuz olarak TV'ye yansıtılır.
3. **Mimari 3 — İkinci Ekran (Companion Screen):** TV'nin yanı sıra telefon, iPad veya ikinci bir ekran üzerinden `http://<macbook-ip>:8765` adresine girilerek canlı Türkçe altyazı takip edilir.

---

## 4. Teknoloji Yığını (M2 MacBook Pro / macOS)

| Katman | Kullanılacak Teknoloji | M2 MacBook Pro Avantajı & Açıklama |
|---|---|---|
| **Programlama Dili** | Python 3.12+ (ARM64 Native) | Apple Silicon yerel (native) çalışma ile maksimum hız ve düşük pil tüketimi |
| **Görüntü Akışı** | PS Remote Play / `chiaki-ng` | PS5 görüntüsünü yerel ağdan Mac'e taşır (M2 donanımsal H.265/HEVC çözücü kullanır) |
| **Pencere Yakalama** | `Quartz` / `ScreenCaptureKit` (`pyobjc`) | Sadece hedef pencereyi çok düşük CPU/GPU yüküyle (8–10 fps) yakalar |
| **Görüntü Ön İşleme** | OpenCV / Pillow + `imagehash` | ROI kırpma, kontrast artırma ve kare değişim algılama (pHash) |
| **OCR (Metin Okuma)** | **Apple Vision** (`VNRecognizeTextRequest`) | M2'nin **16 çekirdekli Neural Engine** birimini kullanır; harici model indirmeden **20–60 ms** içinde okur |
| **Metin Sabitleme** | `rapidfuzz` (Levenshtein) | Yarım çıkan cümleleri ve OCR titremelerini filtreler |
| **Çeviri Motoru (Ana)** | **Gemini Flash API** + **DeepL API Free** | İlk 500B karakterde DeepL ücretsiz, sonrasında veya argo yoğun sahnelerde Gemini |
| **Çeviri Motoru (Yerel)**| Ollama / Apple MLX (opsiyonel) | M2 birleşik bellek (Unified Memory) sayesinde internetsiz yerel LLM çalıştırabilme |
| **Önbellek (Cache)** | SQLite3 | Çevrilen her cümleyi kaydeder; tekrar eden NPC repliklerinde 0 ms ve 0 maliyet |
| **Arayüz & Overlay** | **PyQt6** (`NSWindow` / Cocoa uyumlu) | Tam ekran üstünde duran, tıklamaları alta geçiren (`Qt.WindowTransparentForInput`) altyazı kutusu |
| **TV Aktarımı** | AirPlay 2 / HDMI | Birleşik görüntüyü TV'ye taşır |

---

## 5. Çeviri Kalitesi ve Oyun İçi Uyarlama Özellikleri

Sıradan bir makine çevirisi GTA'nın sokak dilini, esprilerini ve küfürlerini bozar. Yazılımda şu mekanizmalar yer alır:
- **Kayan Bağlam Penceresi (Context Window):** Son 5–10 replik hafızada tutulur ve yeni replik çevrilirken modele bağlam olarak verilir. Böylece "you" zamirinin "sen/siz" ayrımı ve diyalog bütünlüğü korunur.
- **Sabit Terimler Sözlüğü (Glossary):** Karakter, mekan ve özel isimler çevrilmez (`Lucia`, `Jason`, `Vice City`, `Leonida`, `VCPD` vb.).
- **Konuşmacı Ayrıştırma:** `LUCIA: Let's go.` formatındaki metinlerde konuşmacı adı ayrılır, çevrilmez ve ekranda farklı renkle gösterilir.
- **Sistem Talimatı (Prompt):** *"GTA 6 diyaloglarını Türkçeye çeviriyorsun. Sokak ağzını, argoyu ve küfürleri yumuşatmadan, doğal ve akıcı bir Türkçe kullan. Altyazı okunabilirliği için cümleleri kısa tut (en fazla 2 satır, satır başına ~42 karakter)."*

---

## 6. Gecikme Bütçesi

Bir altyazı ekranda belirdikten sonra Türkçesinin TV'de görünmesine kadar geçen süre:

| Aşama | Süre |
|---|---|
| Remote Play ağ akışı | 50 – 100 ms |
| Kare yakalama aralığı (10 fps) | 0 – 100 ms |
| Metin sabitleme (2 ardışık kare doğrulaması) | 100 – 200 ms |
| OCR (Apple Vision — M2 Neural Engine) | 20 – 60 ms |
| Çeviri API (önbellekte yoksa) | 200 – 700 ms |
| Overlay çizimi | < 16 ms |
| TV kablosuz yansıtma gecikmesi (AirPlay 2) | 100 – 200 ms |
| **Toplam Altyazı Gecikmesi** | **~0,5 – 1,3 saniye** |

> Diyaloglar ekranda ortalama 2–5 saniye kaldığı için ~1 saniyelik gecikme okuma deneyimini bozmaz. Önbellekte olan repliklerde çeviri süresi **0 ms**'dir.

---

## 7. Maliyet Tablosu ve Ürün/Servis Bağlantıları

### 7.1 Donanım (Sadece Eksikse)
| Ürün | Gereklilik | Yaklaşık Fiyat | Bağlantılar |
|---|---|---|---|
| **Cat6 Ethernet Kablosu** (PS5 → Modem) | **Şiddetle önerilir** (Wi-Fi bozulması OCR'ı bozar) | ~150 – 450 ₺ | [Hepsiburada](https://www.hepsiburada.com/ara?q=cat6+ethernet+kablo) · [Trendyol](https://www.trendyol.com/sr?q=cat6%20ethernet%20kablo) · [Amazon TR](https://www.amazon.com.tr/s?k=cat6+ethernet+kablosu) |
| **HDMI 2.1 Kablosu** (MacBook → TV) | Opsiyonel (AirPlay yerine kablo istenirse; 14"/16" M2 Pro/Max doğrudan HDMI portuna sahiptir) | ~200 – 600 ₺ | [Hepsiburada](https://www.hepsiburada.com/ara?q=hdmi+2.1+kablo) · [Amazon TR](https://www.amazon.com.tr/s?k=hdmi+2.1+kablo) |
| **USB-C → HDMI Adaptörü** | Opsiyonel (Sadece 13" M2 MacBook Pro modelinde HDMI ile bağlanmak istenirse gerekir) | ~250 – 700 ₺ | [Hepsiburada](https://www.hepsiburada.com/ara?q=usb+c+hdmi+adapt%C3%B6r) · [Amazon TR](https://www.amazon.com.tr/s?k=usb+c+hdmi+adapt%C3%B6r) |

### 7.2 Yazılımlar (Tamamı Ücretsiz — macOS / Apple Silicon)
- **PS Remote Play (macOS):** [remoteplay.dl.playstation.net](https://remoteplay.dl.playstation.net/remoteplay/lang/tr/index.html)
- **chiaki-ng (macOS ARM64 Alternatif İstemci):** [github.com/streetpea/chiaki-ng](https://github.com/streetpea/chiaki-ng)
- **Python 3.12+ (macOS ARM64):** [python.org/downloads/macos](https://www.python.org/downloads/macos/) (veya Homebrew: `brew install python@3.12`)
- **PyObjC (Apple Vision & Quartz):** `pyobjc-framework-Vision`, `pyobjc-framework-Quartz` (macOS yerleşik OCR ve ekran yakalama köprüsü)
- **PyQt6:** [pypi.org/project/PyQt6](https://pypi.org/project/PyQt6/)
- **Ollama (Yerel LLM için opsiyonel):** [ollama.com](https://ollama.com)

### 7.3 Çeviri API Servisleri ve Oynanış Maliyeti
*(Varsayım: Saatte ~600 altyazı satırı ≈ 36.000 karakter)*

| Servis | Ücretsiz Kota | Ücretli Tarife | 60 Saatlik Ana Hikâye Maliyeti | API Anahtarı Alma |
|---|---|---|---|---|
| **DeepL API Free** | **Ayda 500.000 karakter** (~14 saat oynanış) | Pro: ~\$25/ay sabit + \$25/1M karakter | İlk ~14 saat **\$0** | [deepl.com/pro-api](https://www.deepl.com/pro-api) |
| **Gemini Flash API** | AI Studio'da hız limitli ücretsiz katman | **2026:** \$0,75 girdi / \$3,75 çıktı (1M token)<br>**2027:** \$1,50 girdi / \$7,50 çıktı (1M token) | ~\$9 – 18 (2026 tarifesi)<br>~\$18 – 36 (2027 tarifesi) | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) |
| **Google Cloud Translation** | **Ayda 500.000 karakter** (~14 saat oynanış) | \$20 / 1M karakter | İlk ~14 saat **\$0** | [cloud.google.com/translate](https://cloud.google.com/translate/pricing) |

> **Hibrit Maliyet Stratejisi:** Sistem önce SQLite önbelleğe bakar, yoksa DeepL/Google ücretsiz kotasını kullanır, kota dolduğunda veya argo yoğun sahnelerde Gemini Flash'a geçer. Böylece 60 saatlik tam oyun maliyeti **\$0 ile \$14** arasında tutulur.

---

## 8. PS5 ve Oyun İçi Kritik Ayarlar

OCR'ın %99 doğrulukla çalışması için kurulumda şu ayarlar yapılmalıdır:

### PS5 Ayarları
1. **Ayarlar → Sistem → Uzaktan Oynatma → Uzaktan Oynatmayı Etkinleştir:** Açık.
2. **Ayarlar → Sistem → Güç Tasarrufu → Dinlenme Modunda Kullanılabilen Özellikler:** "İnternete Bağlı Kal" ve "PS5'i Ağ Üzerinden Açmayı Etkinleştir" açık.
3. **Ağ Bağlantısı:** PS5 modeme **Ethernet kablosu** ile bağlanmalı, bilgisayar ise 5 GHz Wi-Fi veya Ethernet üzerinde olmalı.

### Oyun İçi Ayarlar (GTA 6 / Test için GTA V & RDR2)
1. **Altyazılar (Subtitles):** Açık (İngilizce).
2. **Altyazı Boyutu:** En Büyük (Largest).
3. **Altyazı Arka Planı (Subtitle Background):** Opak / Siyah kutu açık (hem OCR'ın arka plan gürültüsünden etkilenmesini önler hem de bizim Türkçe katmanın orijinal yazıyı temizce kapatmasını sağlar).
4. **Konuşmacı İsmi:** Açık.

---

## 9. Hızlı Başlangıç (M2 MacBook Pro Kurulum ve Çalıştırma)

### 9.1 Tek Komutla Kurulum ve Sistem Testi
Proje klasöründeki [run.sh](file:///Users/burakkaya/Desktop/gta6-ps5-altyazi/run.sh) betiği Apple Silicon (`arm64`) sanal ortamını (`.venv`) otomatik kurar, gerekli paketleri yükler ve sistemi başlatır:

```zsh
cd /Users/burakkaya/Desktop/gta6-ps5-altyazi

# 1. M2 Neural Engine (Apple Vision OCR) + Çeviri boru hattını uçtan uca test et:
./run.sh --self-test

# 2. PS5 bağlı olmadan örnek GTA 6 (Lucia & Jason) altyazılarıyla ekran üstü katmanı (overlay) dene:
./run.sh --demo

# 3. Canlı PS Remote Play altyazı çeviri sistemini başlat:
./run.sh
```

### 9.2 API Anahtarlarını Tanımlama
İlk çalıştırmada `.env.example` dosyasından otomatik olarak `.env` oluşturulur. Gerçek zamanlı yapay zeka çevirisi için `.env` dosyasına anahtarlarınızı ekleyin:
- `GEMINI_API_KEY`: [Google AI Studio](https://aistudio.google.com/apikey) üzerinden alınan anahtar (`gemini-2.5-flash` modeli oyun argosu ve bağlam penceresi için önerilir).
- `DEEPL_API_KEY`: [DeepL Pro/Free API](https://www.deepl.com/pro-api) anahtarı (Ayda 500.000 karakter ücretsiz).

### 9.3 macOS Ekran Kaydı İzni (Önemli)
macOS'in `PS Remote Play` penceresini okuyabilmesi için ilk çalıştırmada **Sistem Ayarları → Gizlilik ve Güvenlik → Ekran ve Sistem Ses Kaydı** bölümünden kullandığınız Terminal (veya IDE) uygulamasına izin vermeniz gerekir.

---

## 10. Uygulama Yol Haritası

- **Faz 0 — Altyapı ve Yansıtma Testi (1 Akşam):**
  PS5 Ethernet bağlantısı, MacBook Pro'da Remote Play kurulumu (1080p/60fps), Mac ekranını TV'ye AirPlay 2 (veya HDMI) ile yansıtıp kontrol gecikmesini test etme.
- **Faz 1 — Çekirdek Prototip (Tamamlandı ✅):**
  macOS ARM64 Python ortamının kurulması, Remote Play penceresinden `Quartz` ile ROI yakalama, `Apple Vision` (M2 Neural Engine) ile İngilizce metni okuma, API ile çevirme ve PyQt6 şeffaf katmanında ekrana basma.
- **Faz 2 — Kalite ve Optimizasyon (Tamamlandı ✅):**
  pHash değişim filtresi, Levenshtein metin sabitleme, SQLite önbellek, son 8 repliği tutan bağlam penceresi ve GTA 6 terimler sözlüğü.
- **Faz 3 — Kullanım Konforu (Tamamlandı ✅):**
  Fareyle kolay altyazı bölgesi seçimi (`ROISelectorWindow`), kontrol paneli (`ControlPanelWindow`), kendi altyazı katmanını ekran yakalamadan hariç tutma (`kCGWindowListOptionOnScreenBelowWindow`) ve tek tıkla başlatma betiği (`run.sh`).
