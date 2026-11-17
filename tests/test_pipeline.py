from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# rapidfuzz henüz kurulmamışsa bile temel mantığı test edebilmek için yedek
try:
    import rapidfuzz  # noqa: F401
    HAS_RAPIDFUZZ = True
except ImportError:
    HAS_RAPIDFUZZ = False

from src.stabilizer import SubtitleStabilizer
from src.translator import SubtitleTranslator
from src.tv_server import LocalSubtitleServer


class TestTranslatorAndConfig(unittest.TestCase):
    def setUp(self) -> None:
        self.config_path = Path(__file__).resolve().parent.parent / "config.json"
        with open(self.config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)

    def test_config_and_glossary_exist(self) -> None:
        glossary_path = Path(__file__).resolve().parent.parent / "data" / "glossary.json"
        self.assertTrue(glossary_path.exists())
        with open(glossary_path, "r", encoding="utf-8") as f:
            glossary = json.load(f)
        self.assertIn("Lucia", glossary["do_not_translate"])
        self.assertIn("Vice City", glossary["do_not_translate"])

    def test_sqlite_cache_and_builtin_phrases(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            (root / "data").mkdir(parents=True, exist_ok=True)
            glossary_src = Path(__file__).resolve().parent.parent / "data" / "glossary.json"
            (root / "data" / "glossary.json").write_text(
                glossary_src.read_text(encoding="utf-8"), encoding="utf-8"
            )

            translator = SubtitleTranslator(self.config, root)
            res = translator.translate(
                "LUCIA",
                "The only way we're gonna get through this is by sticking together",
            )
            self.assertEqual(res.speaker, "LUCIA")
            self.assertIn("birbirimize kenetlenmek", res.translated_text)
            self.assertTrue(res.cached)

            # Özel çeviri kaydet ve önbellekten oku
            translator._save_to_cache("Stay in the car, Jason.", "Arabada kal Jason.", "gemini-flash")
            cached_res = translator.translate("LUCIA", "Stay in the car, Jason.")
            self.assertTrue(cached_res.cached)
            self.assertEqual(cached_res.translated_text, "Arabada kal Jason.")
            self.assertEqual(cached_res.provider, "cache(gemini-flash)")

    def test_line_wrapping_for_tv(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            translator = SubtitleTranslator(self.config, root)
            long_tr = (
                "VCPD devriyeleri bütün köprüleri kapatmadan önce Vice City "
                "limanındaki tekneye ulaşmamız gerekiyor."
            )
            wrapped = translator.format_subtitle_lines(long_tr)
            lines = wrapped.split("\n")
            self.assertLessEqual(len(lines), 2)

    def test_stabilizer_speaker_and_consecutive_frames(self) -> None:
        stab = SubtitleStabilizer(self.config)
        # 1. kare: henüz aday, onaylanmamalı (required_consecutive_frames = 2)
        r1 = stab.process_ocr_text("LUCIA: Let's get out of here!")
        self.assertIsNone(r1)

        # 2. kare: ardışık doğrulama tamamlandı -> onaylanmalı
        r2 = stab.process_ocr_text("LUCIA: Let's get out of here!")
        self.assertIsNotNone(r2)
        assert r2 is not None
        self.assertEqual(r2.speaker, "LUCIA")
        self.assertEqual(r2.dialogue, "Let's get out of here!")
        self.assertFalse(r2.is_clear_event)

        # 3. kare: aynı metin ekranda duruyor -> tekrar çeviri tetiklememeli
        r3 = stab.process_ocr_text("LUCIA: Let's get out of here.")
        self.assertIsNone(r3)

    def test_tv_server_state_broadcast(self) -> None:
        srv = LocalSubtitleServer(port=0)
        srv.broadcast_subtitle(
            speaker="LUCIA",
            turkish_text="Hemen buradan toz olalım!",
            english_text="Let's get out of here!",
            meta="Vision 24ms",
        )
        state = json.loads(srv.get_state_json())
        self.assertEqual(state["speaker"], "LUCIA")
        self.assertEqual(state["turkish_text"], "Hemen buradan toz olalım!")
        self.assertEqual(state["seq"], 1)

        srv.broadcast_clear()
        cleared = json.loads(srv.get_state_json())
        self.assertEqual(cleared["turkish_text"], "")
        self.assertEqual(cleared["seq"], 2)


if __name__ == "__main__":
    unittest.main()
