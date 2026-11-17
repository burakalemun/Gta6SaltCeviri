from __future__ import annotations

import argparse
import json
import logging
import os
import shutil
import sys
import time
from pathlib import Path
from typing import Any, Dict, Optional

from dotenv import dotenv_values, load_dotenv
from PIL import Image, ImageDraw, ImageFont

from src.capture import MacWindowCapturer
from src.ocr import AppleVisionOCR
from src.stabilizer import SubtitleStabilizer
from src.translator import SubtitleTranslator
from src.tv_server import LocalSubtitleServer


def get_bundle_resource_dir() -> Path:
    """PyInstaller .app paketi içinde veya kaynak kod dizininde kaynak klasörünü döndürür."""
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        return Path(getattr(sys, "_MEIPASS"))
    return Path(__file__).resolve().parent.parent


def get_user_data_dir() -> Path:
    """
    Uygulama .app / .dmg olarak /Applications içinden çalıştırıldığında
    kullanıcı ayarlarını, .env dosyasını ve SQLite önbelleğini
    ~/Library/Application Support/GTA6PS5Altyazi altında tutar.
    Proje klasöründen doğrudan çalıştırılıyorsa proje klasörünü kullanır.
    """
    bundle_dir = get_bundle_resource_dir()
    if getattr(sys, "frozen", False):
        app_support = (
            Path.home() / "Library" / "Application Support" / "GTA6PS5Altyazi"
        )
        app_support.mkdir(parents=True, exist_ok=True)
        (app_support / "data").mkdir(parents=True, exist_ok=True)

        for rel_file in ["config.json", "data/glossary.json"]:
            src_f = bundle_dir / rel_file
            dst_f = app_support / rel_file
            if src_f.exists() and not dst_f.exists():
                dst_f.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src_f, dst_f)

        env_dst = app_support / ".env"
        env_src = bundle_dir / ".env.example"
        if not env_dst.exists() and env_src.exists():
            shutil.copy2(env_src, env_dst)

        return app_support
    return bundle_dir


PROJECT_ROOT = get_user_data_dir()


def load_config(config_path: Path) -> Dict[str, Any]:
    if not config_path.exists():
        fallback = get_bundle_resource_dir() / "config.json"
        if fallback.exists():
            shutil.copy2(fallback, config_path)
        else:
            raise FileNotFoundError(f"Yapılandırma dosyası bulunamadı: {config_path}")
    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_config(config_path: Path, config: Dict[str, Any]) -> None:
    config_path.parent.mkdir(parents=True, exist_ok=True)
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=2, ensure_ascii=False)


def save_env_file(env_path: Path, values: Dict[str, str]) -> None:
    lines = [
        "# GTA 6 (PS5) Canlı Türkçe Altyazı Sistemi — Dashboard Tarafından Kaydedildi",
        f"TRANSLATION_PROVIDER={values.get('TRANSLATION_PROVIDER', 'auto')}",
        f"GEMINI_API_KEY={values.get('GEMINI_API_KEY', '')}",
        f"GEMINI_MODEL={values.get('GEMINI_MODEL', 'gemini-2.5-flash')}",
        f"DEEPL_API_KEY={values.get('DEEPL_API_KEY', '')}",
        f"OLLAMA_BASE_URL={values.get('OLLAMA_BASE_URL', 'http://127.0.0.1:11434')}",
        f"OLLAMA_MODEL={values.get('OLLAMA_MODEL', 'gemma2:9b')}",
        "",
    ]
    env_path.write_text("\n".join(lines), encoding="utf-8")
    for k, v in values.items():
        os.environ[k] = v


