import AppKit
import SwiftUI

// MARK: - Vice City / Leonida Premium Renk Paleti
extension Color {
    static let luciaPink    = Color(red: 1.00, green: 0.36, blue: 0.58) // #FF5C94
    static let jasonCyan    = Color(red: 0.22, green: 0.82, blue: 0.98) // #38D1FA
    static let viceGold     = Color(red: 1.00, green: 0.82, blue: 0.28) // #FFD147
    static let neonEmerald  = Color(red: 0.00, green: 0.92, blue: 0.54) // #00EB8A
    static let bgDeep       = Color(red: 0.04, green: 0.05, blue: 0.09)
    static let bgCard       = Color(red: 0.08, green: 0.10, blue: 0.16)
    static let bgCardHover  = Color(red: 0.11, green: 0.14, blue: 0.22)

    static func speakerColor(for speaker: String) -> Color {
        switch speaker.uppercased() {
        case "LUCIA":    return .luciaPink
        case "JASON":    return .jasonCyan
        case "DRE'QUAN": return Color(red: 0.76, green: 0.48, blue: 0.98)
        case "BOOBIE":   return .viceGold
        default:         return .viceGold
        }
    }
}

// MARK: - Kompakt, Sadece Metni Saran Ekran Üstü Türkçe Altyazı Görünümü (SwiftUI)
struct SubtitleOverlayView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            if !state.currentTurkishSubtitle.isEmpty {
                VStack(spacing: 2) {
                    // Tek/Çift Satır Kompakt Altyazı Metni
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if !state.currentSpeaker.isEmpty {
                            Text("\(state.currentSpeaker):")
                                .font(.system(size: CGFloat(state.fontSize), weight: .heavy, design: .rounded))
                                .foregroundColor(Color.speakerColor(for: state.currentSpeaker))
                                .shadow(color: .black.opacity(0.95), radius: 2, x: 0, y: 1)
                        }

                        Text(state.currentTurkishSubtitle)
                            .font(.system(size: CGFloat(state.fontSize), weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.95), radius: 2, x: 0, y: 1)
                            .lineLimit(2)
                    }

                    // Opsiyonel Orijinal İngilizce Alt Satırı
                    if state.showOriginalEnglish && !state.currentEnglishSubtitle.isEmpty {
                        Text(state.currentEnglishSubtitle)
                            .font(.system(size: CGFloat(max(11, state.fontSize - 7)), weight: .regular).italic())
                            .foregroundColor(Color(white: 0.75))
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                    }

                    // Opsiyonel Küçük Hız Rozeti (Varsayılan kapalı, yer kaplamaz)
                    if state.showStatusBadge && !state.currentLatencyBadge.isEmpty {
                        Text(state.currentLatencyBadge)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.60))
                    }

                    if state.isOverlayDraggable {
                        Text("✋ Fareyle sürükleyip istediğiniz yere bırakın")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.jasonCyan)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(state.backgroundOpacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    state.isOverlayDraggable ? Color.jasonCyan : Color.white.opacity(0.12),
                                    lineWidth: state.isOverlayDraggable ? 1.8 : 0.8
                                )
                        )
                )
                .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

// MARK: - Tıklama Geçirgen / Konumu Ayarlanabilir macOS NSPanel (Overlay Penceresi)
@MainActor
final class SubtitleOverlayController {
    private var panel: NSPanel?
    private weak var appState: AppState?

    init(state: AppState) {
        self.appState = state
        setupPanel(state: state)
    }

    private func setupPanel(state: AppState) {
        let initialFrame = NSRect(x: 320, y: 120, width: 780, height: 84)
        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: SubtitleOverlayView(state: state))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    var windowNumber: CGWindowID {
        guard let num = panel?.windowNumber, num > 0 else { return 0 }
        return CGWindowID(num)
    }

    func setDraggable(_ draggable: Bool) {
        guard let panel = panel else { return }
        panel.ignoresMouseEvents = !draggable
        panel.isMovableByWindowBackground = draggable
    }

