#!/bin/bash
set -euo pipefail

APP_NAME="Week Sheet"
BUNDLE_NAME="WeekSheet.app"
INSTALL_DIR="$HOME/Applications"
BUILD_DIR=".build/release"

echo "Building Week Sheet..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$BUNDLE_NAME"
mkdir -p "$BUNDLE_NAME/Contents/MacOS"
cp Info.plist "$BUNDLE_NAME/Contents/"
cp "$BUILD_DIR/WeekSheetApp" "$BUNDLE_NAME/Contents/MacOS/"

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$BUNDLE_NAME"
cp -R "$BUNDLE_NAME" "$INSTALL_DIR/"

echo ""
echo "Done! $APP_NAME installed to $INSTALL_DIR/$BUNDLE_NAME"
echo ""
echo "To start:  open \"$INSTALL_DIR/$BUNDLE_NAME\""
echo "To auto-start: use the 'Launch at Login' toggle in the menu bar icon"
echo ""
echo "Tip: You can also drag $INSTALL_DIR/$BUNDLE_NAME to your Dock."