def run_self_test(config: Dict[str, Any]) -> int:
    """
    PS5 bağlı olmadan M2 MacBook Pro üzerindeki tüm boru hattını
    (Apple Vision OCR -> Stabilizer -> SQLite/Translator) gerçek bir test
    altyazı görüntüsüyle uçtan uca test eder ve gecikmeleri raporlar.
    """
    print("=" * 68)
    print("GTA 6 (PS5) Canlı Türkçe Altyazı — M2 MacBook Pro Sistem Testi")
    print("=" * 68)

    ocr = AppleVisionOCR(config)
    stabilizer = SubtitleStabilizer(config)
    translator = SubtitleTranslator(config, PROJECT_ROOT)

    img = Image.new("RGB", (920, 140), color=(12, 14, 18))
    draw = ImageDraw.Draw(img)
    sample_line = "LUCIA: The only way we're gonna get through this is by sticking together."
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 28)
    except Exception:
        font = ImageFont.load_default()
    draw.text((28, 48), sample_line, fill=(255, 255, 255), font=font)

    ocr_res = ocr.recognize(img)
    print(f"[1/3] Apple Vision OCR Okunan : {ocr_res.text!r}")
    print(f"      Doğruluk (Confidence)   : {ocr_res.confidence:.2%}")
    print(f"      OCR Gecikmesi (M2 ANE)  : {ocr_res.latency_ms:.1f} ms")

    if not ocr_res.text:
        print("HATA: Apple Vision metni okuyamadı!")
        return 1

    stab_res = None
    for _ in range(stabilizer.required_consecutive):
        stab_res = stabilizer.process_ocr_text(ocr_res.text)

    if stab_res is None:
        print("HATA: Sabitleyici metni onaylamadı!")
        return 1

    print(
        f"[2/3] Konuşmacı Ayrıştırma    : Konuşmacı={stab_res.speaker!r} | Replik={stab_res.dialogue!r}"
    )

    tr_res = translator.translate(stab_res.speaker, stab_res.dialogue)
    print(f"[3/3] Türkçe Çeviri Çıktısı   : {tr_res.speaker}: {tr_res.formatted_lines}")
    print(f"      Çeviri Kaynağı & Süre   : {tr_res.provider} ({tr_res.latency_ms:.2f} ms)")
    print("=" * 68)
    print("SONUÇ: M2 Apple Vision + Sabitleyici + Çeviri hattı sorunsuz çalışıyor!")
    return 0


