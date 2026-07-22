# Ensure script runs with Administrator privileges (required to write to C:\Windows)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] This installer must be run as Administrator to copy files to system directories." -ForegroundColor Red
    Write-Host "Please restart PowerShell as Administrator and try again." -ForegroundColor Yellow
    Exit 1
}

Write-Host "=========================================" -ForegroundColor Yellow
Write-Host "               DISCLAIMER                " -ForegroundColor Yellow
Write-Host "=========================================" -ForegroundColor Yellow
Write-Host "This installation script requires Administrator privileges to place the"
Write-Host "global launcher directly into your C:\Windows system directory."
Write-Host ""
Write-Host "If you are unsure or do not fully trust this installer, please review"
Write-Host "the code manually first, or inspect the installed files at:"
Write-Host "  -> C:\Windows\flash.py" -ForegroundColor Cyan
Write-Host "  -> C:\Windows\flash.bat" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Yellow
Write-Host ""
Read-Host "Press Enter to agree and proceed with the installation, or Ctrl+C to abort..."

# Capture the folder we were launched from BEFORE we change location or copy
# anything - this is what we'll optionally delete at the very end.
$sourceDir  = (Get-Location).Path
$sourceFile = Join-Path $sourceDir "flash"
$destPy     = "C:\Windows\flash.py"
$destBat    = "C:\Windows\flash.bat"

# 0. Verify the file we're supposed to install actually exists before we
#    touch anything, so we don't do a partial/broken install.
if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
    Write-Host "[ERROR] Could not find the source file to install: '$sourceFile'" -ForegroundColor Red
    Write-Host "Make sure you're running this script from the folder that contains 'flash', and try again." -ForegroundColor Yellow
    Exit 1
}

# 1. Check/Install Python
$pythonInstalled = $false
try {
    $null = Get-Command python -ErrorAction Stop
    $pythonInstalled = $true
} catch {
    $pythonInstalled = $false
}

if (-not $pythonInstalled) {
    Write-Host "[INFO] Python is not detected. Installing Python via winget..." -ForegroundColor Yellow
    try {
        winget install -e --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "winget exited with code $LASTEXITCODE"
        }
    } catch {
        Write-Host "[ERROR] Failed to install Python automatically: $_" -ForegroundColor Red
        Write-Host "Please install Python manually from https://www.python.org/downloads/ and re-run this installer." -ForegroundColor Yellow
        Exit 1
    }
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    # Re-check after install so we don't silently continue with a broken PATH
    try {
        $null = Get-Command python -ErrorAction Stop
    } catch {
        Write-Host "[ERROR] Python still isn't available on PATH after installation." -ForegroundColor Red
        Write-Host "Please open a new terminal (or restart) and re-run this installer." -ForegroundColor Yellow
        Exit 1
    }
}

# Helper: undo whatever partially made it onto the system, so a failed
# install doesn't leave stray files in C:\Windows or lose the user's copy.
function Undo-Install {
    param(
        [bool]$pyWasCopied,
        [bool]$batWasCreated
    )

    Write-Host "[INFO] Rolling back changes..." -ForegroundColor Yellow

    if ($batWasCreated -and (Test-Path -LiteralPath $destBat -PathType Leaf)) {
        Remove-Item -LiteralPath $destBat -Force -ErrorAction SilentlyContinue
        Write-Host "[INFO] Removed $destBat" -ForegroundColor Yellow
    }

    if ($pyWasCopied -and (Test-Path -LiteralPath $destPy -PathType Leaf)) {
        try {
            Move-Item -LiteralPath $destPy -Destination $sourceFile -Force -ErrorAction Stop
            Write-Host "[INFO] Moved $destPy back to '$sourceFile'" -ForegroundColor Yellow
        } catch {
            Write-Host "[ERROR] Could not move $destPy back to '$sourceFile': $_" -ForegroundColor Red
            Write-Host "The original file was left in place at $destPy - please move it back manually." -ForegroundColor Red
        }
    }
}

# 2. Copy flash.py to C:\Windows (already in system PATH)
Write-Host "Copying script to system directory..." -ForegroundColor Cyan
$pyCopied = $false
try {
    Copy-Item -LiteralPath $sourceFile -Destination $destPy -Force -ErrorAction Stop
    $pyCopied = $true
} catch {
    Write-Host "[ERROR] Failed to copy '$sourceFile' to '$destPy': $_" -ForegroundColor Red
    Undo-Install -pyWasCopied $false -batWasCreated $false
    Exit 1
}

# 3. Create flash.bat in C:\Windows so typing "flash" launches the script instantly
$batCreated = $false
try {
    $BatchContent = "@echo off`npython `"$destPy`" %*"
    Set-Content -LiteralPath $destBat -Value $BatchContent -Force -ErrorAction Stop
    $batCreated = $true
} catch {
    Write-Host "[ERROR] Failed to create '$destBat': $_" -ForegroundColor Red
    Undo-Install -pyWasCopied $pyCopied -batWasCreated $false
    Exit 1
}

# 4. Verify both files actually landed where they should before declaring victory.
$pyOk  = Test-Path -LiteralPath $destPy -PathType Leaf
$batOk = Test-Path -LiteralPath $destBat -PathType Leaf

if (-not ($pyOk -and $batOk)) {
    Write-Host "[ERROR] Verification failed - installed files were not found where expected." -ForegroundColor Red
    Write-Host "  $destPy  exists: $pyOk"
    Write-Host "  $destBat exists: $batOk"
    Undo-Install -pyWasCopied $pyCopied -batWasCreated $batCreated
    Exit 1
}

Write-Host " "
Write-Host "=========================================" -ForegroundColor Green
Write-Host "         FLASHING MADE EASY              " -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host "Installation Complete! You can now run:" -ForegroundColor White
Write-Host "  flash" -ForegroundColor Yellow
Write-Host "from any folder on your computer instantly!" -ForegroundColor White
Write-Host "=========================================" -ForegroundColor Green

# 5. Everything verified and in place, so the folder we launched from is no
#    longer needed. We can't just Remove-Item it directly here: this script
#    (and this PowerShell process's working directory) is still running out
#    of that folder, so Windows keeps a handle open on it and an immediate
#    delete usually fails with "file in use" / "access denied" errors, even
#    after cd-ing out of it.
#
# Workaround: move out of the folder, then spawn a small detached helper
# process that waits a couple seconds for THIS process to fully exit and
# release its handle, then deletes the folder on its own. The helper is
# started with -WindowStyle Hidden and is not a child job of this session,
# so it keeps running after this script (and its window) closes.
$parentDir = Split-Path -Parent $sourceDir
Set-Location $parentDir

try {
    $cleanupScript = "Start-Sleep -Seconds 2; " +
        "try { Remove-Item -LiteralPath '$sourceDir' -Recurse -Force -ErrorAction Stop } catch { }"

    Start-Process -FilePath "powershell.exe" `
        -ArgumentList @("-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", $cleanupScript) `
        -WindowStyle Hidden | Out-Null

    Write-Host "[INFO] Temporary install folder will be removed automatically: $sourceDir" -ForegroundColor Cyan
} catch {
    Write-Host "[WARN] Installation succeeded, but automatic cleanup could not be scheduled: $_" -ForegroundColor Yellow
    Write-Host "You can safely delete '$sourceDir' yourself." -ForegroundColor Yellow
}
