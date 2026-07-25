#!/bin/bash
set -e

# ---------------------------------------------------------------------------
# Detect whether we're running inside Termux (Android) before we print the
# disclaimer, so the wording matches the environment we're actually in.
# ---------------------------------------------------------------------------
IS_TERMUX=false
if [ -n "$TERMUX_VERSION" ]; then
    IS_TERMUX=true
elif [ -n "$PREFIX" ] && [[ "$PREFIX" == *"/com.termux/"* ]]; then
    IS_TERMUX=true
elif [ -n "$HOME" ] && [[ "$HOME" == *"/com.termux/"* ]]; then
    IS_TERMUX=true
elif [ -d "/data/data/com.termux/files/usr" ]; then
    IS_TERMUX=true
fi

# If PREFIX itself isn't set (shouldn't happen in a real Termux shell, but
# we don't want to reference an empty/undefined path later), fall back to
# the standard Termux location.
if $IS_TERMUX && [ -z "$PREFIX" ]; then
    PREFIX="/data/data/com.termux/files/usr"
fi

# Default to no sudo wrapper; the PC branch below may override this.
SUDO=""

# ---------------------------------------------------------------------------
# Optional: download Magisk, pull out the right libmagiskboot.so for this
# CPU, rename it to 'mb', and install it alongside 'flash' so that
# `flash -p/--payload-bin <payload.bin>` works. Works on both Termux and
# regular Linux (Magisk ships arm64-v8a / armeabi-v7a / x86 / x86_64 libs).
# Always cleans up its working directory when done, success or failure.
# ---------------------------------------------------------------------------
install_payload_bin_support() {
    local install_dir="$1"

    echo ""
    read -p "Add payload.bin support (via magiskboot, lets 'flash -p <payload.bin>' unpack and flash OTA images)? [y/N] " ADD_PAYLOAD
    if [[ ! "$ADD_PAYLOAD" =~ ^[Yy]$ ]]; then
        echo "[INFO] Skipping payload.bin support."
        return
    fi

    if [ -z "$install_dir" ] || [ ! -d "$install_dir" ]; then
        echo "[ERROR] No valid install directory to place 'mb' in - skipping payload.bin support."
        return
    fi

    local work_dir
    if $IS_TERMUX; then
        work_dir="$HOME/tmp/magisk-extract"
    else
        work_dir="/tmp/magisk-extract"
    fi
    mkdir -p "$work_dir"

    local magisk_url="https://github.com/topjohnwu/Magisk/releases/download/v30.7/Magisk-v30.7.apk"
    local apk_file="$work_dir/Magisk-v30.7.apk"
    local zip_file="$work_dir/Magisk-v30.7.zip"

    echo "[INFO] Downloading Magisk v30.7..."
    if command -v curl >/dev/null 2>&1; then
        curl -fL -o "$apk_file" "$magisk_url" || true
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$apk_file" "$magisk_url" || true
    else
        echo "[ERROR] Neither curl nor wget is available - can't download Magisk."
        rm -rf "$work_dir"
        return
    fi

    if [ ! -s "$apk_file" ]; then
        echo "[ERROR] Download failed or produced an empty file."
        rm -rf "$work_dir"
        return
    fi

    # An APK is just a zip file with a different extension - copy/rename so
    # unzip doesn't complain, without touching the original download.
    cp "$apk_file" "$zip_file"

    local arch libdir=""
    arch=$(uname -m)
    case "$arch" in
        aarch64|arm64)      libdir="arm64-v8a"  ;;
        armv7l|armv8l|arm)  libdir="armeabi-v7a" ;;
        x86_64|amd64)       libdir="x86_64"     ;;
        i686|i386)          libdir="x86"        ;;
    esac

    if [ -z "$libdir" ]; then
        echo "[ERROR] Unrecognized CPU architecture '$arch' - don't know which libmagiskboot.so to grab."
        rm -rf "$work_dir"
        return
    fi
    echo "[INFO] Detected architecture: $arch -> lib/$libdir"

    if ! command -v unzip >/dev/null 2>&1; then
        echo "[ERROR] 'unzip' is required but not found - can't extract the APK."
        rm -rf "$work_dir"
        return
    fi

    # -j flattens the path, so this lands directly at $work_dir/libmagiskboot.so
    unzip -o -j "$zip_file" "lib/$libdir/libmagiskboot.so" -d "$work_dir" >/dev/null 2>&1 || true

    if [ ! -f "$work_dir/libmagiskboot.so" ]; then
        echo "[ERROR] Could not find lib/$libdir/libmagiskboot.so inside the APK."
        echo "This Magisk build may not ship a library for your architecture."
        rm -rf "$work_dir"
        return
    fi

    if $SUDO mv "$work_dir/libmagiskboot.so" "$install_dir/mb" 2>/dev/null; then
        $SUDO chmod +x "$install_dir/mb"
        echo "[INFO] Installed magiskboot as: $install_dir/mb"
        echo "[INFO] Use it via: flash -p <payload.bin>"
    else
        echo "[ERROR] Could not move magiskboot into $install_dir (permission denied?)."
    fi

    # Always clean up the temp working folder, whether or not this succeeded.
    rm -rf "$work_dir"
}