def run_gui_app(
    config: Dict[str, Any],
    config_path: Path,
    env_path: Path,
    start_demo: bool = False,
) -> int:
    from PyQt6.QtCore import QThread, QTimer, pyqtSignal
    from PyQt6.QtWidgets import QApplication

    from src.dashboard import DashboardWindow
    from src.overlay import (
        ControlPanelWindow,
        ROISelectorWindow,
        SubtitleOverlayWindow,
    )

    class PipelineWorker(QThread):
        subtitle_ready = pyqtSignal(str, str, str, str)  # speaker, tr_text, en_text, meta
        subtitle_clear = pyqtSignal()
        roi_updated = pyqtSignal(int, int, int, int)
        status_updated = pyqtSignal(str)
        telemetry_updated = pyqtSignal(str, str)  # source_title, meta_info

        def __init__(
            self,
            capturer: MacWindowCapturer,
            ocr_engine: AppleVisionOCR,
            stabilizer: SubtitleStabilizer,
            translator: SubtitleTranslator,
            fps: int,
        ) -> None:
            super().__init__()
            self.capturer = capturer
            self.ocr_engine = ocr_engine
            self.stabilizer = stabilizer
            self.translator = translator
            self.interval_sec = 1.0 / max(1, min(30, fps))
            self.running = True
            self.paused = False

        def set_fps(self, fps: int) -> None:
            self.interval_sec = 1.0 / max(1, min(30, int(fps)))

        def run(self) -> None:
            empty_check_counter = 0
            while self.running:
                loop_start = time.perf_counter()
                if self.paused:
                    time.sleep(0.15)
                    continue

                cap = self.capturer.capture_roi()
                if cap is None:
                    self.status_updated.emit(
                        "Durum: Ekran yakalama izni bekleniyor (Sistem Ayarları -> Ekran Kaydı)"
                    )
                    self.telemetry_updated.emit("Ekran Kaydı İzni Gerekli", "--")
                    time.sleep(0.5)
                    continue

                rx, ry, rw, rh = cap.screen_rect
                self.roi_updated.emit(rx, ry, rw, rh)

                if not cap.changed:
                    empty_check_counter += 1
                    if empty_check_counter < 6:
                        elapsed = time.perf_counter() - loop_start
                        sleep_for = max(0.01, self.interval_sec - elapsed)
                        time.sleep(sleep_for)
                        continue

                empty_check_counter = 0
                ocr_res = self.ocr_engine.recognize(cap.image)
                stab = self.stabilizer.process_ocr_text(ocr_res.text)

                if stab is not None:
                    if stab.is_clear_event:
                        self.subtitle_clear.emit()
                        self.status_updated.emit(
                            f"Kaynak: {cap.window_title} | Altyazı bekleniyor..."
                        )
                        self.telemetry_updated.emit(
                            cap.window_title, f"Vision: {ocr_res.latency_ms:.0f}ms (Boş)"
                        )
                    else:
                        tr_res = self.translator.translate(stab.speaker, stab.dialogue)
                        meta = (
                            f"Vision {ocr_res.latency_ms:.0f}ms | "
                            f"{tr_res.provider} {tr_res.latency_ms:.0f}ms"
                        )
                        self.subtitle_ready.emit(
                            tr_res.speaker or "",
                            tr_res.formatted_lines,
                            tr_res.source_text,
                            meta,
                        )
                        self.status_updated.emit(f"Kaynak: {cap.window_title} | {meta}")
                        self.telemetry_updated.emit(cap.window_title, meta)

                elapsed = time.perf_counter() - loop_start
                sleep_for = max(0.01, self.interval_sec - elapsed)
                time.sleep(sleep_for)

    app = QApplication(sys.argv)
    app.setApplicationName("GTA 6 PS5 Türkçe Altyazı")
    app.setQuitOnLastWindowClosed(False)

    capturer = MacWindowCapturer(config)
    ocr_engine = AppleVisionOCR(config)
    stabilizer = SubtitleStabilizer(config)
    translator = SubtitleTranslator(config, PROJECT_ROOT)

    tv_port = int(config.get("tv_server_port", 8765))
    tv_server = LocalSubtitleServer(port=tv_port)
    tv_server.start()
    tv_server_url = f"http://{tv_server.get_local_ip()}:{tv_port}"

    overlay = SubtitleOverlayWindow(config)
    overlay.show()
    overlay_win_id = overlay.configure_macos_native_window()
    capturer.set_overlay_window_id(overlay_win_id)

    worker = PipelineWorker(
        capturer=capturer,
        ocr_engine=ocr_engine,
        stabilizer=stabilizer,
        translator=translator,
        fps=int(config.get("capture_fps", 10)),
    )

    demo_samples = [
        (
            "LUCIA",
            "The only way we're gonna get through this is by sticking together.",
        ),
        ("JASON", "Let's get out of here before VCPD shows up!"),
        ("LUCIA", "We got heat on our tail, step on it!"),
        ("DRE'QUAN", "Welcome to Leonida, where anything can happen."),
    ]
    demo_index = {"idx": 0}
    roi_selector_ref: Dict[str, Optional[ROISelectorWindow]] = {"win": None}

    def on_subtitle_ready(speaker: str, tr_text: str, en_text: str, meta: str) -> None:
        overlay.update_subtitle(
            speaker=speaker if speaker else None,
            turkish_text=tr_text,
            english_text=en_text,
            status_meta=meta,
        )
        tv_server.broadcast_subtitle(
            speaker=speaker if speaker else None,
            turkish_text=tr_text,
            english_text=en_text,
            meta=meta,
            show_original=overlay.show_original,
        )
        dashboard.append_dialogue_log(speaker, tr_text, en_text, meta)

    def on_subtitle_clear() -> None:
        overlay.clear_subtitle()
        tv_server.broadcast_clear()

    def on_roi_updated(rx: int, ry: int, rw: int, rh: int) -> None:
        overlay.align_to_roi((rx, ry, rw, rh))

    def toggle_pause() -> bool:
        worker.paused = not worker.paused
        state_str = "Duraklatıldı" if worker.paused else "Çalışıyor"
        panel.set_status_text(f"Durum: {state_str}")
        dashboard.set_paused_ui(worker.paused)
        return worker.paused

    def open_roi_selector() -> None:
        selector = ROISelectorWindow()

        def handle_selected(x: int, y: int, w: int, h: int) -> None:
            capturer.set_custom_screen_rect(x, y, w, h)
            stabilizer.reset()
            overlay.align_to_roi((x, y, w, h))
            save_config(config_path, config)
            msg = f"Özel ROI ({x}, {y}, {w}x{h})"
            panel.set_status_text(f"Kaydedildi: {msg}")
            dashboard.update_telemetry(msg, "Kalibre Edildi")

        selector.roi_selected.connect(handle_selected)
        roi_selector_ref["win"] = selector
        selector.show()

    def use_auto_roi() -> None:
        capturer.use_auto_window_roi()
        stabilizer.reset()
        save_config(config_path, config)
        panel.set_status_text("Otomatik PS Remote Play Pencere ROI Modu Aktif")
        dashboard.update_telemetry("PS Remote Play (Otomatik)", "")

    def toggle_english() -> bool:
        shown = overlay.toggle_original_english()
        config.setdefault("overlay", {})["show_original_english"] = shown
        save_config(config_path, config)
        dashboard.chk_show_en.blockSignals(True)
        dashboard.chk_show_en.setChecked(shown)
        dashboard.chk_show_en.blockSignals(False)
        return shown

    def trigger_demo_line() -> None:
        spk, eng = demo_samples[demo_index["idx"] % len(demo_samples)]
        demo_index["idx"] += 1
        tr_res = translator.translate(spk, eng)
        meta = f"Demo | {tr_res.provider} ({tr_res.latency_ms:.1f}ms)"
        overlay.update_subtitle(
            speaker=spk,
            turkish_text=tr_res.formatted_lines,
            english_text=eng,
            status_meta=meta,
        )
        tv_server.broadcast_subtitle(
            speaker=spk,
            turkish_text=tr_res.formatted_lines,
            english_text=eng,
            meta=meta,
            show_original=overlay.show_original,
        )
        panel.set_status_text(f"Demo Repliği Gösteriliyor: {spk}")
        dashboard.append_dialogue_log(spk, tr_res.formatted_lines, eng, meta)

    def handle_save_api_settings(new_env: Dict[str, str]) -> None:
        save_env_file(env_path, new_env)
        translator.reload_settings(
            provider_mode=new_env.get("TRANSLATION_PROVIDER"),
            gemini_api_key=new_env.get("GEMINI_API_KEY"),
            gemini_model=new_env.get("GEMINI_MODEL"),
            deepl_api_key=new_env.get("DEEPL_API_KEY"),
            ollama_base_url=new_env.get("OLLAMA_BASE_URL"),
            ollama_model=new_env.get("OLLAMA_MODEL"),
        )
        panel.set_status_text(
            f"API Ayarları Güncellendi ({new_env.get('TRANSLATION_PROVIDER', 'auto')})"
        )

    def handle_appearance_changed(
        font_size: int,
        bg_opacity: float,
        show_en: bool,
        show_badge: bool,
        fps: int,
    ) -> None:
        overlay.apply_appearance_settings(
            font_size=font_size,
            bg_opacity=bg_opacity,
            show_original=show_en,
            show_status_badge=show_badge,
        )
        worker.set_fps(fps)
        ov_cfg = config.setdefault("overlay", {})
        ov_cfg["font_size"] = font_size
        ov_cfg["background_opacity"] = round(bg_opacity, 2)
        ov_cfg["show_original_english"] = show_en
        ov_cfg["show_status_badge"] = show_badge
        config["capture_fps"] = fps
        panel.btn_eng.setText("EN: Açık" if show_en else "EN: Kapalı")
        save_config(config_path, config)

    def handle_clear_cache() -> None:
        translator.clear_cache()
        panel.set_status_text("SQLite çeviri önbelleği sıfırlandı.")

    def quit_app() -> None:
        worker.running = False
        tv_server.stop()
        worker.wait(1000)
        app.quit()

    env_values = {
        "TRANSLATION_PROVIDER": os.getenv("TRANSLATION_PROVIDER", "auto"),
        "GEMINI_API_KEY": os.getenv("GEMINI_API_KEY", ""),
        "GEMINI_MODEL": os.getenv("GEMINI_MODEL", "gemini-2.5-flash"),
        "DEEPL_API_KEY": os.getenv("DEEPL_API_KEY", ""),
        "OLLAMA_BASE_URL": os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434"),
        "OLLAMA_MODEL": os.getenv("OLLAMA_MODEL", "gemma2:9b"),
    }

    dashboard = DashboardWindow(
        config=config,
        env_values=env_values,
        cache_count_fn=translator.get_cache_count,
        on_toggle_pause=toggle_pause,
        on_select_roi=open_roi_selector,
        on_auto_roi=use_auto_roi,
        on_trigger_demo=trigger_demo_line,
        on_save_api_settings=handle_save_api_settings,
        on_appearance_changed=handle_appearance_changed,
        on_clear_cache=handle_clear_cache,
        on_quit=quit_app,
        tv_server_url=tv_server_url,
        on_connect_adb=LocalSubtitleServer.connect_android_tv_adb,
    )
    dashboard.show()

    def show_dashboard() -> None:
        dashboard.show()
        dashboard.raise_()
        dashboard.activateWindow()

    panel = ControlPanelWindow(
        on_toggle_pause=toggle_pause,
        on_select_roi=open_roi_selector,
        on_auto_roi=use_auto_roi,
        on_toggle_english=toggle_english,
        on_trigger_demo=trigger_demo_line,
        on_quit=quit_app,
        on_open_dashboard=show_dashboard,
    )
    panel.show()

    worker.subtitle_ready.connect(on_subtitle_ready)
    worker.subtitle_clear.connect(on_subtitle_clear)
    worker.roi_updated.connect(on_roi_updated)
    worker.status_updated.connect(panel.set_status_text)
    worker.telemetry_updated.connect(dashboard.update_telemetry)
    worker.start()

    if start_demo:
        QTimer.singleShot(300, trigger_demo_line)

    return app.exec()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="GTA 6 (PS5) Canlı Türkçe Altyazı Sistemi — M2 MacBook Pro"
    )
    parser.add_argument(
        "--config",
        default=str(PROJECT_ROOT / "config.json"),
        help="Yapılandırma dosyası yolu (varsayılan: config.json)",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Apple Vision OCR + Stabilizer + Çeviri boru hattını uçtan uca test et ve çık",
    )
    parser.add_argument(
        "--demo",
        action="store_true",
        help="Başlangıçta örnek GTA 6 Türkçe altyazısını ekranda göster",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    env_path = PROJECT_ROOT / ".env"
    if env_path.exists():
        load_dotenv(env_path)
    else:
        dotenv_values()

    config_path = Path(args.config)
    config = load_config(config_path)

    if args.self_test:
        return run_self_test(config)

    return run_gui_app(config, config_path, env_path, start_demo=args.demo)


if __name__ == "__main__":
    sys.exit(main())
