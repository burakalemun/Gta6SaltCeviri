import AppKit
import SwiftUI

@main
struct GTA6AltyaziApp: App {
    @StateObject private var appState = AppState()

    init() {
        if CommandLine.arguments.contains("--self-test") {
            let code = AppState.runSelfTestCLI()
            exit(code)
        }
    }

    var body: some Scene {
        WindowGroup("SaltÇeviri — Canlı Ekran & PS5 Türkçe Altyazı") {
            DashboardView(state: appState)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    appState.startPipeline()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1060, height: 700)

        MenuBarExtra("SaltÇeviri", systemImage: "captions.bubble.fill") {
            Button(appState.isPaused ? "▶ Canlı Çeviriyi Başlat" : "⏸ Yakalamayı Duraklat") {
                appState.togglePause()
            }
            Divider()
            Button("🎯 Fareyle Altyazı Bölgesi Seç (ROI)") {
                appState.selectROIFromScreen()
            }
            Button("🖥 Otomatik Remote Play Penceresi") {
                appState.switchToAutoWindowMode()
            }
            Button("🎬 Test Repliği Gönder (Lucia / Jason)") {
                appState.triggerDemoSubtitle()
            }
            Divider()
            Button("Çıkış") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