echo -e "\033[1;33m========================================="
echo "               DISCLAIMER                "
echo -e "=========================================\033[0m"
if $IS_TERMUX; then
    echo "This installation script will place the 'flash' launcher into"
    echo "\$PREFIX/bin (Termux) or, if you choose and your device supports it,"
    echo "into your system bin path (requires root)."
else
    echo "This installation script requires root privileges to place the"
    echo "global launcher directly into your system binary folders (/usr/sbin and /usr/bin)."
    echo "If it's not already running as root, it will use sudo for those steps."
fi
echo ""
echo "If you are unsure or do not fully trust this installer, please review"
echo "the code manually first - the source file this installer will copy from is:"
echo -e "  -> \033[1;36m$(pwd)/flash\033[0m"
echo -e "\033[1;33m=========================================\033[0m"
echo ""
read -p "Press Enter to agree and proceed with the installation, or Ctrl+C to abort..."

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

# ===========================================================================
# TERMUX (ANDROID) INSTALL PATH
# ===========================================================================
if $IS_TERMUX; then
    echo "Running on Android (Termux)"
    echo ""
    echo "fastboot/adb don't work natively under Termux. nohajc's termux-adb project"
    echo "(https://github.com/nohajc/termux-adb) adds working termux-fastboot / termux-adb"
    echo "support by installing the 'termux-adb' package from his apt repo."
    echo ""
    read -p "Install termux-adb/termux-fastboot support now? [y/N] " INSTALL_TERMUX_ADB
    if [[ "$INSTALL_TERMUX_ADB" =~ ^[Yy]$ ]]; then
        echo "[INFO] Installing termux-adb (from https://nohajc.github.io)..."
        apt-get update
        apt-get --assume-yes upgrade
        apt-get --assume-yes install coreutils gnupg wget

        if [ ! -f "$PREFIX/etc/apt/sources.list.d/termux-adb.list" ]; then
            mkdir -p "$PREFIX/etc/apt/sources.list.d"
            echo "deb https://nohajc.github.io termux extras" > "$PREFIX/etc/apt/sources.list.d/termux-adb.list"
            wget -qP "$PREFIX/etc/apt/trusted.gpg.d" https://nohajc.github.io/nohajc.gpg
            apt update
        else
            echo "[INFO] nohajc's repo is already configured."
        fi

        apt install -y termux-adb
        echo "[INFO] termux-adb installed."
    else
        echo "[INFO] Skipping termux-adb install."
    fi
    echo ""

    # Check for root. On a non-rooted device with no su binary, Termux's
    # own su stub prints a fixed message to stderr; we capture both
    # stdout and stderr so we can pattern-match on it. "|| true" stops
    # 'set -e' from killing the script on the non-zero exit code.
    ROOT_CHECK=$(su -c whoami 2>&1) || true
    INSTALL_DIR=""

    if echo "$ROOT_CHECK" | grep -qi "No su program found"; then
        # --- Not rooted (or su not granted) ---
        echo "[INFO] Root was not detected on this device - either it is not rooted,"
        echo "or you have not granted it superuser permissions."
        echo "Installing to \$PREFIX/bin instead."
        cp "$BUILD_FILE" "$PREFIX/bin/flash"
        chmod +x "$PREFIX/bin/flash"
        echo "Installed: $PREFIX/bin/flash"
        INSTALL_DIR="$PREFIX/bin"

    elif echo "$ROOT_CHECK" | grep -qw "root"; then
        # --- su exists and grants root ---
        if [ "$(id -u)" -eq 0 ]; then
            # Script itself is currently running as root (e.g. launched via su).
            echo "You are running this as root."
            echo "Do you want to continue and add this script to your system's bin path?"
            read -p "Press Enter to continue, or Ctrl+C to cancel..."

            # Check whether the system partition is mounted rw and is ext4.
            MOUNT_INFO=$(mount | grep -E ' on /system ' || mount | grep -E ' /system ' || true)

            if echo "$MOUNT_INFO" | grep -qi 'ext4' && echo "$MOUNT_INFO" | grep -Eq '\(rw|rw,'; then
                mount -o rw,remount /system 2>/dev/null || true
                cp "$BUILD_FILE" /system/bin/flash
                chmod +x /system/bin/flash
                echo "Installed: /system/bin/flash"
                INSTALL_DIR="/system/bin"
            else
                echo "[ERROR] This device is not capable of adding custom scripts to your system path."
                echo "Your /system partition is not both ext4 and mounted read-write."
                echo "If you would like to add it to your system path, consider using a custom ROM"
                echo "such as LineageOS, which may give you an ext4, rw /system partition"
                echo "(and other changes needed to make this work)."
            fi
        else
            # Root is available on the device, but this script wasn't launched as root.
            echo "[INFO] Root was detected on this device."
            echo "If you want to add this script to your system bin path, please run this script as root."
            read -p "Press Enter to continue and install to \$PREFIX/bin instead, or Ctrl+C to abort and rerun as root..."
            cp "$BUILD_FILE" "$PREFIX/bin/flash"
            chmod +x "$PREFIX/bin/flash"
            echo "Installed: $PREFIX/bin/flash"
            INSTALL_DIR="$PREFIX/bin"
        fi

    else
        # Unexpected su output - fall back safely rather than guessing.
        echo "[WARN] Unrecognized response from root check: $ROOT_CHECK"
        echo "Installing to \$PREFIX/bin instead."
        cp "$BUILD_FILE" "$PREFIX/bin/flash"
        chmod +x "$PREFIX/bin/flash"
        INSTALL_DIR="$PREFIX/bin"
    fi

    rm -f "$BUILD_FILE"

    if [ -n "$INSTALL_DIR" ]; then
        install_payload_bin_support "$INSTALL_DIR"
    fi

    echo ""
    echo "========================================="
    echo "         FLASHING MADE EASY              "
    echo "========================================="
    echo "Installation complete."
    echo "========================================="
    exit 0
fi

# ===========================================================================
# REGULAR LINUX / PC INSTALL PATH (unchanged behavior)
# ===========================================================================

if [ "$EUID" -eq 0 ]; then
    SUDO=""
    echo "[INFO] Already running as root - skipping sudo for install commands."
else
    SUDO="sudo"
fi

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

install_payload_bin_support "/usr/bin"

echo ""
echo "========================================="
echo "         FLASHING MADE EASY              "
echo "========================================="
echo "Installation Complete! You can now type 'flash' from any directory."
echo "========================================="
echo ""

