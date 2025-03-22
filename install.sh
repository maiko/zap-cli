#!/usr/bin/env bash

set -e

ZAP_NAME="zap"
ZAP_SRC="zap.sh"
INSTALL_DIR="${HOME}/bin"
INSTALL_PATH="${INSTALL_DIR}/${ZAP_NAME}"

echo "📦 Installing Zap to: ${INSTALL_PATH}"
mkdir -p "${INSTALL_DIR}"
cp "${ZAP_SRC}" "${INSTALL_PATH}"
chmod +x "${INSTALL_PATH}"

echo "✅ Installed successfully!"

# Check if ~/bin is in PATH
if ! echo "$PATH" | grep -q "${INSTALL_DIR}"; then
  echo "⚠️  Warning: ${INSTALL_DIR} is not in your \$PATH"
  echo "👉 Add this line to your ~/.bashrc or ~/.zshrc:"
  echo "   export PATH=\"${INSTALL_DIR}:\$PATH\""
fi

# Check dependencies
echo "🔍 Checking dependencies..."
missing=0

for bin in yq fzf ssh ping; do
  if ! command -v "$bin" > /dev/null; then
    echo "❌ Missing dependency: $bin"
    missing=1
  fi
done

if [[ "$missing" -eq 1 ]]; then
  echo ""
  echo "💡 Tip: Install missing dependencies using your package manager."
  echo "   macOS: brew install yq fzf"
  echo "   Debian/Ubuntu: see README for manual yq install"
else
  echo "✅ All dependencies look good!"
fi

echo ""
echo "🚀 You're ready to teleport with: zap help"
