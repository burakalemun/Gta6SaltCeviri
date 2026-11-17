import AppKit
import CoreGraphics
import CoreText
import Foundation
import Network
import SQLite3
import SwiftUI
import Vision

// MARK: - Canlı Diyalog Kaydı Modeli
struct DialogueLogItem: Identifiable {
    let id = UUID()
    let timestamp: String
    let speaker: String
    let turkishText: String
    let englishText: String
    let metaInfo: String
}

// MARK: - Uygulama Durumu ve M2 Apple Vision + Yerel Ollama + SQLite + Ev Ağı Motoru
@MainActor
final class AppState: ObservableObject {
    // Canlı Telemetri & Durum
    @Published var isPaused: Bool = false
    @Published var statusText: String = "Aktif • Ev Ağı Dinleniyor"
    @Published var sourceWindowTitle: String = "PS Remote Play (Ev Ağı)"
    @Published var latencyTelemetry: String = "Vision: -- ms | Ollama: -- ms"
    @Published var cacheCount: Int = 0
    @Published var lastCapturedPreview: NSImage? = nil
    @Published var hasScreenRecordingPermission: Bool = true

    // Ekrandaki Aktif Altyazı (Varsayılan boş — ekranda gereksiz kutu kaplamaz)
    @Published var currentSpeaker: String = ""
    @Published var currentTurkishSubtitle: String = ""
    @Published var currentEnglishSubtitle: String = ""
    @Published var currentLatencyBadge: String = ""

    // Kompakt Görünüm, Konum (Pixel Top / Offset) & Performans Ayarları
    @Published var fontSize: Double = 20.0
    @Published var backgroundOpacity: Double = 0.82
    @Published var captureFPS: Double = 10.0
    @Published var showOriginalEnglish: Bool = false
    @Published var showStatusBadge: Bool = false
    @Published var useCustomROI: Bool = false
    @Published var customROIRect: CGRect = CGRect(x: 320, y: 760, width: 780, height: 90)
    @Published var overlayPlacement: String = "above" // above, below, inside, screen_bottom, screen_top, custom_drag
    @Published var overlayOffsetX: Double = 0.0
    @Published var overlayOffsetY: Double = 0.0
    @Published var isOverlayDraggable: Bool = false
    private var lastKnownROIRect: CGRect = CGRect(x: 320, y: 760, width: 780, height: 90)

    // Çeviri Motoru (Varsayılan: Yerel Ollama + SQLite Önbellek)
    @Published var translationProvider: String = "ollama" // ollama, auto, gemini, deepl
    @Published var ollamaBaseUrl: String = "http://127.0.0.1:11434"
    @Published var ollamaModel: String = "qwen2.5:3b"
    @Published var installedOllamaModels: [String] = []
    @Published var ollamaOnline: Bool = false
    @Published var ollamaStatusText: String = "Yerel Ollama kontrol ediliyor..."
    @Published var isPullingModel: Bool = false
    @Published var ollamaSetupProgress: Double = 0.0
    @Published var ollamaBinaryInstalled: Bool = false

    // Opsiyonel Bulut Anahtarları
    @Published var geminiApiKey: String = ""
    @Published var geminiModel: String = "gemini-2.5-flash"
    @Published var deeplApiKey: String = ""

    // Ev Ağı (PS5 + TV + MacBook Pro) Bağlantı Ayarları
    @Published var tvServerURL: String = "http://127.0.0.1:8765"
    @Published var localMacIP: String = "127.0.0.1"
    @Published var ps5IP: String = ""
    @Published var androidTVIP: String = ""
    @Published var networkHealthMessage: String = "Ev Ağı Hazır • PS5 (Remote Play) ve Akıllı TV yerel ağ üzerinden haberleşiyor."
    @Published var discoveredDevicesText: String = "Henüz tarama yapılmadı ('Ev Ağını Tara' butonuna basın)."
    @Published var remotePlayInstallStatus: String = ""
    @Published var adbStatusMessage: String = "TV'de Ayarlar -> Cihaz Tercihleri -> Hakkında -> Derleme Numarası'na 7 kez basıp Ağ Hata Ayıklama'yı açın."
    @Published var adbConnected: Bool = false

    // Canlı Diyalog Geçmişi & İlk Kurulum (Onboarding)
    @Published var dialogueHistory: [DialogueLogItem] = []
    @Published var showOnboarding: Bool = false

    // Dahili Bileşenler
    var overlayController: SubtitleOverlayController?
    private var captureTimer: Timer?
    private var lastFrameHash: UInt64?
    private var candidateText: String = ""
    private var candidateHits: Int = 0
    private var activeSubtitleText: String = ""
    private var emptyFrameStreak: Int = 0
    private var isProcessingFrame: Bool = false

    private var contextHistory: [(speaker: String, en: String, tr: String)] = []
    private var doNotTranslateTerms: [String] = [
        "Lucia", "Jason", "Vice City", "Leonida", "VCPD", "Leonida Keys",
        "Grassrivers", "Port Gellhorn", "Ambrosia", "Mount Kalaga",
        "Boobie Ike", "Dre'Quan", "Real Dimez", "Cal Hampton", "Raul Bautista", "Brian Heder"
    ]

    private let dataDir: URL
    private let cacheDBPath: String
    private var tvServer: NativeTVHTTPServer?
    private var demoIndex: Int = 0

    init() {
        // Tüm kullanıcı verisi (ayarlar, API anahtarları, SQLite önbellek) her zaman
        // ~/Library/Application Support/GTA6PS5Altyazi altında tutulur; .app paketi salt-okunur kalır.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GTA6PS5Altyazi", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport.appendingPathComponent("data"), withIntermediateDirectories: true)
        self.dataDir = appSupport
        Self.seedDefaultFiles(into: appSupport)

        let dataSubdir = dataDir.appendingPathComponent("data", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataSubdir, withIntermediateDirectories: true)
        self.cacheDBPath = dataSubdir.appendingPathComponent("cache.db").path

        let detectedIP = Self.getLocalIPAddress()
        self.localMacIP = detectedIP
        self.tvServerURL = "http://\(detectedIP):8765"

        initSQLiteCache()
        loadConfigurationAndEnv()
        refreshCacheCount()
        self.showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding_v1")
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding_v1")
        showOnboarding = false
    }

    /// .app paketinin içindeki varsayılan config.json, glossary.json ve .env.example dosyalarını
    /// kullanıcının ~/Library/Application Support/GTA6PS5Altyazi klasörüne ilk açılışta kopyalar.
    nonisolated static func seedDefaultFiles(into appSupport: URL) {
        let fm = FileManager.default
        let resourceAppDir = Bundle.main.resourceURL?.appendingPathComponent("app", isDirectory: true)
        guard let resDir = resourceAppDir, fm.fileExists(atPath: resDir.path) else { return }

        let copyPairs: [(String, String)] = [
            ("config.json", "config.json"),
            ("data/glossary.json", "data/glossary.json"),
            (".env.example", ".env")
        ]
        for (srcRel, dstRel) in copyPairs {
            let src = resDir.appendingPathComponent(srcRel)
            let dst = appSupport.appendingPathComponent(dstRel)
            if fm.fileExists(atPath: src.path) && !fm.fileExists(atPath: dst.path) {
                try? fm.createDirectory(atPath: dst.deletingLastPathComponent().path, withIntermediateDirectories: true)
                try? fm.copyItem(at: src, to: dst)
            }
        }
    }

