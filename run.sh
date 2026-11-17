#!/usr/bin/env zsh
# ============================================================================
# GTA 6 (PS5) Canlı Türkçe Altyazı — M2 MacBook Pro Tek Tık Başlatıcı
# Kullanım:
#   ./run.sh              -> Canlı altyazı arayüzünü başlatır
#   ./run.sh --demo       -> Örnek GTA 6 altyazısıyla arayüzü başlatır
#   ./run.sh --self-test  -> M2 Apple Vision OCR + Çeviri hız testini çalıştırır
# ============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

if [ ! -f ".env" ] && [ -f ".env.example" ]; then
    cp .env.example .env
    echo "[Bilgi] .env dosyası oluşturuldu. API anahtarlarınızı .env içine ekleyebilirsiniz."
fi

if [ ! -d ".venv" ]; then
    echo "[Kurulum] Apple Silicon (arm64) Python sanal ortamı (.venv) oluşturuluyor..."
    python3 -m venv .venv
fi

source .venv/bin/activate

if ! python3 -c "import Vision, Quartz, PyQt6, rapidfuzz, imagehash" >/dev/null 2>&1; then
    echo "[Kurulum] Gerekli kütüphaneler yükleniyor..."
    pip install --upgrade pip
    pip install -r requirements.txt
fi

exec python3 -m src.main "$@"
