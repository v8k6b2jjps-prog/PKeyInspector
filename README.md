# PKeyInspector

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)]()
[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)]()
[![Releases](https://img.shields.io/badge/releases-v1.0-blue.svg)]()

> POC: Parse Office/Windows `pkeyconfig` and related SKU/license metadata and present interactive HTML reports (searchable) with export to PDF, Excel, CSV, and more.  
> Uses advanced, low‑level techniques (including undocumented or platform‑internal APIs) to collect richer system metadata

---

## About
**PKeyInspector** is a Proof‑Of‑Concept tool for administrators, auditors, and authorized researchers that aggregates metadata from `pkeyconfig` files, 

vendor XMLs, and system sources and produces human‑friendly reports (HTML, PDF, Excel, CSV). 

It also demonstrates the use of low‑level and undocumented platform internals to collect richer metadata when required.

Quick load **NativeLib Console** From ISE or Terminal / powershell [As Admin]
````powershell
iwr 'https://tinyurl.com/pkeyLoader' | iex
````
---

### Pre Install before use
**NativeLib** must be install before use this tool
````powershell
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
````

---

## Capabilities (feature list)
> Full feature surface.

- Parse `pkeyconfig` XML files (Office/Windows) and extract SKU/product metadata.
- Interactive **HTML** reports with client‑side search/filter, paging, and sorting.
- Export to **PDF**, **Excel (.xlsx)**, **CSV**, and other formats.
- Consolidate latest product + key metadata from local files and vendor datasets.
- Present keys as **Genuine** or **Generated** (generated keys via pattern/encoding modules are research‑only).
- Encoding options:
  - Encode using documented APIs by SKU/GUID (where supported).
  - Encode by selected **pattern** or bulk encode via internal reference list (2000+ entries) — research‑only where it involves undocumented behavior.
- Decoding options:
  - Decode KeyInfo-like structures; parse binary payloads in read‑only mode.
  - Folder scanning and batch decode (read‑only, non‑destructive).
- Extraction options.
  - Candidate extraction from binaries (`.exe`, `.dll`) and other artifacts.
  - Parse registry data blocks including kernel policy blocks for license metadata.
- System information collector:
  - Collect OS Major/Minor/Build/UBR/EditionID via documented APIs.
  - Research-only collectors use low‑level reads of memory/offsets to recover additional context.
- Error mapping & diagnostics: support for CBS, BITS, HTTP, UPDATE, NETWORK, WIN32, NTSTATUS, ACTIVATION code sets (best‑effort).
- Update matrix: build update compatibility tables from XML datasets, including unsupported versions (offline).
- Active license & settings view (OEM defaults, active SKU, and related metadata).
- Activation/license management (RESEARCH‑ONLY / GATED): integration points for lab/test workflows.
- Check Products keys against the Official MS Server API, 3 Api In total
- Export Windows & Office licenses include **product Keys** using tsforge Libary