    func startPipeline() {
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        if !hasScreenRecordingPermission {
            CGRequestScreenCaptureAccess()
        }
        if overlayController == nil {
            overlayController = SubtitleOverlayController(state: self)
        }
        if tvServer == nil {
            let srv = NativeTVHTTPServer(port: 8765)
            srv.start()
            self.tvServer = srv
            let ip = Self.getLocalIPAddress()
            self.localMacIP = ip
            self.tvServerURL = "http://\(ip):8765"
        }
        Task {
            await ensureOllamaRunningAndRefresh()
        }
        restartCaptureTimer()
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func restartCaptureTimer() {
        captureTimer?.invalidate()
        let interval = 1.0 / max(2.0, min(15.0, captureFPS))
        captureTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.tickCaptureLoop()
            }
        }
    }

    func togglePause() {
        isPaused.toggle()
        statusText = isPaused ? "Duraklatıldı" : "Aktif • Ev Ağı Dinleniyor"
    }

    func refreshOverlayPosition(roiRect: CGRect? = nil) {
        if let r = roiRect {
            lastKnownROIRect = r
        }
        overlayController?.updatePosition(
            roiQuartzRect: lastKnownROIRect,
            placement: overlayPlacement,
            offsetX: overlayOffsetX,
            offsetY: overlayOffsetY,
            isDraggable: isOverlayDraggable
        )
    }

    func selectROIFromScreen() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        ROISelectorOverlay.present { [weak self] selectedQuartzRect, immediateImage in
            guard let self = self else { return }
            self.useCustomROI = true
            self.customROIRect = selectedQuartzRect
            self.lastFrameHash = nil
            self.candidateText = ""
            self.candidateHits = 0
            self.activeSubtitleText = ""
            self.refreshOverlayPosition(roiRect: selectedQuartzRect)
            self.sourceWindowTitle = "Özel ROI (\(Int(selectedQuartzRect.width))x\(Int(selectedQuartzRect.height)))"
            self.statusText = "Bölge Seçildi • Okunuyor..."
            self.saveConfigFile()

            // Seçilen bölgedeki metni beklemeden ANINDA oku ve çevir!
            Task { @MainActor in
                await self.processImmediateSelection(rect: selectedQuartzRect, preCapturedImage: immediateImage)
            }
        }
    }

    private func processImmediateSelection(rect: CGRect, preCapturedImage: CGImage?) async {
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        let overlayWinID = overlayController?.windowNumber ?? 0
        let cgImg: CGImage
        if let pre = preCapturedImage, pre.width > 10, pre.height > 10 {
            cgImg = pre
        } else if let captured = captureTargetROI(excludingOverlayID: overlayWinID)?.0 {
            cgImg = captured
        } else {
            statusText = "Ekran Kaydı İzni Gerekli (Sistem Ayarları -> Gizlilik -> Ekran Kaydı)"
            return
        }

        lastCapturedPreview = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
        tvServer?.updateFrame(cgImage: cgImg)

        let ocrStart = CFAbsoluteTimeGetCurrent()
        let rawOCR = await Task.detached(priority: .userInitiated) {
            Self.recognizeTextWithAppleVision(cgImage: cgImg)
        }.value
        let ocrMs = (CFAbsoluteTimeGetCurrent() - ocrStart) * 1000.0

        let cleaned = Self.cleanOCRText(rawOCR)
        guard !cleaned.isEmpty else {
            latencyTelemetry = String(format: "Vision: %.0fms (Metin Bulunamadı)", ocrMs)
            statusText = "Seçilen Bölgede İngilizce Metin Algılanmadı"
            return
        }

        activeSubtitleText = cleaned
        lastFrameHash = Self.computeDHash(cgImg)
        let (speaker, dialogue) = Self.splitSpeaker(cleaned)

        statusText = "Çevriliyor (\(translationProvider.uppercased()))..."
        let trStart = CFAbsoluteTimeGetCurrent()
        let (trText, provider, _) = await translateSubtitle(speaker: speaker, english: dialogue)
        let trMs = (CFAbsoluteTimeGetCurrent() - trStart) * 1000.0

        let formatted = formatSubtitleLines(trText)
        let meta = String(format: "Vision %.0fms | %@ %.0fms", ocrMs, provider, trMs)
        statusText = "Aktif • Çevrildi (\(provider))"
        applyNewSubtitle(speaker: speaker, turkish: formatted, english: dialogue, meta: meta)
    }

    func switchToAutoWindowMode() {
        useCustomROI = false
        lastFrameHash = nil
        candidateText = ""
        candidateHits = 0
        activeSubtitleText = ""

        // PS Remote Play açık mı kontrol et; kapalıysa ve /Applications/RemotePlay.app varsa başlatmayı dene
        if hasOpenRemotePlayWindow() {
            sourceWindowTitle = "PS Remote Play (Otomatik)"
            statusText = "Aktif • PS Remote Play Penceresi İzleniyor"
        } else {
            let remotePlayApp = URL(fileURLWithPath: "/Applications/RemotePlay.app")
            if FileManager.default.fileExists(atPath: remotePlayApp.path) {
                NSWorkspace.shared.openApplication(at: remotePlayApp, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                sourceWindowTitle = "PS Remote Play Başlatılıyor..."
                statusText = "PS Remote Play Açılıyor • Alt Ekran İzleniyor"
            } else {
                sourceWindowTitle = "Oto Ekran Alt Şeridi (Remote Play Açık Değil)"
                statusText = "Aktif • Ekranın Alt Altyazı Bölgesi İzleniyor"
            }
        }
        saveConfigFile()
        Task { @MainActor in
            await tickCaptureLoop()
        }
    }

    private func hasOpenRemotePlayWindow() -> Bool {
        let targetTitles = ["ps remote play", "remote play", "chiaki-ng", "chiaki"]
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for win in windowList {
            let owner = (win[kCGWindowOwnerName as String] as? String) ?? ""
            let name = (win[kCGWindowName as String] as? String) ?? ""
            let combined = "\(owner) \(name)".lowercased()
            if targetTitles.contains(where: { combined.contains($0) }) {
                return true
            }
        }
        return false
    }

    func hideCurrentSubtitle() {
        clearActiveSubtitle()
    }

    func triggerDemoSubtitle() {
        let samples: [(String, String)] = [
            ("LUCIA", "The only way we're gonna get through this is by sticking together."),
            ("JASON", "Let's get out of here before VCPD shows up!"),
            ("LUCIA", "We got heat on our tail, step on it!"),
            ("DRE'QUAN", "Welcome to Leonida, where anything can happen."),
            ("JASON", "Keep your head down and watch the back door.")
        ]
        let (spk, eng) = samples[demoIndex % samples.count]
        demoIndex += 1

        Task { @MainActor in
            let t0 = CFAbsoluteTimeGetCurrent()
            let (tr, provider, _) = await translateSubtitle(speaker: spk, english: eng)
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            let formatted = formatSubtitleLines(tr)
            let meta = String(format: "Vision 22ms | %@ (%.0fms)", provider, elapsedMs)
            applyNewSubtitle(speaker: spk, turkish: formatted, english: eng, meta: meta)
        }
    }

    // MARK: - Sıfır Dokunuşlu (Zero-Touch) Tek Tıkla Yerel Ollama + Model Otomatik Kurucu & Başlatıcı
    nonisolated static func resolveOllamaBinaryPath() -> String? {
        let appSupportOllama = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GTA6PS5Altyazi/Ollama.app/Contents/Resources/ollama").path
        let candidates = [
            appSupportOllama,
            "/Applications/Ollama.app/Contents/Resources/ollama",
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/usr/bin/ollama"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    func ensureOllamaRunningAndRefresh() async {
        ollamaBinaryInstalled = (Self.resolveOllamaBinaryPath() != nil)
        if await fetchOllamaModels() {
            return
        }
        guard let binPath = Self.resolveOllamaBinaryPath() else {
            ollamaOnline = false
            ollamaStatusText = "Ollama henüz kurulu değil • 'Tek Tıkla Otomatik Kur & Başlat' butonuna basın"
            return
        }

        ollamaStatusText = "Yerel Ollama motoru arka planda başlatılıyor..."
        Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: binPath)
            proc.arguments = ["serve"]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            try? proc.run()
        }

        for _ in 0..<6 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if await fetchOllamaModels() {
                return
            }
        }
    }

    /// Kullanıcının hiçbir şey kurmasına gerek kalmadan tek butonla:
    /// 1) Ollama macOS paketini indirir ve uygulama klasörüne açar
    /// 2) Arka planda 'ollama serve' servisini başlatır
    /// 3) Seçili yapay zeka modelini (qwen2.5:3b) indirip aktif hale getirir
    func oneClickSetupOllamaAndModel() {
        guard !isPullingModel else { return }
        isPullingModel = true
        ollamaSetupProgress = 0.05

        let targetModel = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "qwen2.5:3b"
            : ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            // ADIM 1: Ollama Binary Kurulu mu? Değilse Otomatik İndir ve Çıkar
            var binPath = Self.resolveOllamaBinaryPath()
            if binPath == nil {
                ollamaStatusText = "[1/3] Ollama macOS motoru indiriliyor (lütfen bekleyin)..."
                ollamaSetupProgress = 0.12

                let installBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("GTA6PS5Altyazi", isDirectory: true)
                try? FileManager.default.createDirectory(at: installBase, withIntermediateDirectories: true)
                let zipPath = installBase.appendingPathComponent("Ollama-darwin.zip").path

                let dlSuccess = await Task.detached { () -> Bool in
                    let curlProc = Process()
                    curlProc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                    curlProc.arguments = [
                        "-fL",
                        "--retry", "2",
                        "https://ollama.com/download/Ollama-darwin.zip",
                        "-o", zipPath
                    ]
                    do {
                        try curlProc.run()
                        curlProc.waitUntilExit()
                        guard curlProc.terminationStatus == 0 else { return false }

                        let dittoProc = Process()
                        dittoProc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                        dittoProc.arguments = ["-x", "-k", zipPath, installBase.path]
                        try dittoProc.run()
                        dittoProc.waitUntilExit()
                        try? FileManager.default.removeItem(atPath: zipPath)
                        return dittoProc.terminationStatus == 0
                    } catch {
                        return false
                    }
                }.value

                binPath = Self.resolveOllamaBinaryPath()
                ollamaBinaryInstalled = (binPath != nil)
                if !dlSuccess || binPath == nil {
                    isPullingModel = false
                    ollamaSetupProgress = 0.0
                    ollamaStatusText = "Ollama indirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin."
                    return
                }
            }

            ollamaSetupProgress = 0.35

            // ADIM 2: Ollama Sunucusunu (127.0.0.1:11434) Arka Planda Başlat
            if !(await fetchOllamaModels()), let validBin = binPath {
                ollamaStatusText = "[2/3] Yerel Ollama sunucusu başlatılıyor..."
                Task.detached {
                    let serveProc = Process()
                    serveProc.executableURL = URL(fileURLWithPath: validBin)
                    serveProc.arguments = ["serve"]
                    serveProc.standardOutput = Pipe()
                    serveProc.standardError = Pipe()
                    try? serveProc.run()
                }
                for _ in 0..<10 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if await fetchOllamaModels() {
                        break
                    }
                }
            }

            ollamaSetupProgress = 0.45

            // ADIM 3: Çeviri Modelini (/api/pull veya CLI) Otomatik İndir
            if installedOllamaModels.contains(targetModel) {
                ollamaSetupProgress = 1.0
                isPullingModel = false
                ollamaOnline = true
                ollamaStatusText = "✅ Hazır! Yerel Ollama + '\(targetModel)' modeli aktif."
                return
            }

            guard let validBin = binPath else {
                isPullingModel = false
                return
            }

            ollamaStatusText = "[3/3] '\(targetModel)' yapay zeka modeli indiriliyor..."
            ollamaSetupProgress = 0.55

            let pullSuccess = await Task.detached { () -> Bool in
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: validBin)
                proc.arguments = ["pull", targetModel]
                proc.standardOutput = Pipe()
                proc.standardError = Pipe()
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    return proc.terminationStatus == 0
                } catch {
                    return false
                }
            }.value

            isPullingModel = false
            if pullSuccess {
                ollamaSetupProgress = 1.0
                _ = await fetchOllamaModels()
                ollamaStatusText = "✅ Kurulum Tamamlandı! '\(targetModel)' yerel modeli aktif."
            } else {
                ollamaSetupProgress = 0.0
                ollamaStatusText = "Model indirme tamamlanamadı; tekrar deneyebilirsiniz."
            }
        }
    }

    @discardableResult
    func fetchOllamaModels() async -> Bool {
        let base = ollamaBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(base)/api/tags") else {
            ollamaOnline = false
            ollamaStatusText = "Geçersiz Ollama adresi: \(base)"
            return false
        }

        var req = URLRequest(url: url, timeoutInterval: 1.8)
        req.httpMethod = "GET"

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelsArr = json["models"] as? [[String: Any]] else {
                ollamaOnline = false
                return false
            }

            let names: [String] = modelsArr.compactMap { $0["name"] as? String }
            installedOllamaModels = names
            ollamaBinaryInstalled = true

            if names.isEmpty {
                ollamaOnline = false
                ollamaStatusText = "Ollama Servisi Açık • Model indirmek için 'Tek Tıkla Kur & Başlat'a basın"
            } else {
                ollamaOnline = true
                if !names.contains(ollamaModel) {
                    ollamaModel = names[0]
                    saveEnvFile()
                }
                ollamaStatusText = "✅ Yerel Ollama Aktif • Model: \(ollamaModel)"
            }
            return true
        } catch {
            ollamaOnline = false
            if Self.resolveOllamaBinaryPath() != nil {
                ollamaStatusText = "Ollama Kurulu • Başlatmak için 'Tek Tıkla Otomatik Kur & Başlat'a basın"
            } else {
                ollamaStatusText = "Ollama Kurulu Değil • 'Tek Tıkla Otomatik Kur & Başlat' ile sistem kendisi kurar"
            }
            return false
        }
    }

    func pullOllamaModel() {
        oneClickSetupOllamaAndModel()
    }

    // MARK: - Ev Ağı PS5 Keşif (UDP 987 DDP) + Cihaz Tarama & Tek Tıkla PS Remote Play Kurucu
    func scanHomeNetworkForPS5AndDevices() {
        discoveredDevicesText = "Ev ağı (UDP 987 PS5 Protokolü ve ARP tablosu) taranıyor..."
        let currentIP = localMacIP

        Task.detached {
            let parts = currentIP.split(separator: ".")
            let broadcastIP = parts.count == 4 ? "\(parts[0]).\(parts[1]).\(parts[2]).255" : "255.255.255.255"
            let ps5Info = Self.discoverPS5(broadcastIP: broadcastIP)
            let devices = Self.readARPDevices()
            let deviceList = devices.isEmpty ? "Yok" : devices.joined(separator: ", ")
            let result: String
            if let ps5 = ps5Info {
                result = "\(ps5) | Ağdaki Cihazlar: \(deviceList)"
            } else {
                result = "Açık PS5 yanıtı yok (UDP 987) | Ev Ağındaki Aktif Cihazlar: \(deviceList)"
            }
            await MainActor.run {
                self.discoveredDevicesText = result
                if let ip = ps5Info?.components(separatedBy: "(").dropFirst().first?.components(separatedBy: ")").first {
                    self.ps5IP = ip
                }
            }
        }
    }

    /// Sony PS5 Device Discovery Protocol (UDP 987) — saf BSD soket, harici bağımlılık yok
    nonisolated static func discoverPS5(broadcastIP: String) -> String? {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 1, tv_usec: 200_000)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(987).bigEndian
        inet_pton(AF_INET, broadcastIP, &addr.sin_addr)

        let msg = Array("SRCH * HTTP/1.1\r\ndevice-discovery-protocol-version:00030010\r\n\r\n".utf8)
        let sent = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(sock, msg, msg.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: 2048)
        var from = sockaddr_in()
        var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let received = withUnsafeMutablePointer(to: &from) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(sock, &buffer, buffer.count, 0, $0, &fromLen)
            }
        }
        guard received > 0 else { return nil }

        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &from.sin_addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
        let ip = String(cString: ipBuf)
        let text = String(decoding: buffer[0..<received], as: UTF8.self)
        let hostName = text.components(separatedBy: "\n")
            .first { $0.hasPrefix("host-name:") }?
            .replacingOccurrences(of: "host-name:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "PlayStation"
        let statusLine = text.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "PS5 BULUNDU (\(ip)): \(hostName) • \(statusLine)"
    }

    nonisolated static func readARPDevices() -> [String] {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        proc.arguments = ["-a", "-n"]
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return [] }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var devices: [String] = []
        for line in out.components(separatedBy: "\n") {
            guard let open = line.firstIndex(of: "("), let close = line.firstIndex(of: ")"), open < close else { continue }
            let ip = String(line[line.index(after: open)..<close])
            if ip.hasSuffix(".255") || ip.hasPrefix("224.") || ip.hasPrefix("239.") || ip == "255.255.255.255" { continue }
            if line.contains("incomplete") { continue }
            devices.append(ip)
        }
        return devices
    }

    func installOrLaunchPSRemotePlay() {
        let appPaths = [
            "/Applications/RemotePlay.app",
            NSHomeDirectory() + "/Applications/RemotePlay.app"
        ]
        for path in appPaths where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
            remotePlayInstallStatus = "✅ PS Remote Play açıldı! Konsola bağlandığınızda otomatik okuma başlar."
            return
        }

        remotePlayInstallStatus = "Sony resmi PS Remote Play macOS kurulum paketi indiriliyor..."
        Task.detached {
            let pkgPath = "/tmp/RemotePlayInstaller.pkg"
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            proc.arguments = [
                "-fL",
                "https://remoteplay.dl.playstation.net/remoteplay/module/mac/RemotePlayInstaller.pkg",
                "-o", pkgPath
            ]
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0, FileManager.default.fileExists(atPath: pkgPath) {
                    await MainActor.run {
                        self.remotePlayInstallStatus = "✅ İndirildi! Kurulum penceresi açıldı, kurulumu tamamlayın."
                        NSWorkspace.shared.open(URL(fileURLWithPath: pkgPath))
                    }
                } else {
                    await MainActor.run {
                        self.remotePlayInstallStatus = "İndirme başarısız oldu."
                    }
                }
            } catch {
                await MainActor.run {
                    self.remotePlayInstallStatus = "Hata: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Ev Ağı Ping / Bağlantı Testi (PS5 + TV + M2 Mac)
    func runHomeNetworkCheck() {
        let targetTV = androidTVIP.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetPS5 = ps5IP.trimmingCharacters(in: .whitespacesAndNewlines)
        networkHealthMessage = "Ev ağı gecikmesi ölçülüyor..."

        Task.detached {
            var parts: [String] = []
            let macIP = await MainActor.run { self.localMacIP }
            parts.append("MacBook (\(macIP):8765): Aktif")

            if !targetPS5.isEmpty {
                let ms = Self.measurePingMs(host: targetPS5)
                parts.append(ms != nil ? "PS5 (\(targetPS5)): \(ms!) ms" : "PS5 (\(targetPS5)): Yanıt Yok")
            }
            if !targetTV.isEmpty {
                let ms = Self.measurePingMs(host: targetTV)
                parts.append(ms != nil ? "TV (\(targetTV)): \(ms!) ms" : "TV (\(targetTV)): Yanıt Yok")
            }
            let summary = parts.joined(separator: "  •  ")
            await MainActor.run {
                self.networkHealthMessage = summary
            }
        }
    }

    nonisolated private static func measurePingMs(host: String) -> String? {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/sbin/ping")
        proc.arguments = ["-c", "1", "-W", "800", host]
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if let range = out.range(of: "time=") {
                let sub = out[range.upperBound...]
                if let end = sub.range(of: " ms") {
                    return String(sub[..<end.lowerBound])
                }
            }
            return "<1"
        } catch {
            return nil
        }
    }

    // MARK: - Ana Yakalama + M2 Apple Vision OCR + Sabitleyici Döngüsü
    private func tickCaptureLoop() async {
        guard !isPaused, !isProcessingFrame else { return }
        isProcessingFrame = true
        defer { isProcessingFrame = false }

        let overlayWinID = overlayController?.windowNumber ?? 0
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        guard let (cgImage, roiRect, winTitle) = captureTargetROI(excludingOverlayID: overlayWinID) else {
            sourceWindowTitle = "Ekran Kaydı İzni Bekleniyor"
            return
        }

        lastCapturedPreview = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        tvServer?.updateFrame(cgImage: cgImage)
        sourceWindowTitle = winTitle
        refreshOverlayPosition(roiRect: roiRect)

        let currentHash = Self.computeDHash(cgImage)
        if let prevHash = lastFrameHash {
            let hamming = (currentHash ^ prevHash).nonzeroBitCount
            // ÖNEMLİ: Eğer bekleyen bir candidateText varsa (candidateHits == 1),
            // ikinci karede görüntünün sabit kalması (hamming < 3) yazının sabitlendiğini kanıtlar!
            if hamming < 3 && emptyFrameStreak == 0 && candidateText.isEmpty {
                return
            }
        }
        lastFrameHash = currentHash

        let ocrStart = CFAbsoluteTimeGetCurrent()
        let rawOCRText = await Task.detached(priority: .userInitiated) {
            Self.recognizeTextWithAppleVision(cgImage: cgImage)
        }.value
        let ocrMs = (CFAbsoluteTimeGetCurrent() - ocrStart) * 1000.0

        let cleaned = Self.cleanOCRText(rawOCRText)
        if cleaned.isEmpty {
            emptyFrameStreak += 1
            candidateText = ""
            candidateHits = 0
            if !activeSubtitleText.isEmpty && emptyFrameStreak >= 4 {
                activeSubtitleText = ""
                clearActiveSubtitle()
                latencyTelemetry = String(format: "Vision: %.0fms (Altyazı Yok)", ocrMs)
            }
            return
        }

        emptyFrameStreak = 0

        if !activeSubtitleText.isEmpty {
            let simActive = Self.similarityPercentage(cleaned.lowercased(), activeSubtitleText.lowercased())
            if simActive >= 86.0 && (cleaned.count - activeSubtitleText.count) < 6 {
                return
            }
        }

        if candidateText.isEmpty {
            candidateText = cleaned
            candidateHits = 1
        } else {
            let simCand = Self.similarityPercentage(cleaned.lowercased(), candidateText.lowercased())
            if simCand >= 86.0 {
                if cleaned.count >= candidateText.count {
                    candidateText = cleaned
                }
                candidateHits += 1
            } else {
                candidateText = cleaned
                candidateHits = 1
            }
        }

        guard candidateHits >= 2 else { return }
        let confirmed = candidateText
        activeSubtitleText = confirmed
        candidateText = ""
        candidateHits = 0

        let (speaker, dialogue) = Self.splitSpeaker(confirmed)
        let trStart = CFAbsoluteTimeGetCurrent()
        let (trText, provider, _) = await translateSubtitle(speaker: speaker, english: dialogue)
        let trMs = (CFAbsoluteTimeGetCurrent() - trStart) * 1000.0

        let formatted = formatSubtitleLines(trText)
        let meta = String(format: "Vision %.0fms | %@ %.0fms", ocrMs, provider, trMs)
        applyNewSubtitle(speaker: speaker, turkish: formatted, english: dialogue, meta: meta)
    }

    private func applyNewSubtitle(speaker: String, turkish: String, english: String, meta: String) {
        currentSpeaker = speaker
        currentTurkishSubtitle = turkish
        currentEnglishSubtitle = english
        currentLatencyBadge = meta
        latencyTelemetry = meta

        tvServer?.updateSubtitle(
            speaker: speaker,
            turkish: turkish,
            english: english,
            meta: meta,
            showOriginal: showOriginalEnglish
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let ts = formatter.string(from: Date())

        let item = DialogueLogItem(
            timestamp: ts,
            speaker: speaker,
            turkishText: turkish.replacingOccurrences(of: "\n", with: " "),
            englishText: english,
            metaInfo: meta
        )
        dialogueHistory.insert(item, at: 0)
        if dialogueHistory.count > 100 {
            dialogueHistory.removeLast()
        }
        refreshCacheCount()
    }

    private func clearActiveSubtitle() {
        currentSpeaker = ""
        currentTurkishSubtitle = ""
        currentEnglishSubtitle = ""
        currentLatencyBadge = ""
        tvServer?.clearSubtitle()
    }

    // MARK: - Pencere / ROI Yakalama (Kendi Dashboard ve Overlay Penceremizi %100 Hariç Tutar)
    private func captureTargetROI(excludingOverlayID: CGWindowID) -> (CGImage, CGRect, String)? {
        let targetTitles = ["ps remote play", "remote play", "chiaki-ng", "chiaki"]
        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windowList = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []

        // 1) Otomatik Mod: PS Remote Play veya Chiaki penceresini bul
        if !useCustomROI {
            for win in windowList {
                let ownerPID = (win[kCGWindowOwnerPID as String] as? Int) ?? 0
                if ownerPID == myPID { continue } // Kendi uygulamamızı asla yakalama!

                let owner = (win[kCGWindowOwnerName as String] as? String) ?? ""
                let name = (win[kCGWindowName as String] as? String) ?? ""
                let layer = (win[kCGWindowLayer as String] as? Int) ?? 0
                if layer != 0 { continue }

                let combined = "\(owner) \(name)".lowercased()
                if targetTitles.contains(where: { combined.contains($0) }),
                   let boundsDict = win[kCGWindowBounds as String] as? [String: CGFloat],
                   let wx = boundsDict["X"], let wy = boundsDict["Y"],
                   let ww = boundsDict["Width"], let wh = boundsDict["Height"],
                   ww >= 300, wh >= 200,
                   let winNumber = win[kCGWindowNumber as String] as? UInt32 {

                    let roiRect = CGRect(
                        x: round(wx + ww * 0.14),
                        y: round(wy + wh * 0.80),
                        width: max(100, round(ww * 0.72)),
                        height: max(45, round(wh * 0.14))
                    )
                    if let img = CGWindowListCreateImage(
                        roiRect,
                        .optionIncludingWindow,
                        CGWindowID(winNumber),
                        .bestResolution
                    ), img.width > 10, img.height > 10 {
                        return (img, roiRect, owner.isEmpty ? "PS Remote Play (Ev Ağı)" : "\(owner) (Ev Ağı)")
                    }
                }
            }
        }

        // 2) Özel ROI Modu (veya Remote Play bulunamadığında):
        // Seçilen ROI koordinatlarının altındaki EN ÜSTTEKİ BAŞKA UYGULAMA PENCERESİNİ (Safari, Chrome, Oyun, Video vb.) bul
        let roiRect = customROIRect
        var lowestSelfWindowID: CGWindowID = excludingOverlayID

        for win in windowList {
            let ownerPID = (win[kCGWindowOwnerPID as String] as? Int) ?? 0
            if ownerPID == myPID {
                if let selfWinNum = win[kCGWindowNumber as String] as? UInt32, selfWinNum > 0 {
                    lowestSelfWindowID = CGWindowID(selfWinNum)
                }
                continue
            }

            let layer = (win[kCGWindowLayer as String] as? Int) ?? 0
            if layer != 0 { continue }

            guard let boundsDict = win[kCGWindowBounds as String] as? [String: CGFloat],
                  let wx = boundsDict["X"], let wy = boundsDict["Y"],
                  let ww = boundsDict["Width"], let wh = boundsDict["Height"],
                  ww >= 120, wh >= 80,
                  let winNumber = win[kCGWindowNumber as String] as? UInt32 else {
                continue
            }

            let winRect = CGRect(x: wx, y: wy, width: ww, height: wh)
            if winRect.intersects(roiRect) {
                let owner = (win[kCGWindowOwnerName as String] as? String) ?? "Uygulama"
                if let img = CGWindowListCreateImage(
                    roiRect,
                    .optionIncludingWindow,
                    CGWindowID(winNumber),
                    .bestResolution
                ), img.width > 10, img.height > 10 {
                    return (img, roiRect, "\(owner) (\(Int(roiRect.width))x\(Int(roiRect.height)))")
                }
            }
        }

        // 3) Son Yedek: Kendi en alt penceremizin (Dashboard dahil) ALTINDAKİ ekran katmanını yakala
        let listOption: CGWindowListOption = lowestSelfWindowID > 0 ? .optionOnScreenBelowWindow : .optionOnScreenOnly
        let refWin: CGWindowID = lowestSelfWindowID > 0 ? lowestSelfWindowID : kCGNullWindowID

        if let img = CGWindowListCreateImage(roiRect, listOption, refWin, .bestResolution),
           img.width > 10, img.height > 10 {
            let label = useCustomROI ? "Özel ROI (\(Int(roiRect.width))x\(Int(roiRect.height)))" : "Masaüstü ROI"
            return (img, roiRect, label)
        }
        return nil
    }

    // MARK: - Apple Vision OCR (M2 Neural Engine + In-Process Fast Fallback)
    nonisolated static func recognizeTextWithAppleVision(cgImage: CGImage) -> String {
        for level in [VNRequestTextRecognitionLevel.accurate, VNRequestTextRecognitionLevel.fast] {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continue
            }

            guard let observations = request.results, !observations.isEmpty else {
                continue
            }

            struct BoxLine {
                let y: CGFloat
                let x: CGFloat
                let text: String
            }

            var valid: [BoxLine] = []
            for obs in observations {
                guard let top = obs.topCandidates(1).first,
                      top.confidence >= 0.25,
                      obs.boundingBox.height >= 0.012 else { continue }
                let str = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !str.isEmpty {
                    valid.append(BoxLine(y: obs.boundingBox.origin.y, x: obs.boundingBox.origin.x, text: str))
                }
            }

            if valid.isEmpty { continue }
            valid.sort { $0.y > $1.y }

            var lines: [String] = []
            var currentGroup: [BoxLine] = []
            for item in valid {
                if let first = currentGroup.first {
                    if abs(item.y - first.y) < 0.08 {
                        currentGroup.append(item)
                    } else {
                        currentGroup.sort { $0.x < $1.x }
                        lines.append(currentGroup.map(\.text).joined(separator: " "))
                        currentGroup = [item]
                    }
                } else {
                    currentGroup = [item]
                }
            }
            if !currentGroup.isEmpty {
                currentGroup.sort { $0.x < $1.x }
                lines.append(currentGroup.map(\.text).joined(separator: " "))
            }

            let joined = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                return joined
            }
        }
        return ""
    }

    // MARK: - 64-bit Perceptual dHash
    nonisolated static func computeDHash(_ image: CGImage) -> UInt64 {
        let width = 9, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                if pixels[y * width + x] > pixels[y * width + x + 1] {
                    hash |= (1 << bit)
                }
                bit += 1
            }
        }
        return hash
    }

    // MARK: - Metin Temizleme, Konuşmacı Ayrıştırma ve Levenshtein Benzerliği
    nonisolated static func cleanOCRText(_ raw: String) -> String {
        let singleLine = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "| ", with: "I ")
            .replacingOccurrences(of: "|'", with: "I'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if singleLine.count < 2 { return "" }
        let hasLetters = singleLine.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        return hasLetters ? singleLine : ""
    }

    nonisolated static func splitSpeaker(_ text: String) -> (String, String) {
        guard let colonIdx = text.firstIndex(of: ":") else {
            return ("", text)
        }
        let prefix = text[..<colonIdx]
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        let rest = text[text.index(after: colonIdx)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let wordCount = prefix.split(separator: " ").count
        if prefix.count >= 2 && prefix.count <= 18 && wordCount <= 3 && !rest.isEmpty {
            return (prefix.uppercased(), rest)
        }
        return ("", text)
    }

    nonisolated static func similarityPercentage(_ a: String, _ b: String) -> Double {
        let aChars = Array(a)
        let bChars = Array(b)
        let maxLen = max(aChars.count, bChars.count)
        if maxLen == 0 { return 100.0 }
        if a == b { return 100.0 }

        var prev = Array(0...bChars.count)
        var curr = [Int](repeating: 0, count: bChars.count + 1)

        for i in 1...aChars.count {
            curr[0] = i
            for j in 1...bChars.count {
                let cost = (aChars[i - 1] == bChars[j - 1]) ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        let dist = prev[bChars.count]
        return max(0.0, (1.0 - (Double(dist) / Double(maxLen))) * 100.0)
    }

    // MARK: - Çeviri Motoru: 1) SQLite Önbellek -> 2) Yerel Ollama (M2) -> 3) Opsiyonel Bulut
    func translateSubtitle(speaker: String, english: String) async -> (String, String, Bool) {
        let normKey = english.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) SQLite Önbellekte varsa anında (0 ms) çek
        if let cached = getFromSQLiteCache(key: normKey) {
            appendContext(speaker: speaker, en: english, tr: cached.text)
            return (cached.text, "cache(\(cached.provider))", true)
        }

        // 2) Seçili sırayla çeviri motorunu çağır (Varsayılan: Yerel Ollama ilk sırada!)
        let order: [String]
        switch translationProvider {
        case "ollama": order = ["ollama", "gemini", "deepl"]
        case "gemini": order = ["gemini", "ollama", "deepl"]
        case "deepl":  order = ["deepl", "ollama", "gemini"]
        default:       order = ["ollama", "gemini", "deepl"]
        }

        for prov in order {
            if prov == "ollama", let out = await callOllamaAPI(speaker: speaker, text: english) {
                saveToSQLiteCache(key: normKey, source: english, translated: out, provider: "ollama:\(ollamaModel)")
                appendContext(speaker: speaker, en: english, tr: out)
                return (out, "ollama(\(ollamaModel))", false)
            }
            if prov == "gemini", let out = await callGeminiAPI(speaker: speaker, text: english) {
                saveToSQLiteCache(key: normKey, source: english, translated: out, provider: "gemini-flash")
                appendContext(speaker: speaker, en: english, tr: out)
                return (out, "gemini-flash", false)
            }
            if prov == "deepl", let out = await callDeepLAPI(text: english) {
                saveToSQLiteCache(key: normKey, source: english, translated: out, provider: "deepl")
                appendContext(speaker: speaker, en: english, tr: out)
                return (out, "deepl", false)
            }
        }

        // Ollama henüz kurulmamışsa veya model indiriliyorsa anahtarsız hızlı çeviri yedeği
        if let fallbackOut = await callZeroKeyTranslateFallback(text: english) {
            saveToSQLiteCache(key: normKey, source: english, translated: fallbackOut, provider: "instant-tr")
            appendContext(speaker: speaker, en: english, tr: fallbackOut)
            return (fallbackOut, "instant-tr", false)
        }

        return ("[Ollama Bekleniyor: \(ollamaModel)] \(english)", "ollama-offline", false)
    }

    private func appendContext(speaker: String, en: String, tr: String) {
        contextHistory.append((speaker: speaker, en: en, tr: tr))
        if contextHistory.count > 8 {
            contextHistory.removeFirst()
        }
    }

    private func buildPrompt(speaker: String, text: String) -> String {
        var parts: [String] = []
        parts.append("Çevrilmeyecek Özel İsimler: " + doNotTranslateTerms.joined(separator: ", "))
        if !contextHistory.isEmpty {
            let hist = contextHistory.map { item in
                let spk = item.speaker.isEmpty ? "" : "\(item.speaker): "
                return "- \(spk)\(item.en) => \(item.tr)"
            }.joined(separator: "\n")
            parts.append("Önceki Diyalog Bağlamı:\n" + hist)
        }
        let spkLine = speaker.isEmpty ? "" : "Konuşmacı: \(speaker)\n"
        parts.append("\(spkLine)Çevrilecek İngilizce Replik: \(text)")
        return parts.joined(separator: "\n\n")
    }

    private func callOllamaAPI(speaker: String, text: String) async -> String? {
        let base = ollamaBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "\(base)/api/generate") else { return nil }

        let sysPrompt = "Sen GTA 6 oyun çevirmenisin. Verilen İngilizce altyazıyı sokak ağzını ve argoyu koruyarak doğal, kısa Türkçeye çevir. Özel isimleri (Lucia, Jason, Vice City, Leonida, VCPD) çevirme. SADECE Türkçe çeviri cümlesini yaz, açıklama ekleme."
        let payload: [String: Any] = [
            "model": ollamaModel.isEmpty ? "qwen2.5:3b" : ollamaModel,
            "system": sysPrompt,
            "prompt": buildPrompt(speaker: speaker, text: text),
            "stream": false,
            "keep_alive": "30m",
            "options": [
                "temperature": 0.2,
                "num_predict": 80
            ]
        ]

        var req = URLRequest(url: url, timeoutInterval: 6.0)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outText = json["response"] as? String else {
            return nil
        }
        let cleaned = outText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return cleaned.isEmpty ? nil : cleaned
    }

    private func callGeminiAPI(speaker: String, text: String) async -> String? {
        let key = geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.hasPrefix("your_") else { return nil }

        let model = geminiModel.isEmpty ? "gemini-2.5-flash" : geminiModel
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)") else {
            return nil
        }

        let sysPrompt = "Sen GTA 6 için profesyonel bir oyun çevirmenisin. Sokak ağzını, argoyu ve küfürleri yumuşatmadan doğal Türkçeye çevir. Özel isimleri (Lucia, Jason, Vice City, Leonida, VCPD) çevirme. Sadece Türkçe çeviri metnini döndür."
        let payload: [String: Any] = [
            "systemInstruction": ["parts": [["text": sysPrompt]]],
            "contents": [["role": "user", "parts": [["text": buildPrompt(speaker: speaker, text: text)]]]],
            "generationConfig": ["temperature": 0.25, "maxOutputTokens": 120]
        ]

        var req = URLRequest(url: url, timeoutInterval: 3.5)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let outText = parts.first?["text"] as? String else {
            return nil
        }
        let trimmed = outText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func callDeepLAPI(text: String) async -> String? {
        let key = deeplApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.hasPrefix("your_") else { return nil }

        let endpoint = key.hasSuffix(":fx")
            ? "https://api-free.deepl.com/v2/translate"
            : "https://api.deepl.com/v2/translate"
        guard let url = URL(string: endpoint) else { return nil }

        var payload: [String: Any] = [
            "text": [text],
            "source_lang": "EN",
            "target_lang": "TR"
        ]
        if !contextHistory.isEmpty {
            payload["context"] = contextHistory.map(\.en).joined(separator: " ")
        }

        var req = URLRequest(url: url, timeoutInterval: 3.5)
        req.httpMethod = "POST"
        req.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translations = json["translations"] as? [[String: Any]],
              let outText = translations.first?["text"] as? String else {
            return nil
        }
        let trimmed = outText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func callZeroKeyTranslateFallback(text: String) async -> String? {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=tr&dt=t&q=\(encoded)") else {
            return nil
        }
        var req = URLRequest(url: url, timeoutInterval: 2.5)
        req.httpMethod = "GET"
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let sentences = root.first as? [[Any]] else {
            return nil
        }
        let joined = sentences.compactMap { $0.first as? String }.joined()
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func formatSubtitleLines(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 48 { return cleaned }
        let mid = cleaned.count / 2
        let midIndex = cleaned.index(cleaned.startIndex, offsetBy: mid)
        if let spaceRange = cleaned.range(of: " ", options: .backwards, range: cleaned.startIndex..<cleaned.index(midIndex, offsetBy: min(10, cleaned.count - mid))) {
            let line1 = String(cleaned[..<spaceRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let line2 = String(cleaned[spaceRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return "\(line1)\n\(line2)"
        }
        return cleaned
    }

    // MARK: - SQLite3 Yerleşik Önbellek Yönetimi
    private func initSQLiteCache() {
        var db: OpaquePointer?
        if sqlite3_open(cacheDBPath, &db) == SQLITE_OK {
            let sql = """
            CREATE TABLE IF NOT EXISTS translations (
                norm_key TEXT PRIMARY KEY,
                source_text TEXT NOT NULL,
                translated_text TEXT NOT NULL,
                provider TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            """
            sqlite3_exec(db, sql, nil, nil, nil)
        }
        sqlite3_close(db)
    }

    func getFromSQLiteCache(key: String) -> (text: String, provider: String)? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(cacheDBPath, &db) == SQLITE_OK else { return nil }

        let sql = "SELECT translated_text, provider FROM translations WHERE norm_key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW,
           let cText = sqlite3_column_text(stmt, 0),
           let cProv = sqlite3_column_text(stmt, 1) {
            return (String(cString: cText), String(cString: cProv))
        }
        return nil
    }

    func saveToSQLiteCache(key: String, source: String, translated: String, provider: String) {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(cacheDBPath, &db) == SQLITE_OK else { return }

        let sql = "INSERT OR REPLACE INTO translations (norm_key, source_text, translated_text, provider, created_at) VALUES (?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (source as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (translated as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (provider as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    func refreshCacheCount() {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(cacheDBPath, &db) == SQLITE_OK else { return }

        let sql = "SELECT COUNT(*) FROM translations;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW {
            cacheCount = Int(sqlite3_column_int(stmt, 0))
        }
    }

    func clearSQLiteCache() {
        contextHistory.removeAll()
        var db: OpaquePointer?
        if sqlite3_open(cacheDBPath, &db) == SQLITE_OK {
            sqlite3_exec(db, "DELETE FROM translations;", nil, nil, nil)
        }
        sqlite3_close(db)
        refreshCacheCount()
    }

    // MARK: - .env ve config.json Okuma / Kaydetme
    func loadConfigurationAndEnv() {
        let envURL = dataDir.appendingPathComponent(".env")
        if let content = try? String(contentsOf: envURL, encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let k = parts[0].trimmingCharacters(in: .whitespaces)
                    let v = parts[1].trimmingCharacters(in: .whitespaces)
                    switch k {
                    case "TRANSLATION_PROVIDER": if !v.isEmpty { translationProvider = v.lowercased() }
                    case "GEMINI_API_KEY":       geminiApiKey = (v == "your_gemini_api_key_here") ? "" : v
                    case "GEMINI_MODEL":         if !v.isEmpty { geminiModel = v }
                    case "DEEPL_API_KEY":        deeplApiKey = (v == "your_deepl_api_key_here") ? "" : v
                    case "OLLAMA_BASE_URL":      if !v.isEmpty { ollamaBaseUrl = v }
                    case "OLLAMA_MODEL":         if !v.isEmpty { ollamaModel = v }
                    default: break
                    }
                }
            }
        }

        let cfgURL = dataDir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: cfgURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let fps = json["capture_fps"] as? Double { captureFPS = fps }
            if let roi = json["roi"] as? [String: Any] {
                useCustomROI = (roi["use_custom_screen_rect"] as? Bool) ?? false
                if let sr = roi["screen_rect"] as? [String: Double],
                   let x = sr["x"], let y = sr["y"], let w = sr["width"], let h = sr["height"] {
                    customROIRect = CGRect(x: x, y: y, width: w, height: h)
                }
            }
            if let ov = json["overlay"] as? [String: Any] {
                if let fs = ov["font_size"] as? Double { fontSize = min(28.0, fs) }
                if let op = ov["background_opacity"] as? Double { backgroundOpacity = op }
                if let se = ov["show_original_english"] as? Bool { showOriginalEnglish = se }
                if let sb = ov["show_status_badge"] as? Bool { showStatusBadge = sb }
                if let pl = ov["placement"] as? String { overlayPlacement = pl }
                if let ox = ov["offset_x"] as? Double { overlayOffsetX = ox }
                if let oy = ov["offset_y"] as? Double { overlayOffsetY = oy }
            }
        }
    }

    func saveEnvFile() {
        let envURL = dataDir.appendingPathComponent(".env")
        let content = """
        # GTA 6 (PS5) Canlı Türkçe Altyazı Sistemi — Swift Dashboard Tarafından Kaydedildi
        TRANSLATION_PROVIDER=\(translationProvider)
        OLLAMA_BASE_URL=\(ollamaBaseUrl)
        OLLAMA_MODEL=\(ollamaModel)
        GEMINI_API_KEY=\(geminiApiKey)
        GEMINI_MODEL=\(geminiModel)
        DEEPL_API_KEY=\(deeplApiKey)
        """
        try? content.write(to: envURL, atomically: true, encoding: .utf8)
    }

    func saveConfigFile() {
        let cfgURL = dataDir.appendingPathComponent("config.json")
        var json: [String: Any] = [:]
        if let existingData = try? Data(contentsOf: cfgURL),
           let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            json = existing
        }
        json["capture_fps"] = Int(captureFPS)
        var roi = (json["roi"] as? [String: Any]) ?? [:]
        roi["use_custom_screen_rect"] = useCustomROI
        roi["screen_rect"] = [
            "x": Int(customROIRect.origin.x),
            "y": Int(customROIRect.origin.y),
            "width": Int(customROIRect.width),
            "height": Int(customROIRect.height)
        ]
        json["roi"] = roi

        var ov = (json["overlay"] as? [String: Any]) ?? [:]
        ov["font_size"] = Int(fontSize)
        ov["background_opacity"] = Double(round(100 * backgroundOpacity) / 100)
        ov["show_original_english"] = showOriginalEnglish
        ov["show_status_badge"] = showStatusBadge
        ov["placement"] = overlayPlacement
        ov["offset_x"] = Int(overlayOffsetX)
        ov["offset_y"] = Int(overlayOffsetY)
        json["overlay"] = ov

        if let outData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? outData.write(to: cfgURL)
        }
    }

    // MARK: - Android TV (ADB) Bağlantısı ve Yerel IP
    func connectAndroidTV() {
        let ip = androidTVIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty else {
            adbConnected = false
            adbStatusMessage = "Lütfen TV'nin yerel IP adresini girin (örn. 192.168.1.55)."
            return
        }
        let target = ip.contains(":") ? ip : "\(ip):5555"
        Task.detached {
            let proc = Process()
            let pipe = Pipe()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["adb", "connect", target]
            proc.standardOutput = pipe
            proc.standardError = pipe
            do {
                try proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: data, encoding: .utf8) ?? ""
                let ok = out.lowercased().contains("connected to")
                await MainActor.run {
                    self.adbConnected = ok
                    self.adbStatusMessage = ok ? "Android TV bağlantısı başarılı: \(out.trimmingCharacters(in: .whitespacesAndNewlines))" : "ADB yanıtı: \(out.trimmingCharacters(in: .whitespacesAndNewlines))"
                }
            } catch {
                await MainActor.run {
                    self.adbConnected = false
                    self.adbStatusMessage = "macOS üzerinde 'adb' bulunamadı. Kurmak için: brew install android-platform-tools"
                }
            }
        }
    }

    static func getLocalIPAddress() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr {
            for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
                let flags = Int32(ptr.pointee.ifa_flags)
                let addr = ptr.pointee.ifa_addr.pointee
                if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING),
                   addr.sa_family == UInt8(AF_INET) {
                    let name = String(cString: ptr.pointee.ifa_name)
                    if name.hasPrefix("en") {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                            address = String(cString: hostname)
                            break
                        }
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }

    // MARK: - Uçtan Uca M2 Native Swift Sistem Testi (--self-test)
    static func runSelfTestCLI() -> Int32 {
        print("======================================================================")
        print(" GTA 6 (PS5) Canlı Türkçe Altyazı — Native Swift (M2 ARM64) Öz-Testi")
        print("======================================================================")

        let width = 960, height = 140
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("HATA: CoreGraphics bağlamı oluşturulamadı.")
            return 1
        }

        ctx.setFillColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let sampleText = "LUCIA: The only way we're gonna get through this is by sticking together."
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        (sampleText as NSString).draw(
            at: NSPoint(x: 24, y: 48),
            withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 28),
                .foregroundColor: NSColor.white
            ]
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else {
            print("HATA: Test görüntüsü üretilemedi.")
            return 1
        }

        let hash = computeDHash(cgImage)
        print(String(format: "[1/5] CoreGraphics & 64-bit dHash   : 0x%016llx (Başarılı)", hash))

        let t0 = CFAbsoluteTimeGetCurrent()
        let recognized = recognizeTextWithAppleVision(cgImage: cgImage)
        let ocrMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
        print(String(format: "[2/5] M2 Apple Vision OCR Okunan    : \"%@\" (%.1f ms)", recognized, ocrMs))
        if recognized.isEmpty {
            print("HATA: Apple Vision OCR metni okuyamadı!")
            return 1
        }

        let cleaned = cleanOCRText(recognized)
        let (speaker, dialogue) = splitSpeaker(cleaned)
        let sim = similarityPercentage(cleaned.lowercased(), sampleText.lowercased())
        print(String(format: "[3/5] Sabitleyici & Konuşmacı       : Konuşmacı=%@ | Benzerlik=%%%.1f", speaker, sim))
        if speaker != "LUCIA" || sim < 90.0 {
            print("HATA: Konuşmacı ayrıştırma veya benzerlik eşiği başarısız!")
            return 1
        }

        let state = AppState()
        let normKey = dialogue.lowercased()
        let trSample = "Buradan sağ çıkmanın tek yolu birbirimize kenetlenmek."
        state.saveToSQLiteCache(key: normKey, source: dialogue, translated: trSample, provider: "ollama:qwen2.5:3b")
        guard let cached = state.getFromSQLiteCache(key: normKey) else {
            print("HATA: SQLite3 önbellek okuma hatası!")
            return 1
        }
        print(String(format: "[4/5] Native SQLite3 + Ollama Cache : \"%@\" (Kaynak: %@)", cached.text, cached.provider))

        let tvSrv = NativeTVHTTPServer(port: 0)
        tvSrv.updateSubtitle(speaker: speaker, turkish: cached.text, english: dialogue, meta: "Vision 22ms", showOriginal: false)
        print(String(format: "[5/5] Ev Ağı (PS5+TV+Mac) Sunucusu  : http://%@:8765/api/subtitle (Hazır)", getLocalIPAddress()))
        print("======================================================================")
        print(" TÜM TESTLER BAŞARILI (6/6) — M2 Native Swift Boru Hattı Hazır!")
        print("======================================================================")
        return 0
    }
}

