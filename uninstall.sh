#!/bin/bash
set -e

APP_NAME="TwinTub"
INSTALL_DIR="/Applications"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      TwinTub Uninstaller             ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
echo ""

# Check if app is installed
if [ ! -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo -e "${YELLOW}⚠️  TwinTub is not installed${NC}"
    exit 0
fi

# Ask for confirmation
echo -e "${YELLOW}This will remove TwinTub from your Applications folder.${NC}"
read -p "Continue? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled.${NC}"
    exit 0
fi

# Quit the app if running
if pgrep -x "$APP_NAME" > /dev/null; then
    echo -e "${YELLOW}   Closing running TwinTub...${NC}"
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
fi

# Remove the app
echo -e "${YELLOW}🗑️  Removing TwinTub...${NC}"

if [ -w "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
else
    echo -e "${YELLOW}   Administrator password required...${NC}"
    sudo rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

# Verify removal
if [ ! -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ TwinTub uninstalled successfully ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
else
    echo -e "${RED}❌ Uninstallation failed${NC}"
    exit 1
fi

# Optional: Ask about config files
CONFIG_DIR="$HOME/.twintub"
if [ -d "$CONFIG_DIR" ]; then
    echo -e "${YELLOW}Config directory found at $CONFIG_DIR${NC}"
    read -p "Remove config files too? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        echo -e "${GREEN}✓ Config files removed${NC}"
    fi
fi