    /// Yakalanan ROI bölgesine, seçilen konum moduna (Üstü / Altı / Ekran Altı / Üzeri)
    /// ve X/Y piksel kaydırma (offset) değerlerine göre altyazı katmanını konumlandırır.
    func updatePosition(
        roiQuartzRect: CGRect,
        placement: String,
        offsetX: Double,
        offsetY: Double,
        isDraggable: Bool
    ) {
        guard let panel = panel,
              let primaryScreen = NSScreen.screens.first else { return }

        setDraggable(isDraggable)
        // Kullanıcı fareyle sürükleme modundaysa pencereyi zorla eski yere çekme
        if isDraggable || placement == "custom_drag" {
            return
        }

        let screenW = primaryScreen.frame.width
        let screenH = primaryScreen.frame.height
        let overlayH: CGFloat = 86.0
        let overlayW: CGFloat = max(420.0, min(screenW - 40.0, roiQuartzRect.width + 80.0))

        let roiCocoaY = screenH - (roiQuartzRect.origin.y + roiQuartzRect.height)
        let roiCenterX = roiQuartzRect.origin.x + (roiQuartzRect.width / 2.0)

        var targetX: CGFloat
        var targetY: CGFloat

        switch placement {
        case "above":
            // Yakalanan bölgenin TAM ÜSTÜNE (Pixel Top) yerleştir — okunan alanı asla kapatmaz!
            targetX = roiCenterX - (overlayW / 2.0)
            targetY = roiCocoaY + roiQuartzRect.height + 10.0
        case "below":
            // Yakalanan bölgenin TAM ALTINA yerleştir
            targetX = roiCenterX - (overlayW / 2.0)
            targetY = roiCocoaY - overlayH - 10.0
        case "screen_bottom":
            // Ekranın alt ortasına sabitle
            targetX = (screenW - overlayW) / 2.0
            targetY = 48.0
        case "screen_top":
            // Ekranın üst ortasına sabitle
            targetX = (screenW - overlayW) / 2.0
            targetY = screenH - overlayH - 52.0
        default: // "inside" — doğrudan seçilen bölgenin üzerine
            targetX = roiCenterX - (overlayW / 2.0)
            targetY = roiCocoaY
        }

        // Kullanıcının verdiği X ve Y piksel kaydırmalarını uygula (offsetY: negatif = yukarı, pozitif = aşağı)
        targetX += CGFloat(offsetX)
        targetY -= CGFloat(offsetY)

        // Ekran sınırları içinde tut
        targetX = max(8.0, min(screenW - overlayW - 8.0, targetX))
        targetY = max(8.0, min(screenH - overlayH - 8.0, targetY))

        let targetFrame = NSRect(
            x: round(targetX),
            y: round(targetY),
            width: round(overlayW),
            height: overlayH
        )
        if panel.frame != targetFrame {
            panel.setFrame(targetFrame, display: true)
        }
    }
}

// MARK: - Fareyle Sürükle-Bırak Altyazı Bölgesi (ROI) Seçici Pencere
@MainActor
final class ROISelectorOverlay: NSWindow {
    static func present(onSelected: @escaping (CGRect, CGImage?) -> Void) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        // Bölge seçerken kendi Dashboard penceremizi geçici olarak gizle ki arkadaki oyun/tarayıcı/ekran görünsün
        let visibleAppWindows = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
        for win in visibleAppWindows {
            win.orderOut(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let window = ROISelectorOverlay(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let restoreDashboard = {
                for win in visibleAppWindows {
                    win.makeKeyAndOrderFront(nil)
                }
            }

            let view = ROISelectionCanvasView(frame: NSRect(origin: .zero, size: screen.frame.size)) { localCocoaRect in
                let screenCocoaRect = window.convertToScreen(localCocoaRect)
                let primaryHeight = (NSScreen.screens.first?.frame.height) ?? screen.frame.height
                let quartzY = primaryHeight - (screenCocoaRect.origin.y + screenCocoaRect.height)
                let quartzRect = CGRect(
                    x: round(screenCocoaRect.origin.x),
                    y: round(quartzY),
                    width: round(screenCocoaRect.width),
                    height: round(screenCocoaRect.height)
                )
                let selectorWinID = CGWindowID(max(0, window.windowNumber))
                // Seçim penceresinin hemen ALTINDAKİ gerçek ekran görüntüsünü yakala
                let immediateImage = CGWindowListCreateImage(
                    quartzRect,
                    selectorWinID > 0 ? .optionOnScreenBelowWindow : .optionOnScreenOnly,
                    selectorWinID > 0 ? selectorWinID : kCGNullWindowID,
                    .bestResolution
                )
                window.orderOut(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    restoreDashboard()
                    onSelected(quartzRect, immediateImage)
                }
            } onCancel: {
                window.orderOut(nil)
                restoreDashboard()
            }

            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

final class ROISelectionCanvasView: NSView {
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private let onComplete: (NSRect) -> Void
    private let onCancel: () -> Void

    init(frame frameRect: NSRect, onComplete: @escaping (NSRect) -> Void, onCancel: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancel()
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let s = startPoint, let c = currentPoint else {
            onCancel()
            return
        }
        let rect = NSRect(
            x: min(s.x, c.x),
            y: min(s.y, c.y),
            width: abs(c.x - s.x),
            height: abs(c.y - s.y)
        )
        if rect.width >= 60 && rect.height >= 25 {
            onComplete(rect)
        } else {
            onCancel()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.52).setFill()
        dirtyRect.fill()

        let title = "PS Remote Play Altyazı Bölgesini Fareyle Seçin (İptal: ESC)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 21),
            .foregroundColor: NSColor.white
        ]
        let size = title.size(withAttributes: attrs)
        let titlePoint = NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height - 84)
        title.draw(at: titlePoint, withAttributes: attrs)

        if let s = startPoint, let c = currentPoint {
            let sel = NSRect(
                x: min(s.x, c.x),
                y: min(s.y, c.y),
                width: abs(c.x - s.x),
                height: abs(c.y - s.y)
            )
            NSColor.clear.setFill()
            sel.fill(using: .copy)

            NSColor(calibratedRed: 0.22, green: 0.82, blue: 0.98, alpha: 1.0).setStroke()
            let path = NSBezierPath(rect: sel)
            path.lineWidth = 2.5
            path.stroke()
        }
    }
}
