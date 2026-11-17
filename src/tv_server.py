from __future__ import annotations

import json
import logging
import socket
import subprocess
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict, Optional, Tuple

logger = logging.getLogger(__name__)


TV_WEB_CLIENT_HTML = """<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>GTA 6 (PS5) Canlı Türkçe Altyazı — TV Ekranı</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background: transparent;
    background-color: #000000;
    color: #ffffff;
    font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
    height: 100vh;
    display: flex;
    flex-direction: column;
    justify-content: flex-end;
    align-items: center;
    padding-bottom: 5vh;
    overflow: hidden;
  }
  body.chromakey { background-color: #00ff00; }
  #sub-box {
    max-width: 88vw;
    min-width: 40vw;
    background: rgba(10, 12, 18, 0.90);
    border: 1px solid rgba(255, 255, 255, 0.16);
    border-radius: 14px;
    padding: 18px 32px;
    text-align: center;
    box-shadow: 0 10px 30px rgba(0,0,0,0.75);
    transition: opacity 0.15s ease;
  }
  #sub-box.empty { opacity: 0; }
  #tr-text {
    font-size: clamp(22px, 3.2vw, 44px);
    font-weight: 700;
    line-height: 1.32;
    text-shadow: 2px 2px 4px rgba(0,0,0,0.95);
    white-space: pre-line;
  }
  #en-text {
    margin-top: 8px;
    font-size: clamp(14px, 1.8vw, 24px);
    color: #b0bec5;
    font-style: italic;
    display: none;
  }
  #meta {
    margin-top: 6px;
    font-size: 11px;
    color: #78909c;
    text-align: right;
  }
</style>
</head>
<body>
  <div id="sub-box" class="empty">
    <div id="tr-text"></div>
    <div id="en-text"></div>
    <div id="meta"></div>
  </div>
<script>
  const box = document.getElementById('sub-box');
  const trEl = document.getElementById('tr-text');
  const enEl = document.getElementById('en-text');
  const metaEl = document.getElementById('meta');
  let lastSeq = -1;

  const speakerColors = {
    "LUCIA": "#FF6B9D",
    "JASON": "#4FC3F7",
    "DEFAULT": "#FFD54F"
  };

  async function pollSubtitle() {
    try {
      const res = await fetch('/api/subtitle?since=' + lastSeq, { cache: 'no-store' });
      if (res.ok) {
        const data = await res.json();
        if (data.seq !== lastSeq) {
          lastSeq = data.seq;
          if (!data.turkish_text) {
            box.classList.add('empty');
          } else {
            box.classList.remove('empty');
            const spk = (data.speaker || '').toUpperCase();
            if (spk) {
              const color = speakerColors[spk] || speakerColors.DEFAULT;
              trEl.style.color = color;
              trEl.textContent = spk + ': ' + data.turkish_text;
            } else {
              trEl.style.color = '#FFFFFF';
              trEl.textContent = data.turkish_text;
            }
            if (data.show_original && data.english_text) {
              enEl.style.display = 'block';
              enEl.textContent = data.english_text;
            } else {
              enEl.style.display = 'none';
            }
            metaEl.textContent = data.meta || '';
          }
        }
      }
    } catch (e) {}
    setTimeout(pollSubtitle, 120);
  }
  pollSubtitle();
</script>
</body>
</html>
"""


