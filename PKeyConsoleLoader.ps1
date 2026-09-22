try {
    $adminRequired = [Security.Principal.WindowsIdentity]::GetCurrent()
    $adminRole = [Security.Principal.WindowsPrincipal]$adminRequired
    if (-not $adminRole.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Error: This script must be run as Administrator."
        Read-Host
        exit 1
    }

    $repoUrl = "https://github.com/v8k6b2jjps-prog/Unmanaged.PS1.Library/archive/refs/heads/main.zip"
    $moduleFolder = "C:\Windows\System32\WindowsPowerShell\v1.0\Modules\NativeInteropLib"
    $tempFolder = "$env:TEMP\Unmanaged.PS1.Library"
    $zipFile = "$tempFolder.zip"

    Invoke-WebRequest -Uri $repoUrl -OutFile $zipFile
    Expand-Archive -Path $zipFile -DestinationPath $tempFolder -Force
    if (-not (Test-Path $moduleFolder)) { New-Item -Path $moduleFolder -ItemType Directory }
    Copy-Item -Path "$tempFolder\Unmanaged.PS1.Library-main\*" -Destination $moduleFolder -Recurse -Force
    Remove-Item -Path $zipFile -Force | Out-Null
    Remove-Item -Path $tempFolder -Recurse -Force | Out-Null
}
catch {
	write-error "Fail to install Libary"
}

# Define paths and URLs
$installDir = "$env:TEMP\PKeyInspector"
if (!(Test-Path $installDir)) { New-Item -ItemType Directory -Force -Path $installDir | Out-Null }

$consoleUrl = "https://raw.githubusercontent.com/v8k6b2jjps-prog/PKeyInspector/refs/heads/main/PKeyConsole.ps1"
$guiUrl     = "https://raw.githubusercontent.com/v8k6b2jjps-prog/PKeyInspector/refs/heads/main/PKeyInspector.ps1"

$consolePath = "$installDir\PKeyConsole.ps1"
$guiPath     = "$installDir\PKeyInspector.ps1"

Write-Host "Downloading required files locally..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $consoleUrl -OutFile $consolePath -ErrorAction Stop
    Invoke-WebRequest -Uri $guiUrl -OutFile $guiPath -ErrorAction Stop
    Write-Host "Download complete!" -ForegroundColor Green
} catch {
    Write-Error "Failed to download files: $_"
    exit
}

# Menu selection
do {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "         PKeyInspector Launcher         " -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " [1] Run Console Mode (PKeyConsole.ps1)"
    Write-Host " [2] Run GUI Mode (PKeyInspector.ps1)"
    Write-Host " [3] Exit"
    Write-Host "----------------------------------------"
    
    $choice = Read-Host "Please select an option (1-3)"

    switch ($choice) {
        '1' {
            Write-Host "Starting Console Mode..." -ForegroundColor Green
            & $consolePath
            Pause
        }
        '2' {
            Write-Host "Starting GUI Mode..." -ForegroundColor Green
            & $guiPath
            Pause
        }
        '3' {
            Write-Host "Exiting..." -ForegroundColor Yellow
            break
        }
        default {
            Write-Host "Invalid choice. Please select 1, 2, or 3." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while ($choice -ne '3')