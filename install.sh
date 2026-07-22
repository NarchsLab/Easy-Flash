#!/bin/bash
set -e

echo -e "\033[1;33m========================================="
echo "               DISCLAIMER                "
echo -e "=========================================\033[0m"
echo "This installation script requires root privileges to place the"
echo "global launcher directly into your system binary folders (/usr/sbin and /usr/bin)."
echo "If it's not already running as root, it will use sudo for those steps."
echo ""
echo "If you are unsure or do not fully trust this installer, please review"
echo "the code manually first - the source file this installer will copy from is:"
echo -e "  -> \033[1;36m$(pwd)/flash\033[0m"
echo -e "\033[1;33m=========================================\033[0m"
echo ""
read -p "Press Enter to agree and proceed with the installation, or Ctrl+C to abort..."

# If we're already root (e.g. script itself was launched with sudo, or by
# root directly), don't wrap every command in sudo on top of that.
if [ "$EUID" -eq 0 ]; then
    SUDO=""
    echo "[INFO] Already running as root - skipping sudo for install commands."
else
    SUDO="sudo"
fi

# 0. Make sure the file we're about to install actually exists before we
#    touch anything else. This is the plain 'flash' source file (no
#    .py extension) - the shebang gets prepended below.
SOURCE_FILE="flash"
if [ ! -f "$SOURCE_FILE" ]; then
    echo "[ERROR] Could not find '$SOURCE_FILE' in the current directory."
    echo "Make sure you're running this script from the folder that contains it, and try again."
    exit 1
fi

# 1. Find the correct Python path on the system
#    "|| true" keeps this from tripping 'set -e' if neither python3 nor
#    python is found, so our own error message below always gets a chance
#    to run.
PYTHON_PATH=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)
if [ -z "$PYTHON_PATH" ]; then
    echo "[ERROR] Python is not installed. Please install Python 3 first."
    exit 1
fi
echo "[INFO] Found Python at: $PYTHON_PATH"

# 2. Build the executable into a SEPARATE temp file, not back into
#    'flash' itself - since the source and destination share the same
#    name, writing the shebang straight into 'flash' with '>' would
#    truncate it before 'tail' ever reads the rest of the file.
BUILD_FILE=$(mktemp)
echo "Preparing extensionless 'flash' executable..."
echo "#!$PYTHON_PATH" > "$BUILD_FILE"
tail -n +2 "$SOURCE_FILE" >> "$BUILD_FILE"
chmod +x "$BUILD_FILE"

# 3. Copy to /usr/sbin and /usr/bin, tracking what succeeded so we can
#    roll back cleanly if something fails partway through.
sbin_copied=false
bin_copied=false

echo "Copying 'flash' executable to system paths..."

if ! $SUDO cp "$BUILD_FILE" /usr/sbin/flash; then
    echo "[ERROR] Failed to copy 'flash' to /usr/sbin/flash"
    rm -f "$BUILD_FILE"
    exit 1
fi
sbin_copied=true

if ! $SUDO cp "$BUILD_FILE" /usr/bin/flash; then
    echo "[ERROR] Failed to copy 'flash' to /usr/bin/flash"
    echo "[INFO] Rolling back /usr/sbin/flash..."
    $SUDO rm -f /usr/sbin/flash
    rm -f "$BUILD_FILE"
    exit 1
fi
bin_copied=true

# 4. Ensure permissions are correct
$SUDO chmod +x /usr/sbin/flash
$SUDO chmod +x /usr/bin/flash

# 5. Verify both installed files actually exist and are executable before
#    declaring success.
if [ ! -x "/usr/sbin/flash" ] || [ ! -x "/usr/bin/flash" ]; then
    echo "[ERROR] Verification failed - installed files were not found where expected."
    echo "  /usr/sbin/flash executable: $([ -x /usr/sbin/flash ] && echo yes || echo no)"
    echo "  /usr/bin/flash  executable: $([ -x /usr/bin/flash ] && echo yes || echo no)"
    echo "[INFO] Rolling back..."
    $sbin_copied && $SUDO rm -f /usr/sbin/flash
    $bin_copied && $SUDO rm -f /usr/bin/flash
    rm -f "$BUILD_FILE"
    exit 1
fi

# Clean up local temp file (leaves the original 'flash' source untouched)
rm -f "$BUILD_FILE"

echo ""
echo "========================================="
echo "         FLASHING MADE EASY              "
echo "========================================="
echo "Installation Complete! You can now type 'flash' from any directory."
echo "========================================="
echo ""
