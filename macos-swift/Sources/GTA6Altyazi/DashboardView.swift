import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var state: AppState
    @State private var selectedTab: Int = 0
    @State private var showSavedBanner: Bool = false
    @State private var copiedURLToast: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // SOL KENAR ÇUBUĞU (Premium Sidebar)
            sidebarView
                .frame(width: 242)

            Divider()
                .overlay(Color.white.opacity(0.08))

            // SAĞ ANA İÇERİK ALANI
            VStack(spacing: 14) {
                // 1) Üst Ev Ağı Topolojisi (PS5 ⇄ Ev Ağı ⇄ M2 Mac ⇄ Akıllı TV)
                topNetworkTopologyBanner

                // 2) 4'lü Canlı Telemetri Kartları
                telemetryGrid

                // 2.2) macOS Ekran Kaydı İzni Uyarısı (İzin Kapalıysa veya Güncelleme Sonrası Yenilenmesi Gerekiyorsa)
                if !state.hasScreenRecordingPermission {
                    screenRecordingPermissionBanner
                }

                // 2.5) Sadece Ollama seçiliyse ve henüz kurulu/açık değilse Tek Tıkla Otomatik Kurulum Çubuğu göster
                if state.translationProvider == "ollama" && !state.ollamaOnline {
                    oneClickOllamaBanner
                }

                // 3) Seçili Sekme İçeriği
                Group {
                    switch selectedTab {
                    case 0:
                        liveStageAndDialogueTab
                    case 1:
                        homeNetworkHubTab
                    case 2:
                        ollamaAndAISettingsTab
                    default:
                        appearanceSettingsTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)
            .background(
                ZStack {
                    Color.bgDeep
                    RadialGradient(
                        colors: [Color.luciaPink.opacity(0.07), Color.clear],
                        center: .topTrailing,
                        startRadius: 20,
                        endRadius: 500
                    )
                    RadialGradient(
                        colors: [Color.jasonCyan.opacity(0.06), Color.clear],
                        center: .bottomLeading,
                        startRadius: 20,
                        endRadius: 460
                    )
                }
            )
        }
        .frame(minWidth: 1000, minHeight: 660)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $state.showOnboarding) {
            OnboardingView(state: state)
        }
    }

    // MARK: - Sol Kenar Çubuğu (Premium Sidebar)
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Marka Başlığı
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.luciaPink, .jasonCyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                    Text("VI")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SALTÇEVİRİ")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("M2 VISION • CANLI ALTYAZI")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.jasonCyan)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)

            // Ana Başlat / Duraklat Butonu
            Button(action: { state.togglePause() }) {
                HStack(spacing: 8) {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(state.isPaused ? "Canlı Çeviriyi Başlat" : "Yakalamayı Duraklat")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Circle()
                        .fill(state.isPaused ? Color.orange : Color.neonEmerald)
                        .frame(width: 8, height: 8)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: state.isPaused
                                    ? [Color.orange.opacity(0.28), Color.orange.opacity(0.14)]
                                    : [Color.luciaPink.opacity(0.85), Color(red: 0.72, green: 0.12, blue: 0.48)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)

            // Menü Sekmeleri
            VStack(spacing: 5) {
                sidebarNavItem(
                    index: 0,
                    title: "Canlı Diyalog Akışı",
                    subtitle: "Kompakt önizleme ve kayıtlar",
                    icon: "captions.bubble.fill"
                )
                sidebarNavItem(
                    index: 1,
                    title: "Ev Ağı (PS5 + TV + Mac)",
                    subtitle: "Kablosuz TV yayını ve ping",
                    icon: "wifi.router.fill"
                )
                sidebarNavItem(
                    index: 2,
                    title: "Yerel Ollama (M2) & AI",
                    subtitle: "Local LLM + SQLite önbellek",
                    icon: "cpu.fill"
                )
                sidebarNavItem(
                    index: 3,
                    title: "Görünüm & Kalibrasyon",
                    subtitle: "Kompakt font, opaklık ve ROI",
                    icon: "slider.horizontal.below.rectangle"
                )
            }
            .padding(.horizontal, 12)

            Spacer()

            // Hızlı Kalibrasyon ve Test Kartı
            VStack(alignment: .leading, spacing: 7) {
                Text("HIZLI ARAÇLAR")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.50))

                Button(action: { state.selectROIFromScreen() }) {
                    Label("Fareyle Bölge Seç (ROI)", systemImage: "viewfinder")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)

                Button(action: { state.switchToAutoWindowMode() }) {
                    Label("Oto Remote Play Penceresi", systemImage: "macwindow.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    Button(action: { state.triggerDemoSubtitle() }) {
                        Label("Test Çevir", systemImage: "bolt.horizontal.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.jasonCyan.opacity(0.18)))
                            .foregroundColor(.jasonCyan)
                    }
                    .buttonStyle(.plain)

                    Button(action: { state.hideCurrentSubtitle() }) {
                        Label("Gizle", systemImage: "eye.slash")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
                            .foregroundColor(Color(white: 0.75))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 12)

            Button(action: { state.showOnboarding = true }) {
                HStack {
                    Image(systemName: "book.pages.fill")
                    Text("Kurulum Rehberi & Notlar")
                    Spacer()
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.jasonCyan)
                .padding(.horizontal, 16)
                .padding(.top, 2)
            }
            .buttonStyle(.plain)

            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack {
                    Image(systemName: "power")
                    Text("Uygulamadan Çık")
                    Spacer()
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(red: 1.0, green: 0.50, blue: 0.55))
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .buttonStyle(.plain)
        }
        .background(Color(red: 0.05, green: 0.06, blue: 0.11))
    }

    private func sidebarNavItem(index: Int, title: String, subtitle: String, icon: String) -> some View {
        let isSelected = (selectedTab == index)
        return Button(action: {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                selectedTab = index
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isSelected ? .jasonCyan : Color(white: 0.58))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isSelected ? .white : Color(white: 0.78))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.50))
                }
                Spacer()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.09) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? Color.jasonCyan.opacity(0.45) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var activeEngineBadgeText: String {
        if state.translationProvider == "deepl" && !state.deeplApiKey.isEmpty {
            return "DeepL API Free (Aktif)"
        }
        if state.translationProvider == "gemini" && !state.geminiApiKey.isEmpty {
            return "Gemini Flash (Aktif)"
        }
        if state.ollamaOnline {
            return "Ollama (\(state.ollamaModel))"
        }
        if !state.deeplApiKey.isEmpty {
            return "DeepL API Free (Hazır)"
        }
        return "Hazır (Yedek / Ollama)"
    }

    // MARK: - 1) Üst Ev Ağı Topolojisi Barı (PS5 ⇄ Ev Ağı ⇄ M2 Mac ⇄ Akıllı TV)
    private var topNetworkTopologyBanner: some View {
        HStack(spacing: 12) {
            topologyNode(
                icon: "gamecontroller.fill",
                title: "PS5 Konsol",
                subtitle: "TV'de 4K/HDR",
                accent: .jasonCyan
            )

            topologyArrow(label: "Ev Ağı (Remote Play)")

            topologyNode(
                icon: "laptopcomputer",
                title: "M2 MacBook Pro",
                subtitle: activeEngineBadgeText,
                accent: .luciaPink
            )

            topologyArrow(label: "Ev Ağı Wi-Fi (:8765)")

            topologyNode(
                icon: "tv.fill",
                title: "Akıllı TV Katmanı",
                subtitle: state.tvServerURL,
                accent: .neonEmerald
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.jasonCyan.opacity(0.32), Color.luciaPink.opacity(0.32)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    private func topologyNode(icon: String, title: String, subtitle: String, accent: Color) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.16))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(white: 0.62))
                    .lineLimit(1)
            }
        }
    }

    private func topologyArrow(label: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.52))
            HStack(spacing: 3) {
                Rectangle()
                    .fill(LinearGradient(colors: [.jasonCyan.opacity(0.4), .luciaPink.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1.5)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.luciaPink)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 2) 4'lü Telemetri Kartları
    private var telemetryGrid: some View {
        HStack(spacing: 10) {
            statCard(
                title: "SİSTEM DURUMU",
                value: state.statusText,
                valueColor: state.isPaused ? .orange : .neonEmerald,
                icon: "waveform.path.ecg"
            )
            statCard(
                title: "AKTİF ÇEVİRİ MOTORU",
                value: activeEngineBadgeText,
                valueColor: (!state.deeplApiKey.isEmpty || !state.geminiApiKey.isEmpty || state.ollamaOnline) ? .neonEmerald : .viceGold,
                icon: "cpu"
            )
            statCard(
                title: "SON OCR & ÇEVİRİ HIZI",
                value: state.latencyTelemetry,
                valueColor: .jasonCyan,
                icon: "bolt.fill"
            )
            statCard(
                title: "SQLITE ÖNBELLEK",
                value: "\(state.cacheCount) Kayıtlı Replik",
                valueColor: .viceGold,
                icon: "cylinder.split.1x2.fill"
            )
        }
    }

    private func statCard(title: String, value: String, valueColor: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(valueColor)
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.56))
            }
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - 2.2) macOS Ekran Kaydı İzni Bandı
    private var screenRecordingPermissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("macOS Ekran Kaydı İzni Gerekli (Diğer Pencereleri Okuyabilmek İçin)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Text("İzin kapalıysa macOS sadece boş masaüstü duvar kağıdını verir ve 'Metin Bulunamadı' yazar. Ayarlar'dan 'SaltÇeviri' iznini açın (açıksa kapatıp tekrar açın).")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.78))
            }

            Spacer()

            Button("🔓 Ekran Kaydı İznini Aç") {
                state.openScreenRecordingSettings()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.orange.opacity(0.55), lineWidth: 1)
                )
        )
    }

    // MARK: - 2.5) Tek Tıkla Otomatik Ollama + Model Kurulum Bandı
    private var oneClickOllamaBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.viceGold)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Yerel Yapay Zeka (Ollama) Otomatik Kurulumu")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                    Text(state.ollamaStatusText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.72))
                }

                Spacer()

                Button(action: {
                    state.oneClickSetupOllamaAndModel()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: state.isPullingModel ? "arrow.triangle.2.circlepath" : "bolt.fill")
                        Text(state.isPullingModel ? "Otomatik Kuruluyor..." : "⚡ Tek Tıkla Otomatik Kur & Başlat")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.neonEmerald.opacity(0.85), Color.jasonCyan.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .foregroundColor(.black)
                }
                .buttonStyle(.plain)
                .disabled(state.isPullingModel)
            }

            if state.isPullingModel {
                ProgressView(value: state.ollamaSetupProgress, total: 1.0)
                    .tint(.neonEmerald)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.viceGold.opacity(0.45), lineWidth: 1)
                )
        )
    }

    // MARK: - Sekme 0: İnce/Kompakt Altyazı Şeridi + Canlı Diyalog Akışı
    private var liveStageAndDialogueTab: some View {
        VStack(spacing: 12) {
            // İnce ve az yer kaplayan Canlı Altyazı Önizleme Bandı
            HStack(spacing: 12) {
                Text("AKTİF ALTYAZI:")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.jasonCyan)

                if state.currentTurkishSubtitle.isEmpty {
                    Text("Şu an ekranda altyazı yok (Oyun ekranı temiz)")
                        .font(.system(size: 12).italic())
                        .foregroundColor(Color(white: 0.50))
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if !state.currentSpeaker.isEmpty {
                            Text("\(state.currentSpeaker):")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundColor(Color.speakerColor(for: state.currentSpeaker))
                        }
                        Text(state.currentTurkishSubtitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.black.opacity(state.backgroundOpacity))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                            )
                    )
                }

                Spacer()

                if let previewImg = state.lastCapturedPreview {
                    HStack(spacing: 6) {
                        Text("YAKALANAN KARE:")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(white: 0.55))
                        Image(nsImage: previewImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 150, maxHeight: 34)
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                            )
                    }
                }

                if !state.currentTurkishSubtitle.isEmpty {
                    Button(state.isOverlayDraggable ? "🔒 Konumu Kilitle" : "✋ Fareyle Taşı") {
                        state.isOverlayDraggable.toggle()
                        if state.isOverlayDraggable {
                            state.overlayPlacement = "custom_drag"
                        }
                        state.refreshOverlayPosition()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Ekrandan Gizle") {
                        state.hideCurrentSubtitle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
            )

            // Alt Canlı Diyalog Geçmişi Listesi
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("CANLI DİYALOG AKIŞI (VISION OCR ➔ YEREL OLLAMA / SQLITE CACHE)", systemImage: "captions.bubble.fill")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.75))
                    Spacer()

                    Button("Test Repliği Çevir") {
                        state.triggerDemoSubtitle()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Listeyi Temizle") {
                        state.dialogueHistory.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("SQLite Önbelleği Sıfırla") {
                        state.clearSQLiteCache()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if state.dialogueHistory.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Text("Henüz çevrilen replik yok. PS Remote Play'de altyazı çıktığında veya 'Test Repliği Çevir'e bastığında yerel Ollama + SQLite önbellek devreye girer.")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.55))
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 7) {
                            ForEach(state.dialogueHistory) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(item.timestamp)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(Color(white: 0.50))
                                        .padding(.top, 2)

                                    if !item.speaker.isEmpty {
                                        Text("\(item.speaker):")
                                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                                            .foregroundColor(Color.speakerColor(for: item.speaker))
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.turkishText)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text("EN: \(item.englishText)")
                                            .font(.system(size: 11).italic())
                                            .foregroundColor(Color(white: 0.58))
                                    }

                                    Spacer()

                                    Text(item.metaInfo)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(.jasonCyan)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.black.opacity(0.28))
                                )
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
            )
        }
    }

    // MARK: - Sekme 1: Ev Ağı (PS5 + TV + M2 MacBook Pro) Kablosuz Merkez
    private var homeNetworkHubTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("EV AĞI MİMARİSİ (MACBOOK İÇİN HDMI KABLOSU GEREKMEZ)", systemImage: "wifi.circle.fill")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.neonEmerald)
                        Spacer()
                        if copiedURLToast {
                            Text("✓ Yayın Adresi Kopyalandı")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.neonEmerald)
                        }
                    }

                    Text("1. PS5 kendi HDMI kablosuyla doğrudan TV'ye bağlı kalır (4K/HDR görüntü ve 0 ms kol gecikmesi korunur).\n2. M2 MacBook Pro, ev ağı üzerinden PS Remote Play ile PS5 görüntüsünü arka planda çeker ve M2 Neural Engine ile altyazıyı okur.\n3. Yerel Ollama (veya SQLite önbellek) ile çevrilen Türkçe altyazı aşağıdaki yerel ağ adresinden anında TV ekranına basılır:")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.78))
                        .lineSpacing(3)

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CANLI TV WEB / OVERLAY ADRESİ")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(white: 0.55))
                            Text(state.tvServerURL)
                                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                                .foregroundColor(.neonEmerald)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.42)))

                        Button("Adresi Kopyala") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(state.tvServerURL, forType: .string)
                            copiedURLToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedURLToast = false
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Tarayıcıda Test Aç") {
                            if let url = URL(string: state.tvServerURL) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("📡 Canlı Uzak Ekran + Altyazı (/remote)") {
                            if let url = URL(string: "\(state.tvServerURL)/remote") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.jasonCyan)
                    }

                    Text("• Sadece Altyazı: \(state.tvServerURL)  |  • Canlı Ekran Kaydı + Altyazı: \(state.tvServerURL)/remote  |  • JSON: \(state.tvServerURL)/api/subtitle")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.jasonCyan)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.neonEmerald.opacity(0.28), lineWidth: 1))
                )

                // PS5 Ev Ağı Tarayıcısı & Tek Tıkla PS Remote Play Kurucu
                VStack(alignment: .leading, spacing: 10) {
                    Label("PS5 EV AĞI TARAYICISI (UDP 987) & TEK TIKLA PS REMOTE PLAY KURUCU", systemImage: "gamecontroller.fill")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.luciaPink)

                    HStack(spacing: 10) {
                        Button("🔍 Ev Ağında PS5 & Cihazları Tara") {
                            state.scanHomeNetworkForPS5AndDevices()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("🎮 Tek Tıkla PS Remote Play İndir / Aç") {
                            state.installOrLaunchPSRemotePlay()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(state.discoveredDevicesText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.neonEmerald)

                    if !state.remotePlayInstallStatus.isEmpty {
                        Text(state.remotePlayInstallStatus)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.viceGold)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.luciaPink.opacity(0.28), lineWidth: 1))
                )

                VStack(alignment: .leading, spacing: 10) {
                    Label("EV AĞI CİHAZ KONTROLÜ (PS5 + AKILLI TV GECİKME TESTİ)", systemImage: "network")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.jasonCyan)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PS5 Yerel IP Adresi (Opsiyonel):")
                                .font(.system(size: 11, weight: .semibold))
                            TextField("Örn: 192.168.1.40", text: $state.ps5IP)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Akıllı TV Yerel IP Adresi:")
                                .font(.system(size: 11, weight: .semibold))
                            TextField("Örn: 192.168.1.55", text: $state.androidTVIP)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(" ")
                                .font(.system(size: 11))
                            Button("⚡ Ev Ağı Hız Testi Yap") {
                                state.runHomeNetworkCheck()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    Text(state.networkHealthMessage)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.viceGold)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                )

                VStack(alignment: .leading, spacing: 10) {
                    Label("ANDROID TV / GOOGLE TV DOĞRUDAN EKRAN KATMANI (ADB)", systemImage: "tv.inset.filled")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.luciaPink)

                    HStack(spacing: 12) {
                        Button(state.isConnectingADB ? "⏳ Bağlanılıyor..." : "🔗 Android TV'ye Kablosuz Bağlan (ADB)") {
                            state.connectAndroidTV()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.isConnectingADB)

                        if state.isConnectingADB {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text(state.adbStatusMessage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(state.adbConnected ? .neonEmerald : .viceGold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                )
            }
        }
    }

    // MARK: - Sekme 2: Yerel Ollama (M2) + SQLite Önbellek & Çeviri Motoru
    private var ollamaAndAISettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1) Yerel Ollama Yönetim Kartı
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("YEREL OLLAMA MOTORU (M2 UNIFIED MEMORY — ÜCRETSİZ & İNTERNETSİZ)", systemImage: "cpu.fill")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.neonEmerald)
                        Spacer()
                        Circle()
                            .fill(state.ollamaOnline ? Color.neonEmerald : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(state.ollamaOnline ? "Ollama Bağlı" : "Ollama Bekleniyor")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.ollamaOnline ? .neonEmerald : .orange)
                    }

                    Text("Çeviriler önce SQLite önbellekte aranır (0 ms). Önbellekte yoksa doğrudan M2 MacBook Pro üzerinde çalışan yerel Ollama modelinden çekilir ve bir sonraki sefer için önbelleğe kaydedilir.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.75))

                    HStack(spacing: 10) {
                        TextField("Ollama Adresi (http://127.0.0.1:11434)", text: $state.ollamaBaseUrl)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)

                        TextField("Model Adı (Örn: qwen2.5:3b veya gemma2:9b)", text: $state.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)

                        Button("🔄 Ollama Başlat / Kontrol Et") {
                            Task {
                                await state.ensureOllamaRunningAndRefresh()
                            }
                        }
                        .buttonStyle(.bordered)

                        Button(state.isPullingModel ? "Otomatik Kuruluyor..." : "⚡ Tek Tıkla Otomatik Kur & Başlat") {
                            state.oneClickSetupOllamaAndModel()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.isPullingModel)
                    }

                    if state.isPullingModel {
                        ProgressView(value: state.ollamaSetupProgress, total: 1.0)
                            .tint(.neonEmerald)
                    }

                    // Hızlı Model Seçim Çipleri
                    HStack(spacing: 8) {
                        Text("Önerilen M2 Modelleri:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(white: 0.60))

                        ForEach(["qwen2.5:3b", "qwen2.5:7b", "gemma2:9b", "llama3.2:3b"], id: \.self) { m in
                            Button(m) {
                                state.ollamaModel = m
                                state.saveEnvFile()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if !state.installedOllamaModels.isEmpty {
                            Text("| Yüklü: " + state.installedOllamaModels.joined(separator: ", "))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.jasonCyan)
                        }
                    }

                    Text(state.ollamaStatusText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(state.ollamaOnline ? .neonEmerald : .viceGold)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.neonEmerald.opacity(0.32), lineWidth: 1))
                )

                // 2) Çeviri Önceliği ve Opsiyonel Bulut API Anahtarları
                VStack(alignment: .leading, spacing: 12) {
                    Label("ÇEVİRİ ÖNCELİĞİ VE OPSİYONEL BULUT YEDEKLERİ", systemImage: "key.radiowaves.forward.fill")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.jasonCyan)

                    Form {
                        Picker("Aktif Çeviri Motoru:", selection: $state.translationProvider) {
                            Text("Yerel Ollama + SQLite Önbellek (Varsayılan — Tamamen Yerel)").tag("ollama")
                            Text("Otomatik Hibrit (SQLite -> Yerel Ollama -> Gemini -> DeepL)").tag("auto")
                            Text("Google Gemini Flash + SQLite Önbellek").tag("gemini")
                            Text("DeepL API Free + SQLite Önbellek").tag("deepl")
                        }

                        SecureField("Opsiyonel Gemini API Anahtarı:", text: $state.geminiApiKey)
                        SecureField("Opsiyonel DeepL API Anahtarı:", text: $state.deeplApiKey)
                    }
                    .textFieldStyle(.roundedBorder)

                    // Tek Tıkla API Anahtarı Alma Bağlantıları
                    HStack(spacing: 10) {
                        Text("Ücretsiz API Anahtarı Al:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(white: 0.65))

                        Button("🔑 DeepL API Free (500K/ay)") {
                            if let url = URL(string: "https://www.deepl.com/en/pro-api") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("✨ Google Gemini Flash (AI Studio)") {
                            if let url = URL(string: "https://aistudio.google.com/apikey") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    HStack(spacing: 12) {
                        Button(action: {
                            state.saveEnvFile()
                            showSavedBanner = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                showSavedBanner = false
                            }
                        }) {
                            Label("Ayarları Kaydet", systemImage: "checkmark.seal.fill")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.borderedProminent)

                        if showSavedBanner {
                            Text("✓ Çeviri ayarları kaydedildi!")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.neonEmerald)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                )
            }
        }
    }

    // MARK: - Sekme 3: Altyazı Görünümü, Konumu (Pixel Top) & Kalibrasyon
    private var appearanceSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1) Altyazı Konumlandırma ve Pixel Top / Offset Kartı
                VStack(alignment: .leading, spacing: 14) {
                    Label("TÜRKÇE ALTYAZI KONUMU VE PİKSEL KAYDIRMA (PIXEL TOP / OFFSET)", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.jasonCyan)

                    Text("Yakalanan İngilizce metnin üstüne binmemesi için altyazıyı bölgenin üstüne (Pixel Top), altına, ekranın sabit bir yerine koyabilir veya X/Y piksel sürgüsüyle milimetrik kaydırabilirsiniz.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.72))

                    HStack(spacing: 8) {
                        placementPresetButton(title: "⬆ Bölgenin Üstü (Pixel Top)", mode: "above")
                        placementPresetButton(title: "⬇ Bölgenin Altı", mode: "below")
                        placementPresetButton(title: "📺 Ekran Alt Orta", mode: "screen_bottom")
                        placementPresetButton(title: "📺 Ekran Üst Orta", mode: "screen_top")
                        placementPresetButton(title: "🎯 Tam Üzerine Kapat", mode: "inside")
                    }

                    HStack {
                        Text("Dikey Piksel Kaydır (Pixel Top / Y): \(Int(state.overlayOffsetY)) px")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 280, alignment: .leading)
                        Slider(value: $state.overlayOffsetY, in: -450...450, step: 2) { _ in
                            state.refreshOverlayPosition()
                            state.saveConfigFile()
                        }
                        .onChange(of: state.overlayOffsetY) { _ in
                            state.refreshOverlayPosition()
                        }
                    }

                    HStack {
                        Text("Yatay Piksel Kaydır (X Offset): \(Int(state.overlayOffsetX)) px")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 280, alignment: .leading)
                        Slider(value: $state.overlayOffsetX, in: -500...500, step: 2) { _ in
                            state.refreshOverlayPosition()
                            state.saveConfigFile()
                        }
                        .onChange(of: state.overlayOffsetX) { _ in
                            state.refreshOverlayPosition()
                        }
                    }

                    HStack(spacing: 12) {
                        Button(state.isOverlayDraggable ? "🔒 Fareyle Taşımayı Kilitle (Tıklama Geçirgen Yap)" : "✋ Altyazı Kutusunu Fareyle İstediğin Yere Sürükle") {
                            state.isOverlayDraggable.toggle()
                            if state.isOverlayDraggable {
                                state.overlayPlacement = "custom_drag"
                                if state.currentTurkishSubtitle.isEmpty {
                                    state.triggerDemoSubtitle()
                                }
                            }
                            state.refreshOverlayPosition()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Piksel Kaydırmayı Sıfırla (0 px)") {
                            state.overlayOffsetX = 0
                            state.overlayOffsetY = 0
                            state.isOverlayDraggable = false
                            if state.overlayPlacement == "custom_drag" {
                                state.overlayPlacement = "above"
                            }
                            state.refreshOverlayPosition()
                            state.saveConfigFile()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.jasonCyan.opacity(0.30), lineWidth: 1))
                )

                // 2) Boyut, Opaklık ve Hız Ayarları
                VStack(alignment: .leading, spacing: 14) {
                    Label("KOMPAKT TV ALTYAZI BOYUTU, OPAKLIK & HIZ AYARLARI", systemImage: "paintbrush.pointed.fill")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.luciaPink)

                    HStack {
                        Text("Türkçe Altyazı Boyutu: \(Int(state.fontSize)) pt")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 250, alignment: .leading)
                        Slider(value: $state.fontSize, in: 14...34, step: 1) { _ in
                            state.saveConfigFile()
                        }
                    }

                    HStack {
                        Text("Altyazı Kutusu Opaklığı: %\(Int(state.backgroundOpacity * 100))")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 250, alignment: .leading)
                        Slider(value: $state.backgroundOpacity, in: 0.30...0.95, step: 0.05) { _ in
                            state.saveConfigFile()
                        }
                    }

                    HStack {
                        Text("Remote Play Okuma Hızı: \(Int(state.captureFPS)) FPS")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 250, alignment: .leading)
                        Slider(value: $state.captureFPS, in: 4...15, step: 1) { _ in
                            state.restartCaptureTimer()
                            state.saveConfigFile()
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.1))

                    Toggle("Türkçe çevirinin altında orijinal İngilizce repliği de göster", isOn: $state.showOriginalEnglish)
                        .onChange(of: state.showOriginalEnglish) { _ in
                            state.saveConfigFile()
                        }

                    Toggle("Altyazı kutusunun altında küçük M2 Vision / API hız rozetini göster", isOn: $state.showStatusBadge)
                        .onChange(of: state.showStatusBadge) { _ in
                            state.saveConfigFile()
                        }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                )
            }
        }
    }

    private func placementPresetButton(title: String, mode: String) -> some View {
        let active = (state.overlayPlacement == mode)
        return Button(action: {
            state.isOverlayDraggable = false
            state.overlayPlacement = mode
            state.refreshOverlayPosition()
            state.saveConfigFile()
        }) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? Color.jasonCyan.opacity(0.24) : Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(active ? Color.jasonCyan : Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
                .foregroundColor(active ? .jasonCyan : .white)
        }
        .buttonStyle(.plain)
    }
}
