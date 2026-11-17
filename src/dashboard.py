from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any, Callable, Dict, Optional

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QColor, QFont
from PyQt6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QFormLayout,
    QFrame,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QSlider,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)


class DashboardWindow(QMainWindow):
    """
    GTA 6 (PS5) Canlı Türkçe Altyazı Sistemi — M2 MacBook Pro Kontrol Merkezi (Dashboard).
    Terminal veya .env dosyası düzenlemeye gerek kalmadan tüm ayarları,
    API anahtarlarını, ROI seçimini ve canlı altyazı geçmişini yönetir.
    """

    def __init__(
        self,
        config: Dict[str, Any],
        env_values: Dict[str, str],
        cache_count_fn: Callable[[], int],
        on_toggle_pause: Callable[[], bool],
        on_select_roi: Callable[[], None],
        on_auto_roi: Callable[[], None],
        on_trigger_demo: Callable[[], None],
        on_save_api_settings: Callable[[Dict[str, str]], None],
        on_appearance_changed: Callable[[int, float, bool, bool, int], None],
        on_clear_cache: Callable[[], None],
        on_quit: Callable[[], None],
        tv_server_url: str = "http://127.0.0.1:8765",
        on_connect_adb: Optional[Callable[[str], tuple[bool, str]]] = None,
    ) -> None:
        super().__init__(None)
        self.config = config
        self.env_values = env_values
        self._cache_count_fn = cache_count_fn
        self._on_toggle_pause = on_toggle_pause
        self._on_select_roi = on_select_roi
        self._on_auto_roi = on_auto_roi
        self._on_trigger_demo = on_trigger_demo
        self._on_save_api_settings = on_save_api_settings
        self._on_appearance_changed = on_appearance_changed
        self._on_clear_cache = on_clear_cache
        self._on_quit = on_quit
        self.tv_server_url = tv_server_url
        self._on_connect_adb = on_connect_adb

        self.setWindowTitle("GTA 6 (PS5) Canlı Türkçe Altyazı — M2 Kontrol Merkezi")
        self.resize(860, 620)
        self._apply_theme()
        self._build_ui()
        self.refresh_cache_badge()

    def _apply_theme(self) -> None:
        self.setStyleSheet(
            """
            QMainWindow, QWidget#centralWidget {
                background-color: #0F131A;
                color: #ECEFF4;
                font-family: 'Helvetica Neue';
                font-size: 13px;
            }
            QFrame#statCard {
                background-color: #181F2C;
                border: 1px solid #2A354B;
                border-radius: 10px;
                padding: 10px;
            }
            QLabel#cardTitle {
                color: #8F9EB5;
                font-size: 11px;
                font-weight: bold;
            }
            QLabel#cardValue {
                color: #FFFFFF;
                font-size: 16px;
                font-weight: bold;
            }
            QLabel#heroTitle {
                color: #FF6B9D;
                font-size: 20px;
                font-weight: bold;
            }
            QLabel#heroSubtitle {
                color: #9AA8BE;
                font-size: 12px;
            }
            QPushButton {
                background-color: #232C3D;
                color: #ECEFF4;
                border: 1px solid #384661;
                border-radius: 8px;
                padding: 8px 14px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #2E3A50;
            }
            QPushButton#primaryBtn {
                background-color: #E91E63;
                border-color: #FF6090;
                color: #FFFFFF;
            }
            QPushButton#primaryBtn:hover {
                background-color: #F06292;
            }
            QPushButton#accentBtn {
                background-color: #0288D1;
                border-color: #29B6F6;
                color: #FFFFFF;
            }
            QPushButton#accentBtn:hover {
                background-color: #039BE5;
            }
            QPushButton#dangerBtn {
                background-color: #4A2028;
                border-color: #7D3542;
                color: #FFCDD2;
            }
            QTabWidget::pane {
                border: 1px solid #2A354B;
                border-radius: 8px;
                background-color: #151B26;
            }
            QTabBar::tab {
                background-color: #181F2C;
                color: #9AA8BE;
                padding: 9px 16px;
                border-top-left-radius: 8px;
                border-top-right-radius: 8px;
                margin-right: 4px;
                font-weight: bold;
            }
            QTabBar::tab:selected {
                background-color: #253044;
                color: #4FC3F7;
            }
            QLineEdit, QComboBox {
                background-color: #10151E;
                border: 1px solid #32405A;
                border-radius: 6px;
                padding: 7px 10px;
                color: #FFFFFF;
            }
            QListWidget {
                background-color: #0E1219;
                border: 1px solid #263145;
                border-radius: 8px;
                padding: 6px;
                color: #E5E9F0;
            }
            QGroupBox {
                border: 1px solid #2A354B;
                border-radius: 8px;
                margin-top: 10px;
                padding-top: 12px;
                font-weight: bold;
                color: #4FC3F7;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 12px;
                padding: 0 6px;
            }
            """
        )

    def _build_ui(self) -> None:
        central = QWidget()
        central.setObjectName("centralWidget")
        self.setCentralWidget(central)

        root_layout = QVBoxLayout(central)
        root_layout.setContentsMargins(18, 16, 18, 16)
        root_layout.setSpacing(14)

        # 1) Üst Başlık (Header)
        header_row = QHBoxLayout()
        title_col = QVBoxLayout()
        hero_title = QLabel("GTA 6 (PS5) Canlı Türkçe Altyazı Sistemi")
        hero_title.setObjectName("heroTitle")
        hero_sub = QLabel(
            "Apple Silicon M2 Neural Engine (Vision OCR) + Hibrit Yapay Zeka Çeviri + Tıklama Geçirgen TV Katmanı"
        )
        hero_sub.setObjectName("heroSubtitle")
        title_col.addWidget(hero_title)
        title_col.addWidget(hero_sub)
        header_row.addLayout(title_col)
        header_row.addStretch()

        self.btn_quit = QPushButton("Uygulamadan Çık")
        self.btn_quit.setObjectName("dangerBtn")
        self.btn_quit.clicked.connect(self._on_quit)
        header_row.addWidget(self.btn_quit)
        root_layout.addLayout(header_row)

        # 2) Canlı Durum Kartları (4 Kart)
        cards_grid = QGridLayout()
        cards_grid.setSpacing(10)

        self.lbl_state_val = QLabel("Aktif (Dinleniyor)")
        self.lbl_source_val = QLabel("PS Remote Play Aranıyor")
        self.lbl_latency_val = QLabel("Vision: -- ms | Çeviri: -- ms")
        self.lbl_cache_val = QLabel("0 Cümle")

        cards_grid.addWidget(
            self._create_stat_card("SİSTEM DURUMU", self.lbl_state_val), 0, 0
        )
        cards_grid.addWidget(
            self._create_stat_card("YAKALANAN KAYNAK", self.lbl_source_val), 0, 1
        )
        cards_grid.addWidget(
            self._create_stat_card("SON GECİKME (M2 ANE + API)", self.lbl_latency_val),
            0,
            2,
        )
        cards_grid.addWidget(
            self._create_stat_card("SQLITE ÖNBELLEK", self.lbl_cache_val), 0, 3
        )
        root_layout.addLayout(cards_grid)

        # 3) Hızlı Aksiyon Butonları
        action_row = QHBoxLayout()
        action_row.setSpacing(8)

        self.btn_pause = QPushButton("⏸ Yakalamayı Duraklat")
        self.btn_pause.setObjectName("primaryBtn")
        self.btn_pause.clicked.connect(self._handle_pause_click)
        action_row.addWidget(self.btn_pause)

        self.btn_roi = QPushButton("🎯 Fareyle Altyazı Bölgesi Seç (ROI)")
        self.btn_roi.setObjectName("accentBtn")
        self.btn_roi.clicked.connect(self._on_select_roi)
        action_row.addWidget(self.btn_roi)

        self.btn_auto_win = QPushButton("🖥 Otomatik Remote Play Penceresi")
        self.btn_auto_win.clicked.connect(self._on_auto_roi)
        action_row.addWidget(self.btn_auto_win)

        self.btn_demo = QPushButton("🎬 Test Altyazısı Göster (Lucia/Jason)")
        self.btn_demo.clicked.connect(self._on_trigger_demo)
        action_row.addWidget(self.btn_demo)

        root_layout.addLayout(action_row)

        # 4) Sekmeler (Canlı Diyalog Akışı | TV Doğrudan Bağlantı | API Anahtarları | Görünüm Ayarları)
        self.tabs = QTabWidget()
        self.tabs.addTab(self._build_live_log_tab(), "📡 Canlı Diyalog Akışı")
        self.tabs.addTab(
            self._build_tv_direct_tab(), "📺 TV Doğrudan Bağlantı (Ev Ağı)"
        )
        self.tabs.addTab(self._build_api_settings_tab(), "🔑 Çeviri Motoru & API Anahtarları")
        self.tabs.addTab(self._build_appearance_tab(), "🎨 Altyazı Görünümü & TV Ayarları")
        root_layout.addWidget(self.tabs, stretch=1)

    def _create_stat_card(self, title: str, value_label: QLabel) -> QFrame:
        card = QFrame()
        card.setObjectName("statCard")
        layout = QVBoxLayout(card)
        layout.setContentsMargins(12, 8, 12, 8)
        layout.setSpacing(4)
        lbl_title = QLabel(title)
        lbl_title.setObjectName("cardTitle")
        value_label.setObjectName("cardValue")
        layout.addWidget(lbl_title)
        layout.addWidget(value_label)
        return card

    def _build_live_log_tab(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(14, 14, 14, 14)
        layout.setSpacing(10)

        top_bar = QHBoxLayout()
        info = QLabel(
            "Oyunda yakalanan İngilizce replikler ve Türkçe çevirileri anlık olarak aşağıya düşer:"
        )
        top_bar.addWidget(info)
        top_bar.addStretch()

        btn_clear_log = QPushButton("Listeyi Temizle")
        btn_clear_log.clicked.connect(lambda: self.dialogue_list.clear())
        top_bar.addWidget(btn_clear_log)

        btn_clear_cache = QPushButton("SQLite Önbelleği Sıfırla")
        btn_clear_cache.clicked.connect(self._handle_clear_cache)
        top_bar.addWidget(btn_clear_cache)

        layout.addLayout(top_bar)

        self.dialogue_list = QListWidget()
        layout.addWidget(self.dialogue_list, stretch=1)
        return page

    def _build_tv_direct_tab(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(14)

        net_group = QGroupBox(
            "Seçenek A — PS5 Doğrudan TV'de (4K/HDR & 0 ms Gecikme) + Yerel Ağdan Altyazı Yayını"
        )
        net_layout = QVBoxLayout(net_group)
        net_layout.setSpacing(8)

        desc = QLabel(
            "Bu modda PS5 doğrudan HDMI ile TV'ye bağlı kalır. MacBook Pro arka planda Remote Play'den\n"
            "altyazıyı okur (OCR) ve sadece çevrilen Türkçe metni ev ağı üzerinden TV'ye gönderir."
        )
        desc.setStyleSheet("color: #B0BEC5;")
        net_layout.addWidget(desc)

        url_row = QHBoxLayout()
        url_lbl = QLabel("Canlı TV Altyazı Yayın Adresi:")
        self.input_tv_url = QLineEdit(self.tv_server_url)
        self.input_tv_url.setReadOnly(True)
        self.input_tv_url.setStyleSheet(
            "color: #00E676; font-weight: bold; font-size: 14px;"
        )
        url_row.addWidget(url_lbl)
        url_row.addWidget(self.input_tv_url, stretch=1)
        net_layout.addLayout(url_row)

        api_lbl = QLabel(
            f"• Akıllı TV Multi-View / PiP Tarayıcı veya Telefon/Tablet için: {self.tv_server_url}\n"
            f"• Android TV / LG webOS / Samsung Tizen JSON Uç Noktası: {self.tv_server_url}/api/subtitle"
        )
        api_lbl.setStyleSheet("color: #81D4FA; font-size: 12px;")
        net_layout.addWidget(api_lbl)
        layout.addWidget(net_group)

        adb_group = QGroupBox("Android TV / Google TV (ADB) Doğrudan Bağlantı Aracı")
        adb_form = QFormLayout(adb_group)
        adb_form.setSpacing(10)

        self.input_tv_ip = QLineEdit()
        self.input_tv_ip.setPlaceholderText("Örn: 192.168.1.55 (TV Ayarları -> Ağ -> IP Adresi)")
        adb_form.addRow("Akıllı TV IP Adresi:", self.input_tv_ip)

        btn_adb = QPushButton("🔗 Android TV'ye Yerel Ağdan Bağlan (ADB)")
        btn_adb.setObjectName("accentBtn")
        btn_adb.clicked.connect(self._handle_adb_connect)
        adb_form.addRow("", btn_adb)

        self.lbl_adb_status = QLabel(
            "İpucu: TV'de Ayarlar -> Cihaz Tercihleri -> Hakkında -> Derleme Numarası'na 7 kez basıp 'Ağ Hata Ayıklama'yı açın."
        )
        self.lbl_adb_status.setStyleSheet("color: #9AA8BE; font-size: 11px;")
        adb_form.addRow("", self.lbl_adb_status)

        layout.addWidget(adb_group)
        layout.addStretch()
        return page

    def _handle_adb_connect(self) -> None:
        if self._on_connect_adb is None:
            return
        ok, msg = self._on_connect_adb(self.input_tv_ip.text())
        self.lbl_adb_status.setText(msg)
        self.lbl_adb_status.setStyleSheet(
            f"color: {'#00E676' if ok else '#FF8A80'}; font-size: 12px; font-weight: bold;"
        )

    def _build_api_settings_tab(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)

        group = QGroupBox("Yapay Zeka Çeviri Servisi Yapılandırması (.env Dosyasına Otomatik Kaydedilir)")
        form = QFormLayout(group)
        form.setSpacing(12)

        self.combo_provider = QComboBox()
        self.combo_provider.addItem(
            "Otomatik Hibrit (Önce SQLite Önbellek -> Gemini Flash -> DeepL -> Ollama)",
            "auto",
        )
        self.combo_provider.addItem(
            "Google Gemini Flash (Sokak Dili, Argo ve Bağlam İçin Önerilen)",
            "gemini",
        )
        self.combo_provider.addItem(
            "DeepL API Free / Pro (Ayda 500.000 Karakter Ücretsiz)",
            "deepl",
        )
        self.combo_provider.addItem(
            "Ollama Yerel LLM (M2 MacBook Pro Üzerinde İnternetsiz / Ücretsiz)",
            "ollama",
        )
        current_prov = self.env_values.get("TRANSLATION_PROVIDER", "auto").lower()
        idx = self.combo_provider.findData(current_prov)
        if idx >= 0:
            self.combo_provider.setCurrentIndex(idx)
        form.addRow("Aktif Çeviri Motoru:", self.combo_provider)

        self.input_gemini_key = QLineEdit(self.env_values.get("GEMINI_API_KEY", ""))
        self.input_gemini_key.setPlaceholderText("AIzaSy... (Google AI Studio API Anahtarı)")
        self.input_gemini_key.setEchoMode(QLineEdit.EchoMode.PasswordEchoOnEdit)
        form.addRow("Gemini API Anahtarı:", self.input_gemini_key)

        self.input_gemini_model = QLineEdit(
            self.env_values.get("GEMINI_MODEL", "gemini-2.5-flash")
        )
        form.addRow("Gemini Modeli:", self.input_gemini_model)

        self.input_deepl_key = QLineEdit(self.env_values.get("DEEPL_API_KEY", ""))
        self.input_deepl_key.setPlaceholderText("...:fx (DeepL Free veya Pro API Anahtarı)")
        self.input_deepl_key.setEchoMode(QLineEdit.EchoMode.PasswordEchoOnEdit)
        form.addRow("DeepL API Anahtarı:", self.input_deepl_key)

        self.input_ollama_url = QLineEdit(
            self.env_values.get("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
        )
        form.addRow("Ollama Yerel Adres:", self.input_ollama_url)

        self.input_ollama_model = QLineEdit(
            self.env_values.get("OLLAMA_MODEL", "gemma2:9b")
        )
        form.addRow("Ollama Model Adı:", self.input_ollama_model)

        layout.addWidget(group)

        btn_save_api = QPushButton("💾 API Ayarlarını Kaydet ve Canlı Uygula")
        btn_save_api.setObjectName("accentBtn")
        btn_save_api.clicked.connect(self._handle_save_api)
        layout.addWidget(btn_save_api)
        layout.addStretch()
        return page

    def _build_appearance_tab(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(14)

        overlay_cfg = self.config.get("overlay", {})
        cur_font_size = int(overlay_cfg.get("font_size", 26))
        cur_opacity = int(float(overlay_cfg.get("background_opacity", 0.88)) * 100)
        cur_show_en = bool(overlay_cfg.get("show_original_english", False))
        cur_show_badge = bool(overlay_cfg.get("show_status_badge", True))
        cur_fps = int(self.config.get("capture_fps", 10))

        group = QGroupBox("TV Ekranı Altyazı Katmanı (Overlay) Görünümü")
        form = QFormLayout(group)
        form.setSpacing(14)

        # Font boyutu slider
        font_row = QHBoxLayout()
        self.slider_font = QSlider(Qt.Orientation.Horizontal)
        self.slider_font.setRange(16, 46)
        self.slider_font.setValue(cur_font_size)
        self.lbl_font_val = QLabel(f"{cur_font_size} pt")
        self.slider_font.valueChanged.connect(self._emit_appearance_update)
        font_row.addWidget(self.slider_font)
        font_row.addWidget(self.lbl_font_val)
        form.addRow("Türkçe Altyazı Boyutu:", font_row)

        # Arka plan opaklığı slider
        op_row = QHBoxLayout()
        self.slider_opacity = QSlider(Qt.Orientation.Horizontal)
        self.slider_opacity.setRange(30, 100)
        self.slider_opacity.setValue(cur_opacity)
        self.lbl_opacity_val = QLabel(f"%{cur_opacity}")
        self.slider_opacity.valueChanged.connect(self._emit_appearance_update)
        op_row.addWidget(self.slider_opacity)
        op_row.addWidget(self.lbl_opacity_val)
        form.addRow("Siyah Kutu Koyuluğu (Opaklık):", op_row)

        # Yakalama FPS slider
        fps_row = QHBoxLayout()
        self.slider_fps = QSlider(Qt.Orientation.Horizontal)
        self.slider_fps.setRange(4, 15)
        self.slider_fps.setValue(cur_fps)
        self.lbl_fps_val = QLabel(f"{cur_fps} FPS")
        self.slider_fps.valueChanged.connect(self._emit_appearance_update)
        fps_row.addWidget(self.slider_fps)
        fps_row.addWidget(self.lbl_fps_val)
        form.addRow("Ekran Yakalama Hızı (FPS):", fps_row)

        self.chk_show_en = QCheckBox(
            "Türkçe çevirinin altında orijinal İngilizce cümleyi de göster"
        )
        self.chk_show_en.setChecked(cur_show_en)
        self.chk_show_en.stateChanged.connect(self._emit_appearance_update)
        form.addRow("", self.chk_show_en)

        self.chk_show_badge = QCheckBox(
            "Altyazı kutusunun sağ alt köşesinde OCR/API hız rozetini göster"
        )
        self.chk_show_badge.setChecked(cur_show_badge)
        self.chk_show_badge.stateChanged.connect(self._emit_appearance_update)
        form.addRow("", self.chk_show_badge)

        layout.addWidget(group)
        layout.addStretch()
        return page

    def _handle_pause_click(self) -> None:
        paused = self._on_toggle_pause()
        self.set_paused_ui(paused)

    def set_paused_ui(self, paused: bool) -> None:
        if paused:
            self.btn_pause.setText("▶ Canlı Çeviriyi Başlat")
            self.lbl_state_val.setText("Duraklatıldı")
            self.lbl_state_val.setStyleSheet("color: #FFB74D; font-size: 16px; font-weight: bold;")
        else:
            self.btn_pause.setText("⏸ Yakalamayı Duraklat")
            self.lbl_state_val.setText("Aktif (Dinleniyor)")
            self.lbl_state_val.setStyleSheet("color: #00E676; font-size: 16px; font-weight: bold;")

    def _handle_save_api(self) -> None:
        new_env = {
            "TRANSLATION_PROVIDER": str(self.combo_provider.currentData()),
            "GEMINI_API_KEY": self.input_gemini_key.text().strip(),
            "GEMINI_MODEL": self.input_gemini_model.text().strip() or "gemini-2.5-flash",
            "DEEPL_API_KEY": self.input_deepl_key.text().strip(),
            "OLLAMA_BASE_URL": self.input_ollama_url.text().strip()
            or "http://127.0.0.1:11434",
            "OLLAMA_MODEL": self.input_ollama_model.text().strip() or "gemma2:9b",
        }
        self._on_save_api_settings(new_env)
        QMessageBox.information(
            self,
            "Ayarlar Kaydedildi",
            "Çeviri motoru ve API anahtarları kaydedildi ve canlı olarak etkinleştirildi.",
        )

    def _emit_appearance_update(self) -> None:
        font_sz = int(self.slider_font.value())
        opacity_pct = int(self.slider_opacity.value())
        fps_val = int(self.slider_fps.value())
        show_en = bool(self.chk_show_en.isChecked())
        show_badge = bool(self.chk_show_badge.isChecked())

        self.lbl_font_val.setText(f"{font_sz} pt")
        self.lbl_opacity_val.setText(f"%{opacity_pct}")
        self.lbl_fps_val.setText(f"{fps_val} FPS")

        self._on_appearance_changed(
            font_sz, opacity_pct / 100.0, show_en, show_badge, fps_val
        )

    def _handle_clear_cache(self) -> None:
        self._on_clear_cache()
        self.refresh_cache_badge()

    def refresh_cache_badge(self) -> None:
        count = self._cache_count_fn()
        self.lbl_cache_val.setText(f"{count} Cümle")

    def update_telemetry(self, source_title: str, meta_info: str) -> None:
        self.lbl_source_val.setText(source_title)
        if meta_info:
            self.lbl_latency_val.setText(meta_info)

    def append_dialogue_log(
        self, speaker: str, tr_text: str, en_text: str, meta: str
    ) -> None:
        ts = time.strftime("%H:%M:%S")
        spk_prefix = f"[{speaker}] " if speaker else ""
        flat_tr = tr_text.replace("\n", " ")
        entry_text = f"[{ts}] {spk_prefix}{flat_tr}\n    ↳ EN: {en_text}  ({meta})"

        item = QListWidgetItem(entry_text)
        if speaker.upper() == "LUCIA":
            item.setForeground(QColor("#FF80AB"))
        elif speaker.upper() == "JASON":
            item.setForeground(QColor("#81D4FA"))
        else:
            item.setForeground(QColor("#FFF59D"))

        self.dialogue_list.insertItem(0, item)
        if self.dialogue_list.count() > 100:
            self.dialogue_list.takeItem(self.dialogue_list.count() - 1)
        self.refresh_cache_badge()