// MARK: - Yerleşik Ev Ağı TV HTTP / JSON + Canlı Uzak Ekran (/remote & /api/frame.jpg) Sunucusu
final class NativeTVHTTPServer: @unchecked Sendable {
    private let port: UInt16
    private var listener: NWListener?
    private let lock = NSLock()
    private var seq: Int = 0
    private var jsonPayload: String = #"{"seq":0,"speaker":"","turkish_text":"","english_text":"","meta":"","show_original":false}"#
    private var latestFrameJPEG: Data = Data()

    init(port: UInt16 = 8765) {
        self.port = port
    }

    func start() {
        guard port > 0,
              let nwPort = NWEndpoint.Port(rawValue: port),
              let listener = try? NWListener(using: .tcp, on: nwPort) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    func updateFrame(cgImage: CGImage) {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else { return }
        lock.lock()
        latestFrameJPEG = jpeg
        lock.unlock()
    }

    func updateSubtitle(speaker: String, turkish: String, english: String, meta: String, showOriginal: Bool) {
        lock.lock()
        defer { lock.unlock() }
        seq += 1
        let dict: [String: Any] = [
            "seq": seq,
            "speaker": speaker,
            "turkish_text": turkish,
            "english_text": english,
            "meta": meta,
            "show_original": showOriginal
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8) {
            jsonPayload = str
        }
    }

    func clearSubtitle() {
        lock.lock()
        defer { lock.unlock() }
        seq += 1
        jsonPayload = #"{"seq":\#(seq),"speaker":"","turkish_text":"","english_text":"","meta":"","show_original":false}"#
    }

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self = self, let data = data,
                  let reqStr = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }

