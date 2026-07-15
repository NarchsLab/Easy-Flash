#!/bin/bash
set -e

echo -e "\033[1;33m========================================="
echo "               DISCLAIMER                "
echo -e "=========================================\033[0m"
echo "This installation script requires root privileges (sudo) to place the"
echo "global launcher directly into your system binary folders (/usr/sbin and /usr/bin)."
echo ""
echo "If you are unsure or do not fully trust this installer, please review"
echo "the code manually first, or inspect the installed files at:"
echo -e "  -> \033[1;36m/usr/sbin/flash\033[0m"
echo -e "  -> \033[1;36m/usr/bin/flash\033[0m"
echo -e "\033[1;33m=========================================\033[0m"
echo ""
read -p "Press Enter to agree and proceed with the installation, or Ctrl+C to abort..."

# 1. Find the correct Python path on the system
PYTHON_PATH=$(which python3 || which python)

if [ -z "$PYTHON_PATH" ]; then
    echo "[ERROR] Python is not installed. Please install Python 3 first."
    exit 1
fi

echo "[INFO] Found Python at: $PYTHON_PATH"

# 2. Prepare the clean 'flash' file without .py extension
echo "Preparing extensionless 'flash' executable..."
echo "#!$PYTHON_PATH" > flash
tail -n +2 flash.py >> flash
chmod +x flash

# 3. Copy to /usr/sbin and /usr/bin (requires sudo)
echo "Copying 'flash' executable to system paths (requires sudo)..."
sudo cp flash /usr/sbin/flash
sudo cp flash /usr/bin/flash

# 4. Ensure permissions are correct
sudo chmod +x /usr/sbin/flash
sudo chmod +x /usr/bin/flash

# Clean up local temporary file
rm flash

echo ""
echo "========================================="
echo "         FLASHING MADE EASY              "
echo "========================================="
echo "Installation Complete! You can now type 'sudo flash' from any directory."
echo "========================================="
echo ""
