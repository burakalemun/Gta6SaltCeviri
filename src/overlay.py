from __future__ import annotations

import logging
from typing import Any, Callable, Dict, Optional, Tuple

from PyQt6.QtCore import QPoint, QRect, Qt, pyqtSignal
from PyQt6.QtGui import (
    QColor,
    QFont,
    QGuiApplication,
     QKeyEvent,
    QMouseEvent,
    QPainter,
    QPainterPath,
    QPen,
)
from PyQt6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

try:
    import objc
    from AppKit import (
        NSFloatingWindowLevel,
        NSStatusWindowLevel,
        NSWindowCollectionBehaviorCanJoinAllSpaces,
        NSWindowCollectionBehaviorFullScreenAuxiliary,
    )

    HAS_APPKIT = True
except ImportError:
    HAS_APPKIT = False

logger = logging.getLogger(__name__)


class SubtitleOverlayWindow(QWidget):
    """
    Orijinal İngilizce altyazının tam üzerine oturan, tıklamaları alta geçiren
    (click-through) ve macOS Tam Ekran / AirPlay 2 ile uyumlu Türkçe altyazı katmanı.
    """

    def __init__(self, config: Dict[str, Any]) -> None:
        super().__init__(None)
        self.config = config
        overlay_cfg = config.get("overlay", {})

        self.font_family: str = str(overlay_cfg.get("font_family", "Helvetica Neue"))
        self.font_size: int = int(overlay_cfg.get("font_size", 26))
        self.original_font_size: int = int(overlay_cfg.get("original_font_size", 14))
        self.bg_opacity: float = float(overlay_cfg.get("background_opacity", 0.88))
        self.border_radius: int = int(overlay_cfg.get("border_radius", 10))
        self.padding_x: int = int(overlay_cfg.get("padding_x", 24))
        self.padding_y: int = int(overlay_cfg.get("padding_y", 14))
        self.show_original: bool = bool(
            overlay_cfg.get("show_original_english", False)
        )
        self.show_status_badge: bool = bool(
            overlay_cfg.get("show_status_badge", True)
        )
        self.speaker_colors: Dict[str, str] = dict(
            overlay_cfg.get(
                "speaker_colors",
                {
                    "LUCIA": "#FF6B9D",
                    "JASON": "#4FC3F7",
                    "DEFAULT": "#FFD54F",
                },
            )
        )

        self._speaker: Optional[str] = None
        self._turkish_text: str = ""
        self._english_text: str = ""
        self._status_meta: str = ""

        self._init_window_flags()

    def _init_window_flags(self) -> None:
        flags = (
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
            | Qt.WindowType.WindowDoesNotAcceptFocus
        )
        self.setWindowFlags(flags)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, True)
        self.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents, True)
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating, True)

        # Varsayılan başlangıç konumu
        roi_rect = self.config.get("roi", {}).get("screen_rect", {})
        x = int(roi_rect.get("x", 260))
        y = int(roi_rect.get("y", 720))
        w = int(roi_rect.get("width", 920))
        h = int(roi_rect.get("height", 160))
        self.setGeometry(x, y, w, h)

    def configure_macos_native_window(self) -> Optional[int]:
        """
        macOS NSWindow ayarlarını yapılandırır:
        - Tıklama geçirgenliği (ignoresMouseEvents)
        - Tam ekran (Full Screen) ve tüm masaüstü alanlarında (Spaces) görünürlük
        - Kendi penceremizi ekran yakalamadan hariç tutmak için CGWindowID döndürür.
        """
        if not HAS_APPKIT:
            return None
        try:
            view_ptr = int(self.winId())
            ns_view = objc.objc_object(c_void_p=view_ptr)
            ns_window = ns_view.window()
            if ns_window is None:
                return None

            ns_window.setIgnoresMouseEvents_(True)
            ns_window.setLevel_(NSStatusWindowLevel)
            behavior = (
                NSWindowCollectionBehaviorCanJoinAllSpaces
                | NSWindowCollectionBehaviorFullScreenAuxiliary
            )
            ns_window.setCollectionBehavior_(behavior)
            win_number = int(ns_window.windowNumber())
            return win_number if win_number > 0 else None
        except Exception as exc:
            logger.debug("macOS NSWindow yapılandırma uyarısı: %s", exc)
            return None

    def align_to_roi(self, screen_rect: Tuple[int, int, int, int]) -> None:
        """Overlay penceresini yakalanan altyazı bölgesinin (ROI) tam üzerine hizalar."""
        if not self.config.get("overlay", {}).get("auto_cover_roi", True):
            return
        rx, ry, rw, rh = screen_rect
        current = self.geometry()
        if (current.x(), current.y(), current.width(), current.height()) != (
            rx,
            ry,
            rw,
            rh,
        ):
            self.setGeometry(rx, ry, rw, rh)

    def update_subtitle(
        self,
        speaker: Optional[str],
        turkish_text: str,
        english_text: str = "",
        status_meta: str = "",
    ) -> None:
        """Ekrandaki Türkçe altyazıyı günceller ve yeniden çizer."""
        self._speaker = speaker
        self._turkish_text = turkish_text.strip()
        self._english_text = english_text.strip()
        self._status_meta = status_meta.strip()
        if not self.isVisible():
            self.show()
        self.update()

    def clear_subtitle(self) -> None:
        """Altyazıyı temizler (arka plan kutusunu gizler)."""
        if self._turkish_text or self._english_text:
            self._speaker = None
            self._turkish_text = ""
            self._english_text = ""
            self._status_meta = ""
            self.update()

    def toggle_original_english(self) -> bool:
        self.show_original = not self.show_original
        self.update()
        return self.show_original

    def apply_appearance_settings(
        self,
        font_size: Optional[int] = None,
        bg_opacity: Optional[float] = None,
        show_original: Optional[bool] = None,
        show_status_badge: Optional[bool] = None,
    ) -> None:
        """Dashboard üzerinden değiştirilen yazı boyutu ve opaklık ayarlarını canlı uygular."""
        if font_size is not None:
            self.font_size = max(14, min(56, int(font_size)))
        if bg_opacity is not None:
            self.bg_opacity = max(0.2, min(1.0, float(bg_opacity)))
        if show_original is not None:
            self.show_original = bool(show_original)
        if show_status_badge is not None:
            self.show_status_badge = bool(show_status_badge)
        self.update()

    def paintEvent(self, event: Any) -> None:
        if not self._turkish_text:
            return

        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        painter.setRenderHint(QPainter.RenderHint.TextAntialiasing, True)

        rect = self.rect().adjusted(6, 6, -6, -6)

        # 1) Orijinal İngilizce altyazıyı örten koyu yarı-opak/opak kutu
        path = QPainterPath()
        path.addRoundedRect(
            float(rect.x()),
            float(rect.y()),
            float(rect.width()),
            float(rect.height()),
            float(self.border_radius),
            float(self.border_radius),
        )
        bg_alpha = int(max(0.2, min(1.0, self.bg_opacity)) * 255)
        painter.fillPath(path, QColor(10, 12, 16, bg_alpha))

        # İnce çerçeve
        pen = QPen(QColor(255, 255, 255, 38))
        pen.setWidth(1)
        painter.setPen(pen)
        painter.drawPath(path)

        content_rect = rect.adjusted(
            self.padding_x, self.padding_y, -self.padding_x, -self.padding_y
        )

        # 2) Konuşmacı + Türkçe Altyazı Metni
        main_font = QFont(self.font_family, self.font_size)
        main_font.setBold(True)
        painter.setFont(main_font)

        display_text = self._turkish_text
        if self._speaker:
            display_text = f"{self._speaker}: {self._turkish_text}"

        text_rect = QRect(content_rect)
        if self.show_original and self._english_text:
            text_rect.setHeight(int(content_rect.height() * 0.68))

        # Metin gölgesi (TV uzaktan okumada maksimum netlik)
        shadow_rect = text_rect.translated(2, 2)
        painter.setPen(QColor(0, 0, 0, 230))
        painter.drawText(
            shadow_rect,
            Qt.AlignmentFlag.AlignCenter | Qt.TextFlag.TextWordWrap,
            display_text,
        )

        # Konuşmacı rengi veya parlak beyaz/sarı metin
        if self._speaker:
            spk_hex = self.speaker_colors.get(
                self._speaker.upper(),
                self.speaker_colors.get("DEFAULT", "#FFD54F"),
            )
            painter.setPen(QColor(spk_hex))
        else:
            painter.setPen(QColor("#FFFFFF"))

        painter.drawText(
            text_rect,
            Qt.AlignmentFlag.AlignCenter | Qt.TextFlag.TextWordWrap,
            display_text,
        )

        # 3) Opsiyonel Orijinal İngilizce Alt Satırı
        if self.show_original and self._english_text:
            orig_font = QFont(self.font_family, self.original_font_size)
            orig_font.setItalic(True)
            painter.setFont(orig_font)
            painter.setPen(QColor(185, 195, 210, 215))
            orig_rect = QRect(
                content_rect.x(),
                text_rect.bottom() + 2,
                content_rect.width(),
                content_rect.height() - text_rect.height(),
            )
            painter.drawText(
                orig_rect,
                Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignTop,
                self._english_text,
            )

        # 4) Sağ alt köşede küçük gecikme/kaynak rozeti
        if self.show_status_badge and self._status_meta:
            badge_font = QFont(self.font_family, 10)
            painter.setFont(badge_font)
            painter.setPen(QColor(150, 165, 180, 165))
            painter.drawText(
                rect.adjusted(8, 4, -10, -4),
                Qt.AlignmentFlag.AlignBottom | Qt.AlignmentFlag.AlignRight,
                self._status_meta,
            )


