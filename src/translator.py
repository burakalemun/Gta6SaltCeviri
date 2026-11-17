from __future__ import annotations

import json
import logging
import os
import re
import sqlite3
import textwrap
import time
import urllib.request
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Deque, Dict, List, Optional, Tuple

try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False

logger = logging.getLogger(__name__)


@dataclass
class TranslationResult:
    """Çeviri çıktısını, kullanılan servisi ve gecikme bilgisini taşır."""

    speaker: Optional[str]
    source_text: str
    translated_text: str
    formatted_lines: str
    provider: str
    cached: bool
    latency_ms: float


class SubtitleTranslator:
    """
    SQLite önbellek + Kayan Bağlam Penceresi (Context Window) + GTA 6 Terimler Sözlüğü
    destekli hibrit çeviri motoru (Gemini Flash / DeepL API Free / Ollama Yerel LLM).
    """

    SYSTEM_PROMPT = (
        "Sen Grand Theft Auto VI (GTA 6) için profesyonel bir oyun yerelleştirme uzmanısın. "
        "Verilen İngilizce oyun altyazısını Türkçeye çevir.\n"
        "Kurallar:\n"
        "1. Sokak ağzını, argoyu, esprileri ve küfürleri sansürlemeden/yumuşatmadan doğal, "
        "akıcı bir sokak Türkçesiyle çevir.\n"
        "2. Özel isimleri, karakter adlarını ve yer adlarını (Lucia, Jason, Vice City, Leonida, VCPD vb.) "
        "kesinlikle çevirme.\n"
        "3. Altyazı okunabilirliği için çeviriyi kısa ve vurucu tut.\n"
        "4. SADECE Türkçe çeviri metnini döndür; açıklama, tırnak işareti veya konuşmacı adı ekleme."
    )

    # API anahtarı henüz girilmemişken test/demo modunda anında yanıt veren yerleşik GTA replikleri
    BUILTIN_DEMO_PHRASES: Dict[str, str] = {
        "the only way we're gonna get through this is by sticking together": (
            "Buradan sağ çıkmanın tek yolu birbirimize kenetlenmek."
        ),
        "trust?": "Güven mi?",
        "trust.": "Güven.",
        "let's get out of here before vcpd shows up!": (
            "VCPD buraya damlamadan hemen toz olalım!"
        ),
        "keep your head down and watch the back door.": (
            "Kafanı eğ ve arka kapıyı kolla."
        ),
        "we got heat on our tail, step on it!": (
            "Aynasızlar peşimizde, köklesene şu gazı!"
        ),
        "welcome to leonida, where anything can happen.": (
            "Her şeyin olabileceği Leonida'ya hoş geldiniz."
        ),
        "you know where to find boobie ike?": (
            "Boobie Ike'ı nerede bulacağımızı biliyor musun?"
        ),
    }

    def __init__(self, config: Dict[str, Any], project_root: Path) -> None:
        self.config = config
        self.project_root = project_root
        trans_cfg = config.get("translator", {})

        self.context_window_size: int = int(trans_cfg.get("context_window_size", 8))
        self.max_chars_per_line: int = int(trans_cfg.get("max_chars_per_line", 44))
        self.max_lines: int = int(trans_cfg.get("max_lines", 2))
        self.timeout_sec: float = float(trans_cfg.get("request_timeout_sec", 3.5))

        self.provider_mode: str = os.getenv("TRANSLATION_PROVIDER", "auto").strip().lower()
        self.gemini_api_key: str = os.getenv("GEMINI_API_KEY", "").strip()
        self.gemini_model: str = os.getenv("GEMINI_MODEL", "gemini-2.5-flash").strip()
        self.deepl_api_key: str = os.getenv("DEEPL_API_KEY", "").strip()
        self.ollama_base_url: str = os.getenv(
            "OLLAMA_BASE_URL", "http://127.0.0.1:11434"
        ).strip()
        self.ollama_model: str = os.getenv("OLLAMA_MODEL", "gemma2:9b").strip()

        self._context_history: Deque[Tuple[Optional[str], str, str]] = deque(
            maxlen=self.context_window_size
        )
        self._http = requests.Session() if HAS_REQUESTS else None

        # Sözlük ve Önbellek kurulumu
        glossary_rel = trans_cfg.get("glossary_path", "data/glossary.json")
        self.glossary_path = self.project_root / glossary_rel
        self.do_not_translate: List[str] = []
        self.slang_hints: Dict[str, str] = {}
        self._load_glossary()

        cache_rel = trans_cfg.get("cache_db_path", "data/cache.db")
        self.cache_db_path = (
            Path(cache_rel)
            if Path(cache_rel).is_absolute()
            else (self.project_root / cache_rel)
        )
        self.cache_db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_cache_db()

    def reload_settings(
        self,
        provider_mode: Optional[str] = None,
        gemini_api_key: Optional[str] = None,
        gemini_model: Optional[str] = None,
        deepl_api_key: Optional[str] = None,
        ollama_base_url: Optional[str] = None,
        ollama_model: Optional[str] = None,
    ) -> None:
        """Dashboard üzerinden değiştirilen API anahtarlarını ve motor seçimini canlı günceller."""
        if provider_mode is not None:
            self.provider_mode = provider_mode.strip().lower()
        if gemini_api_key is not None:
            self.gemini_api_key = gemini_api_key.strip()
        if gemini_model is not None:
            self.gemini_model = gemini_model.strip() or "gemini-2.5-flash"
        if deepl_api_key is not None:
            self.deepl_api_key = deepl_api_key.strip()
        if ollama_base_url is not None:
            self.ollama_base_url = ollama_base_url.strip() or "http://127.0.0.1:11434"
        if ollama_model is not None:
            self.ollama_model = ollama_model.strip() or "gemma2:9b"

    def get_cache_count(self) -> int:
        """SQLite önbellekte kayıtlı toplam çeviri sayısını döndürür."""
        try:
            with sqlite3.connect(self.cache_db_path) as conn:
                row = conn.execute("SELECT COUNT(*) FROM translations").fetchone()
                return int(row[0]) if row else 0
        except Exception:
            return 0

    def clear_cache(self) -> None:
        """SQLite önbelleğini ve diyalog bağlam geçmişini temizler."""
        self._context_history.clear()
        try:
            with sqlite3.connect(self.cache_db_path) as conn:
                conn.execute("DELETE FROM translations")
                conn.commit()
        except Exception as exc:
            logger.warning("Önbellek temizlenemedi: %s", exc)

    def _load_glossary(self) -> None:
        if not self.glossary_path.exists():
            return
        try:
            with open(self.glossary_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.do_not_translate = list(data.get("do_not_translate", []))
            self.slang_hints = dict(data.get("slang_hints", {}))
        except Exception as exc:
            logger.warning("Sözlük yüklenemedi (%s): %s", self.glossary_path, exc)

    def _init_cache_db(self) -> None:
        with sqlite3.connect(self.cache_db_path) as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS translations (
                    norm_key TEXT PRIMARY KEY,
                    source_text TEXT NOT NULL,
                    translated_text TEXT NOT NULL,
                    provider TEXT NOT NULL,
                    created_at REAL NOT NULL
                )
                """
            )
            conn.commit()

    @staticmethod
    def _normalize_key(text: str) -> str:
        cleaned = re.sub(r"\s+", " ", text.strip().lower())
        return cleaned

    def _get_from_cache(self, source_text: str) -> Optional[Tuple[str, str]]:
        key = self._normalize_key(source_text)
        if not key:
            return None
        try:
            with sqlite3.connect(self.cache_db_path) as conn:
                row = conn.execute(
                    "SELECT translated_text, provider FROM translations WHERE norm_key = ?",
                    (key,),
                ).fetchone()
                if row:
                    return str(row[0]), f"cache({row[1]})"
        except Exception as exc:
            logger.debug("Önbellek okuma hatası: %s", exc)

        if key in self.BUILTIN_DEMO_PHRASES:
            return self.BUILTIN_DEMO_PHRASES[key], "builtin-demo"
        return None

    def _save_to_cache(self, source_text: str, translated_text: str, provider: str) -> None:
        key = self._normalize_key(source_text)
        if not key or not translated_text:
            return
        try:
            with sqlite3.connect(self.cache_db_path) as conn:
                conn.execute(
                    """
                    INSERT OR REPLACE INTO translations
                    (norm_key, source_text, translated_text, provider, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (key, source_text, translated_text, provider, time.time()),
                )
                conn.commit()
        except Exception as exc:
            logger.debug("Önbellek yazma hatası: %s", exc)

    def format_subtitle_lines(self, text: str) -> str:
        """
        Çeviri metnini TV ekranında rahat okunacak şekilde
        en fazla `max_lines` satıra ve satır başına ~44 karaktere böler.
        """
        cleaned = re.sub(r"\s+", " ", text.strip()).strip('"').strip("'")
        if len(cleaned) <= self.max_chars_per_line:
            return cleaned

        wrapped = textwrap.wrap(
            cleaned,
            width=self.max_chars_per_line,
            break_long_words=False,
            break_on_hyphens=False,
        )
        if len(wrapped) <= self.max_lines:
            return "\n".join(wrapped)

        # 2 satırı aşıyorsa dengeli iki satır halinde birleştir
        mid = len(cleaned) // 2
        split_pos = cleaned.rfind(" ", 0, mid + 10)
        if split_pos == -1:
            split_pos = mid
        line1 = cleaned[:split_pos].strip()
        line2 = cleaned[split_pos:].strip()
        return f"{line1}\n{line2}"

    def _build_context_block(self, current_speaker: Optional[str], text: str) -> str:
        parts: List[str] = []
        if self.do_not_translate:
            parts.append(
                "Çevrilmeyecek Özel İsimler: " + ", ".join(self.do_not_translate[:25])
            )

        # Metinde geçen argo ipuçlarını ekle
        lower_text = text.lower()
        matched_slang = [
            f"{eng} -> {tr}"
            for eng, tr in self.slang_hints.items()
            if eng.lower() in lower_text
        ]
        if matched_slang:
            parts.append("Argo İpuçları: " + "; ".join(matched_slang))

        if self._context_history:
            hist_lines = []
            for spk, eng, tr in self._context_history:
                prefix = f"{spk}: " if spk else ""
                hist_lines.append(f"- {prefix}{eng} => {tr}")
            parts.append("Önceki Diyalog Bağlamı:\n" + "\n".join(hist_lines))

        speaker_note = f"Konuşmacı: {current_speaker}\n" if current_speaker else ""
        parts.append(f"{speaker_note}Çevrilecek İngilizce Replik: {text}")
        return "\n\n".join(parts)

    def _post_json(
        self,
        url: str,
        payload: Dict[str, Any],
        headers: Optional[Dict[str, str]] = None,
    ) -> Dict[str, Any]:
        req_headers = {"Content-Type": "application/json"}
        if headers:
            req_headers.update(headers)

        if self._http is not None:
            resp = self._http.post(
                url, json=payload, headers=req_headers, timeout=self.timeout_sec
            )
            resp.raise_for_status()
            return resp.json()

        raw_body = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url, data=raw_body, headers=req_headers, method="POST"
        )
        with urllib.request.urlopen(req, timeout=self.timeout_sec) as resp:
            return json.loads(resp.read().decode("utf-8"))

    def _translate_gemini(self, speaker: Optional[str], text: str) -> Optional[str]:
        if not self._has_valid_key(self.gemini_api_key):
            return None

        url = (
            f"https://generativelanguage.googleapis.com/v1beta/models/"
            f"{self.gemini_model}:generateContent?key={self.gemini_api_key}"
        )
        user_prompt = self._build_context_block(speaker, text)
        payload = {
            "systemInstruction": {"parts": [{"text": self.SYSTEM_PROMPT}]},
            "contents": [{"role": "user", "parts": [{"text": user_prompt}]}],
            "generationConfig": {
                "temperature": 0.25,
                "maxOutputTokens": 120,
            },
        }
        data = self._post_json(url, payload)
        candidates = data.get("candidates", [])
        if not candidates:
            return None
        parts = candidates[0].get("content", {}).get("parts", [])
        if not parts:
            return None
        result = str(parts[0].get("text", "")).strip()
        return result or None

    def _translate_deepl(self, speaker: Optional[str], text: str) -> Optional[str]:
        if not self._has_valid_key(self.deepl_api_key):
            return None

        is_free = self.deepl_api_key.endswith(":fx")
        base_url = (
            "https://api-free.deepl.com/v2/translate"
            if is_free
            else "https://api.deepl.com/v2/translate"
        )
        context_str = " ".join(eng for _, eng, _ in self._context_history)
        payload: Dict[str, Any] = {
            "text": [text],
            "source_lang": "EN",
            "target_lang": "TR",
        }
        if context_str:
            payload["context"] = context_str

        headers = {
            "Authorization": f"DeepL-Auth-Key {self.deepl_api_key}",
            "Content-Type": "application/json",
        }
        data = self._post_json(base_url, payload, headers=headers)
        translations = data.get("translations", [])
        if not translations:
            return None
        return str(translations[0].get("text", "")).strip() or None

    def _translate_ollama(self, speaker: Optional[str], text: str) -> Optional[str]:
        url = f"{self.ollama_base_url.rstrip('/')}/api/generate"
        prompt = f"{self.SYSTEM_PROMPT}\n\n{self._build_context_block(speaker, text)}"
        payload = {
            "model": self.ollama_model,
            "prompt": prompt,
            "stream": False,
            "options": {"temperature": 0.2, "num_predict": 90},
        }
        data = self._post_json(url, payload)
        return str(data.get("response", "")).strip() or None

    def _has_valid_key(self, key: str) -> bool:
        return bool(key) and not key.startswith("your_")

    def translate(self, speaker: Optional[str], dialogue: str) -> TranslationResult:
        """
        İngilizce altyazıyı önce SQLite önbellekte arar, yoksa seçili çeviri
        motoru zinciriyle (Gemini Flash / DeepL Free / Ollama) Türkçeye çevirir.
        """
        t0 = time.perf_counter()
        source = dialogue.strip()
        if not source:
            return TranslationResult(
                speaker=speaker,
                source_text="",
                translated_text="",
                formatted_lines="",
                provider="none",
                cached=True,
                latency_ms=0.0,
            )

        # 1) SQLite Önbellek kontrolü (0 ms)
        cached_hit = self._get_from_cache(source)
        if cached_hit is not None:
            tr_text, provider_name = cached_hit
            formatted = self.format_subtitle_lines(tr_text)
            self._context_history.append((speaker, source, tr_text))
            elapsed = (time.perf_counter() - t0) * 1000.0
            return TranslationResult(
                speaker=speaker,
                source_text=source,
                translated_text=tr_text,
                formatted_lines=formatted,
                provider=provider_name,
                cached=True,
                latency_ms=elapsed,
            )

        # 2) Çeviri Motoru Zinciri
        providers_order: List[Tuple[str, Any]] = []
        if self.provider_mode == "gemini":
            providers_order = [
                ("gemini-flash", self._translate_gemini),
                ("deepl-free", self._translate_deepl),
            ]
        elif self.provider_mode == "deepl":
            providers_order = [
                ("deepl-free", self._translate_deepl),
                ("gemini-flash", self._translate_gemini),
            ]
        elif self.provider_mode == "ollama":
            providers_order = [
                ("ollama-local", self._translate_ollama),
                ("gemini-flash", self._translate_gemini),
            ]
        else:
            # "auto": Argo kalitesi için önce Gemini veya DeepL (hangisinin anahtarı varsa)
            providers_order = [
                ("gemini-flash", self._translate_gemini),
                ("deepl-free", self._translate_deepl),
                ("ollama-local", self._translate_ollama),
            ]

        translated: Optional[str] = None
        used_provider = "unconfigured"

        for prov_name, fn in providers_order:
            try:
                out = fn(speaker, source)
                if out:
                    translated = out
                    used_provider = prov_name
                    break
            except Exception as exc:
                logger.debug("%s çeviri hatası: %s", prov_name, exc)

        # Hiçbir API anahtarı girilmemişse kullanıcıya bilgi vererek orijinal metni göster
        if not translated:
            translated = f"[Çeviri API Anahtarı Bekleniyor] {source}"
            used_provider = "fallback"
        else:
            self._save_to_cache(source, translated, used_provider)
            self._context_history.append((speaker, source, translated))

        formatted = self.format_subtitle_lines(translated)
        elapsed = (time.perf_counter() - t0) * 1000.0

        return TranslationResult(
            speaker=speaker,
            source_text=source,
            translated_text=translated,
            formatted_lines=formatted,
            provider=used_provider,
            cached=False,
            latency_ms=elapsed,
        )
