try {
    $adminRequired = [Security.Principal.WindowsIdentity]::GetCurrent()
    $adminRole = [Security.Principal.WindowsPrincipal]$adminRequired
    if (-not $adminRole.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Error: This script must be run as Administrator."
        Read-Host
        exit 1
    }

    $repoUrl = "https://github.com/BlueOnBLack/Unmanaged.PS1.Library/archive/refs/heads/main.zip"
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
iwr -Uri 'https://raw.githubusercontent.com/BlueOnBLack/PKeyInspector/refs/heads/main/PKeyConsole.ps1' | iex