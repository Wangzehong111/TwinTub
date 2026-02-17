#!/bin/bash
set -e

REPO="Wangzehong111/TwinTub"
APP_NAME="TwinTub"
INSTALL_DIR="/Applications"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       TwinTub Installer              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
echo ""

# Check for macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}❌ TwinTub is only supported on macOS${NC}"
    exit 1
fi

# Check architecture
ARCH=$(uname -m)
echo -e "${YELLOW}🔍 Detected architecture: $ARCH${NC}"

# Fetch latest release
echo -e "${YELLOW}📥 Fetching latest release...${NC}"
LATEST_URL=$(curl -s https://api.github.com/repos/$REPO/releases/latest | grep "browser_download_url.*\.zip" | head -1 | cut -d '"' -f 4)

if [ -z "$LATEST_URL" ]; then
    echo -e "${RED}❌ No release found. Please check if releases are published.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found release: $(basename $LATEST_URL)${NC}"

# Check if app already exists
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo -e "${YELLOW}⚠️  TwinTub already installed. Updating...${NC}"

    # Try to quit the app if running
    if pgrep -x "$APP_NAME" > /dev/null; then
        echo -e "${YELLOW}   Closing running TwinTub...${NC}"
        pkill -x "$APP_NAME" 2>/dev/null || true
        sleep 1
    fi

    # Remove old version
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

# Download
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

echo -e "${YELLOW}📦 Downloading...${NC}"
curl -L --progress-bar "$LATEST_URL" -o "$TMP_DIR/TwinTub.zip"

# Verify download
if [ ! -f "$TMP_DIR/TwinTub.zip" ] || [ ! -s "$TMP_DIR/TwinTub.zip" ]; then
    echo -e "${RED}❌ Download failed${NC}"
    exit 1
fi

# Extract
echo -e "${YELLOW}📂 Extracting...${NC}"
unzip -q "$TMP_DIR/TwinTub.zip" -d "$TMP_DIR"

# Verify extraction
if [ ! -d "$TMP_DIR/$APP_NAME.app" ]; then
    echo -e "${RED}❌ Extraction failed - app not found in archive${NC}"
    exit 1
fi

# Install
echo -e "${YELLOW}🚀 Installing to $INSTALL_DIR...${NC}"

# Use sudo if needed for /Applications
if [ -w "$INSTALL_DIR" ]; then
    mv "$TMP_DIR/$APP_NAME.app" "$INSTALL_DIR/"
else
    echo -e "${YELLOW}   Administrator password required...${NC}"
    sudo mv "$TMP_DIR/$APP_NAME.app" "$INSTALL_DIR/"
fi

# Verify installation
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ TwinTub installed successfully!  ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "   Open from Applications or run:"
    echo -e "   ${BLUE}open $INSTALL_DIR/$APP_NAME.app${NC}"
    echo ""
else
    echo -e "${RED}❌ Installation failed${NC}"
    exit 1
fi