class LocalSubtitleServer:
    """
    Ev Ağı Hibrit Mimarisi:
    PS5 doğrudan HDMI ile TV'ye bağlıyken (4K/HDR ve 0 ms kol gecikmesi),
    M2 MacBook Pro'nun okuduğu ve Türkçeye çevirdiği altyazıları yerel ağ (Wi-Fi/LAN)
    üzerinden Akıllı TV'ye (Android TV, LG webOS, Samsung Tizen, Multi-View Tarayıcı)
    anlık olarak yayınlayan yerel sunucu.
    """

    def __init__(self, port: int = 8765) -> None:
        self.port = port
        self._lock = threading.Lock()
        self._seq: int = 0
        self._state: Dict[str, Any] = {
            "seq": 0,
            "speaker": "",
            "turkish_text": "",
            "english_text": "",
            "meta": "",
            "show_original": False,
            "timestamp": time.time(),
        }
        self._server: Optional[ThreadingHTTPServer] = None
        self._thread: Optional[threading.Thread] = None

    @staticmethod
    def get_local_ip() -> str:
        """MacBook Pro'nun ev ağındaki yerel IP adresini (örn. 192.168.1.x) bulur."""
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.connect(("8.8.8.8", 80))
                return str(s.getsockname()[0])
        except Exception:
            return "127.0.0.1"

    def start(self) -> None:
        if self._server is not None:
            return

        parent = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: Any) -> None:
                pass  # Konsolu kirletmemek için HTTP erişim loglarını sustur

            def do_GET(self) -> None:
                if self.path.startswith("/api/subtitle"):
                    payload = parent.get_state_json()
                    body = payload.encode("utf-8")
                    self.send_response(HTTPStatus.OK)
                    self.send_header("Content-Type", "application/json; charset=utf-8")
                    self.send_header("Access-Control-Allow-Origin", "*")
                    self.send_header("Cache-Control", "no-store")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return

                # Ana sayfa: TV / Multi-View / WebOS / Tizen / Mobil Altyazı Ekranı
                body = TV_WEB_CLIENT_HTML.encode("utf-8")
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        try:
            self._server = ThreadingHTTPServer(("0.0.0.0", self.port), Handler)
            self._thread = threading.Thread(
                target=self._server.serve_forever,
                name="LocalSubtitleServer",
                daemon=True,
            )
            self._thread.start()
            logger.info(
                "Ev Ağı TV Altyazı Sunucusu başlatıldı: http://%s:%d",
                self.get_local_ip(),
                self.port,
            )
        except Exception as exc:
            logger.warning("TV Sunucusu başlatılamadı (port %d): %s", self.port, exc)

    def stop(self) -> None:
        if self._server is not None:
            try:
                self._server.shutdown()
                self._server.server_close()
            except Exception:
                pass
            self._server = None

    def broadcast_subtitle(
        self,
        speaker: Optional[str],
        turkish_text: str,
        english_text: str = "",
        meta: str = "",
        show_original: bool = False,
    ) -> None:
        with self._lock:
            self._seq += 1
            self._state = {
                "seq": self._seq,
                "speaker": speaker or "",
                "turkish_text": turkish_text,
                "english_text": english_text,
                "meta": meta,
                "show_original": show_original,
                "timestamp": time.time(),
            }

    def broadcast_clear(self) -> None:
        with self._lock:
            self._seq += 1
            self._state = {
                "seq": self._seq,
                "speaker": "",
                "turkish_text": "",
                "english_text": "",
                "meta": "",
                "show_original": False,
                "timestamp": time.time(),
            }

    def get_state_json(self) -> str:
        with self._lock:
            return json.dumps(self._state, ensure_ascii=False)

    @staticmethod
    def connect_android_tv_adb(tv_ip: str) -> Tuple[bool, str]:
        """
        Android TV / Google TV'ye yerel ağ üzerinden ADB ile bağlanmayı dener.
        (Android TV geliştirici modu bağlantısı).
        """
        clean_ip = tv_ip.strip()
        if not clean_ip:
            return False, "Lütfen TV'nin yerel IP adresini girin (örn. 192.168.1.50)."
        target = clean_ip if ":" in clean_ip else f"{clean_ip}:5555"
        try:
            proc = subprocess.run(
                ["adb", "connect", target],
                capture_output=True,
                text=True,
                timeout=5.0,
            )
            output = (proc.stdout or "") + (proc.stderr or "")
            if "connected to" in output.lower():
                return True, f"Android TV bağlantısı başarılı: {output.strip()}"
            return False, f"ADB yanıtı: {output.strip()}"
        except FileNotFoundError:
            return (
                False,
                "macOS üzerinde 'adb' aracı bulunamadı. Kurmak için Terminal'de: brew install android-platform-tools",
            )
        except Exception as exc:
            return False, f"Bağlantı hatası: {exc}"
