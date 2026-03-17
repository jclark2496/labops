#!/usr/bin/env bash
set -e

# ── WSL 2 Bootstrap for LabOps ──
# Run this instead of 'make install' on Windows (WSL 2).
# It installs prerequisites, then hands off to the Makefile.

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  LabOps — WSL 2 Bootstrap                                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Check: are we in WSL 2? ──
if ! grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
    echo "⚠️  This script is for Windows (WSL 2) only."
    echo "   On macOS or Linux, run: make install"
    exit 1
fi
echo "✅ Running in WSL 2"

# ── Check: filesystem location ──
if echo "$PWD" | grep -q "^/mnt/[a-z]/"; then
    echo ""
    echo "❌ You cloned this repo on the Windows filesystem ($PWD)."
    echo "   Docker volume mounts will be extremely slow here."
    echo ""
    echo "   Fix: clone inside the WSL 2 filesystem instead:"
    echo "     cd ~"
    echo "     git clone https://github.com/jclark2496/labops.git"
    echo "     cd labops"
    echo "     ./setup-wsl.sh"
    echo ""
    exit 1
fi
echo "✅ Repo is on WSL 2 filesystem (good)"

# ── Install system prerequisites ──
echo "▶ Checking system packages..."
NEED_INSTALL=""
command -v make  >/dev/null 2>&1 || NEED_INSTALL="$NEED_INSTALL make"
command -v git   >/dev/null 2>&1 || NEED_INSTALL="$NEED_INSTALL git"
command -v pip3  >/dev/null 2>&1 || NEED_INSTALL="$NEED_INSTALL python3-pip"

if [ -n "$NEED_INSTALL" ]; then
    echo "▶ Installing:$NEED_INSTALL"
    sudo apt-get update -qq
    sudo apt-get install -y $NEED_INSTALL
    echo "✅ System packages installed"
else
    echo "✅ make, git, pip3 already installed"
fi

# ── Check Docker ──
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "✅ Docker is available"
else
    echo ""
    echo "❌ Docker is not available in this WSL 2 session."
    echo ""
    echo "   Fix:"
    echo "   1. Install Docker Desktop for Windows: https://docs.docker.com/desktop/install/windows-install/"
    echo "   2. Open Docker Desktop → Settings → Resources → WSL Integration"
    echo "   3. Enable integration for your Ubuntu distro"
    echo "   4. Restart this terminal and re-run ./setup-wsl.sh"
    echo ""
    exit 1
fi

# ── Fix line endings (prevent CRLF issues) ──
git config core.autocrlf input 2>/dev/null || true

# ── Hand off to Makefile ──
echo ""
echo "▶ Prerequisites ready — running 'make install'..."
echo ""
make install