class ROISelectorWindow(QWidget):
    """
    Fare ile PS Remote Play penceresindeki altyazı bölgesini (ROI)
    sürükleyip seçmeyi sağlayan tam ekran kalibrasyon katmanı.
    """

    roi_selected = pyqtSignal(int, int, int, int)

    def __init__(self) -> None:
        super().__init__(None)
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, True)
        self.setCursor(Qt.CursorShape.CrossCursor)

        screen = QGuiApplication.primaryScreen()
        if screen is not None:
            self.setGeometry(screen.geometry())
        else:
            self.setGeometry(0, 0, 1440, 900)

        self._start_pos: Optional[QPoint] = None
        self._end_pos: Optional[QPoint] = None

    def mousePressEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton:
            self._start_pos = event.pos()
            self._end_pos = event.pos()
            self.update()

    def mouseMoveEvent(self, event: QMouseEvent) -> None:
        if self._start_pos is not None:
            self._end_pos = event.pos()
            self.update()

    def mouseReleaseEvent(self, event: QMouseEvent) -> None:
        if event.button() == Qt.MouseButton.LeftButton and self._start_pos and self._end_pos:
            rect = QRect(self._start_pos, self._end_pos).normalized()
            self._start_pos = None
            self._end_pos = None
            self.close()
            if rect.width() >= 60 and rect.height() >= 25:
                self.roi_selected.emit(
                    rect.x(), rect.y(), rect.width(), rect.height()
                )

    def keyPressEvent(self, event: QKeyEvent) -> None:
        if event.key() == Qt.Key.Key_Escape:
            self.close()

    def paintEvent(self, event: Any) -> None:
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        painter.fillRect(self.rect(), QColor(0, 0, 0, 110))

        # Üst bilgi metni
        font = QFont("Helvetica Neue", 18)
        font.setBold(True)
        painter.setFont(font)
        painter.setPen(QColor("#FFFFFF"))
        painter.drawText(
            QRect(0, 40, self.width(), 50),
            Qt.AlignmentFlag.AlignCenter,
            "Fareyle PS Remote Play Altyazı Bölgesini Seçin (İptal: ESC)",
        )

        if self._start_pos and self._end_pos:
            sel_rect = QRect(self._start_pos, self._end_pos).normalized()
            painter.setCompositionMode(
                QPainter.CompositionMode.CompositionMode_Clear
            )
            painter.fillRect(sel_rect, Qt.GlobalColor.transparent)
            painter.setCompositionMode(
                QPainter.CompositionMode.CompositionMode_SourceOver
            )
            pen = QPen(QColor("#00E676"), 2)
            painter.setPen(pen)
            painter.drawRect(sel_rect)


