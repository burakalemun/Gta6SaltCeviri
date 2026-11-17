import AppKit
import SwiftUI

// MARK: - İlk Kurulum Sihirbazı (Onboarding) & Kullanıcı Notları
struct OnboardingView: View {
    @ObservedObject var state: AppState
    @State private var step: Int = 0

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Üst Başlık
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.luciaPink, .jasonCyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Text("VI")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Hoş Geldiniz — Hızlı Kurulum Rehberi")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("GTA 6 (PS5) Canlı Türkçe Altyazı Sistemini 4 adımda kullanıma hazırlayın")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.68))
                }

                Spacer()

                Text("Adım \(step + 1) / \(totalSteps)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.jasonCyan.opacity(0.18)))
                    .foregroundColor(.jasonCyan)
            }
            .padding(20)
            .background(Color(red: 0.06, green: 0.08, blue: 0.13))

            Divider().overlay(Color.white.opacity(0.08))

            // Adım Göstergesi (Progress Pills)
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { idx in
                    Capsule()
                        .fill(idx <= step ? Color.jasonCyan : Color.white.opacity(0.12))
                        .frame(height: 4)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                step = idx
                            }
                        }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)

            // Adım İçeriği
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case 0:
                        step1PermissionCard
                    case 1:
                        step2TranslatorCard
                    case 2:
                        step3PS5AndROICard
                    default:
                        step4PositionAndTVCard
                    }
                }
                .padding(22)
            }

            Divider().overlay(Color.white.opacity(0.08))

            // Alt Gezinme Çubuğu
            HStack {
                if step > 0 {
                    Button("← Önceki Adım") {
                        withAnimation { step -= 1 }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Rehberi Atla") {
                        state.completeOnboarding()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(white: 0.55))
                }

                Spacer()

                if step < totalSteps - 1 {
                    Button("Sonraki Adım →") {
                        withAnimation { step += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.jasonCyan)
                } else {
                    Button("✅ Kurulumu Tamamla ve Başla") {
                        state.completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.neonEmerald)
                }
            }
            .padding(18)
            .background(Color(red: 0.06, green: 0.08, blue: 0.13))
        }
        .frame(width: 680, height: 500)
        .background(Color.bgDeep)
        .preferredColorScheme(.dark)
    }

    // MARK: - Adım 1: macOS Ekran Kaydı İzni
    private var step1PermissionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(
                icon: "lock.shield.fill",
                color: .orange,
                title: "1. macOS Ekran Kaydı İznini Verin",
                subtitle: "Uygulamanın PS Remote Play veya tarayıcıdaki altyazıları okuyabilmesi için tek seferlik izin gerekir."
            )

            noteBox(items: [
                "Aşağıdaki butona tıklayarak Sistem Ayarları → Gizlilik ve Güvenlik → Ekran ve Sistem Ses Kaydı ekranını açın.",
                "Listede 'GTA6 Türkçe Altyazı' anahtarını açık konuma getirin.",
                "macOS 'Çık ve Yeniden Aç' uyarısı gösterirse onaylayın."
            ])

            HStack(spacing: 12) {
                Button("🔓 Sistem Ayarlarını Aç (Ekran Kaydı)") {
                    state.openScreenRecordingSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                HStack(spacing: 6) {
                    Image(systemName: state.hasScreenRecordingPermission ? "checkmark.circle.fill" : "clock.fill")
                        .foregroundColor(state.hasScreenRecordingPermission ? .neonEmerald : .orange)
                    Text(state.hasScreenRecordingPermission ? "İzin Aktif" : "İzin Bekleniyor")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(state.hasScreenRecordingPermission ? .neonEmerald : .orange)
                }
            }
        }
    }

    // MARK: - Adım 2: Çeviri Motoru (Yerel Ollama veya API)
    private var step2TranslatorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(
                icon: "cpu.fill",
                color: .neonEmerald,
                title: "2. Çeviri Motorunu Seçin (Ücretsiz Yerel veya API)",
                subtitle: "İlk okunan cümleler SQLite önbelleğe kaydedilir; tekrar eden cümleler 0 ms'de çevrilir."
            )

            noteBox(items: [
                "Seçenek A (İnternetsiz & Ücretsiz): 'Yerel Ollama (M2) & AI' sekmesinden 'Tek Tıkla Otomatik Kur & Başlat' butonuna basın; sistem M2 çipe özel qwen2.5:3b modelini kendisi kurar.",
                "Seçenek B (Hızlı Bulut API): DeepL API Free (ayda 500.000 karakter ücretsiz) veya Google Gemini Flash anahtarınızı yapıştırıp kaydedin.",
                "Hiçbir şey girmezseniz bile sistem anahtarsız hızlı çeviri yedeğiyle hemen çalışır."
            ])

            HStack(spacing: 10) {
                Button("⚡ Ollama'yı Şimdi Otomatik Kur") {
                    state.oneClickSetupOllamaAndModel()
                }
                .buttonStyle(.borderedProminent)
                .tint(.neonEmerald)

                Text(state.ollamaOnline ? "✅ Ollama Aktif" : (!state.deeplApiKey.isEmpty ? "✅ DeepL Aktif" : state.ollamaStatusText))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.viceGold)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Adım 3: PS5 + Ev Ağı Bağlantısı & ROI Seçimi
    private var step3PS5AndROICard: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(
                icon: "gamecontroller.fill",
                color: .jasonCyan,
                title: "3. PS5 Ev Ağı Bağlantısı veya Ekran Seçimi",
                subtitle: "MacBook ile TV arasına HDMI kablosu çekmeden her şeyi ev ağı üzerinden bağlayın."
            )

            noteBox(items: [
                "PS5 konsolunuz kendi HDMI kablosuyla doğrudan TV'ye bağlı kalır (4K/HDR ve 0 ms kol gecikmesi korunur).",
                "MacBook Pro üzerinde 'PS Remote Play' uygulamasını açıp ev ağından PS5'e bağlanın ('Oto Remote Play Penceresi' otomatik algılar).",
                "İsterseniz 'Fareyle Bölge Seç (ROI)' butonuyla ekrandaki herhangi bir İngilizce yazı veya video altyazı alanını çerçeve içine alıp anında çevirebilirsiniz."
            ])

            HStack(spacing: 10) {
                Button("🎮 PS Remote Play Başlat / İndir") {
                    state.installOrLaunchPSRemotePlay()
                }
                .buttonStyle(.borderedProminent)
                .tint(.jasonCyan)

                Button("🔍 Ev Ağında PS5 Tara") {
                    state.scanHomeNetworkForPS5AndDevices()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Adım 4: Altyazı Konumu (Pixel Top) & TV Yayını
    private var step4PositionAndTVCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepHeader(
                icon: "tv.fill",
                color: .luciaPink,
                title: "4. Altyazı Konumu ve TV Ekranında Gösterim",
                subtitle: "Türkçe altyazı yakalanan metnin üstünü kapatmaz; yerini dilediğiniz gibi ayarlayabilirsiniz."
            )

            noteBox(items: [
                "Varsayılan mod 'Bölgenin Üstü (Pixel Top)' olarak ayarlıdır; böylece seçtiğiniz İngilizce yazının üstüne binmez.",
                "'Görünüm & Kalibrasyon' sekmesinden X/Y piksel kaydırma sürgülerini kullanabilir veya 'Fareyle Taşı' ile kutuyu istediğiniz yere sürükleyebilirsiniz.",
                "Aynı ağdaki TV tarayıcısı, tablet veya telefondan \(state.tvServerURL) adresini açarak canlı Türkçe altyazıyı TV'de görebilirsiniz."
            ])

            HStack(spacing: 10) {
                Text("Canlı TV Yayın Adresi: \(state.tvServerURL)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.neonEmerald)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.35)))

                Button("Adresi Kopyala") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.tvServerURL, forType: .string)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func stepHeader(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.68))
            }
        }
    }

    private func noteBox(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, text in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(idx + 1).")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.jasonCyan)
                    Text(text)
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
