# Ensure script runs with Administrator privileges (required to write to C:\Windows)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] This installer must be run as Administrator to copy files to system directories." -ForegroundColor Red
    Write-Host "Please restart PowerShell as Administrator and try again." -ForegroundColor Yellow
    Exit
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

# 1. Check/Install Python
$pythonInstalled = $false
try {
    $null = python --version -ErrorAction SilentlyContinue
    $pythonInstalled = $true
} catch {
    $pythonInstalled = $false
}

if (-not $pythonInstalled) {
    Write-Host "[INFO] Python is not detected. Installing Python via winget..." -ForegroundColor Yellow
    winget install -e --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# 2. Copy flash.py directly to C:\Windows (already in system PATH)
Write-Host "Copying script to system directory..." -ForegroundColor Cyan
Copy-Item -Path ".\flash.py" -Destination "C:\Windows\flash.py" -Force

# 3. Create flash.bat in C:\Windows so typing "flash" launches the script instantly
$BatchContent = "@echo off`npython `"C:\Windows\flash.py`" %*"
Set-Content -Path "C:\Windows\flash.bat" -Value $BatchContent -Force

Write-Host " "
Write-Host "=========================================" -ForegroundColor Green
Write-Host "         FLASHING MADE EASY              " -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host "Installation Complete! You can now run:" -ForegroundColor White
Write-Host "  flash" -ForegroundColor Yellow
Write-Host "from any folder on your computer instantly!" -ForegroundColor White
Write-Host "=========================================" -ForegroundColor Green