class ControlPanelWindow(QWidget):
    """
    MacBook Pro ekranının üst köşesinde duran kompakt kontrol çubuğu:
    - Duraklat / Başlat
    - Fareyle Altyazı Bölgesi (ROI) Seç
    - Otomatik Remote Play Penceresi Modu
    - Orijinal İngilizce Aç/Kapat
    - Test Repliği Gönder
    """

    def __init__(
        self,
        on_toggle_pause: Callable[[], bool],
        on_select_roi: Callable[[], None],
        on_auto_roi: Callable[[], None],
        on_toggle_english: Callable[[], bool],
        on_trigger_demo: Callable[[], None],
        on_quit: Callable[[], None],
        on_open_dashboard: Optional[Callable[[], None]] = None,
    ) -> None:
        super().__init__(None)
        self._on_toggle_pause = on_toggle_pause
        self._on_select_roi = on_select_roi
        self._on_auto_roi = on_auto_roi
        self._on_toggle_english = on_toggle_english
        self._on_trigger_demo = on_trigger_demo
        self._on_quit = on_quit
        self._on_open_dashboard = on_open_dashboard

        self.setWindowTitle("GTA 6 PS5 Canlı Altyazı — M2 Kontrol Paneli")
        self.setWindowFlags(
            Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
        )
        self.setStyleSheet(
            """
            QWidget {
                background-color: #141820;
                color: #ECEFF4;
                font-family: 'Helvetica Neue';
                font-size: 12px;
            }
            QPushButton {
                background-color: #242B38;
                border: 1px solid #364156;
                border-radius: 6px;
                padding: 5px 10px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #323C4E;
            }
            QLabel#statusLabel {
                color: #88C0D0;
                font-size: 11px;
            }
            """
        )

        layout = QVBoxLayout(self)
        layout.setContentsMargins(10, 8, 10, 8)
        layout.setSpacing(6)

        btn_row = QHBoxLayout()
        btn_row.setSpacing(6)

        if self._on_open_dashboard is not None:
            self.btn_dash = QPushButton("⚙ Dashboard")
            self.btn_dash.setStyleSheet(
                "background-color: #1A3A4F; border-color: #29B6F6; color: #FFFFFF;"
            )
            self.btn_dash.clicked.connect(self._on_open_dashboard)
            btn_row.addWidget(self.btn_dash)

        self.btn_pause = QPushButton("Duraklat")
        self.btn_pause.clicked.connect(self._handle_pause)
        btn_row.addWidget(self.btn_pause)

        self.btn_roi = QPushButton("Bölge Seç (ROI)")
        self.btn_roi.clicked.connect(self._on_select_roi)
        btn_row.addWidget(self.btn_roi)

        self.btn_auto = QPushButton("Oto Pencere")
        self.btn_auto.clicked.connect(self._on_auto_roi)
        btn_row.addWidget(self.btn_auto)

        self.btn_eng = QPushButton("EN: Kapalı")
        self.btn_eng.clicked.connect(self._handle_toggle_eng)
        btn_row.addWidget(self.btn_eng)

        self.btn_demo = QPushButton("Test Repliği")
        self.btn_demo.clicked.connect(self._on_trigger_demo)
        btn_row.addWidget(self.btn_demo)

        self.btn_quit = QPushButton("Çıkış")
        self.btn_quit.setStyleSheet(
            "background-color: #4C232A; border-color: #7A3540;"
        )
        self.btn_quit.clicked.connect(self._on_quit)
        btn_row.addWidget(self.btn_quit)

        layout.addLayout(btn_row)

        self.status_label = QLabel("Durum: Başlatılıyor... (M2 Apple Vision OCR Hazır)")
        self.status_label.setObjectName("statusLabel")
        layout.addWidget(self.status_label)

        self.move(24, 36)

    def _handle_pause(self) -> None:
        paused = self._on_toggle_pause()
        self.btn_pause.setText("Devam Et" if paused else "Duraklat")

    def _handle_toggle_eng(self) -> None:
        shown = self._on_toggle_english()
        self.btn_eng.setText("EN: Açık" if shown else "EN: Kapalı")

    def set_status_text(self, text: str) -> None:
        self.status_label.setText(text)
