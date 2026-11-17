from __future__ import annotations

import difflib
import re
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple

try:
    from rapidfuzz import fuzz

    def _similarity_ratio(a: str, b: str) -> float:
        return float(fuzz.ratio(a, b))

except ImportError:

    def _similarity_ratio(a: str, b: str) -> float:
        return difflib.SequenceMatcher(None, a, b).ratio() * 100.0


@dataclass
class StabilizedSubtitle:
    """Sabitlenmiş ve konuşmacısı ayrıştırılmış altyazı verisi."""

    raw_text: str
    speaker: Optional[str]
    dialogue: str
    is_clear_event: bool = False


class SubtitleStabilizer:
    """
    Levenshtein benzerlik filtresiyle yarım çıkan altyazıları,
    OCR titremelerini ve tekrar eden kareleri süzer; konuşmacı adını ayrıştırır.
    """

    # Örn: "LUCIA: Let's go." veya "[JASON]: Hold on!" veya "Dre'Quan: What's up?"
    SPEAKER_PATTERN = re.compile(
        r"^\s*(?:\[([A-Za-z0-9'\-\s]{2,20})\]|([A-Za-z0-9'\-\s]{2,20}))\s*:\s*(.+)$"
    )
    NOISE_ONLY_PATTERN = re.compile(r"^[\W\d_]+$")

    def __init__(self, config: Dict[str, Any]) -> None:
        stab_cfg = config.get("stabilizer", {})
        self.similarity_threshold: float = float(
            stab_cfg.get("similarity_threshold", 86.0)
        )
        self.required_consecutive: int = max(
            1, int(stab_cfg.get("required_consecutive_frames", 2))
        )
        self.clear_after_empty: int = max(
            1, int(stab_cfg.get("clear_after_empty_frames", 4))
        )

        self._candidate_text: str = ""
        self._candidate_hits: int = 0
        self._active_text: str = ""
        self._empty_streak: int = 0

    def reset(self) -> None:
        """Sabitleyici durumunu sıfırlar."""
        self._candidate_text = ""
        self._candidate_hits = 0
        self._active_text = ""
        self._empty_streak = 0

    @classmethod
    def clean_ocr_text(cls, text: str) -> str:
        """OCR kaynaklı tipik karakter hatalarını ve gereksiz boşlukları temizler."""
        if not text:
            return ""
        cleaned = text.replace("\n", " ").replace("\r", " ")
        # Dik çizgiyi I harfine dönüştür (örn. "| don't know" -> "I don't know")
        cleaned = re.sub(r"(?<![A-Za-z])\|(?=\s+[a-zA-Z]|'[a-zA-Z])", "I", cleaned)
        cleaned = re.sub(r"\s+", " ", cleaned).strip()

        # Sadece sayı veya noktalama işaretlerinden oluşan HUD gürültüsünü yoksay
        if len(cleaned) < 2 or cls.NOISE_ONLY_PATTERN.match(cleaned):
            return ""
        return cleaned

    @classmethod
    def split_speaker(cls, text: str) -> Tuple[Optional[str], str]:
        """
        Metin başındaki 'LUCIA: ...' gibi konuşmacı etiketini ayrıştırır.
        Dönüş: (SPEAKER_UPPER, dialogue_text)
        """
        match = cls.SPEAKER_PATTERN.match(text)
        if match:
            speaker = (match.group(1) or match.group(2) or "").strip()
            dialogue = match.group(3).strip()
            # Konuşmacı adı çok uzunsa veya cümle parçasıysa ayırma
            if 1 < len(speaker) <= 18 and len(speaker.split()) <= 3 and dialogue:
                return speaker.upper(), dialogue
        return None, text

    def process_ocr_text(self, raw_ocr_text: str) -> Optional[StabilizedSubtitle]:
        """
        Yeni bir OCR metnini işler.
        - Yeni ve kararlı bir altyazı tespit edilirse `StabilizedSubtitle` döner.
        - Altyazı ekrandan silindiyse `StabilizedSubtitle(..., is_clear_event=True)` döner.
        - Henüz kararlı değilse veya ekrandaki aktif altyazıyla aynıysa `None` döner.
        """
        cleaned = self.clean_ocr_text(raw_ocr_text)

        # 1) Boş kare durumu
        if not cleaned:
            self._empty_streak += 1
            self._candidate_text = ""
            self._candidate_hits = 0
            if self._active_text and self._empty_streak >= self.clear_after_empty:
                self._active_text = ""
                return StabilizedSubtitle(
                    raw_text="",
                    speaker=None,
                    dialogue="",
                    is_clear_event=True,
                )
            return None

        self._empty_streak = 0

        # 2) Zaten ekranda gösterilen aktif altyazı ile büyük ölçüde aynı mı?
        if self._active_text:
            sim_to_active = _similarity_ratio(cleaned.lower(), self._active_text.lower())
            if sim_to_active >= self.similarity_threshold:
                # Eğer yeni okunan metin aktif metinden daha uzunsa (ör. cümlenin devamı eklendiyse)
                if len(cleaned) - len(self._active_text) >= 6:
                    pass
                else:
                    return None

        # 3) Aday metin ile karşılaştır (ardışık kare doğrulaması)
        if not self._candidate_text:
            self._candidate_text = cleaned
            self._candidate_hits = 1
        else:
            sim_to_candidate = _similarity_ratio(cleaned.lower(), self._candidate_text.lower())
            if sim_to_candidate >= self.similarity_threshold:
                # Daha eksiksiz/uzun olan okumayı tercih et
                if len(cleaned) >= len(self._candidate_text):
                    self._candidate_text = cleaned
                self._candidate_hits += 1
            else:
                # Yeni bir cümle başladı
                self._candidate_text = cleaned
                self._candidate_hits = 1

        if self._candidate_hits >= self.required_consecutive:
            confirmed = self._candidate_text
            self._active_text = confirmed
            self._candidate_text = ""
            self._candidate_hits = 0
            speaker, dialogue = self.split_speaker(confirmed)
            return StabilizedSubtitle(
                raw_text=confirmed,
                speaker=speaker,
                dialogue=dialogue,
                is_clear_event=False,
            )

        return None