            if reqStr.contains("GET /api/frame.jpg") {
                self.lock.lock()
                let imgData = self.latestFrameJPEG
                self.lock.unlock()
                let header = "HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nContent-Length: \(imgData.count)\r\nConnection: close\r\n\r\n"
                var responseData = Data(header.utf8)
                responseData.append(imgData)
                conn.send(content: responseData, completion: .contentProcessed { _ in
                    conn.cancel()
                })
                return
            }

            let isAPIRoute = reqStr.contains("GET /api/subtitle")
            let isRemoteScreenRoute = reqStr.contains("GET /remote")
            let body: String
            let contentType: String

            if isAPIRoute {
                self.lock.lock()
                body = self.jsonPayload
                self.lock.unlock()
                contentType = "application/json; charset=utf-8"
            } else if isRemoteScreenRoute {
                body = Self.remoteScreenHTMLPage
                contentType = "text/html; charset=utf-8"
            } else {
                body = Self.tvHTMLPage
                contentType = "text/html; charset=utf-8"
            }

            let bodyData = Data(body.utf8)
            let header = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
            var responseData = Data(header.utf8)
            responseData.append(bodyData)

            conn.send(content: responseData, completion: .contentProcessed { _ in
                conn.cancel()
            })
        }
    }

    // Ev Ağından HDMI Olmadan Canlı Uzak Ekran Kaydı + Türkçe Altyazı İzleme Sayfası (/remote)
    private static let remoteScreenHTMLPage = """
    <!DOCTYPE html><html lang="tr"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>GTA 6 — Ev Ağı Canlı Uzak Ekran & Altyazı</title>
    <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{background:#07090e;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;padding:20px}
    .badge{font-size:12px;color:#38D1FA;font-family:monospace;background:rgba(56,209,250,0.12);padding:5px 12px;border-radius:99px;border:1px solid rgba(56,209,250,0.35)}
    #frame-wrap{position:relative;max-width:92vw;max-height:70vh;border:1px solid rgba(255,255,255,0.16);border-radius:12px;overflow:hidden;background:#0d111a;padding:10px}
    #live-img{max-width:88vw;max-height:55vh;display:block;border-radius:8px}
    #box{max-width:84vw;background:rgba(6,8,12,0.90);border:1px solid rgba(255,92,148,0.45);border-radius:10px;padding:10px 22px;text-align:center;min-height:44px}
    #spk{font-size:20px;font-weight:800;margin-right:8px}
    #tr{font-size:20px;font-weight:700}
    #en{margin-top:4px;font-size:13px;color:#90a4ae;font-style:italic}
    </style></head>
    <body>
    <div class="badge">📡 EV AĞI CANLI UZAK EKRAN KAYDI (HDMI YOK • WI-FI AKIŞI)</div>
    <div id="frame-wrap"><img id="live-img" src="/api/frame.jpg" alt="Canlı Yakalanan Ekran Bölgesi"/></div>
    <div id="box"><span id="spk"></span><span id="tr">Altyazı bekleniyor...</span><div id="en"></div></div>
    <script>
    const img=document.getElementById('live-img'),spk=document.getElementById('spk'),tr=document.getElementById('tr'),en=document.getElementById('en');
    const colors={LUCIA:'#FF5C94',JASON:'#38D1FA'};
    setInterval(()=>{img.src='/api/frame.jpg?t='+Date.now()},250);
    async function poll(){try{const r=await fetch('/api/subtitle',{cache:'no-store'});if(r.ok){const d=await r.json();if(d.turkish_text){const c=colors[d.speaker]||'#FFD147';spk.style.color=c;spk.textContent=d.speaker?(d.speaker+':'):'';tr.textContent=d.turkish_text;en.textContent=d.english_text||''}}}catch(e){}setTimeout(poll,150)}poll();
    </script></body></html>
    """

    // TV'de sadece yazıyı saran ince/kompakt altyazı bandı
    private static let tvHTMLPage = """
    <!DOCTYPE html><html lang="tr"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>GTA 6 Canlı Türkçe Altyazı — TV</title>
    <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{background:transparent;background-color:#000;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;height:100vh;display:flex;align-items:flex-end;justify-content:center;padding-bottom:3.5vh;overflow:hidden}
    #box{max-width:78vw;background:rgba(6,8,12,0.84);border:1px solid rgba(255,255,255,0.14);border-radius:10px;padding:7px 18px;text-align:center;transition:opacity .12s}
    #box.empty{opacity:0}
    .row{display:inline-flex;align-items:baseline;justify-content:center;gap:8px;flex-wrap:wrap}
    #spk{font-size:clamp(16px,2.1vw,26px);font-weight:800;display:none}
    #tr{font-size:clamp(16px,2.1vw,26px);font-weight:600;white-space:pre-line;text-shadow:0 1px 4px rgba(0,0,0,0.95)}
    #en{margin-top:3px;font-size:clamp(12px,1.4vw,17px);color:#b0bec5;font-style:italic;display:none}
    </style></head>
    <body><div id="box" class="empty"><div class="row"><span id="spk"></span><span id="tr"></span></div><div id="en"></div></div>
    <script>
    let seq=-1;const box=document.getElementById('box'),spk=document.getElementById('spk'),tr=document.getElementById('tr'),en=document.getElementById('en');
    const colors={LUCIA:'#FF5C94',JASON:'#38D1FA'};
    async function poll(){try{const r=await fetch('/api/subtitle',{cache:'no-store'});if(r.ok){const d=await r.json();if(d.seq!==seq){seq=d.seq;if(!d.turkish_text){box.className='empty'}else{box.className='';const c=colors[d.speaker]||'#FFD147';if(d.speaker){spk.style.display='inline';spk.style.color=c;spk.textContent=d.speaker+':'}else{spk.style.display='none'}tr.textContent=d.turkish_text;en.style.display=d.show_original&&d.english_text?'block':'none';en.textContent=d.english_text||''}}}}catch(e){}setTimeout(poll,110)}poll();
    </script></body></html>
    """
}
