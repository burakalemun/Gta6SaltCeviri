from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple

import imagehash
from PIL import Image

try:
    import Quartz
    from Quartz import (
        CGDataProviderCopyData,
        CGImageGetBytesPerRow,
        CGImageGetDataProvider,
        CGImageGetHeight,
        CGImageGetWidth,
        CGRectMake,
        CGWindowListCopyWindowInfo,
        CGWindowListCreateImage,
        kCGNullWindowID,
        kCGWindowImageBoundsIgnoreFraming,
        kCGWindowImageDefault,
        kCGWindowListExcludeDesktopElements,
        kCGWindowListOptionIncludingWindow,
        kCGWindowListOptionOnScreenBelowWindow,
        kCGWindowListOptionOnScreenOnly,
    )

    HAS_QUARTZ = True
except ImportError:
    HAS_QUARTZ = False

logger = logging.getLogger(__name__)


@dataclass
class CaptureResult:
    """Tek bir yakalanan ROI karesini ve meta verisini temsil eder."""

    image: Image.Image
    screen_rect: Tuple[int, int, int, int]  # (x, y, width, height) ekran koordinatlarında
    window_title: str
    phash: imagehash.ImageHash
    changed: bool
    capture_ms: float


class MacWindowCapturer:
    """
    M2 MacBook Pro (macOS Quartz) üzerinde PS Remote Play / chiaki-ng penceresini
    veya kullanıcının seçtiği ekran altyazı bölgesini (ROI) düşük gecikmeyle yakalar.
    """

    def __init__(self, config: Dict[str, Any]) -> None:
        self.config = config
        self.target_titles: List[str] = [
            t.lower()
            for t in config.get(
                "target_window_titles",
                ["PS Remote Play", "Remote Play", "chiaki-ng", "Chiaki"],
            )
        ]
        self.phash_threshold: int = int(
            config.get("ocr", {}).get("phash_threshold", 4)
        )
        self._last_phash: Optional[imagehash.ImageHash] = None
        self._cached_window_id: Optional[int] = None
        self._cached_window_bounds: Optional[Tuple[int, int, int, int]] = None
        self._cached_window_title: str = "Ekran Bölgesi (ROI)"
        self._last_window_lookup: float = 0.0
        self._overlay_window_id: Optional[int] = None

    def set_overlay_window_id(self, window_id: Optional[int]) -> None:
        """
        Kendi PyQt6 Türkçe altyazı katmanımızın (overlay) CGWindowID değerini kaydeder.
        Böylece ekran yakalama sırasında kendi yazdığımız Türkçe metni asla tekrar okumayız.
        """
        self._overlay_window_id = window_id

    def reset_hash(self) -> None:
        """Son kare özetini (pHash) sıfırlar; bir sonraki kare zorunlu olarak OCR'a girer."""
        self._last_phash = None

    def set_custom_screen_rect(self, x: int, y: int, width: int, height: int) -> None:
        """Fare ile seçilen özel altyazı bölgesini (ekran koordinatları) günceller."""
        roi_cfg = self.config.setdefault("roi", {})
        roi_cfg["use_custom_screen_rect"] = True
        roi_cfg["screen_rect"] = {
            "x": int(x),
            "y": int(y),
            "width": max(60, int(width)),
            "height": max(30, int(height)),
        }
        self.reset_hash()

    def use_auto_window_roi(self) -> None:
        """Otomatik Remote Play penceresi alt %20 ROI moduna geri döner."""
        roi_cfg = self.config.setdefault("roi", {})
        roi_cfg["use_custom_screen_rect"] = False
        self._cached_window_id = None
        self.reset_hash()

    def find_remote_play_window(self) -> Optional[Tuple[int, str, Tuple[int, int, int, int]]]:
        """
        Ekranda açık olan PS Remote Play veya chiaki-ng penceresini bulur.
        Dönüş: (window_id, window_title, (x, y, width, height)) veya None.
        """
        if not HAS_QUARTZ:
            return None

        now = time.monotonic()
        if (
            self._cached_window_id is not None
            and self._cached_window_bounds is not None
            and (now - self._last_window_lookup) < 2.0
        ):
            return (
                self._cached_window_id,
                self._cached_window_title,
                self._cached_window_bounds,
            )

        self._last_window_lookup = now
        options = kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements
        window_list = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        if not window_list:
            return None

        for win in window_list:
            owner_name = str(win.get("kCGWindowOwnerName", "") or "")
            win_name = str(win.get("kCGWindowName", "") or "")
            layer = int(win.get("kCGWindowLayer", 0) or 0)
            if layer != 0:
                continue

            combined = f"{owner_name} {win_name}".lower()
            if any(target in combined for target in self.target_titles):
                bounds = win.get("kCGWindowBounds", {})
                w = int(bounds.get("Width", 0))
                h = int(bounds.get("Height", 0))
                if w < 300 or h < 200:
                    continue
                x = int(bounds.get("X", 0))
                y = int(bounds.get("Y", 0))
                win_id = int(win.get("kCGWindowNumber", 0))
                title = owner_name or win_name or "PS Remote Play"
                self._cached_window_id = win_id
                self._cached_window_title = title
                self._cached_window_bounds = (x, y, w, h)
                return win_id, title, (x, y, w, h)

        self._cached_window_id = None
        self._cached_window_bounds = None
        return None

    def compute_target_roi_rect(self) -> Tuple[Tuple[int, int, int, int], Optional[int], str]:
        """
        Yakalanacak (x, y, width, height) ekran koordinatlarını, varsa pencere ID'sini
        ve kaynak başlığını hesaplar.
        """
        roi_cfg = self.config.get("roi", {})
        use_custom = bool(roi_cfg.get("use_custom_screen_rect", False))

        if not use_custom:
            found = self.find_remote_play_window()
            if found is not None:
                win_id, title, (wx, wy, ww, wh) = found
                rel = roi_cfg.get("window_relative", {})
                x_ratio = float(rel.get("x_ratio", 0.12))
                y_ratio = float(rel.get("y_ratio", 0.76))
                w_ratio = float(rel.get("w_ratio", 0.76))
                h_ratio = float(rel.get("h_ratio", 0.19))

                rx = int(wx + ww * x_ratio)
                ry = int(wy + wh * y_ratio)
                rw = max(80, int(ww * w_ratio))
                rh = max(40, int(wh * h_ratio))
                return (rx, ry, rw, rh), win_id, title

        screen_rect = roi_cfg.get("screen_rect", {})
        rx = int(screen_rect.get("x", 260))
        ry = int(screen_rect.get("y", 720))
        rw = max(80, int(screen_rect.get("width", 920)))
        rh = max(40, int(screen_rect.get("height", 160)))
        return (rx, ry, rw, rh), None, "Özel Ekran Bölgesi (ROI)"

    @staticmethod
    def _cgimage_to_pil(cg_image: Any) -> Optional[Image.Image]:
        """macOS CGImage nesnesini sıfır kopya hızında PIL Image (RGB) formatına çevirir."""
        if cg_image is None:
            return None
        width = CGImageGetWidth(cg_image)
        height = CGImageGetHeight(cg_image)
        if width <= 0 or height <= 0:
            return None

        provider = CGImageGetDataProvider(cg_image)
        if provider is None:
            return None
        raw_data = CGDataProviderCopyData(provider)
        if raw_data is None:
            return None

        bytes_per_row = CGImageGetBytesPerRow(cg_image)
        img = Image.frombuffer(
            "RGBA",
            (width, height),
            raw_data,
            "raw",
            "BGRA",
            bytes_per_row,
            1,
        )
        return img.convert("RGB")

    def capture_roi(self) -> Optional[CaptureResult]:
        """
        Hedef altyazı bölgesini (ROI) yakalar ve pHash ile bir önceki kareden
        farklı olup olmadığını hesaplar.
        """
        if not HAS_QUARTZ:
            logger.error("macOS Quartz framework bulunamadı (pyobjc-framework-Quartz gerekli).")
            return None

        t0 = time.perf_counter()
        (rx, ry, rw, rh), win_id, title = self.compute_target_roi_rect()
        cg_rect = CGRectMake(rx, ry, rw, rh)

        if win_id is not None:
            cg_img = CGWindowListCreateImage(
                cg_rect,
                kCGWindowListOptionIncludingWindow,
                win_id,
                kCGWindowImageBoundsIgnoreFraming | kCGWindowImageDefault,
            )
        elif self._overlay_window_id is not None and self._overlay_window_id > 0:
            # Özel ROI modunda kendi Türkçe overlay penceremizin ALTINDAKİ görüntüyü yakala
            cg_img = CGWindowListCreateImage(
                cg_rect,
                kCGWindowListOptionOnScreenBelowWindow,
                self._overlay_window_id,
                kCGWindowImageDefault,
            )
        else:
            cg_img = CGWindowListCreateImage(
                cg_rect,
                kCGWindowListOptionOnScreenOnly,
                kCGNullWindowID,
                kCGWindowImageDefault,
            )

        pil_img = self._cgimage_to_pil(cg_img)
        if pil_img is None:
            return None

        current_hash = imagehash.phash(pil_img)
        if self._last_phash is None:
            changed = True
        else:
            diff = current_hash - self._last_phash
            changed = diff >= self.phash_threshold

        if changed:
            self._last_phash = current_hash

        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        return CaptureResult(
            image=pil_img,
            screen_rect=(rx, ry, rw, rh),
            window_title=title,
            phash=current_hash,
            changed=changed,
            capture_ms=elapsed_ms,
        )
