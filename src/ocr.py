from __future__ import annotations

import io
import logging
import time
from dataclasses import dataclass
from typing import Any, Dict, List

from PIL import Image, ImageOps

try:
    from Foundation import NSData
    import Vision

    HAS_APPLE_VISION = True
except ImportError:
    HAS_APPLE_VISION = False

logger = logging.getLogger(__name__)


@dataclass
class OCRResult:
    """Apple Vision OCR çıktısını ve performans ölçütlerini taşır."""

    text: str
    confidence: float
    latency_ms: float
    lines: List[str]


class AppleVisionOCR:
    """
    M2 MacBook Pro'nun 16 çekirdekli Neural Engine birimini kullanan
    yerleşik macOS Apple Vision (VNRecognizeTextRequest) metin okuyucu.
    """

    def __init__(self, config: Dict[str, Any]) -> None:
        ocr_cfg = config.get("ocr", {})
        self.language: str = str(ocr_cfg.get("language", "en-US"))
        self.min_confidence: float = float(ocr_cfg.get("min_confidence", 0.45))
        self.min_text_height_ratio: float = float(
            ocr_cfg.get("min_text_height_ratio", 0.08)
        )

    @staticmethod
    def _preprocess_image(image: Image.Image) -> bytes:
        """
        Görüntüyü hafif kontrast iyileştirmesiyle PNG bayt dizisine dönüştürür.
        Apple Vision renkli ve yüksek kontrastlı altyazılarda doğrudan çok yüksek başarım verir.
        """
        if image.mode != "RGB":
            image = image.convert("RGB")
        # Çok küçük ROI yakalamalarında OCR başarımını artırmak için hafif büyütme
        w, h = image.size
        if h < 70:
            scale = 2
            image = image.resize((w * scale, h * scale), Image.Resampling.BICUBIC)

        image = ImageOps.autocontrast(image, cutoff=1)
        buf = io.BytesIO()
        image.save(buf, format="PNG", compress_level=1)
        return buf.getvalue()

    def recognize(self, image: Image.Image) -> OCRResult:
        """
        PIL.Image içerisindeki İngilizce oyun altyazısını Apple Vision ile okur.
        """
        t0 = time.perf_counter()
        if not HAS_APPLE_VISION:
            logger.error(
                "Apple Vision framework bulunamadı (pyobjc-framework-Vision gerekli)."
            )
            return OCRResult(text="", confidence=0.0, latency_ms=0.0, lines=[])

        png_bytes = self._preprocess_image(image)
        ns_data = NSData.dataWithBytes_length_(png_bytes, len(png_bytes))
        handler = Vision.VNImageRequestHandler.alloc().initWithData_options_(
            ns_data, None
        )

        request = Vision.VNRecognizeTextRequest.alloc().init()
        request.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
        request.setUsesLanguageCorrection_(True)
        request.setRecognitionLanguages_([self.language, "en-US"])

        success, error = handler.performRequests_error_([request], None)
        elapsed_ms = (time.perf_counter() - t0) * 1000.0

        if not success or error is not None:
            logger.warning("Apple Vision OCR hatası: %s", error)
            return OCRResult(text="", confidence=0.0, latency_ms=elapsed_ms, lines=[])

        observations = request.results()
        if not observations:
            return OCRResult(text="", confidence=0.0, latency_ms=elapsed_ms, lines=[])

        # Apple Vision koordinat sisteminde (0,0) sol-alttır.
        # Satırları yukarıdan aşağıya ve soldan sağa sıralamak için (-y, x) kullanıyoruz.
        valid_items = []
        for obs in observations:
            candidates = obs.topCandidates_(1)
            if not candidates:
                continue
            top_candidate = candidates[0]
            conf = float(top_candidate.confidence())
            if conf < self.min_confidence:
                continue

            bbox = obs.boundingBox()
            box_h = float(bbox.size.height)
            box_y = float(bbox.origin.y)
            box_x = float(bbox.origin.x)

            if box_h < self.min_text_height_ratio:
                continue

            line_str = str(top_candidate.string()).strip()
            if not line_str:
                continue

            valid_items.append((box_y, box_x, line_str, conf))

        if not valid_items:
            return OCRResult(text="", confidence=0.0, latency_ms=elapsed_ms, lines=[])

        # Aynı satıra denk gelen kutuları grupla (y farkı < 0.08 ise aynı satır kabul et)
        valid_items.sort(key=lambda item: -item[0])  # yukarıdan aşağıya
        grouped_lines: List[List[Any]] = []
        for item in valid_items:
            if not grouped_lines:
                grouped_lines.append([item])
            else:
                prev_y = grouped_lines[-1][0][0]
                if abs(item[0] - prev_y) < 0.08:
                    grouped_lines[-1].append(item)
                else:
                    grouped_lines.append([item])

        lines: List[str] = []
        confidences: List[float] = []
        for group in grouped_lines:
            group.sort(key=lambda item: item[1])  # soldan sağa
            merged_line = " ".join(x[2] for x in group)
            lines.append(merged_line)
            confidences.extend(x[3] for x in group)

        full_text = " ".join(lines).strip()
        avg_conf = sum(confidences) / len(confidences) if confidences else 0.0

        return OCRResult(
            text=full_text,
            confidence=avg_conf,
            latency_ms=elapsed_ms,
            lines=lines,
        )
