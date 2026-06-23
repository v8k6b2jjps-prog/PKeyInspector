using namespace System
using namespace System.IO
using namespace System.Net
using namespace System.Web
using namespace System.Numerics
using namespace System.Security.Cryptography
using namespace System.Collections.Generic
using namespace System.Drawing
using namespace System.IO.Compression
using namespace System.Management.Automation
using namespace System.Net
using namespace System.Diagnostics
using namespace System.Reflection
using namespace System.Reflection.Emit
using namespace System.Runtime.InteropServices
using namespace System.Security.AccessControl
using namespace System.Security.Principal
using namespace System.ServiceProcess
using namespace System.Text
using namespace System.Text.RegularExpressions
using namespace System.Threading
using namespace System.Windows.Forms

param (
    [switch]$AutoMode,
    [switch]$RunHWID,
    [switch]$RunoHook,
    [switch]$RunVolume,
    [switch]$RunTsforge,
    [switch]$RunUpgrade,
    [switch]$RunCheckActivation,
    [switch]$RunWmiRepair,
    [switch]$RecoverKeys,
    [switch]$RunTokenStoreReset,
    [switch]$RunUninstallLicenses,
    [switch]$RunScrubOfficeC2R,
    [switch]$RunOfficeLicenseInstaller,
    [switch]$RunOfficeOnlineInstallation,
    
    # Office pattern for Auto Mode
    [string]$LicensePattern = $null
)

Add-Type -AssemblyName System.Web
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$ProgressPreference = 'SilentlyContinue'

Import-Module NativeInteropLib -ErrorAction Stop
Import-Module NtObjectManager -ErrorAction SilentlyContinue
if (!([PSTypeName]'NtCoreLib.NtToken').Type) {
    Write-warning 'NtObjectManager types cant be found!'
}

<#
# Auto Mode example !
# Remove Store, Install Windows & office *365app* licenses, 
# Also, Activate with hwid/kms38, also install oHook bypass

* Option A
powershell -ep bypass -nop -f Activate_.ps1 -AutoMode -RunHWID

* Option B
Set-Location 'C:\Users\Administrator\Desktop'
.\Activate.ps1 -AutoMode -RunTokenStoreReset -RunOfficeLicenseInstaller -RunHWID -RunoHook -LicensePattern "365App"

* Option C
-- icm -scr ([scriptblock]::Create((irm officertool.org/Download/Activate.php))) -arg $true,$true
-- powershell -ep bypass -nop -c icm -scr ([scriptblock]::Create((irm officertool.org/Download/Activate.php))) -arg $true,$true
#>

<#
.SYNOPSIS
This script automates the Windows activation process. 
It checks system requirements, verifies the PowerShell version, 
and handles manual activation through HWID, KMS38, and OHooks methods.

.DESCRIPTION
This script requires PowerShell 3.0 or higher and administrator privileges to run. 
It uses methods for activating Windows, including HWID and KMS38 activations. 
Links for manual activation guides are provided.

.REMOTE EXECUTION:
- To remotely execute the script, use the following command:
  irm tinyurl.com/tshook | iex

.MANUAL ACTIVATION GUIDES:
- HWID Activation: https://massgrave.dev/manual_hwid_activation
- KMS38 Activation: https://massgrave.dev/manual_kms38_activation
- OHooks Activation: https://massgrave.dev/manual_ohook_activation

.VERSION:
- This is the PowerShell 1.0 version of HWID_Activation.cmd
- Credits: WindowsAddict, Mass Project

.CREDITS:
- Code logic borrowed from abbodi1406 KMS_VL_ALL & R`Tool Projects
#>

# Kernel-Mode Windows Versions
# https://www.geoffchappell.com/studies/windows/km/versions.htm

# ZwQuerySystemInformation
# https://www.geoffchappell.com/studies/windows/km/ntoskrnl/api/ex/sysinfo/query.htm

# RtlGetNtVersionNumbers Function
# The RtlGetNtVersionNumbers function gets Windows version numbers directly from NTDLL.
# https://www.geoffchappell.com/studies/windows/win32/ntdll/api/ldrinit/getntversionnumbers.htm

# RtlGetVersion function (wdm.h)
# https://learn.microsoft.com/en-us/windows/win32/devnotes/rtlgetversion
# https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wdm/nf-wdm-rtlgetversion

# Process Environment Block (PEB)
# https://www.geoffchappell.com/studies/windows/km/ntoskrnl/inc/api/pebteb/peb/index.htm

# KUSER_SHARED_DATA
# https://www.geoffchappell.com/studies/windows/km/ntoskrnl/inc/api/ntexapi_x/kuser_shared_data/index.htm

# KUSER_SHARED_DATA structure (ntddk.h)
# https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ntddk/ns-ntddk-kuser_shared_data

# The read-only user-mode address for the shared data is 0x7FFE0000, both in 32-bit and 64-bit Windows.
# The only formal definition among headers in the Windows Driver Kit (WDK) or the Software Development Kit (SDK) is in assembly language headers: KS386.
# INC from the WDK and KSAMD64.
# INC from the SDK both define MM_SHARED_USER_DATA_VA for the user-mode address.

# That they also define USER_SHARED_DATA for the kernel-mode address suggests that they too are intended for kernel-mode programming,
# albeit of a sort that is at least aware of what address works for user-mode access.

# Among relatively large structures,
# the KUSER_SHARED_DATA is highly unusual for having exactly the same layout in 32-bit and 64-bit Windows.
# This is because the one instance must be simultaneously accessible by both 32-bit and 64-bit code on 64-bit Windows,
# and it's desired that 32-bit user-mode code can run unchanged on both 32-bit and 64-bit Windows.

# 2.2.9.6 OSEdition Enumeration
# https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-mde2/d92ead8f-faf3-47a8-a341-1921dc2c463b

# ntdef.h
# https://github.com/tpn/winsdk-10/blob/master/Include/10.0.10240.0/shared/ntdef.h

<#
Example's from MAS' AIO

$editionIDPtr = [IntPtr]::Zero
$hresults = $Global:PKHElper::GetEditionNameFromId(126,[ref]$editionIDPtr)
if ($hresults -eq 0) {
    $editionID = [Marshal]::PtrToStringUni($editionIDPtr)
    Write-Host "BrandingInfo: 126 > Edition: $editionID"
}

[int]$brandingInfo = 0
$hresults = $Global:PKHElper::GetEditionIdFromName("enterprisesn", [ref]$brandingInfo)
if ($brandingInfo -ne 0) {
    Write-Host "Edition: enterprisesn > BrandingInfo: $brandingInfo"
}

Full Table, include Name, Sku, etc etc provide by [abbodi1406]
#>
$Global:productTypeTable = @'
ProductID,OSEdition,DWORD
undefined,PRODUCT_UNDEFINED,0x00000000
ultimate,PRODUCT_ULTIMATE,0x00000001
homebasic,PRODUCT_HOME_BASIC,0x00000002
homepremium,PRODUCT_HOME_PREMIUM,0x00000003
enterprise,PRODUCT_ENTERPRISE,0x00000004
homebasicn,PRODUCT_HOME_BASIC_N,0x00000005
business,PRODUCT_BUSINESS,0x00000006
serverstandard,PRODUCT_STANDARD_SERVER,0x00000007
serverdatacenter,PRODUCT_DATACENTER_SERVER,0x00000008
serversbsstandard,PRODUCT_SMALLBUSINESS_SERVER,0x00000009
serverenterprise,PRODUCT_ENTERPRISE_SERVER,0x0000000A
starter,PRODUCT_STARTER,0x0000000B
serverdatacentercore,PRODUCT_DATACENTER_SERVER_CORE,0x0000000C
serverstandardcore,PRODUCT_STANDARD_SERVER_CORE,0x0000000D
serverenterprisecore,PRODUCT_ENTERPRISE_SERVER_CORE,0x0000000E
serverenterpriseia64,PRODUCT_ENTERPRISE_SERVER_IA64,0x0000000F
businessn,PRODUCT_BUSINESS_N,0x00000010
serverweb,PRODUCT_WEB_SERVER,0x00000011
serverhpc,PRODUCT_CLUSTER_SERVER,0x00000012
serverhomestandard,PRODUCT_HOME_SERVER,0x00000013
serverstorageexpress,PRODUCT_STORAGE_EXPRESS_SERVER,0x00000014
serverstoragestandard,PRODUCT_STORAGE_STANDARD_SERVER,0x00000015
serverstorageworkgroup,PRODUCT_STORAGE_WORKGROUP_SERVER,0x00000016
serverstorageenterprise,PRODUCT_STORAGE_ENTERPRISE_SERVER,0x00000017
serverwinsb,PRODUCT_SERVER_FOR_SMALLBUSINESS,0x00000018
serversbspremium,PRODUCT_SMALLBUSINESS_SERVER_PREMIUM,0x00000019
homepremiumn,PRODUCT_HOME_PREMIUM_N,0x0000001A
enterprisen,PRODUCT_ENTERPRISE_N,0x0000001B
ultimaten,PRODUCT_ULTIMATE_N,0x0000001C
serverwebcore,PRODUCT_WEB_SERVER_CORE,0x0000001D
servermediumbusinessmanagement,PRODUCT_MEDIUMBUSINESS_SERVER_MANAGEMENT,0x0000001E
servermediumbusinesssecurity,PRODUCT_MEDIUMBUSINESS_SERVER_SECURITY,0x0000001F
servermediumbusinessmessaging,PRODUCT_MEDIUMBUSINESS_SERVER_MESSAGING,0x00000020
serverwinfoundation,PRODUCT_SERVER_FOUNDATION,0x00000021
serverhomepremium,PRODUCT_HOME_PREMIUM_SERVER,0x00000022
serverwinsbv,PRODUCT_SERVER_FOR_SMALLBUSINESS_V,0x00000023
serverstandardv,PRODUCT_STANDARD_SERVER_V,0x00000024
serverdatacenterv,PRODUCT_DATACENTER_SERVER_V,0x00000025
serverenterprisev,PRODUCT_ENTERPRISE_SERVER_V,0x00000026
serverdatacentervcore,PRODUCT_DATACENTER_SERVER_CORE_V,0x00000027
serverstandardvcore,PRODUCT_STANDARD_SERVER_CORE_V,0x00000028
serverenterprisevcore,PRODUCT_ENTERPRISE_SERVER_CORE_V,0x00000029
serverhypercore,PRODUCT_HYPERV,0x0000002A
serverstorageexpresscore,PRODUCT_STORAGE_EXPRESS_SERVER_CORE,0x0000002B
serverstoragestandardcore,PRODUCT_STORAGE_STANDARD_SERVER_CORE,0x0000002C
serverstorageworkgroupcore,PRODUCT_STORAGE_WORKGROUP_SERVER_CORE,0x0000002D
serverstorageenterprisecore,PRODUCT_STORAGE_ENTERPRISE_SERVER_CORE,0x0000002E
startern,PRODUCT_STARTER_N,0x0000002F
professional,PRODUCT_PROFESSIONAL,0x00000030
professionaln,PRODUCT_PROFESSIONAL_N,0x00000031
serversolution,PRODUCT_SB_SOLUTION_SERVER,0x00000032
serverforsbsolutions,PRODUCT_SERVER_FOR_SB_SOLUTIONS,0x00000033
serversolutionspremium,PRODUCT_STANDARD_SERVER_SOLUTIONS,0x00000034
serversolutionspremiumcore,PRODUCT_STANDARD_SERVER_SOLUTIONS_CORE,0x00000035
serversolutionem,PRODUCT_SB_SOLUTION_SERVER_EM,0x00000036
serverforsbsolutionsem,PRODUCT_SERVER_FOR_SB_SOLUTIONS_EM,0x00000037
serverembeddedsolution,PRODUCT_SOLUTION_EMBEDDEDSERVER,0x00000038
serverembeddedsolutioncore,PRODUCT_SOLUTION_EMBEDDEDSERVER_CORE,0x00000039
professionalembedded,PRODUCT_PROFESSIONAL_EMBEDDED,0x0000003A
serveressentialmanagement,PRODUCT_ESSENTIALBUSINESS_SERVER_MGMT,0x0000003B
serveressentialadditional,PRODUCT_ESSENTIALBUSINESS_SERVER_ADDL,0x0000003C
serveressentialmanagementsvc,PRODUCT_ESSENTIALBUSINESS_SERVER_MGMTSVC,0x0000003D
serveressentialadditionalsvc,PRODUCT_ESSENTIALBUSINESS_SERVER_ADDLSVC,0x0000003E
serversbspremiumcore,PRODUCT_SMALLBUSINESS_SERVER_PREMIUM_CORE,0x0000003F
serverhpcv,PRODUCT_CLUSTER_SERVER_V,0x00000040
embedded,PRODUCT_EMBEDDED,0x00000041
startere,PRODUCT_STARTER_E,0x00000042
homebasice,PRODUCT_HOME_BASIC_E,0x00000043
homepremiume,PRODUCT_HOME_PREMIUM_E,0x00000044
professionale,PRODUCT_PROFESSIONAL_E,0x00000045
enterprisee,PRODUCT_ENTERPRISE_E,0x00000046
ultimatee,PRODUCT_ULTIMATE_E,0x00000047
enterpriseeval,PRODUCT_ENTERPRISE_EVALUATION,0x00000048
prerelease,PRODUCT_PRERELEASE,0x0000004A
servermultipointstandard,PRODUCT_MULTIPOINT_STANDARD_SERVER,0x0000004C
servermultipointpremium,PRODUCT_MULTIPOINT_PREMIUM_SERVER,0x0000004D
serverstandardeval,PRODUCT_STANDARD_EVALUATION_SERVER,0x0000004F
serverdatacentereval,PRODUCT_DATACENTER_EVALUATION_SERVER,0x00000050
prereleasearm,PRODUCT_PRODUCT_PRERELEASE_ARM,0x00000051
prereleasen,PRODUCT_PRODUCT_PRERELEASE_N,0x00000052
enterpriseneval,PRODUCT_ENTERPRISE_N_EVALUATION,0x00000054
embeddedautomotive,PRODUCT_EMBEDDED_AUTOMOTIVE,0x00000055
embeddedindustrya,PRODUCT_EMBEDDED_INDUSTRY_A,0x00000056
thinpc,PRODUCT_THINPC,0x00000057
embeddeda,PRODUCT_EMBEDDED_A,0x00000058
embeddedindustry,PRODUCT_EMBEDDED_INDUSTRY,0x00000059
embeddede,PRODUCT_EMBEDDED_E,0x0000005A
embeddedindustrye,PRODUCT_EMBEDDED_INDUSTRY_E,0x0000005B
embeddedindustryae,PRODUCT_EMBEDDED_INDUSTRY_A_E,0x0000005C
professionalplus,PRODUCT_PRODUCT_PROFESSIONAL_PLUS,0x0000005D
serverstorageworkgroupeval,PRODUCT_STORAGE_WORKGROUP_EVALUATION_SERVER,0x0000005F
serverstoragestandardeval,PRODUCT_STORAGE_STANDARD_EVALUATION_SERVER,0x00000060
corearm,PRODUCT_CORE_ARM,0x00000061
coren,PRODUCT_CORE_N,0x00000062
corecountryspecific,PRODUCT_CORE_COUNTRYSPECIFIC,0x00000063
coresinglelanguage,PRODUCT_CORE_SINGLELANGUAGE,0x00000064
core,PRODUCT_CORE,0x00000065
professionalwmc,PRODUCT_PROFESSIONAL_WMC,0x00000067
mobilecore,PRODUCT_MOBILE_CORE,0x00000068
embeddedindustryeval,PRODUCT_EMBEDDED_INDUSTRY_EVAL,0x00000069
embeddedindustryeeval,PRODUCT_EMBEDDED_INDUSTRY_E_EVAL,0x0000006A
embeddedeval,PRODUCT_EMBEDDED_EVAL,0x0000006B
embeddedeeval,PRODUCT_EMBEDDED_E_EVAL,0x0000006C
coresystemserver,PRODUCT_NANO_SERVER,0x0000006D
servercloudstorage,PRODUCT_CLOUD_STORAGE_SERVER,0x0000006E
coreconnected,PRODUCT_CORE_CONNECTED,0x0000006F
professionalstudent,PRODUCT_PROFESSIONAL_STUDENT,0x00000070
coreconnectedn,PRODUCT_CORE_CONNECTED_N,0x00000071
professionalstudentn,PRODUCT_PROFESSIONAL_STUDENT_N,0x00000072
coreconnectedsinglelanguage,PRODUCT_CORE_CONNECTED_SINGLELANGUAGE,0x00000073
coreconnectedcountryspecific,PRODUCT_CORE_CONNECTED_COUNTRYSPECIFIC,0x00000074
connectedcar,PRODUCT_CONNECTED_CAR,0x00000075
industryhandheld,PRODUCT_INDUSTRY_HANDHELD,0x00000076
ppipro,PRODUCT_PPI_PRO,0x00000077
serverarm64,PRODUCT_ARM64_SERVER,0x00000078
education,PRODUCT_EDUCATION,0x00000079
educationn,PRODUCT_EDUCATION_N,0x0000007A
iotuap,PRODUCT_IOTUAP,0x0000007B
serverhi,PRODUCT_CLOUD_HOST_INFRASTRUCTURE_SERVER,0x0000007C
enterprises,PRODUCT_ENTERPRISE_S,0x0000007D
enterprisesn,PRODUCT_ENTERPRISE_S_N,0x0000007E
professionals,PRODUCT_PROFESSIONAL_S,0x0000007F
professionalsn,PRODUCT_PROFESSIONAL_S_N,0x00000080
enterpriseseval,PRODUCT_ENTERPRISE_S_EVALUATION,0x00000081
enterprisesneval,PRODUCT_ENTERPRISE_S_N_EVALUATION,0x00000082
iotuapcommercial,PRODUCT_IOTUAPCOMMERCIAL,0x00000083
mobileenterprise,PRODUCT_MOBILE_ENTERPRISE,0x00000085
analogonecore,PRODUCT_HOLOGRAPHIC,0x00000087
holographic,PRODUCT_HOLOGRAPHIC_BUSINESS,0x00000088
professionalsinglelanguage,PRODUCT_PRO_SINGLE_LANGUAGE,0x0000008A
professionalcountryspecific,PRODUCT_PRO_CHINA,0x0000008B
enterprisesubscription,PRODUCT_ENTERPRISE_SUBSCRIPTION,0x0000008C
enterprisesubscriptionn,PRODUCT_ENTERPRISE_SUBSCRIPTION_N,0x0000008D
serverdatacenternano,PRODUCT_DATACENTER_NANO_SERVER,0x0000008F
serverstandardnano,PRODUCT_STANDARD_NANO_SERVER,0x00000090
serverdatacenteracor,PRODUCT_DATACENTER_A_SERVER_CORE,0x00000091
serverstandardacor,PRODUCT_STANDARD_A_SERVER_CORE,0x00000092
serverdatacentercor,PRODUCT_DATACENTER_WS_SERVER_CORE,0x00000093
serverstandardcor,PRODUCT_STANDARD_WS_SERVER_CORE,0x00000094
utilityvm,PRODUCT_UTILITY_VM,0x00000095
serverdatacenterevalcor,PRODUCT_DATACENTER_EVALUATION_SERVER_CORE,0x0000009F
serverstandardevalcor,PRODUCT_STANDARD_EVALUATION_SERVER_CORE,0x000000A0
professionalworkstation,PRODUCT_PRO_WORKSTATION,0x000000A1
professionalworkstationn,PRODUCT_PRO_WORKSTATION_N,0x000000A2
serverazure,PRODUCT_AZURE_SERVER,0x000000A3
professionaleducation,PRODUCT_PRO_FOR_EDUCATION,0x000000A4
professionaleducationn,PRODUCT_PRO_FOR_EDUCATION_N,0x000000A5
serverazurecor,PRODUCT_AZURE_SERVER_CORE,0x000000A8
serverazurenano,PRODUCT_AZURE_NANO_SERVER,0x000000A9
enterpriseg,PRODUCT_ENTERPRISEG,0x000000AB
enterprisegn,PRODUCT_ENTERPRISEGN,0x000000AC
businesssubscription,PRODUCT_BUSINESS,0x000000AD
businesssubscriptionn,PRODUCT_BUSINESS_N,0x000000AE
serverrdsh,PRODUCT_SERVERRDSH,0x000000AF
cloud,PRODUCT_CLOUD,0x000000B2
cloudn,PRODUCT_CLOUDN,0x000000B3
hubos,PRODUCT_HUBOS,0x000000B4
onecoreupdateos,PRODUCT_ONECOREUPDATEOS,0x000000B6
cloude,PRODUCT_CLOUDE,0x000000B7
andromeda,PRODUCT_ANDROMEDA,0x000000B8
iotos,PRODUCT_IOTOS,0x000000B9
clouden,PRODUCT_CLOUDEN,0x000000BA
iotedgeos,PRODUCT_IOTEDGEOS,0x000000BB
iotenterprise,PRODUCT_IOTENTERPRISE,0x000000BC
modernpc,PRODUCT_LITE,0x000000BD
iotenterprises,PRODUCT_IOTENTERPRISES,0x000000BF
systemos,PRODUCT_XBOX_SYSTEMOS,0x000000C0
nativeos,PRODUCT_XBOX_NATIVEOS,0x000000C1
gamecorexbox,PRODUCT_XBOX_GAMEOS,0x000000C2
gameos,PRODUCT_XBOX_ERAOS,0x000000C3
durangohostos,PRODUCT_XBOX_DURANGOHOSTOS,0x000000C4
scarletthostos,PRODUCT_XBOX_SCARLETTHOSTOS,0x000000C5
keystone,PRODUCT_XBOX_KEYSTONE,0x000000C6
cloudhost,PRODUCT_AZURE_SERVER_CLOUDHOST,0x000000C7
cloudmos,PRODUCT_AZURE_SERVER_CLOUDMOS,0x000000C8
cloudcore,PRODUCT_AZURE_SERVER_CLOUDCORE,0x000000C9
cloudeditionn,PRODUCT_CLOUDEDITIONN,0x000000CA
cloudedition,PRODUCT_CLOUDEDITION,0x000000CB
winvos,PRODUCT_VALIDATION,0x000000CC
iotenterprisesk,PRODUCT_IOTENTERPRISESK,0x000000CD
iotenterprisek,PRODUCT_IOTENTERPRISEK,0x000000CE
iotenterpriseseval,PRODUCT_IOTENTERPRISESEVAL,0x000000CF
agentbridge,PRODUCT_AZURE_SERVER_AGENTBRIDGE,0x000000D0
nanohost,PRODUCT_AZURE_SERVER_NANOHOST,0x000000D1
wnc,PRODUCT_WNC,0x000000D2
serverazurestackhcicor,PRODUCT_AZURESTACKHCI_SERVER_CORE,0x00000196
serverturbine,PRODUCT_DATACENTER_SERVER_AZURE_EDITION,0x00000197
serverturbinecor,PRODUCT_DATACENTER_SERVER_CORE_AZURE_EDITION,0x00000198
unliccensed,PRODUCT_UNLICENSED,0xABCDABCD
'@ | ConvertFrom-Csv
#region "Misc"
<#
.SYNOPSIS
* keyhelper API
* Source, change edition` script by windows addict

* KMS Local Activation Tool
* https://github.com/laomms/KmsTool/blob/main/Form1.cs

* 'Retail', 'OEM', 'Volume', 'Volume:GVLK', 'Volume:MAK'
  Any other case, it use default key

_wcsnicmp(input, "Retail", 6)           ? _CHANNEL_ENUM = 1
_wcsnicmp(input, "OEM", 3)              ? _CHANNEL_ENUM = 2
_wcsnicmp(input, "Volume:MAK", 10)      ? _CHANNEL_ENUM = 4
_wcsnicmp(input, "Volume:GVLK", 11)     ? _CHANNEL_ENUM = 3
_wcsnicmp(input, "Volume", 6)           ? _CHANNEL_ENUM = 3
)
#>
function Get-ProductKeys {
    param (
        [Parameter(Mandatory = $true)]
        [string]$EditionID,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Default', 'Retail', 'OEM', 'Volume:GVLK', 'Volume:MAK')]
        [string]$ProductKeyType
    )

    $id = 0
    $result = @()
    $defaultKey = ''

    if ([int]::TryParse($EditionID, [ref]$null)) {
        $id = [int]$EditionID
    }
    else {
        $id = $Global:productTypeTable | Where-Object ProductID -eq $EditionID | Select-Object -ExpandProperty DWORD
        if ($id -eq 0) {
            $null = $Global:PKHElper::GetEditionIdFromName($EditionID, [ref]$id)
        }
    }

    if ($id -eq 0) {
        throw "Could not resolve edition ID from input '$EditionID'."
    }

    # Step 1 - Retrieve the 'Default' key for the edition upfront
    $keyOutPtr, $typeOutPtr, $ProductKeyTypePtr = [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero
    try {
        $hResults = $Global:PKHElper::SkuGetProductKeyForEdition($id, [IntPtr]::zero, [ref]$keyOutPtr, [ref]$typeOutPtr)
        if ($hResults -eq 0) {
            $defaultKey = [Marshal]::PtrToStringUni($keyOutPtr)
        }
    }
    catch { }
    finally {
        Free-IntPtr -handle $ProductKeyTypePtr -Method Auto
        ($keyOutPtr, $typeOutPtr) | % { Free-IntPtr -handle $_ -Method Heap}
    }

    # Step 2 - Case of specic group Key
    if ($ProductKeyType) {
        # Handle specific ProductKeyType request
        try {
            $keyOutPtr, $typeOutPtr, $ProductKeyTypePtr = [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero
            if ($ProductKeyType -eq 'Default') {
                $keyOut = $defaultKey
            }
            else {
                $ProductKeyTypePtr = [Marshal]::StringToHGlobalUni($ProductKeyType)
                $hResults = $Global:PKHElper::SkuGetProductKeyForEdition($id, $ProductKeyTypePtr, [ref]$keyOutPtr, [ref]$typeOutPtr)
                if ($hResults -eq 0) {
                    $keyOut = [Marshal]::PtrToStringUni($keyOutPtr)
                }
            }

            $isDefault = !($keyOut -eq $defaultKey)
            $IsValue   = !([String]::IsNullOrWhiteSpace($keyOut))

            if ($IsValue -and (($ProductKeyType -eq 'Default') -or ($ProductKeyType -ne 'Default' -and $isDefault))) {
                $result += [PSCustomObject]@{
                    ProductKeyType = $ProductKeyType
                    ProductKey     = $keyOut
                }
            }
        }
        catch {}
        finally {
            Free-IntPtr -handle $ProductKeyTypePtr -Method Auto
            ($keyOutPtr, $typeOutPtr) | % { Free-IntPtr -handle $_ -Method Heap}
        }
    }

    # Step 3 - Case of Whole option's
    if (-not $ProductKeyType) {
        # Loop through other key types (excluding 'Default' as it's handled above)
        foreach ($group in @('Retail', 'OEM', 'Volume:GVLK', 'Volume:MAK' )) {
            try {
                $keyOutPtr, $typeOutPtr, $ProductKeyTypePtr = [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero
                $ProductKeyTypePtr = [Marshal]::StringToHGlobalUni($group)
                $hResults = $Global:PKHElper::SkuGetProductKeyForEdition($id, $ProductKeyTypePtr, [ref]$keyOutPtr, [ref]$typeOutPtr)
                if ($hResults -eq 0) {
                    $keyOut = [Marshal]::PtrToStringUni($keyOutPtr)
                    if (-not [string]::IsNullOrWhiteSpace($keyOut)) {
                        $result += [PSCustomObject]@{
                            ProductKeyType = $group
                            ProductKey     = $keyOut
                        }
                    }
                }
            }
            catch {}
            finally {
                Free-IntPtr -handle $ProductKeyTypePtr -Method Auto
                ($keyOutPtr, $typeOutPtr) | % { Free-IntPtr -handle $_ -Method Heap}
            }
        }
            
        # Now, filter the collected results based on your specific rules
        $seenKeys = @{}
        $filterResults = @()

        # Add the 'Default' key to results if it's valid
        if (-not [string]::IsNullOrWhiteSpace($defaultKey)) {
            $seenKeys[$defaultKey] = $true
            $filterResults += [PSCustomObject]@{
                ProductKeyType = "Default"
                ProductKey     = $defaultKey
            }
        }

        # Add other entries only if their ProductKey hasn't been seen yet
        foreach ($item in $result) {
            if (-not [string]::IsNullOrWhiteSpace($item.ProductKey) -and -not $seenKeys.ContainsKey($item.ProductKey)) {
                $filterResults += $item
                $seenKeys[$item.ProductKey] = $true
            }
        }
        $result = $filterResults
    }

    return $result
}

<#
.SYNOPSIS
Read PkeyConfig data from System,
Include Windows & Office pKeyConfig license's
#>
function Init-XMLInfo {
    $paths = @(
        "C:\Windows\System32\spp\tokens\pkeyconfig\pkeyconfig.xrm-ms",
        "C:\Windows\System32\spp\tokens\pkeyconfig\pkeyconfig-csvlk.xrm-ms",
        "C:\Windows\System32\spp\tokens\pkeyconfig\pkeyconfig-downlevel.xrm-ms",
        "C:\Program Files\Microsoft Office\root\Licenses16\pkeyconfig-office.xrm-ms"
    )

    $entries = @()
    foreach ($path in $paths) {
        if (Test-Path -Path $path) {
            $extracted = Extract-Base64Xml -FilePath $path
            if ($extracted) {
                $entries += $extracted
            }
        }
    }

    return $entries
}
function Extract-Base64Xml {
    param (
        [string]$FilePath
    )

    # Check if the file exists
    if (-Not (Test-Path $FilePath)) {
        Write-Warning "File not found: $FilePath"
        return $null
    }

    # Read the content of the file
    $content = Get-Content -Path $FilePath -Raw

    # Use regex to find all Base64 encoded strings between <tm:infoBin> tags
    $matches = [regex]::Matches($content, '<tm:infoBin name="pkeyConfigData">(.*?)<\/tm:infoBin>', [RegexOptions]::Singleline)

    $configurationsList = @()

    foreach ($match in $matches) {
        # Extract the Base64 encoded string
        $base64String = $match.Groups[1].Value.Trim()

        # Decode the Base64 string
        try {
            $decodedBytes = [Convert]::FromBase64String($base64String)
            $decodedString = [Encoding]::UTF8.GetString($decodedBytes)
            [xml]$xmlData = $decodedString

            # Process ProductKeyConfiguration
            #$xmlData.OuterXml | Out-File 'C:\Users\Administrator\Desktop\License.txt'
            if ($xmlData.ProductKeyConfiguration.Configurations) {
                foreach ($config in $xmlData.ProductKeyConfiguration.Configurations.ChildNodes) {
                    # Create a PSCustomObject for each configuration
                    $configObj = [PSCustomObject]@{
                        ActConfigId       = $config.ActConfigId
                        RefGroupId        = $config.RefGroupId
                        EditionId         = $config.EditionId
                        ProductDescription = $config.ProductDescription
                        ProductKeyType    = $config.ProductKeyType
                        IsRandomized      = $config.IsRandomized
                    }
                    $configurationsList += $configObj
                }
            }
        } catch {
            Write-Warning "Failed to decode Base64 string: $_"
        }
    }

    # Return the list of configurations
    return $configurationsList
}

<#
.SYNOPSIS
Get System Build numbers using low level methods

#>
Function Init-osVersion {
    
    <#
        First try read from KUSER_SHARED_DATA 
        And, if fail, Read from PEB.!

        RtlGetNtVersionNumbers Read from PEB. [X64 offset]
        * v3 = NtCurrentPeb();
        * OSMajorVersion -> 0x118 (v3->OSMajorVersion)
        * OSMinorVersion -> 0x11C (v3->OSMinorVersion)
        * OSBuildNumber  -> 0x120 (v3->OSBuildNumber | 0xF0000000)

        RtlGetVersion, do the same, just read extra info from PEB
        * v2 = NtCurrentPeb();
        * a1[1] = v2->OSMajorVersion;
        * a1[2] = v2->OSMinorVersion;
        * a1[3] = v2->OSBuildNumber;
        * a1[4] = v2->OSPlatformId;
        * Buffer = v2->CSDVersion.Buffer;
    #>

    if (-not $Global:PebPtr -or $Global:PebPtr -eq [IntPtr]::Zero) {
        $Global:PebPtr = NtCurrentTeb -Peb
        #$Global:PebPtr = $Global:ntdll::RtlGetCurrentPeb()
    }

    try {
        # 0x026C, ULONG NtMajorVersion; NT 4.0 and higher
        $NtMajorVersion = [Marshal]::ReadInt32([IntPtr](0x7FFE0000 + 0x26C))

        # 0x0270, ULONG NtMinorVersion; NT 4.0 and higher
        $NtMinorVersion = [Marshal]::ReadInt32([IntPtr](0x7FFE0000 + 0x270))

        # 0x0260, ULONG NtBuildNumber; NT 10.0 & higher
        $NtBuildNumber  = [Marshal]::ReadInt32([IntPtr](0x7FFE0000 + 0x0260))

        if (($NtMajorVersion -lt 10) -or (
            $NtBuildNumber -lt 10240)) {
      
          # this offset for nt 10.0 & Up
          # NT 6.3 end in 9600,
          # nt 10.0 start with 10240 (RTM)

          # Before, we stop throw, 
          # Try read from PEB memory.

          $offset = if ([IntPtr]::Size -eq 8) { 0x120 } else { 0x0AC }
          $NtBuildNumber = [int][Marshal]::ReadInt16($Global:PebPtr, $offset)

          # 0xAC, 0x0120, USHORT OSBuildNumber; 4.0 and higher
          if ($NtBuildNumber -lt 1381) {
            throw }
        }

        # Extract Service Pack Major (high byte) and Minor (low byte)
        # *((_WORD *)a1 + 138) = HIBYTE(v2->OSCSDVersion);
        # *((_WORD *)a1 + 139) = (unsigned __int8)v2->OSCSDVersion;
        $offset = if ([IntPtr]::Size -eq 8) { 0x122 } else { 0xAE }
        $oscVersion = [Marshal]::ReadInt16($Global:PebPtr, $offset)
        $wServicePackMajor = ($oscVersion -shr 8) -band 0xFF
        $wServicePackMinor = $oscVersion -band 0xFF

        # Retrieve the OS version details
        return [PSCustomObject]@{
            Major   = $NtMajorVersion
            Minor   = $NtMinorVersion
            Build   = $NtBuildNumber
            UBR     = $Global:ubr
            Version = ($NtMajorVersion,$NtMinorVersion,$NtBuildNumber)
            ServicePackMajor = $wServicePackMajor
            ServicePackMinor = $wServicePackMinor
        }
    }
    catch {}
        
    # Fallback: REGISTRY
    try {
        $major = (Get-ItemProperty -Path $Global:CurrentVersion -Name CurrentMajorVersionNumber -ea 0).CurrentMajorVersionNumber
        $minor = (Get-ItemProperty -Path $Global:CurrentVersion -Name CurrentMinorVersionNumber -ea 0).CurrentMinorVersionNumber
        $build = (Get-ItemProperty -Path $Global:CurrentVersion -Name CurrentBuildNumber -ea 0).CurrentBuildNumber
        $osVersion = [PSCustomObject]@{
            Major   = [int]$major
            Minor   = [int]$minor
            Build   = [int]$build
            UBR     = $Global:ubr
            Version = @([int]$major, [int]$minor, [int]$build)
            ServicePackMajor = 0
            ServicePackMinor = 0
        }
        return $osVersion
    }
    catch {
    }

    Clear-host
    Write-Host
    write-host "Failed to retrieve OS version from all methods."
    Write-Host
    read-host
    exit 1
}

<#
.SYNOPSIS
Get Edition Name using low level methods

#>
function Get-ProductID {
    
    <# 
        Experiment way,
        who work only on online active system,
        that why i don't use it !

        $LicensingProducts = (
            Get-SLIDList -eQueryIdType SL_ID_APPLICATION -eReturnIdType SL_ID_PRODUCT_SKU -pQueryId $windowsAppID | ? { Retrieve-SKUInfo -SkuId $_ -eReturnIdType SL_ID_PKEY }
            ) | % {
            [PSCustomObject]@{
                ID            = $_
                Description   = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Description'
                Name          = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'productName'
                LicenseFamily = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Family'
            }
        }
        $ID_PKEY = $LicensingProducts | ? Name -NotMatch 'ESU' | ? Description -NotMatch 'ESU' | select -First 1
        [XML]$licenseData = Get-ProductSkuInformation $ID_PKEY.ID -ReturnRawData
        $Branding = $licenseData.licenseGroup.license[1].otherInfo.infoTables.infoList.infoStr | ? Name -EQ win:branding

        $ID_PKEY.LicenseFamily
        $Branding.'#text'
    #>

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ ! ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    <#
        Retrieves Windows Product Policy values from the registry
        HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions -> ProductPolicy
    #>

    $KernelEdition = Get-ProductPolicy -Filter Kernel-EditionName -UseApi | select -ExpandProperty Value
    #$KernelEdition = Get-ProductPolicy -Filter Kernel-EditionName | ? Name -Match 'Kernel-EditionName' | select -ExpandProperty Value
    if ($KernelEdition -and (-not [string]::IsNullOrWhiteSpace($KernelEdition))) {
        return $KernelEdition
    }

    <#
        Extract Edition Info from Registry -> 
            DigitalProductId4
    #>

    # DigitalProductId4, WCHAR szEditionType[260];
    $DigitalProductId4 = Parse-DigitalProductId4
    if ($DigitalProductId4 -and $DigitalProductId4.EditionType -and 
        (-not [String]::IsNullOrWhiteSpace($DigitalProductId4.EditionType))) {
        return $DigitalProductId4.EditionType
    }

    <#
        Use RtlGetProductInfo to get brand info, And convert the value

        Alternative, 
        * HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions, ProductPolicy
        * Get-ProductPolicy -> Read 'Kernel-BrandingInfo' -or 'Kernel-ProductInfo' -> Value
          Get-ProductPolicy | ? name -Match "Kernel-BrandingInfo|Kernel-ProductInfo" | select -First 1 -ExpandProperty Value
          which i believe, the source data of the function
        * Win32_OperatingSystem Class -> OperatingSystemSKU
          which i believe, call -> RtlGetProductInfo
        * Also, this registry value --> 
          HKLM\SYSTEM\CurrentControlSet\Control\ProductOptions->OSProductPfn
    #>
    try {
        <#
        -- It call ZwQueryLicenseValue -> Kernel-BrandingInfo \ Kernel-ProductInfo
        -- Replace with direct call ...

        [UInt32]$BrandingInfo = 0
        $status = $Global:ntdll::RtlGetProductInfo(
            $OperatingSystemInfo.dwOSMajorVersion,
            $OperatingSystemInfo.dwOSMinorVersion,
            $OperatingSystemInfo.dwSpMajorVersion,
            $OperatingSystemInfo.dwSpMinorVersion,
            [Ref]$BrandingInfo)

        if (!$status) {
            throw }

        # Get Branding info Number of current Build
        [INT]$BrandingInfo
        #>

        [INT]$BrandingInfo = Get-ProductPolicy |
            ? name -Match "Kernel-BrandingInfo|Kernel-ProductInfo" |
                ? Value | Select -First 1 -ExpandProperty Value

        # Get editionID Name using hard coded table,
        # provide by abbodi1406 :)
        $match = $Global:productTypeTable | Where-Object {
            [Convert]::ToInt32($_.DWORD, 16) -eq $BrandingInfo
        }
        if ($match) {
            return $match.ProductID
        }

        # using API to convert from BradingInfo to EditionName
        $editionIDPtr = [IntPtr]::Zero
        $hresults = $Global:PKHElper::GetEditionNameFromId(
            $BrandingInfo, [ref]$editionIDPtr)
        if ($hresults -eq 0) {
            $editionID = [Marshal]::PtrToStringUni($editionIDPtr)
            return $editionID
        }
    }
    catch { }
    Finally {
        New-IntPtr -hHandle $productTypePtr -Release
    }

    # Key: HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion Propery: EditionID
    $EditionID = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name EditionID -ea 0).EditionID
    if ($EditionID) {
        return $EditionID }

    Clear-host
    Write-Host
    write-host "Failed to Edition ID version from all methods."
    Write-Host
    read-host
    exit 1
}

<#
.SYNOPSIS
Retrieves Windows edition upgrade paths and facilitates interactive upgrades.
[Bool] USeApi Option, Only available for > *Current* edition

.EXAMPLE
# Target edition for current system:
Get-EditionTargetsFromMatrix
Get-EditionTargetsFromMatrix -UseApi

.EXAMPLE
# Target edition for a specific ID (e.g., 'EnterpriseSN'):
Get-EditionTargetsFromMatrix -EditionID 'EnterpriseSN'
Get-EditionTargetsFromMatrix -EditionID 'EnterpriseSN' -RawData

.EXAMPLE
# Upgrade from the current version (interactive selection):
Get-EditionTargetsFromMatrix -UpgradeFrom

.EXAMPLE
# Upgrade from a specific base version (e.g., 'EnterpriseSN' or 'CoreCountrySpecific'):
Get-EditionTargetsFromMatrix -UpgradeFrom -EditionID 'EnterpriseSN'
Get-EditionTargetsFromMatrix -UpgradeFrom -EditionID 'CoreCountrySpecific'

.EXAMPLE
# Upgrade to any chosen version (interactive product key selection):
Get-EditionTargetsFromMatrix -UpgradeTo

.EXAMPLE
# Upgrade to a specific edition (e.g., 'EnterpriseSEval' with product key selection):
Get-EditionTargetsFromMatrix -EditionID EnterpriseSEval -UpgradeTo

.EXAMPLE
# List all available editions:
Get-EditionTargetsFromMatrix -ReturnEditionList

--------------------------------------------------

PowerShell, Also support this function apparently
--> Get-WindowsEdition -Online -Target .!

#>
function Get-EditionTargetsFromMatrix {
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet(
            "ultimate","homebasic","homepremium","enterprise","homebasicn","business","serverstandard","serverdatacenter","serversbsstandard","serverenterprise","starter",
            "serverdatacentercore","serverstandardcore","serverenterprisecore","serverenterpriseia64","businessn","serverweb","serverhpc","serverhomestandard","serverstorageexpress",
            "serverstoragestandard","serverstorageworkgroup","serverstorageenterprise","serverwinsb","serversbspremium","homepremiumn","enterprisen","ultimaten","serverwebcore",
            "servermediumbusinessmanagement","servermediumbusinesssecurity","servermediumbusinessmessaging","serverwinfoundation","serverhomepremium","serverwinsbv","serverstandardv",
            "serverdatacenterv","serverenterprisev","serverdatacentervcore","serverstandardvcore","serverenterprisevcore","serverhypercore","serverstorageexpresscore","serverstoragestandardcore",
            "serverstorageworkgroupcore","serverstorageenterprisecore","startern","professional","professionaln","serversolution","serverforsbsolutions","serversolutionspremium",
            "serversolutionspremiumcore","serversolutionem","serverforsbsolutionsem","serverembeddedsolution","serverembeddedsolutioncore","professionalembedded","serveressentialmanagement",
            "serveressentialadditional","serveressentialmanagementsvc","serveressentialadditionalsvc","serversbspremiumcore","serverhpcv","embedded","startere","homebasice",
            "homepremiume","professionale","enterprisee","ultimatee","enterpriseeval","prerelease","servermultipointstandard","servermultipointpremium","serverstandardeval",
            "serverdatacentereval","prereleasearm","prereleasen","enterpriseneval","embeddedautomotive","embeddedindustrya","thinpc","embeddeda","embeddedindustry","embeddede",
            "embeddedindustrye","embeddedindustryae","professionalplus","serverstorageworkgroupeval","serverstoragestandardeval","corearm","coren","corecountryspecific","coresinglelanguage",
            "core","professionalwmc","mobilecore","embeddedindustryeval","embeddedindustryeeval","embeddedeval","embeddedeeval","coresystemserver","servercloudstorage","coreconnected",
            "professionalstudent","coreconnectedn","professionalstudentn","coreconnectedsinglelanguage","coreconnectedcountryspecific","connectedcar","industryhandheld",
            "ppipro","serverarm64","education","educationn","iotuap","serverhi","enterprises","enterprisesn","professionals","professionalsn","enterpriseseval",
            "enterprisesneval","iotuapcommercial","mobileenterprise","analogonecore","holographic","professionalsinglelanguage","professionalcountryspecific","enterprisesubscription",
            "enterprisesubscriptionn","serverdatacenternano","serverstandardnano","serverdatacenteracor","serverstandardacor","serverdatacentercor","serverstandardcor","utilityvm",
            "serverdatacenterevalcor","serverstandardevalcor","professionalworkstation","professionalworkstationn","serverazure","professionaleducation","professionaleducationn",
            "serverazurecor","serverazurenano","enterpriseg","enterprisegn","businesssubscription","businesssubscriptionn","serverrdsh","cloud","cloudn","hubos","onecoreupdateos",
            "cloude","andromeda","iotos","clouden","iotedgeos","iotenterprise","modernpc","iotenterprises","systemos","nativeos","gamecorexbox","gameos","durangohostos",
            "scarletthostos","keystone","cloudhost","cloudmos","cloudcore","cloudeditionn","cloudedition","winvos","iotenterprisesk","iotenterprisek","iotenterpriseseval",
            "agentbridge","nanohost","wnc","serverazurestackhcicor","serverturbine","serverturbinecor"
        )]
        [string]$EditionID = $null,

        [Parameter(Mandatory = $false)]
        [switch]$ReturnEditionList,

        [Parameter(Mandatory = $false)]
        [switch]$UpgradeFrom,

        [Parameter(Mandatory = $false)]
        [switch]$UpgradeTo,

        [Parameter(Mandatory = $false)]
        [switch]$UseApi,

        [Parameter(Mandatory = $false)]
        [switch]$RawData
    )

    $targets = @();

    [string]$xmlPath = "C:\Windows\servicing\Editions\EditionMappings.xml"
    [string]$MatrixPath = "C:\Windows\servicing\Editions\EditionMatrix.xml"
    if (-not $xmlPath -or -not $MatrixPath) {
        Write-Host
         Write-Warning "Required files not found: `n$xmlPath`n$MatrixPath"
        return
    }
    $CurrentEdition = Get-ProductID
    if ($UseApi -and (
            $EditionID -and ($EditionID -ne $CurrentEdition))) {
        Write-Warning "UseApi Only for Current edition."
        return @()
    }

    function Find-Upgrades {
        param (
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$EditionID
        )

        if ($EditionID -and ($Global:productTypeTable.ProductID -notcontains $EditionID)) {
            Write-Warning "EditionID '$EditionID' is not found in the product type table."
            return
        }
    
        $parentEdition = $null
        $relatedEditions = @()

        [xml]$xml = Get-Content -Path $xmlPath
        $WindowsEditions = $xml.WindowsEditions.Edition

        $isVirtual = $WindowsEditions.Name -contains $EditionID
        $isParent = $WindowsEditions.ParentEdition -contains $EditionID

        # If the selected edition is a Virtual Edition, get the Parent Edition
        if ($isVirtual) {
            $selectedEditionNode = $WindowsEditions | Where-Object { $_.Name -eq $EditionID }
            $parentEdition = $selectedEditionNode.ParentEdition
        }

        # If the edition is a Parent Edition, find all related Virtual Editions
        if ($isParent) {
            try {
                $relatedEditions = $WindowsEditions | Where-Object { $_.ParentEdition -eq $EditionID -and $_.virtual -eq "true" }
            }
            catch {
            }
        }

        # If the edition is a Virtual Edition, find all other Virtual Editions linked to the same Parent Edition
        if ($isVirtual) {
            try {
                $relatedEditions += $WindowsEditions | Where-Object { $_.ParentEdition -eq $parentEdition -and $_.virtual -eq "true" }
            }
            catch {
            }
        }

        return [PSCustomObject]@{
            Editions = $relatedEditions | Select-Object -ExpandProperty Name
            Parent   = $parentEdition
        }
    }
    Function Dism-GetTargetEditions {
        try {
            $hr = $Global:DismAPI::DismInitialize(
                0, [IntPtr]::Zero, [IntPtr]::Zero)
            if ($hr -ne 0) {
                Write-Warning "DismInitialize failed: $hr"
                return @()
            }

            $session = [IntPtr]::Zero
            $hr = $Global:DismAPI::DismOpenSession(
                "DISM_{53BFAE52-B167-4E2F-A258-0A37B57FF845}", [IntPtr]::Zero, [IntPtr]::Zero, [ref]$session)
            if ($hr -ne 0) { 
                Write-Warning "DismOpenSession failed: $hr"
                return
            }

            $count = 0
            $editionIds = [IntPtr]::Zero
            $hr = $Global:DismAPI::_DismGetTargetEditions($session, [ref]$editionIds, [ref]$count)
            if ($hr -ne 0) { 
                Write-Warning "_DismGetTargetEditions failed: $hr"
            }

            if ($hr -eq 0 -and $count -gt 0) {
                try {
                    return Convert-PointerArrayToStrings -PointerToArray $editionIds -Count $count
                }
                catch {
                    Write-Warning "Failed to convert editions: $_"
                    return @()
                }
            }
        }
        catch {
        }
        finally {
            if ($editionIds -and (
                $editionIds -ne [IntPtr]::Zero)) {
                    $null = $Global:DismAPI::DismDelete($editionIds)
            }
            if ($session -and (
                $session -ne [IntPtr]::Zero)) {
                    $null = $Global:DismAPI::DismCloseSession($session)
            }
            $null = $Global:DismAPI::DismShutdown()
        }
    }
    function Convert-PointerArrayToStrings {
        param (
            [Parameter(Mandatory = $true)]
            [IntPtr] $PointerToArray,

            [Parameter(Mandatory = $true)]
            [UInt32] $Count
        )

        if ($PointerToArray -eq [IntPtr]::Zero -or $Count -eq 0) {
            return @()
        }

        $strings = @()
        for ($i = 0; $i -lt $Count; $i++) {
            # Calculate pointer to pointer at index $i
            $ptrToStringPtr = [IntPtr]::Add($PointerToArray, $i * [IntPtr]::Size)

            # Read the string pointer
            $stringPtr = [Marshal]::ReadIntPtr($ptrToStringPtr)
            if ($stringPtr -ne [IntPtr]::Zero) {
                # Read the Unicode string from the pointer
                $edition = [Marshal]::PtrToStringUni($stringPtr)
                $strings += $edition
            }
        }
        return $strings
    }

    if (-Not (Test-Path $MatrixPath)) {
        Write-Warning "EditionMatrix.xml not found at $MatrixPath"
        return
    }
    if ($EditionID -and ($Global:productTypeTable.ProductID -notcontains $EditionID)) {
        Write-Warning "EditionID '$EditionID' is not found in the product type table."
        return
    }
    [xml]$xml = Get-Content $MatrixPath
    $LicensingProducts = Get-SLIDList -eQueryIdType SL_ID_PRODUCT_SKU -eReturnIdType SL_ID_PRODUCT_SKU | % {
        [PSCustomObject]@{
            ID            = $_
            Description   = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Description'
            Name          = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'productName'
            LicenseFamily = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Family'
        }
    }
    $uniqueFamilies = $LicensingProducts.LicenseFamily | Select-Object -Unique
    
    if ($UpgradeFrom) {
        if (-not $EditionID) {
            $EditionID = $CurrentEdition
        }
        if (-not $EditionID) {
            Write-Host
            Write-Warning "EditionID is missing. Upgrade may not proceed correctly."
            return
        }

        # Find edition node in XML
        # Editions where this ID is the source (normal lookup)
        $sourceNode = $xml.TmiMatrix.Edition | Where-Object { $_.ID -eq $EditionID }

        # Editions where this ID is a target (reverse lookup)
        $targetNodes = $xml.TmiMatrix.Edition | Where-Object {
            $_.Target.ID -contains $EditionID
        }

        # Combine all
        $editionNode = @()
        if ($sourceNode) { $editionNode += @($sourceNode) }
        if ($targetNodes) { $editionNode += @($targetNodes) }
        $Upgrades = Find-Upgrades -EditionID $EditionID

        if ($UseApi -and (
            $EditionID -eq $CurrentEdition)) {
                $targetEditions = Dism-GetTargetEditions
        }
        else {
            if ($editionNode.Target.ID) {
                $targetEditions += @($editionNode.Target.ID)
            }

            if ($Upgrades.Editions) {
                $targetEditions += @($Upgrades.Editions)
            }

            if ($Upgrades.Parent) {
                $targetEditions += @($Upgrades.Parent)
            }

            $targetEditions = $targetEditions | ? { $_ -ne $CurrentEdition} | select -Unique
            if (-not $targetEditions) {
                Write-Host
                Write-Warning "No upgrade targets found for EditionID '$EditionID'."
                return
            }
            $targetEditions = $targetEditions | Where-Object { $uniqueFamilies  -contains $_ } | select -Unique
        }

        if ($targetEditions.Count -eq 0) {
            Write-Host
            Write-Warning "No targets license's found in Current system for '$EditionID' Edition."
            return
        }
        elseif ($targetEditions.Count -eq 1) {
            $chosenTarget = $targetEditions
            Write-Host
            Write-Warning "Only one upgrade target found: $chosenTarget. Selecting automatically."
        } else {
            # Multiple targets: let user choose
            $chosenTarget = $null
            while (-not $chosenTarget) {
                Clear-Host
                Write-Host
                Write-Host "[Available upgrade targets]"
                Write-Host
                for ($i = 0; $i -lt $targetEditions.Count; $i++) {
                    Write-Host "[$($i+1)] $($targetEditions[$i])"
                }
                $selection = Read-Host "Select upgrade target edition by number (or 'q' to quit)"
                if ($selection -eq 'q') { break }

                $parsedSelection = 0
                if ([int]::TryParse($selection, [ref]$parsedSelection) -and
                    $parsedSelection -ge 1 -and
                    $parsedSelection -le $targetEditions.Count) {
                    $chosenTarget = $targetEditions[$parsedSelection - 1]
                } else {
                    Write-Host "Invalid selection, please try again."
                }
            }
        }

        if (-not $chosenTarget) {
            Write-Host
            Write-Warning "No target edition selected. Cancelling."
            return
        }

        $UpgradeTo = $true
        $EditionID = $chosenTarget
    }
    if ($UpgradeTo) {
        $filteredKeys = $Global:PKeyDatabase | ? { $LicensingProducts.ID -contains $_.ActConfigId}
        if ($EditionID) {
            if ($EditionID -eq $CurrentEdition) {
                Write-Host
                Write-Warning "Attempting to upgrade to the same edition ($EditionID) already installed. No upgrade needed."
                return
            }
            $matchingKeys = @($filteredKeys | Where-Object { $_.EditionId -eq $EditionID })
            if (-not $matchingKeys -or $matchingKeys.Count -eq 0) {
                Write-Host
                Write-Warning "No matching keys found for EditionID '$EditionID'"
                return
            }
        } else {
            # No EditionID specified, use all keys
            $matchingKeys = @($filteredKeys)
        }

        if (-not $matchingKeys -or $matchingKeys.Count -eq 0) {
            Write-Host
            Write-Warning "No product keys available."
            return
        }

        if ($matchingKeys.Count -gt 1) {
            # Multiple keys: show Out-GridView for selection
            $selectedKey = $null
            while (-not $selectedKey) {
                Clear-Host
                Write-Host
                Write-Host "[Available product keys]"
                Write-Host

                for ($i = 0; $i -lt $matchingKeys.Count; $i++) {
                    $item = $matchingKeys[$i]
                    Write-Host ("{0,-4} {1,-30} | {2,-50} | {3,-15} | {4}" -f ("[$($i+1)]"), $item.EditionId, $item.ProductDescription, $item.ProductKeyType, $item.RefGroupId)
                }

                Write-Host
                $input = Read-Host "Select a product key by number (or 'q' to quit)"
                if ($input -eq 'q') { break }

                $parsed = 0
                if ([int]::TryParse($input, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le $matchingKeys.Count) {
                    $selectedKey = $matchingKeys[$parsed - 1]
                } else {
                    Write-Host "Invalid selection. Please try again."
                }
            }            if (-not $selectedKey) {
                Write-Host
                Write-Warning "No selection made. Operation cancelled."
                return
            }
        }
        elseif ($matchingKeys.Count -eq 1) {
            # Only one key: select automatically
            $selectedKey = $matchingKeys
        }
        else {
            Write-Host
            Write-Warning "No product keys available."
            return
        }
        if (-not $selectedKey) {
            Write-Host
            Write-Warning "No selection made. Operation cancelled."
            return
        }

        # Simulated Key Installation
        Write-Host
        SL-InstallProductKey -Keys @(
            (Encode-Key $($selectedKey.RefGroupId) 0 0))

        return
    }
    if (-not $EditionID) {
        $EditionID = Get-ProductID
    }
    if ($ReturnEditionList) {
        return $xml.TmiMatrix.Edition | Select-Object -ExpandProperty ID
    }

    if ($UseApi -and (
        $EditionID -eq $CurrentEdition)) {
            $targets = Dism-GetTargetEditions
    }
    else {
        $Upgrades = Find-Upgrades -EditionID $EditionID
        $editionNode = $xml.TmiMatrix.Edition | Where-Object { $_.ID -eq $EditionID }
        
        if ($editionNode.Target.ID) {
            $targets += $editionNode.Target.ID
        }

        if ($Upgrades.Editions) {
            $targets += $Upgrades.Editions
        }

        if ($Upgrades.Parent) {
            $targets += $Upgrades.Parent
        }
        $FilterList = @($CurrentEdition, $EditionID)
        $targets = $targets | ? {$_ -notin $FilterList} | Sort-Object -Unique
    }
    if ($targets) {
        if ($RawData) {
            return $targets
        }
        Write-Host
        Write-Host "Edition '$EditionID' can be upgraded/downgraded to:" -ForegroundColor Green
        $targets | ForEach-Object { Write-Host "  - $_" }
    } else {
        if ($RawData) {
            return @()
        }
        Write-Host
        Write-Warning "Edition '$EditionID' has no defined upgrade targets."
    }
}

<#
Retrieves Windows Product Policy values from the registry.
Supports filtering by policy names or returns all by default.

Adapted from Windows Product Policy Editor by kost:
https://forums.mydigitallife.net/threads/windows-product-policy-editor.39411/

Software Licensing
https://www.geoffchappell.com/studies/windows/km/ntoskrnl/api/ex/slmem/index.htm?tx=57,58

Windows Vista introduces a formal scheme of named license values,
with API functions to manage them. The license values are stored together -
as binary data for a single registry value. The data format is presented separately.
Like registry values, each license value has its own data.

Windows Internals Book 7th Edition Tools
https://github.com/zodiacon/WindowsInternals/blob/master/SlPolicy/SlPolicy.cpp

windows Sdk
https://github.com/mic101/windows/blob/master/WRK-v1.2/public/internal/base/inc/zwapi.h

ntoskrnl.exe
__int64 __fastcall SLUpdateLicenseDataInternal(__int64 a1, int a2, unsigned int *a3)

typedef struct _SL_LICENSE_Header {
    uint32_t TotalSize;         // total size, including this header      
    uint32_t DataSize;          // size of values array that follows this header
    uint32_t MarkerSize;        // size of end marker that follows the values array
    uint32_t Flags;             // offset 0x0C: Bit 0x1 is checked
    uint32_t Version;           // offset 0x10: Must be 1
    uint8_t  Payload[1];        // offset 0x14: Start of variable data
} SL_UPDATE_BUFFER, *PSL_UPDATE_BUFFER;

typedef struct _SL_POLICY_ELEMENT {
    uint16_t TotalSize;      // offset to the next element
    uint16_t NameLength;     // length of the Wide String
    uint16_t DataType;       // SLDATATYPE enumeration
    uint16_t DataSize;       // data size
    uint32_t Flags;          // flags
    uint32_t Reserved;       // 0x00
    
    // The String (Name)    is located at: (this + 0x10)
    // The Value [Per Type] is located at: (this + TotalSize - 4)
} SL_POLICY_ELEMENT;

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct UNICODE_STRING {
    public ushort Length;
    public ushort MaximumLength;
    public IntPtr Buffer;
}

public static class Ntdll {
    [DllImport("ntdll.dll", CharSet = CharSet.Unicode)]
    public static extern int ZwQueryLicenseValue(
        ref UNICODE_STRING ValueName,
        out uint Type,
        IntPtr Data,
        uint DataSize,
        out uint ResultDataSize
    );
}

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

[PRODUCT POLICY PARSER SUMMARY]

FUNCTIONAL OVERVIEW:
1. LOADER (sppsvc.exe, sub_14010A300): Opens "HKLM\SYSTEM\CurrentControlSet\Control\ProductOptions", 
   reads the "ProductPolicy" binary value, and ensures it is not empty.
2. CONTAINER VALIDATOR (sppsvc.exe, sub_1401AC448): Checks the "Crate" header. 
   It verifies the total size, version (must be 1), and looks for the magic byte 0x45 (decimal 69) at the end of the header data.
3. ENTRY PARSER (sppsvc.exe, sub_1401AC1DC): A loop that "walks" the blob. 
   It reads each item's size, jumps to the next, and extracts data based on Type (1=Flag, 3=String, 4=DWORD).

STRUCT DATA REPRESENTATIONS:

struct ProductPolicyHeader {
    uint32_t TotalSize;      // Offset 0: Must match registry blob size
    uint32_t DataSize;       // Offset 4: Size of all entries combined
    uint32_t HeaderSize;     // Offset 8: Must be 4
    uint32_t Unknown;        // Offset 12: Reserved
    uint32_t Version;        // Offset 16: Must be 1
};

struct ProductPolicyEntry {
    uint16_t EntrySize;      // Offset 0: Bytes to jump to next entry
    uint16_t NameLength;     // Offset 2: Bytes in the UTF-16 Name
    uint16_t DataType;       // Offset 4: 1=Binary, 3=String, 4=DWORD
    uint16_t DataLength;     // Offset 6: Bytes in the Value
    uint32_t Flags;          // Offset 8: Internal policy flags
    uint32_t Reserved;       // Offset 12: Padding
    // wchar_t PolicyName[]; // Name follows at Offset 16
    // uint8_t  PolicyData[]; // Data follows after the Name
};

[ THE SHIPPING MANIFEST (Main Header) ]
---------------------------------------------------------------------------
Offset (Bytes) | Field Name    | What it tells the computer
---------------------------------------------------------------------------
00 to 03       | TotalSize     | "The whole file is exactly this many bytes long."
04 to 07       | DataSize      | "The actual list of items is this many bytes."
08 to 11       | HeaderSize    | "The manifest ends here (Always 4)."
12 to 15       | Reserved      | (Empty space)
16 to 19       | Version       | "This is version 1 of the list."
---------------------------------------------------------------------------

[ THE PILE OF BOXES (The Policy Entries) ]
Starting at Offset 20 (0x14), the computer reads one "Box" at a time.

[ BOX #1 ]
---------------------------------------------------------------------
Offset   | Field Name    | What it tells the computer
---------------------------------------------------------------------
+ 0      | EntrySize     | "To find Box #2, jump forward THIS many bytes."
+ 2      | NameLength    | "The label (Name) is this many characters long."
+ 4      | DataType      | "Is the value a Number, Text, or Binary?"
+ 6      | DataLength    | "The actual data inside is this many bytes."
+ 8      | Flags         | (Special instructions for this item)
+ 12     | Reserved      | (Empty space)
+ 16     | PolicyName    | "My name is: Security-SPP-Reserved-Enable"
+ ???    | PolicyData    | "My value is: 1"
---------------------------------------------------------------------
      
[ JUMP! ] 
The computer adds "EntrySize" to its current position to land 
perfectly at the start of Box #2.


[ BOX #2 ]
---------------------------------------------------------------------
+ 0      | EntrySize     | "To find Box #3, jump forward THIS many..."
... and so on, until the end of the file.

PARSING LOGIC:
The code iterates using 'v13 = (char *)v13 + *v13',
effectively skipping the current 'EntrySize' to reach the next header.
It performs strict boundary checks at every step to prevent buffer overflows
(e.g., checking if the current offset exceeds the DataSize or if an addition results in an integer wrap-around).
It uses Control Flow Guard (CFG) to protect indirect calls during the cleanup of policy objects.
#>
function Get-ProductPolicy {
    [CmdletBinding(DefaultParameterSetName = "Search")]
    param (
        [Parameter(Mandatory=$false, ParameterSetName = "Search")]
        [string[]]$Filter = @(),
        
        [Parameter(Mandatory=$true, ParameterSetName = "List")]
        [switch]$OutList,

        [Parameter(Mandatory=$false)]
        [switch]$UseApi
    )

    $results = [System.Collections.Generic.List[object]]::new()

    if ($UseApi) {
        if (-not $Filter -or $Filter.Count -eq 0) {
            Write-Warning "API mode requires at least one value name in -Filter."
            return $null
        }

        foreach ($valueName in $Filter) {
            try {
                [uint32]$type = 0
                [uint32]$resultSize = 0
                $unicodeStringPtr = Init-NativeString -Value $valueName -Encoding Unicode

                # Allocate a buffer to receive the value (arbitrary size like 3 KB)
                $dataSize = 3000
                $dataBuffer = [Marshal]::AllocHGlobal($dataSize)

                try {
                    $status = $Global:ntdll::ZwQueryLicenseValue(
                        $unicodeStringPtr,
                        [ref]$type,
                        $dataBuffer,
                        [uint32]$dataSize,
                        [ref]$resultSize
                    )

                    if ($status -eq 0) {
                        $result = [PSCustomObject]@{
                            Name  = $valueName
                            Type  = $type
                            Size  = $resultSize
                            Value = $null
                        }

                        $result.Value = Parse-RegistryData `
                            -dataType $type `
                            -ptr $dataBuffer `
                            -valueSize $resultSize `
                            -valueName $valueName
                        $results.Add($result)
                    }
                    else {
                        $statusHex = "0x{0:X}" -f $status

                        switch ($statusHex) {
                            "0x00000000" {
                                # success - no warning needed
                            }
                            "0xC0000272" {
                                Write-Warning "Failed to query '$valueName' via UseApi: There was no match for the specified key in the index. Status: $statusHex"
                                break
                            }
                            "0xC0000023" {
                                Write-Warning "ZwQueryLicenseValue failed for '$valueName': Buffer Too Small. Status: $statusHex"
                                break
                            }
                            "0xC0000034" {
                                Write-Warning "ZwQueryLicenseValue failed for '$valueName': Object Name not found. Status: $statusHex"
                                break
                            }
                            "0xC000001D" {
                                Write-Warning "ZwQueryLicenseValue failed for '$valueName': Illegal Instruction. Status: $statusHex"
                                break
                            }
                            "0xC00000BB" {
                                Write-Warning "ZwQueryLicenseValue failed for '$valueName': The request is not supported. Status: $statusHex"
                                break
                            }
                            default {
                                Write-Warning "ZwQueryLicenseValue failed for '$valueName' with status: $statusHex"
                            }
                        }
                    }
                }
                finally {
                    if ($dataBuffer -ne [IntPtr]::Zero) { 
                        [Marshal]::FreeHGlobal($dataBuffer) }
                }
            }
            finally {
                if ($unicodeStringPtr -ne [IntPtr]::Zero) {
                    Free-NativeString -StringPtr $unicodeStringPtr
                }
            }
        }

        return $results
    }

    $policyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\ProductOptions"
    $blob = (Get-ItemProperty -Path $policyPath -Name ProductPolicy).ProductPolicy
    if (-not $blob) {
        Write-Warning "ProductPolicy blob not found in registry."
        return $null
    }

    $ms = [MemoryStream]::new($blob)
    $br = [BinaryReader]::new($ms)

    try {       
        $hTotalSize = $br.ReadInt32() # uint32_t TotalSize;
        $hDataSize  = $br.ReadInt32() # uint32_t DataSize;
        $MarkerSize = $br.ReadInt32() # uint32_t MarkerSize;

        $bytesToRead = 0
        $ms.Position = 0x14
        
        while ($true) {
            
            # Save Current Position
            $startPos = $ms.Position

            # Read the 8-byte Entry Header
            $cbSize   = $br.ReadUInt16() # Total size of this entry
            if ($cbSize -le 0x10) { break }
            $cbLength = $br.ReadUInt16() # Length of the Name string
            $cbType   = $br.ReadUInt16() # Data Type
            $dataSize = $br.ReadUInt16() # Length of the Data
            $br.ReadUInt32() | Out-Null  # Flags
            $br.ReadUInt32() | Out-Null  # Reserved

            # Read the Property, from offset 0x10
            $cbData = $br.ReadBytes($cbLength)
            $name = [Encoding]::Unicode.GetString($cbData).TrimEnd([char]0)
            
            # Read the value,   from offset (0x10 + $cbLength)
            $cbData = $br.ReadBytes($dataSize)
            $TypeName = switch ($cbType) {
                0x0  { 'NONE' }      # SL_DATA_NONE
                0x1  { 'SZ' }        # SL_DATA_SZ (Unicode string)
                0x3  { 'BINARY' }    # SL_DATA_BINARY
                0x4  { 'DWORD' }     # SL_DATA_DWORD
                0x7  { 'MULTI_SZ' }  # SL_DATA_MULTI_SZ
                0x64 { 'SUM' }       # SL_DATA_SUM
                default { "UNKNOWN ($cbType)" }
            }

            if ($Filter.Count -eq 0 -or $Filter -contains $name) {
                $val = switch ($cbType) {
                    0x1 { [Encoding]::Unicode.GetString($cbData).TrimEnd([char]0) }
                    0x3 {
                        if ($name -eq "Security-SPP-LastWindowsActivationTime" -and $cbData.Length -eq 8) {
                            [DateTime]::FromFileTimeUtc(
                                ([BitConverter]::ToInt64($cbData, 0)))
                        }
                        elseif ($name -eq "Security-SPP-LastWindowsActivationHResult" -and $cbData.Length -eq 4) {
                            [BitConverter]::ToUInt32($cbData, 0)
                        }
                        else {
                            [BitConverter]::ToString($cbData)
                        }
                    }
                    0x04 { if ($cbData.Length -ge 4) { [BitConverter]::ToUInt32($cbData, 0) } else { $cbData } }
                    0x07 { ([Encoding]::Unicode.GetString($cbData)) -split "`0" | Where-Object { $_ } }
                    default { $cbData }
                }

                $results.Add(
                    [PSCustomObject]@{
                        Name  = $name
                        Type  = $TypeName
                        Value = $val
                    }
                )

                if ($Filter.Count -eq 1) {
                    break
                }
            }
            
            $bytesToRead += $cbSize
            $nextElement = $startPos + $cbSize

            if (($bytesToRead -ge $hDataSize) -or (
                $nextElement -ge ($hTotalSize - $MarkerSize))) {
                
                # End of stream,
                # Probably 4 bytes before
                # End marker !
                break
            }
            $ms.Position = $nextElement
        }

        if ($OutList) {
            return $results.Name
        }
        return $results
    }
    finally {
        $br.Close()
        $ms.Close()
    }
}

<#
Alternative call instead of, 
SoftwareLicensingService --> OA3xOriginalProductKey

~~~~~~~~~~~~~~~~~~~~

Evasions: Firmware tables
https://evasions.checkpoint.com/src/Evasions/techniques/firmware-tables.html

Docs » 5. ACPI Software Programming Model
https://uefi.org/specs/ACPI/6.5/05_ACPI_Software_Programming_Model.html#description-header-signatures-for-tables-defined-by-acpi

typedef struct _SYSTEM_FIRMWARE_TABLE_INFORMATION {
    ULONG ProviderSignature;
    SYSTEM_FIRMWARE_TABLE_ACTION Action;
    ULONG TableID;
    ULONG TableBufferLength;
    UCHAR TableBuffer[ANYSIZE_ARRAY];  // <- the result will reside in this field
} SYSTEM_FIRMWARE_TABLE_INFORMATION, *PSYSTEM_FIRMWARE_TABLE_INFORMATION;

// helper enum
typedef enum _SYSTEM_FIRMWARE_TABLE_ACTION
{
    SystemFirmwareTable_Enumerate,
    SystemFirmwareTable_Get
} SYSTEM_FIRMWARE_TABLE_ACTION, *PSYSTEM_FIRMWARE_TABLE_ACTION;

~~~~~~~~~~~~~~~~~~~~

UINT __stdcall GetSystemFirmwareTable(
        DWORD FirmwareTableProviderSignature,
        DWORD FirmwareTableID,
        PVOID pFirmwareTableBuffer,
        DWORD BufferSize)

Heap = RtlAllocateHeap(NtCurrentPeb()->ProcessHeap, KernelBaseGlobalData, BufferSize + 16);
Heap[0] = FirmwareTableProviderSignature; // FirmwareTableProviderSignature
Heap[1] = 1;                              // Action -- 1
Heap[2] = FirmwareTableID;                // FirmwareTableID
Heap[3] = BufferSize;                     // Payload Only

v8 = BufferSize + 16;                     // HeadSize (16) & Payload Size
v11 = NtQuerySystemInformation(0x4C, Heap, v8, &ReturnLength);

So, what happen here, 
* Header  = 16 Byte's
* Heap[3] = PayLoad size, Only!
Allocate --> Header Size & Payload Size. ( DWORD BufferSize & 16 bytes above )
Set Heap[3] --> Payload Size only. ( DWORD BufferSize )
NT! Api call, Total length. ( DWORD BufferSize + 16 )

Case Fail!
 --> Heap[3] = 0
 --> ReturnLength = 16,
 * Return --> Heap[3] --> `0 (Not ReturnLength!)

~~~~~~~~~~~~~~~~~~~~

__kernel_entry NTSTATUS NtQuerySystemInformation(
  [in]            SYSTEM_INFORMATION_CLASS SystemInformationClass,
  [in, out]       PVOID                    SystemInformation,
  [in]            ULONG                    SystemInformationLength,
  [out, optional] PULONG                   ReturnLength

~~~~~~~~~~~~~~~~~~~~

=================================
OEM / ACPI / MSDM ACTIVATION FLOW
=================================

Trace Source:
    sppobjs.dll
    Windows 8 Build 7792
	Windows 10.0.19044.7184

CALL FLOW (OEM Activation Path)
---------------------------------

AuthenticateSlpBinding
sub_1800C0040
        |
        v
Initialize OEM activation context
        |
        v
LoadAcpiTable
sub_1800E39E4  [via sub_1800E9E28]
        |
        |-- Query firmware interface
        |       (function pointer / COM vtable dispatch)
        |
        |-- ACPI table enumeration (firmware selector IDs as 4-char signatures):
        |       1413763928, 0x58534454, {0x58 0x53 0x44 0x54} --> XSDT
        |       1413763922, 0x41435049, {0x41 0x43 0x50 0x49} --> ACPI
        |       1296323405, 0x4D53444D, {0x4D 0x53 0x44 0x4D} --> MSDM
        |
        v
GetRawAcpiTable
sub_1800E1128
        |
        |-- 1. Query ACPI table size from firmware
        |-- 2. Allocate heap buffer for table data
        |-- 3. Retrieve raw ACPI table via firmware callback
        |-- 4. Validate ACPI header + payload integrity
        |
        v
Return OEM activation data
(includes MSDM when present)

~~~~~~~~~~~~~~~~~~~~

FirmwareTables by vurdalakov
https://github.com/vurdalakov/firmwaretables

get_win8key by Christian Korneck
https://github.com/christian-korneck/get_win8key

ctBiosKey.cpp
https://gist.github.com/hosct/456055c0eec4e71bb504489410ed7fb6#file-ctbioskey-cpp

[C++, C#, VB.NET, PowerShell] Read MSDM license information from BIOS ACPI tables | My Digital Life Forums
https://forums.mydigitallife.net/threads/c-c-vb-net-powershell-read-msdm-license-information-from-bios-acpi-tables.43788/

ACPI Tables
https://www.kernel.org/doc/html/next/arm64/acpi_object_usage.html

Microsoft Software Licensing Tables (SLIC and MSDM)
https://learn.microsoft.com/en-us/previous-versions/windows/hardware/design/dn653305(v=vs.85)?redirectedfrom=MSDN

ACPI Software Programming Model
https://uefi.org/htmlspecs/ACPI_Spec_6_4_html/05_ACPI_Software_Programming_Model/ACPI_Software_Programming_Model.html#system-description-table-header

var table = FirmwareTables.GetAcpiTable("MDSM");
var productKeyLength = (int)table.GetPayloadUInt32(16); // offset 52
var productKey = table.GetPayloadString(20, productKeyLength); // offset 56 > Till End
Console.WriteLine("OEM Windows product key: '{0}'", productKey);

Example Code:
~~~~~~~~~~~~

Clear-Host

Write-Host
Write-Host "Get-OA3xOriginalProductKey" -ForegroundColor Green
Get-OA3xOriginalProductKey

Write-Host
Write-Host "Get-ServiceInfo" -ForegroundColor Green
Get-ServiceInfo -loopAllValues | Format-Table -AutoSize

Write-Host
Write-Host "Get-ActiveLicenseInfo" -ForegroundColor Green
Get-ActiveLicenseInfo | Format-List
);

#>
function Get-SignatureInt {
    param (
        [ValidateNotNullOrEmpty()]
        [string]$Sig, 
        [switch]$Reverse
    )
    [byte[]]$bytes = [System.Text.Encoding]::ASCII.GetBytes($Sig)
    if ($Reverse.IsPresent) {
        # -Reverse specified: Keep the bytes in the order they appear in the string.
        # On x86/x64 (Little-Endian), the first char becomes the LEAST significant byte.
        # Example: "ACPI" -> 0x49504341 (Decimal: 1229996865)
        $Val = [BitConverter]::ToUInt32($bytes, 0)
    } else {
        # Default mode: Reverse the array before converting.
        # This counteracts the system's Little-Endian flip, ensuring the first char 
        # is the MOST significant byte (Big-Endian / Human Readable).
        # Example: "ACPI" -> 0x41435049 (Decimal: 1094930505)
        [Array]::Reverse($bytes)
        $Val = [BitConverter]::ToUInt32($bytes, 0)
    }
    return $Val
}
function Get-OA3xOriginalProductKey {
    param (
        $Sig = 'ACPI',
        $ID  = 'MSDM',
        [switch]$Dump
    )

    # Constants
    $PayLoad    = 0x00
    $HeaderSize = 0x10

    # NT System Information Class
    $SystemFirmwareTableInformation = 0x4c

    # Firmware Actions
    $FirmwareActionEnumerate = 0x00
    $FirmwareActionGet       = 0x01

    # Signature Packing & Endianness Alignment
    # Provider: Pack string as Big-Endian (Human-Readable) for the Kernel Provider field.
    [UInt32]$Provider = Get-SignatureInt $Sig 
    
    # TableId: Align with System-Native Little-Endian for direct memory comparison.
    [UInt32]$TableId  = Get-SignatureInt $ID -Reverse

    # First call: dummy buffer
    $buffer  = New-IntPtr -Size $HeaderSize
    @($Provider, $FirmwareActionGet, $TableId, $PayLoad) | % `
        -Begin { $i=-1 } `
        -Process { [Marshal]::WriteInt32($buffer, (++$I*4), [int]$_)}

    [int]$returnLen = 0
    $status = $Ntdll::NtQuerySystemInformation(
        $SystemFirmwareTableInformation, $buffer, $HeaderSize, [ref]$returnLen
    )

    $PayLoad = [Marshal]::ReadInt32($buffer, 0xC)
    Free-IntPtr -handle $buffer
    
    # So, if you have OEM information in UEFI,
    # this check will succeed, and results >0, >16
    # $returnLen should be at least, 
    # 16 for Header & 56 for Base & 29 for CD KEy.!
    if ($PayLoad -le 0 -or (
        $returnLen -le $HeaderSize)) {
            return $null 
    }

    # Second call: real buffer
    $buffer = New-IntPtr -Size ($HeaderSize + $PayLoad)
    @($Provider, $FirmwareActionGet, $TableId, $PayLoad) | % `
        -Begin { $i=-1 } `
        -Process { [Marshal]::WriteInt32($buffer, (++$I*4), [int]$_)}
    
    try {
        [int]$returnLen = 0
        if (0 -ne $Ntdll::NtQuerySystemInformation(
           $SystemFirmwareTableInformation, $buffer, ($HeaderSize + $PayLoad), [ref]$returnLen)) {
              return $null
        }

        if ($Dump) {
            Dump-MemoryAddress `
                -Pointer ([IntPtr]::Add($buffer, $HeaderSize)) `
                -Length $PayLoad
            write-warning "Memory Dump Complete"
            return
        }

        # memcpy_0(buffer, v10+4, v10[3]);
        # v10[0-3] => 16 bytes, v10[4-?] => Rest bytes, v10[3] => Payload Size
        $pkey = $null
        $pkLen = [Marshal]::ReadInt32($buffer, ($HeaderSize + 0x34))
        if ($pkLen -eq 29) {
           $pkey = [Marshal]::PtrToStringAnsi(
              [IntPtr]::Add($buffer, ($HeaderSize + 0x38)), $pkLen)
        }
        return $pkey
    }
    finally {
        Free-IntPtr -handle $buffer
    }
}

<#
.SYNOPSIS
Get Ubr value.

#>
function Scan-FolderWithAPI {
    param(
        [string]$folder
    )
    
    $maxUBR = $null
    $bufferSize = 592
    $cFileNameOffset = 44
    $regex = [regex]'10\.0\.\d+\.(\d+)'
    $wildcard = "$folder\*-edition*10.*.*.*"

    $pBuffer = [Marshal]::AllocHGlobal($bufferSize)
    $Global:ntdll::RtlZeroMemory($pBuffer,[UIntPtr]::new($bufferSize))

    $handle = $Global:KERNEL32::FindFirstFileW($wildcard, $pBuffer)
    if ($handle -eq [IntPtr]::Zero) {
        [Marshal]::FreeHGlobal($pBuffer)
        return $null
    }

    do {
        $strPtr = [IntPtr]::Add($pBuffer, $cFileNameOffset)
        $filename = [Marshal]::PtrToStringUni($strPtr)
        #Write-Warning $filename

        if ($regex.IsMatch($filename)) {
            $ubr = [int]$regex.Match($filename).Groups[1].Value
            if ($maxUBR -eq $null -or $ubr -gt $maxUBR) {
                $maxUBR = $ubr
            }
        }
    } while ($Global:KERNEL32::FindNextFileW($handle, $pBuffer))

    $null = $Global:KERNEL32::FindClose($handle)
    $null = [Marshal]::FreeHGlobal($pBuffer)

    return $maxUBR
}
function Get-LatestUBR {
    param (
      [bool]$UsPs1 = $false
    )
    
    $UBR = $null
    $wildcardPattern = '*-edition*10.*.*.*'
    $regexVersion = [regex]'10\.0\.\d+\.(\d+)'
    $Manifestsfolder = 'C:\Windows\WinSxS\Manifests'
    $Packagessfolder = 'C:\Windows\servicing\Packages'
    $swTotal = [System.Diagnostics.Stopwatch]::StartNew()

    # Try Packages folder
    if (!$UsPs1) {
        $UBR = Scan-FolderWithAPI $Packagessfolder
    } else {
        $files = [Directory]::EnumerateFiles(
            $Packagessfolder, $wildcardPattern, [SearchOption]::TopDirectoryOnly)
        foreach ($file in $files) {
            #Write-Warning $file
            $match = $regexVersion.Match($file)
            if ($match.Success) {
                $candidateUBR = [int]$match.Groups[1].Value
                if ($UBR -eq $null -or $candidateUBR -gt $UBR) {
                    $UBR = $candidateUBR
                }
            }
        }
    }

    # If no result, try Manifests folder
    if ((!$UBR -or $UBR -eq 0) -and !$UsPs1) {
        $UBR = Scan-FolderWithAPI $Manifestsfolder
    }
    elseif ((!$UBR -or $UBR -eq 0) -and $UsPs1) {
        $files = [Directory]::EnumerateFiles(
            $Manifestsfolder, $wildcardPattern, [SearchOption]::TopDirectoryOnly)
        foreach ($file in $files) {
            #Write-Warning $file
            $match = $regexVersion.Match($file)
            if ($match.Success) {
                $candidateUBR = [int]$match.Groups[1].Value
                if ($candidateUBR -gt $UBR) {
                    $UBR = $candidateUBR
                }
            }
        }
    }

    # Fallback to registry if still nothing
    if (!$UBR -or $UBR -eq 0) {
        try {
            $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
            $UBR = Get-ItemPropertyValue -Path $regPath -Name UBR -ErrorAction Stop
        }
        catch {
            #Write-Warning "Failed to read UBR from registry: $_"
        }
    }
    
    $swTotal.Stop()
    #Write-Warning "Results: $UBR"
    #Write-Warning "Total Get-LatestUBR time: $($swTotal.ElapsedMilliseconds) ms"

    if (!$UBR) {
        return 0
    }

    return $UBR
}

function Get-StringFromBytes {
    param(
        [byte[]]$array,
        [int]$start,
        [int]$length
    )
    if ($start + $length -le $array.Length) {
        return [Encoding]::Unicode.GetString($array, $start, $length).TrimEnd([char]0)
    }
    else {
        Write-Warning "Requested string range $start to $($start + $length) exceeds array length $($array.Length)"
        return ""
    }
}
function Get-AsciiString {
    param([byte[]]$array, [int]$start, [int]$length)
    if ($start + $length -le $array.Length) {
        return [Encoding]::ASCII.GetString($array, $start, $length).TrimEnd([char]0)
    }
    else {
        Write-Warning "Requested ASCII string range $start to $($start + $length) exceeds array length $($array.Length)"
        return ""
    }
}

<#
Source,
LicensingDiagSpp.dll, LicensingWinRT.dll, SppComApi.dll, SppWinOb.dll
__int64 __fastcall CProductKeyUtilsT<CEmptyType>::BinaryDecode(__m128i *a1, __int64 a2, unsigned __int16 **a3)

# DigitalProductId (normal key)
$pKeyBytes = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "DigitalProductId" -ErrorAction Stop | Select-Object -ExpandProperty DigitalProductId
$pKey = Get-DigitalProductKey -bCDKeyArray $pKeyBytes[52..66]
SL-InstallProductKey $pKey

# DigitalProductId4 (Windows 10/11 keys)
$pKeyBytes = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "DigitalProductId4" -ErrorAction Stop | Select-Object -ExpandProperty DigitalProductId4
$pKey = Get-DigitalProductKey -bCDKeyArray $pKeyBytes[808..822]
SL-InstallProductKey $pKey
#>
<#
.SYNOPSIS
Extract DigitalProductId + DigitalProductId[4] Data,
using registry Key.

janek2012's magic decoding function
https://forums.mydigitallife.net/threads/the-ultimate-pid-checker.20816/
https://xdaforums.com/t/extract-windows-rt-product-key-without-jailbreak-or-pc.2442791/

PIDX Checker Class
https://github.com/IonBazan/pidgenx/blob/master/pidxcheckerclass.h

sppcomapi.dll
__int64 __fastcall CLicensingStateTools::get_DefaultKeyFromRegistry(CLicensingStateTools *this, unsigned __int16 **a2)
--> v6 = ReadProductKeyFromRegistry(0i64, &hMem);
--> Value = CRegUtilT<void *,CRegType,0,1>::GetValue(a1, v10, L"DigitalProductId", (BYTE **)&hMem, &v14);
--> v13 = CProductKeyUtilsT<CEmptyType>::BinaryDecode((char *)hMem + 52, v11, &v15);
a1: pointer to 16-byte product key data (from DigitalProductId4.m_abCdKey or registry).
a2: length of the data (unused much in the snippet).
a3: output pointer to store the decoded Unicode product key string.

__int64 __fastcall CProductKeyUtilsT(__m128i *a1)
{
  char Src[54];
  [__m128i] v21 = *a1;
  [__int16 *v20;] v20 = 0i64;
  v22 = *(_OWORD *)L"BCDFGHJKMPQRTVWXY2346789";
  if ( (_mm_srli_si128(v21, 8).m128i_u64[0] & 0xF0000000000000i64) != 0 )
    BREAK CODE
  [__int64] v6 = 24i64;
  [BOOL] v7 = (v21.m128i_i8[14] & 8) != 0;
  v21.m128i_i8[14] ^= (v21.m128i_i8[14] ^ (4 * ((v21.m128i_i8[14] & 8) != 0))) & 8;
  do
  {
    __int64 LODWORD(v8) = 0;
    for ( i = 14i64; i >= 0; --i )
    {
      v10 = v21.m128i_u8[i] + ((_DWORD)v8 << 8);
      v21.m128i_i8[i] = v10 / 0x18;
      v8 = v10 % 0x18;
    }
    *(_WORD *)&Src[2 * v6-- - 2] = *((_WORD *)v22 + v8);
  }
  while ( v6 >= 0 );
  
  if ( v21.m128i_i8[0] )
      BREAK CODE
  else
  {
    if ( v7 )
    {
      [__int64] v11 = 2 * v8;
      memmove_0(&v24, Src, 2 * v8);
      *(_WORD *)&Src[v11 - 2] = 78; ` Insert [N]
    }
    v12 = STRAPI_CreateCchBufferN(0x2Du, 0x1Eui64, &v20);
    if ( v12 >= 0 )
    {
      v13 = v20;
      v14 = &v24;
      for ( j = 0; j < 25; ++j )
      {
        v16 = *v14++;
        v17 = j + j / 5;
        v13[v17] = v16;
      }
      *a3 = v13;
    }
    else
       BREAK CODE
  }
}
#>
function Get-DigitalProductKey {
    param (
        [Parameter(Mandatory=$true)]
        [byte[]]$bCDKeyArray,

        [Parameter(Mandatory=$false)]
        [switch]$Log
    )

    # Clone input to v21 (like C++ __m128i copy)
    $keyData = $bCDKeyArray.Clone()

    # +2 for N` Logic Shift right [else fail]
    $Src = New-Object char[] 27

    # Character set for base-24 decoding
    $charset = "BCDFGHJKMPQRTVWXY2346789"

    # Validate input length
    if ($keyData.Length -lt 15 -or $keyData.Length -gt 16) {
        throw "Input data must be a 15 or 16 byte array."
    }

    # Win.8 key check
    if (($keyData[14] -band 0xF0) -ne 0) {
        throw "Failed to decode.!"
    }

    # N-flag
    $T = 0
    $BYTE14 = [byte]$keyData[14]
    $flag = (($BYTE14 -band 0x08) -ne 0)

    # BYTE14(v22) = (4 * (((BYTE14(v22) & 8) != 0) & 2)) | BYTE14(v22) & 0xF7;
    $keyData[14] = (4 * (([int](($BYTE14 -band 8) -ne 0)) -band 2)) -bor ($BYTE14 -band 0xF7)

    # BYTE14(v22) ^= (BYTE14(v22) ^ (4 * ((BYTE14(v22) & 8) != 0))) & 8;
    #$keyData[14] = $BYTE14 -bxor (($BYTE14 -bxor (4 * ([int](($BYTE14 -band 8) -ne 0)))) -band 8)

    # Base-24 decoding loop
    for ($idx = 24; $idx -ge 0; $idx--) {
        $last = 0
        for ($j = 14; $j -ge 0; $j--) {
            $val = $keyData[$j] + ($last -shl 8)
            $keyData[$j] = [math]::Floor($val / 0x18)
            $last = $val % 0x18
        }
        $Src[$idx] = $charset[$last]
    }

    if ($keyData[0] -ne 0) {
        throw "Invalid product key data"
    }

    # Handle N-flag
    $rev = $last -gt 13
    $pos = if ($rev) {25} else {-1}
    if ($Log) {
        $Output = (0..4 | % { -join $Src[(5*$_)..((5*$_)+4)] }) -join '-'
        Write-Warning "Before, $Output"
    }

    # Shift Left, Insert N, At position 0 >> $Src[0]=`N`
    if ($flag -and ($last -le 0)) {
        $Src[0] = [Char]78
    }
    # Shift right, Insert N, Count 1-25 [27 Base,0-24 & 2` Spacer's]
    elseif ($flag -and $rev) {
        while ($pos-- -gt $last){$Src[$pos + 1]=$Src[$pos]}
        $T, $Src[$last+1] = 1, [char]78
    }
    # Shift left, Insert N,
    elseif ($flag -and !$rev) {
        while (++$pos -lt $last){$Src[$pos] = $Src[$pos + 1]}
        $Src[$last] = [char]78
    }

    # Dynamically format 5x5 with dashes
    $Output = (0..4 | % { -join $Src[((5*$_)+$T)..((5*$_)+4+$T)] }) -join '-'
    if ($Log) {
        Write-Warning "After,  $Output"
    }
    return $Output
}
function Parse-DigitalProductId {
    param (
        [string]$RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    )

    try {
        $digitalProductId = (Get-ItemProperty -Path $RegistryPath -ErrorAction Stop).DigitalProductId
    }
    catch {
        Write-Warning "Failed to read DigitalProductId from registry path $RegistryPath"
        return $null
    }

    if (-not $digitalProductId) {
        Write-Warning "DigitalProductId property not found in registry."
        return $null
    }

    # Ensure byte array
    $byteArray = if ($digitalProductId -is [byte[]]) { $digitalProductId } else { [byte[]]$digitalProductId }

    # Define offsets and lengths for each field in one hashtable
    $offsets = @{
        uiSize        = @{ Offset = 0;  Length = 4  }
        MajorVersion  = @{ Offset = 4;  Length = 2  }
        MinorVersion  = @{ Offset = 6;  Length = 2  }
        ProductId     = @{ Offset = 8;  Length = 24 }
        EditionId     = @{ Offset = 36; Length = 16 }
        bCDKey        = @{ Offset = 52; Length = 16 }
    }

    # Extract components safely
    $uiSize = [BitConverter]::ToUInt32($byteArray, $offsets.UISize.Offset)
    $productId = Get-AsciiString -array $byteArray -start $offsets.ProductId.Offset -length $offsets.ProductId.Length
    $editionId = Get-AsciiString -array $byteArray -start $offsets.EditionId.Offset -length $offsets.EditionId.Length

    # Extract bCDKey array for product key decoding
    $bCDKeyArray = $byteArray[$offsets.bCDKey.Offset..($offsets.bCDKey.Offset + $offsets.bCDKey.Length - 1)]

    # Decode Digital Product Key (placeholder function - implement accordingly)
    $digitalProductKey = Get-DigitalProductKey -bCDKeyArray $bCDKeyArray

    # Extract MajorVersion and MinorVersion from byte array
    $majorVersion = [BitConverter]::ToUInt16($byteArray, $offsets.MajorVersion.Offset)
    $minorVersion = [BitConverter]::ToUInt16($byteArray, $offsets.MinorVersion.Offset)

    # Return structured object
    return [PSCustomObject]@{
        UISize       = $uiSize
        MajorVersion = $majorVersion
        MinorVersion = $minorVersion
        ProductId    = $productId
        EditionId    = $editionId
        DigitalKey   = $digitalProductKey
    }
}
function Parse-DigitalProductId4 {
    param(
        [string]$RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion",
        [IntPtr]$Pointer = [System.IntPtr]::Zero,
        [int]$Length = 0,

        [switch] $FromIntPtr,
        [switch] $FromRegistry
    )

    $ParamsCheck = -not ($FromIntPtr -xor $FromRegistry)
    if ($ParamsCheck) {
        $FromIntPtr = $null
        $FromRegistry = $true
        Write-Warning "use default values, read from registry"
    }

    # Retrieve DigitalProductId4
    if ($FromIntPtr) {
        if ($Pointer -ne [System.IntPtr]::Zero -and $Length -gt 0) {
            try {
                $byteArray = New-Object byte[] $Length
                [Marshal]::Copy($Pointer, $byteArray, 0, $Length)
            }
            catch {
                Write-Warning "Failed to copy memory from pointer."
                return $null
            }
        }
    }
    if ($FromRegistry) {
        try {
            $digitalProductId4 = (Get-ItemProperty -Path $RegistryPath -ErrorAction Stop).DigitalProductId4
        }
        catch {
            Write-Warning "Failed to read DigitalProductId4 from registry path $RegistryPath"
            return $null
        }

        if (-not $digitalProductId4) {
            Write-Warning "DigitalProductId4 property not found in registry."
            return $null
        }

        # Ensure we have a byte array
        $byteArray = if ($digitalProductId4 -is [byte[]]) { $digitalProductId4 } else { [byte[]]$digitalProductId4 }
    }

    # Offsets dictionary for structured fields with length included
    $offsets = @{
        uiSize        = @{ Offset = 0;    Length = 4  }
        MajorVersion  = @{ Offset = 4;    Length = 2  }
        MinorVersion  = @{ Offset = 6;    Length = 2  }
        AdvancedPid  = @{ Offset = 8;    Length = 128 }
        ActivationId = @{ Offset = 136;  Length = 128 }
        EditionType  = @{ Offset = 280;  Length = 520 }
        EditionId    = @{ Offset = 888;  Length = 128 }
        KeyType      = @{ Offset = 1016; Length = 128 }
        EULA         = @{ Offset = 1144; Length = 128 }
        bCDKey       = @{ Offset = 808;  Length = 16  }
    }

    # Extract values
    $uiSize = if ($byteArray.Length -ge 4) { [BitConverter]::ToUInt32($byteArray, 0) } else { 0 }

    $advancedPid = Get-StringFromBytes -array $byteArray -start $offsets.AdvancedPid.Offset -length $offsets.AdvancedPid.Length
    $activationId = Get-StringFromBytes -array $byteArray -start $offsets.ActivationId.Offset -length $offsets.ActivationId.Length
    $editionType = Get-StringFromBytes -array $byteArray -start $offsets.EditionType.Offset -length $offsets.EditionType.Length
    $editionId = Get-StringFromBytes -array $byteArray -start $offsets.EditionId.Offset -length $offsets.EditionId.Length
    $keyType = Get-StringFromBytes -array $byteArray -start $offsets.KeyType.Offset -length $offsets.KeyType.Length
    $eula = Get-StringFromBytes -array $byteArray -start $offsets.EULA.Offset -length $offsets.EULA.Length

    # Extract bCDKey array used for key retrieval
    $bCDKeyOffset = $offsets.bCDKey.Offset
    $bCDKeyLength = $offsets.bCDKey.Length
    $bCDKeyArray = $byteArray[$bCDKeyOffset..($bCDKeyOffset + $bCDKeyLength - 1)]

    # Extract MajorVersion and MinorVersion from byte array
    $majorVersion = [BitConverter]::ToUInt16($byteArray, $offsets.MajorVersion.Offset)
    $minorVersion = [BitConverter]::ToUInt16($byteArray, $offsets.MinorVersion.Offset)

    # Call to external helper to decode the Digital Product Key
    # You need to define this function based on your key decoding logic
    $digitalProductKey = Get-DigitalProductKey -bCDKeyArray $bCDKeyArray

    # Return a structured object
    return [PSCustomObject]@{
        UISize       = $uiSize
        MajorVersion = $majorVersion
        MinorVersion = $minorVersion
        AdvancedPID  = $advancedPid
        ActivationID = $activationId
        EditionType  = $editionType
        EditionID    = $editionId
        KeyType      = $keyType
        EULA         = $eula
        DigitalKey   = $digitalProductKey
    }
}
#endregion
#region "HWID_SUB"
<#
Examples.

.DESCRIPTION
    Creates a COM object to access licensing state and related properties.
    Parses various status enums into readable strings.
    Returns a PSCustomObject with detailed licensing info or $null if unable to create the COM object.

.EXAMPLE
    $licInfo = Get-LicensingInfo
    if ($licInfo) {
        $licInfo | Format-List
    } else {
        Write-Error "Failed to retrieve licensing info."
    }
#>
function Get-LicensingInfo {
    try {
        $clsid = "AA04CA0B-7597-4F3E-99A8-36712D13D676"
        $obj = [Activator]::CreateInstance([type]::GetTypeFromCLSID($clsid))
    }
    catch {
        return $null
    }
    try {
        
        # ENUM mappings
        $licensingStatusMap = @{
            0 = "Unlicensed (LICENSING_STATUS_UNLICENSED)"
            1 = "Licensed (LICENSING_STATUS_LICENSED)"
            2 = "In Grace Period (LICENSING_STATUS_IN_GRACE_PERIOD)"
            3 = "Notification Mode (LICENSING_STATUS_NOTIFICATION)"
            4 = "Sentinel (SL_LICENSING_STATUS_LAST)"
        }

        $gracePeriodTypeMap = @{
            0   = "Out of Box Grace Period (E_GPT_OUT_OF_BOX)"
            1   = "Hardware Out-of-Tolerance Grace Period (E_GPT_HARDWARE_OOT)"
            2   = "Time-Based Validity Grace Period (E_GPT_TIMEBASED_VALIDITY)"
            255 = "Undefined Grace Period (E_GPT_UNDEFINED)"
        }

        $channelMap = @{
            0   = "Invalid License (LB_Invalid)"
            1   = "Hardware Bound (LB_HardwareId)"
            2   = "Environment-Based License (LB_Environment)"
            4   = "BIOS COA - Certificate of Authenticity (LB_BiosCOA)"
            8   = "BIOS SLP - System Locked Pre-installation (LB_BiosSLP)"
            16  = "BIOS Hardware ID License (LB_BiosHardwareID)"
            32  = "Token-Based Activation (LB_TokenActivation)"
            64  = "Automatic Virtual Machine Activation (LB_AutomaticVMActivation)"
            17  = "Hardware Binding - Any (LB_BindingHardwareAny)"
            12  = "BIOS Binding - Any (LB_BindingBiosAny)"
            28  = "BIOS Channel - Any (LB_ChannelBiosAny)"
            -1  = "Any Channel - Wildcard (LB_ChannelAny)"
        }

        $activationReasonMap = @{
            0   = "Generic Activation Error (E_AR_GENERIC_ERROR)"
            1   = "Activated Successfully (E_AR_ACTIVATED)"
            2   = "Invalid Product Key (E_AR_INVALID_PK)"
            3   = "Product Key Already Used (E_AR_USED_PRODUCT_KEY)"
            4   = "No Internet Connection (E_AR_NO_INTERNET)"
            5   = "Unexpected Error During Activation (E_AR_UNEXPECTED_ERROR)"
            6   = "Cannot Activate in Safe Mode (E_AR_SAFE_MODE_ERROR)"
            7   = "System State Error Preventing Activation (E_AR_SYSTEM_STATE_ERROR)"
            8   = "OEM COA Error (E_AR_OEM_COA_ERROR)"
            9   = "Expired License(s) (E_AR_EXPIRED_LICENSES)"
            10  = "No Product Key Installed (E_AR_NO_PKEY_INSTALLED)"
            11  = "Tampering Detected (E_AR_TAMPER_DETECTED)"
            12  = "Reinstallation Required for Activation (E_AR_REINSTALL_REQUIRED)"
            13  = "System Reboot Required (E_AR_REBOOT_REQUIRED)"
            14  = "Non-Genuine Windows Detected (E_AR_NON_GENUINE)"
            15  = "Token-Based Activation Error (E_AR_TOKENACTIVATION_ERROR)"
            16  = "Blocked Product Key Due to IP/Location (E_AR_BLOCKED_IPLOCATION_PK)"
            17  = "DNS Resolution Error (E_AR_DNS_ERROR)"
            18  = "Product Key Validation Error (E_VR_PRODUCTKEY_ERROR)"
            19  = "Raw Product Key Error (E_VR_PRODUCTKEY_RAW_ERROR)"
            20  = "Product Key Blocked by UI Policy (E_VR_PRODUCTKEY_UI_BLOCK)"
            255 = "Activation Reason Not Found (E_AR_NOT_FOUND)"
        }

        $systemStateFlagsMap = @{
            1  = "Reboot Policy Detected (SYSTEM_STATE_REBOOT_POLICY_FOUND)"
            2  = "System Tampering Detected (SYSTEM_STATE_TAMPERED)"
            8  = "Trusted Store Tampered (SYSTEM_STATE_TAMPERED_TRUSTED_STORE)"
            32 = "Kernel-Mode Cache Tampered (SYSTEM_STATE_TAMPERED_KM_CACHE)"
        }

        # Parse bitfield SystemStateFlags
        $stateFlags = $obj.SystemStateFlags
        $parsedStateFlags = @()
        foreach ($flag in $systemStateFlagsMap.Keys) {
            if ($stateFlags -band $flag) {
                $parsedStateFlags += $systemStateFlagsMap[$flag]
            }
        }

        $state = $obj.LicensingState
        $errMsg = Parse-ErrorMessage -MessageId $state.StatusReasonCode

        $result = [PSCustomObject]@{
            LicensingSystemDate         = $obj.LicensingSystemDate
            SystemStateFlags      = $parsedStateFlags -join ', '
            ActiveLicenseChannel  = $channelMap[$obj.ActiveLicenseChannel]
            ProductKeyType              = $obj.ProductKeyType
            IsTimebasedKeyInstalled     = [bool]$obj.IsTimebasedKeyInstalled
            DefaultKeyFromRegistry      = $obj.DefaultKeyFromRegistry
            IsLocalGenuine              = $obj.IsLocalGenuine
            skuId                   = $state.skuId
            Status            = $licensingStatusMap[$state.Status]
            StatusReasonCategory    = $activationReasonMap[$state.StatusReasonCategory]
            StatusReasonCode        = $errMsg
            Channel           = $channelMap[$state.Channel]
            GracePeriodType   = $gracePeriodTypeMap[$state.GracePeriodType]
            ValidityExpiration      = $state.ValidityExpiration
            KernelExpiration        = $state.KernelExpiration
        }

        return $result
    }
    catch {
    }
    finally {
        $null = [Marshal]::ReleaseComObject($obj)
        $null = [GC]::Collect()
        $null = [GC]::WaitForPendingFinalizers()
    }
}

<#
 Source ... 
 https://github.com/asdcorp/clic
 https://github.com/gravesoft/CAS
#>
function Active-DigitalLicense {
    $interfaceSpec = Build-ComInterfaceSpec `
       -CLSID "17CCA47D-DAE5-4E4A-AC42-CC54E28F334A" `
       -IID "F2DCB80D-0670-44BC-9002-CD18688730AF" `
       -Index 5 `
       -Name AcquireModernLicenseForWindows `
       -Return int `
       -Params "int bAsync, out int lmReturnCode"

    try {
        $comObject = $interfaceSpec | Initialize-ComObject
        [int]$lmReturnCode = 0
        $hr = $comObject | Invoke-Object -Params (
            @(1, [ref]$lmReturnCode)) -type COM

        if ($hr -eq 0) {
            return ($lmReturnCode -ne 1 -and $lmReturnCode -le [int32]::MaxValue)
        } else {
            return $false
        }

    } catch {
        Write-Warning "An error occurred: $($_.Exception.Message)"
        return $false
    } finally {
        $comObject | Release-ComObject
    }
}

<#
Source: Clic.C
Check if SubscriptionStatus
#>
function Active-SubscriptionStatus {
    $dwSupported = 0 
    $ConsumeAddonPolicy = Get-ProductPolicy -Filter 'ConsumeAddonPolicySet' -UseApi
    if (-not $ConsumeAddonPolicy -or $ConsumeAddonPolicy.Value -eq $null) {
        return $false
    }
    
    $dwSupported = $ConsumeAddonPolicy.Value
    if ($dwSupported -eq 0) {
        return $false
    }

    $StatusPtr = [IntPtr]::Zero
    $ClipResult = $Global:CLIPC::ClipGetSubscriptionStatus([ref]$StatusPtr, [intPtr]::zero, [intPtr]::zero, [intPtr]::zero)
    if ($ClipResult -ne 0 -or $StatusPtr -eq [IntPtr]::Zero) {
        return $false
    }

    # so, it hold return data, no return data, no entiries
    # no entiries --> $False
    try {
        $dwStatus = [Marshal]::ReadInt32($StatusPtr)
        if ($dwStatus -and $dwStatus -gt 0) {
            return $true
        }
        return $false
    }
    finally {
        Free-IntPtr -handle $StatusPtr -Method Heap
    }
}

<#
Source: Clic.C
HRESULT WINAPI ClipGetSubscriptionStatus(
    SUBSCRIPTIONSTATUS **ppStatus
);

typedef struct _tagSUBSCRIPTIONSTATUS {
    DWORD dwEnabled;
    DWORD dwSku;
    DWORD dwState;
} SUBSCRIPTIONSTATUS;   

BOOL PrintSubscriptionStatus() {
    SUBSCRIPTIONSTATUS *pStatus;
    DWORD dwSupported = 0;

    if(SLGetWindowsInformationDWORD(L"ConsumeAddonPolicySet", &dwSupported))
        return FALSE;

    wprintf(L"SubscriptionSupportedEdition=%ws\n", BoolToWStr(dwSupported));

    if(ClipGetSubscriptionStatus(&pStatus))
        return FALSE;

    wprintf(L"SubscriptionEnabled=%ws\n", BoolToWStr(pStatus->dwEnabled));

    if(pStatus->dwEnabled == 0) {
        LocalFree(pStatus);
        return TRUE;
    }

    wprintf(L"SubscriptionSku=%d\n", pStatus->dwSku);
    wprintf(L"SubscriptionState=%d\n", pStatus->dwState);

    LocalFree(pStatus);
    return TRUE;
}

----------------------

typedef struct {
    int count;          // 4 bytes, at offset 0
    struct {
        int field1;     // 4 bytes
        int field2;     // 4 bytes
    } entries[];        // Followed by 'count' of these 8-byte pairs
} ClipSubscriptionData;

#>
function Get-SubscriptionStatus {
    $StatusPtr = [IntPtr]::Zero
    $ClipResult = $Global:CLIPC::ClipGetSubscriptionStatus([ref]$StatusPtr, [intPtr]::zero, [intPtr]::zero, [intPtr]::zero)
    if ($ClipResult -ne 0 -or $StatusPtr -eq [IntPtr]::Zero) {
        return $false
    }

    try {
        $currentOffset = 4
        $subscriptionEntries = @()
        $dwStatus = [Marshal]::ReadInt32($StatusPtr)

        for ($i = 0; $i -lt $dwStatus; $i++) {
            $dwField1 = [Marshal]::ReadInt32([IntPtr]::Add($StatusPtr, $currentOffset))
            $currentOffset += 4

            $dwField2 = [Marshal]::ReadInt32([IntPtr]::Add($StatusPtr, $currentOffset))
            $currentOffset += 4

            $entry = [PSCustomObject]@{
                Sku   = $dwField1
                State = $dwField2
            }
            $subscriptionEntries += $entry
        }
        return $subscriptionEntries
    }
    finally {
        Free-IntPtr -handle $StatusPtr -Method Heap
    }
}
#endregion
#region "FileData"
# Load As Type [C# CODE] Or Assembly [DLL]
function Compress-FileData {
    param (
        [string]$filePath
    )

    $fileBytes = [File]::ReadAllBytes($filePath)
    $compressedMemoryStream = [MemoryStream]::new()
    $gzipStream = New-Object GZipStream($compressedMemoryStream, [CompressionLevel]::Optimal)
    $gzipStream.Write($fileBytes, 0, $fileBytes.Length)
    $gzipStream.Close()
    $compressedBytes = $compressedMemoryStream.ToArray()
    return (
        [Convert]::ToBase64String($compressedBytes)
    )
}
function Load-FileData {
    [CmdletBinding(DefaultParameterSetName = "Base64")]
    param (
        [Parameter(Mandatory, Position = 0, ParameterSetName = "Base64")]
        [ValidateNotNullOrEmpty()]
        [string]$Base64,

        [Parameter(Mandatory, ParameterSetName = "Path")]
        [ValidateScript({ Test-Path $_ })]
        [string]$FilePath,

        [Parameter(Mandatory, ParameterSetName = "Binary")]
        [byte[]]$Data,

        [Parameter(Mandatory)]
        [ValidateSet("Assembly", "Type")]
        [string]$Mode,

        [string]$SelfCheck
    )

    process {
        try {
            $compressedBytes = switch ($PSCmdlet.ParameterSetName) {
                "Binary" { $Data }
                "Base64" { [Convert]::FromBase64String($Base64) }
                "Path"   { [Convert]::FromBase64String([File]::ReadAllText($FilePath)) }
            }

            $msInput  = [MemoryStream]::new($compressedBytes)
            $msOutput = [MemoryStream]::new()
            $gzip     = [GZipStream]::new($msInput, [CompressionMode]::Decompress)
            
            $gzip.CopyTo($msOutput)
            $gzip.Dispose()
            $msInput.Dispose()
            
            $decompressedBytes = $msOutput.ToArray()
            $msOutput.Dispose()

            switch ($Mode) {
                "Assembly" {
                    [Assembly]::Load($decompressedBytes) | Out-Null
                }
                "Type" {
                    $sourceCode = [Encoding]::UTF8.GetString($decompressedBytes)
                    $Assemblies = @("System", "System.Core", "System.Data", "System.Xml", "System.Xml.Linq", "System.Linq", "Microsoft.CSharp")
                    Add-Type -TypeDefinition $sourceCode -ReferencedAssemblies $Assemblies | Out-Null
                }
            }

            if ($SelfCheck) {
                if (([PSTypeName]$SelfCheck).Type) {
                    Write-Host "[+] Self check Succeeded: $SelfCheck" -ForegroundColor Cyan
                } else {
                    Write-Error "Self check Failed: Type '$SelfCheck' not found."
                }
            }
        }
        catch {
            Write-Error "Failed to process data: $($_.Exception.Message)"
        }
    }
}
# Export / Import As DATA File [Base64 Format]
function Export-BinaryToTaggedBase {
    param (
        [Parameter(Mandatory=$true)][string]$FilePath,
        [int]$LineLength = 120
    )

    if (-not (Test-Path $FilePath)) { return }

    # 1. Compress (Deflate)
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $ms = New-Object System.IO.MemoryStream
    $deflate = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionLevel]::Optimal)
    $deflate.Write($bytes, 0, $bytes.Length)
    $deflate.Dispose()
    
    # 2. Base64 Conversion
    $b64 = [Convert]::ToBase64String($ms.ToArray())

    # 3. Splitting logic for readability
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("## HEADER ##")
    [void]$sb.AppendLine("<#")
    for ($i = 0; $i -lt $b64.Length; $i += $LineLength) {
        $len = [Math]::Min($LineLength, $b64.Length - $i)
        [void]$sb.AppendLine($b64.Substring($i, $len))
    }
    [void]$sb.AppendLine("#>")
    [void]$sb.AppendLine("## END ##")

    # 4. Save to Desktop
    $outFile = Join-Path ([Environment]::GetFolderPath("Desktop")) "TaggedBlob.txt"
    $sb.ToString() | Set-Content -Path $outFile -Encoding Ascii
    Write-Host "Tagged blob saved to Desktop: $outFile" -ForegroundColor Green
}
## DATABLOCK ## & <# & ............ & #> & ## END ##
# Import-EmbeddedBlock -BlockName "DATABLOCK" -OutPath $patchExe
function Import-EmbeddedBlock {
    [CmdletBinding(DefaultParameterSetName = "ToFile")]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$BlockName,

        [Parameter(Mandatory=$true, ParameterSetName="ToFile")]
        [string]$OutPath,

        [Parameter(Mandatory=$true, ParameterSetName="ToBytes")]
        [switch]$OutBytes
    )

    try {
        # Managed .NET Read (significant speed boost over Get-Content)
        $content = [System.IO.File]::ReadAllText($PSCommandPath)

        # Managed .NET Regex for extraction
        $regexPattern = "(?s)## $BlockName ##\r?\n<#\r?\n(.*?)\r?\n#>\r?\n## END ##"
        $match = [System.Text.RegularExpressions.Regex]::Match($content, $regexPattern)

        if (-not $match.Success) {
            Write-Warning "Block '## $BlockName ##' not found."
            return $false
        }

        # Cleanup Base64 and Decompress via .NET Streams
        $b64 = $match.Groups[1].Value -replace "[\r\n\s]", ""
        $data = [System.Convert]::FromBase64String($b64)
        
        $msIn = [System.IO.MemoryStream]::new($data)
        $deflate = [System.IO.Compression.DeflateStream]::new($msIn, [System.IO.Compression.CompressionMode]::Decompress)
        $msOut = [System.IO.MemoryStream]::new()
        
        $deflate.CopyTo($msOut)
        $finalBytes = $msOut.ToArray()

        # Explicit cleanup
        $deflate.Dispose(); $msIn.Dispose(); $msOut.Dispose()

        # Output Logic
        switch ($PSCmdlet.ParameterSetName) {
            "ToFile" {
                $fullPath = [System.IO.Path]::GetFullPath($OutPath)
                $dir = [System.IO.Path]::GetDirectoryName($fullPath)

                # Managed Directory Creation
                if ($dir -and -not [System.IO.Directory]::Exists($dir)) {
                    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
                }

                [System.IO.File]::WriteAllBytes($fullPath, $finalBytes)
                return $true
            }
            "ToBytes" {
                return $finalBytes
            }
        }
    } catch {
        Write-Error "Failed to process block $BlockName : $($_.Exception.Message)"
        return $false
    }
}
#endregion

# work - job Here.

if ($null -eq $PSVersionTable -or $null -eq $PSVersionTable.PSVersion -or $null -eq $PSVersionTable.PSVersion.Major) {
    Clear-host
    Write-Host
    Write-Host "Unable to determine PowerShell version." -ForegroundColor Green
    Write-Host "This script requires PowerShell 5.0 or higher!" -ForegroundColor Green
    Write-Host
    Read-Host "Press Enter to exit..."
    Read-Host
    return
}

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Clear-host
    Write-Host
    Write-Host "This script requires PowerShell 5.0 or higher!" -ForegroundColor Green
    Write-Host "Windows 10 & Above are supported." -ForegroundColor Green
    Write-Host
    Read-Host "Press Enter to exit..."
    Read-Host
    return
}

# Check if the current user is System or an Administrator
$isSystem = Check-AccountType -AccType System
$isAdmin  = Check-AccountType -AccType Administrator

if (![bool]$isSystem -and ![bool]$isAdmin) {
    Clear-host
    Write-Host
    if ($isSystem -eq $null -or $isAdmin -eq $null) {
        Write-Host "Unable to determine if the current user is System or Administrator." -ForegroundColor Yellow
        Write-Host "There may have been an internal error or insufficient permissions." -ForegroundColor Yellow
        return
    }
    Write-Host "This script must be run as Administrator or System!" -ForegroundColor Green
    Write-Host "Please run this script as Administrator." -ForegroundColor Green
    Write-Host "(Right-click and select 'Run as Administrator')" -ForegroundColor Green
    Write-Host
    Read-Host "Press Enter to exit..."
    Read-Host
    return
}

$Global:PKeyDatabase = Init-XMLInfo

# Get Minimal Privileges To Load Some NtDll function
$PrivilegeList = @("SeDebugPrivilege", "SeImpersonatePrivilege", "SeIncreaseQuotaPrivilege", "SeAssignPrimaryTokenPrivilege", "SeSystemEnvironmentPrivilege")
Adjust-TokenPrivileges -Privilege $PrivilegeList -Log -SysCall

# INIT Global Variables
$Global:OfficeAppId  = '0ff1ce15-a989-479d-af46-f275c6370663'
$Global:windowsAppID  = '55c92734-d682-4d71-983e-d6ec3f16059f'
$Global:knownAppGuids = @($windowsAppID, $OfficeAppId)
$Global:CurrentVersion = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$Global:ubr = try { Get-LatestUBR } catch { 0 }
$Global:osVersion = Init-osVersion
$OperatingSystem = Get-CimInstance Win32_OperatingSystem -ea 0
$Global:OperatingSystemInfo = [PSCustomObject]@{
    dwOSMajorVersion = $Global:osVersion.Major
    dwOSMinorVersion = $Global:osVersion.Minor
    dwSpMajorVersion = try {$Global:osVersion.ServicePackMajor} catch {0};
    dwSpMinorVersion = try {$Global:osVersion.ServicePackMinor} catch {0};
}

#region "KeyInfo"
$crc32_table = (
    0x0,
    0x04c11db7, 0x09823b6e, 0x0d4326d9, 0x130476dc, 0x17c56b6b,
    0x1a864db2, 0x1e475005, 0x2608edb8, 0x22c9f00f, 0x2f8ad6d6,
    0x2b4bcb61, 0x350c9b64, 0x31cd86d3, 0x3c8ea00a, 0x384fbdbd,
    0x4c11db70, 0x48d0c6c7, 0x4593e01e, 0x4152fda9, 0x5f15adac,
    0x5bd4b01b, 0x569796c2, 0x52568b75, 0x6a1936c8, 0x6ed82b7f,
    0x639b0da6, 0x675a1011, 0x791d4014, 0x7ddc5da3, 0x709f7b7a,
    0x745e66cd, 0x9823b6e0, 0x9ce2ab57, 0x91a18d8e, 0x95609039,
    0x8b27c03c, 0x8fe6dd8b, 0x82a5fb52, 0x8664e6e5, 0xbe2b5b58,
    0xbaea46ef, 0xb7a96036, 0xb3687d81, 0xad2f2d84, 0xa9ee3033,
    0xa4ad16ea, 0xa06c0b5d, 0xd4326d90, 0xd0f37027, 0xddb056fe,
    0xd9714b49, 0xc7361b4c, 0xc3f706fb, 0xceb42022, 0xca753d95,
    0xf23a8028, 0xf6fb9d9f, 0xfbb8bb46, 0xff79a6f1, 0xe13ef6f4,
    0xe5ffeb43, 0xe8bccd9a, 0xec7dd02d, 0x34867077, 0x30476dc0,
    0x3d044b19, 0x39c556ae, 0x278206ab, 0x23431b1c, 0x2e003dc5,
    0x2ac12072, 0x128e9dcf, 0x164f8078, 0x1b0ca6a1, 0x1fcdbb16,
    0x018aeb13, 0x054bf6a4, 0x0808d07d, 0x0cc9cdca, 0x7897ab07,
    0x7c56b6b0, 0x71159069, 0x75d48dde, 0x6b93dddb, 0x6f52c06c,
    0x6211e6b5, 0x66d0fb02, 0x5e9f46bf, 0x5a5e5b08, 0x571d7dd1,
    0x53dc6066, 0x4d9b3063, 0x495a2dd4, 0x44190b0d, 0x40d816ba,
    0xaca5c697, 0xa864db20, 0xa527fdf9, 0xa1e6e04e, 0xbfa1b04b,
    0xbb60adfc, 0xb6238b25, 0xb2e29692, 0x8aad2b2f, 0x8e6c3698,
    0x832f1041, 0x87ee0df6, 0x99a95df3, 0x9d684044, 0x902b669d,
    0x94ea7b2a, 0xe0b41de7, 0xe4750050, 0xe9362689, 0xedf73b3e,
    0xf3b06b3b, 0xf771768c, 0xfa325055, 0xfef34de2, 0xc6bcf05f,
    0xc27dede8, 0xcf3ecb31, 0xcbffd686, 0xd5b88683, 0xd1799b34,
    0xdc3abded, 0xd8fba05a, 0x690ce0ee, 0x6dcdfd59, 0x608edb80,
    0x644fc637, 0x7a089632, 0x7ec98b85, 0x738aad5c, 0x774bb0eb,
    0x4f040d56, 0x4bc510e1, 0x46863638, 0x42472b8f, 0x5c007b8a,
    0x58c1663d, 0x558240e4, 0x51435d53, 0x251d3b9e, 0x21dc2629,
    0x2c9f00f0, 0x285e1d47, 0x36194d42, 0x32d850f5, 0x3f9b762c,
    0x3b5a6b9b, 0x0315d626, 0x07d4cb91, 0x0a97ed48, 0x0e56f0ff,
    0x1011a0fa, 0x14d0bd4d, 0x19939b94, 0x1d528623, 0xf12f560e,
    0xf5ee4bb9, 0xf8ad6d60, 0xfc6c70d7, 0xe22b20d2, 0xe6ea3d65,
    0xeba91bbc, 0xef68060b, 0xd727bbb6, 0xd3e6a601, 0xdea580d8,
    0xda649d6f, 0xc423cd6a, 0xc0e2d0dd, 0xcda1f604, 0xc960ebb3,
    0xbd3e8d7e, 0xb9ff90c9, 0xb4bcb610, 0xb07daba7, 0xae3afba2,
    0xaafbe615, 0xa7b8c0cc, 0xa379dd7b, 0x9b3660c6, 0x9ff77d71,
    0x92b45ba8, 0x9675461f, 0x8832161a, 0x8cf30bad, 0x81b02d74,
    0x857130c3, 0x5d8a9099, 0x594b8d2e, 0x5408abf7, 0x50c9b640,
    0x4e8ee645, 0x4a4ffbf2, 0x470cdd2b, 0x43cdc09c, 0x7b827d21,
    0x7f436096, 0x7200464f, 0x76c15bf8, 0x68860bfd, 0x6c47164a,
    0x61043093, 0x65c52d24, 0x119b4be9, 0x155a565e, 0x18197087,
    0x1cd86d30, 0x029f3d35, 0x065e2082, 0x0b1d065b, 0x0fdc1bec,
    0x3793a651, 0x3352bbe6, 0x3e119d3f, 0x3ad08088, 0x2497d08d,
    0x2056cd3a, 0x2d15ebe3, 0x29d4f654, 0xc5a92679, 0xc1683bce,
    0xcc2b1d17, 0xc8ea00a0, 0xd6ad50a5, 0xd26c4d12, 0xdf2f6bcb,
    0xdbee767c, 0xe3a1cbc1, 0xe760d676, 0xea23f0af, 0xeee2ed18,
    0xf0a5bd1d, 0xf464a0aa, 0xf9278673, 0xfde69bc4, 0x89b8fd09,
    0x8d79e0be, 0x803ac667, 0x84fbdbd0, 0x9abc8bd5, 0x9e7d9662,
    0x933eb0bb, 0x97ffad0c, 0xafb010b1, 0xab710d06, 0xa6322bdf,
    0xa2f33668, 0xbcb4666d, 0xb8757bda, 0xb5365d03, 0xb1f740b4
);
$crc32_table = $crc32_table | % {
    $value = $_
    if ($value -lt 0) {
        $value += 0x100000000
    }
    [uint32]($value -band 0xFFFFFFFF)
}
enum SyncSource {
    U8 = 8
    U16 = 16
    U32 = 32
    U64 = 64
}
class UINT32u {
    [UInt32]   $u32
    [UInt16[]] $u16 = @(0, 0)
    [Byte[]]   $u8  = @(0, 0, 0, 0)

    [void] Sync([SyncSource]$source) {
        switch ($source.value__) {
            8 {
            	$this.u16 = 0..1 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) }
                $this.u32 = [BitConverter]::ToUInt32($this.u8, 0)
                #$this.u16 = [BitConverterHelper]::ToArrayOfType([UINT16],$this.u8)
                #$this.u32 = [BitConverterHelper]::ToArrayOfType([UINT32],$this.u8)[0]
            }
            16 {
                $this.u8 = $this.u16 | % { [BitConverter]::GetBytes($_) } | % {$_} 
                $this.u32 = [BitConverter]::ToUInt32($this.u8, 0)
                #$this.u8 = [BitConverterHelper]::ToByteArray($this.u16)
                #$this.u32 = [BitConverterHelper]::ToArrayOfType([UINT32],$this.u8)[0]
            }
            32 {
                $this.u8 = [BitConverter]::GetBytes($this.u32)
                $this.u16 = 0..1 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) }
                #$this.u8 = [BitConverter]::GetBytes($this.u32)
                #$this.u16 = [BitConverterHelper]::ToArrayOfType([UINT16],$this.u8)
            }
        }
    }
}
class UINT64u {
    [UInt64]   $u64
    [UInt32[]] $u32 = @(0, 0)
    [UInt16[]] $u16 = @(0, 0, 0, 0)
    [Byte[]]   $u8  = @(0, 0, 0, 0, 0, 0, 0, 0)

    [void] Sync([SyncSource]$source) {
        switch ($source.value__) {
            8 {
            	$this.u16 = 0..3 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) }
                $this.u32 = 0..1 | % { [BitConverter]::ToUInt32($this.u8, $_ * 4) }
                $this.u64 = [BitConverter]::ToUInt64($this.u8, 0)
                #$this.u16 = [BitConverterHelper]::ToArrayOfType([UINT16],$this.u8)
                #$this.u32 = [BitConverterHelper]::ToArrayOfType([UINT32],$this.u8)
                #$this.u64 = [BitConverterHelper]::ToArrayOfType([UINT64],$this.u8)[0]
            }
            16 {
            	$this.u8 = $this.u16 | % { [BitConverter]::GetBytes($_) } | % {$_}
                $this.u32 = 0..1 | % { [BitConverter]::ToUInt32($this.u8, $_ * 4) }
                $this.u64 = [BitConverter]::ToUInt64($this.u8, 0)
                #$this.u8 = [BitConverterHelper]::ToByteArray($this.u16)
                #$this.u32 = [BitConverterHelper]::ToArrayOfType([UINT32],$this.u8)
                #$this.u64 = [BitConverterHelper]::ToArrayOfType([UINT64],$this.u8)[0]
            }
            32 {
            	$this.u8 = $this.u32 | % { [BitConverter]::GetBytes($_) } | % {$_}
                $this.u16 = 0..3 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) }
                $this.u64 = [BitConverter]::ToUInt64($this.u8, 0)
                #$this.u8 = [BitConverterHelper]::ToByteArray($this.u32)
                #$this.u16 = [BitConverterHelper]::ToArrayOfType([UINT16],$this.u8)
                #$this.u64 = [BitConverterHelper]::ToArrayOfType([UINT64],$this.u8)[0]
            }
            64 {
                $this.u8 = [BitConverter]::GetBytes($this.u64)
                $this.u16 = 0..3 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) }
                $this.u32 = 0..1 | % { [BitConverter]::ToUInt32($this.u8, $_ * 4) }
                #$this.u8 = [BitConverterHelper]::ToByteArray($this.u64)
                #$this.u16 = [BitConverterHelper]::ToArrayOfType([UINT16],$this.u8)
                #$this.u32 = [BitConverterHelper]::ToArrayOfType([UINT32],$this.u8)
            }
        }
    }
}
class UINT128u {
    [UInt64[]] $u64 = @(0, 0)
    [UInt32[]] $u32 = @(0, 0, 0, 0)
    [UInt16[]] $u16 = @(0, 0, 0, 0, 0, 0, 0, 0)
    [Byte[]]   $u8  = @(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    [void] Sync([SyncSource]$source) {
        switch ($source.value__) {
            8 {
                $this.u16 = 0..7 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) }
                $this.u32 = 0..3 | % { [BitConverter]::ToUInt32($this.u8, $_ * 4) }
                $this.u64 = 0..1 | % { [BitConverter]::ToUInt64($this.u8, $_ * 8) }
                #$this.u16 = [BitConverterHelper]::ToArrayOfType([UINT16],$this.u8)
                #$this.u32 = [BitConverterHelper]::ToArrayOfType([UINT32],$this.u8)
                #$this.u64 = [BitConverterHelper]::ToArrayOfType([UINT64],$this.u8)
            }
            16 {
                $this.u8 = $this.u16 | % { [BitConverter]::GetBytes($_) } | % {$_}
                $this.u32 = 0..3 | % { [BitConverter]::ToUInt32($this.u8, $_ * 4) }
                $this.u64 = 0..1 | % { [BitConverter]::ToUInt64($this.u8, $_ * 8) }
                #$this.u8 = [BitConverterHelper]::ToByteArray($this.u16)
                #$this.u32 = [BitConverterHelper]::ToArrayOfType([UINT32],$this.u8)
                #$this.u64 = [BitConverterHelper]::ToArrayOfType([UINT64],$this.u8)
            }
            32 {
                $this.u8 = $this.u32 | % { [BitConverter]::GetBytes($_) } | % {$_}
                $this.u16 = 0..7 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) }
                $this.u64 = 0..1 | % { [BitConverter]::ToUInt64($this.u8, $_ * 8) }
                #$this.u8 = [BitConverterHelper]::ToByteArray($this.u32)
                #$this.u16 = [BitConverterHelper]::ToArrayOfType([UINT16],$this.u8)
                #$this.u64 = [BitConverterHelper]::ToArrayOfType([UINT64],$this.u8)
            }
            64 {
                $this.u8 = [BitConverter]::GetBytes($this.u64[0]) + [BitConverter]::GetBytes($this.u64[1])
                $this.u16 = 0..7 | % { [BitConverter]::ToUInt16($this.u8, $_ * 2) }
                $this.u32 = 0..3 | % { [BitConverter]::ToUInt32($this.u8, $_ * 4) }
                #$this.u8 = [BitConverterHelper]::ToByteArray($this.u64)
                #$this.u16 = [BitConverterHelper]::ToArrayOfType([UINT16],$this.u8)
                #$this.u32 = [BitConverterHelper]::ToArrayOfType([UINT32],$this.u8)
            }
        }
    }
}
class BitConverterHelper {

    # Convert array of UInt16, Int16, UInt32, Int32, UInt64, or Int64 to byte array
    static [Byte[]] ToByteArray([Object[]] $values) {
        $byteList = New-Object List[Byte]

        foreach ($value in $values) {
            if ($value -is [UInt16]) {
                $byteList.AddRange([BitConverter]::GetBytes([UInt16]$value))
            } elseif ($value -is [Int16]) {
                $byteList.AddRange([BitConverter]::GetBytes([Int16]$value))
            } elseif ($value -is [UInt32]) {
                $byteList.AddRange([BitConverter]::GetBytes([UInt32]$value))
            } elseif ($value -is [Int32]) {
                $byteList.AddRange([BitConverter]::GetBytes([Int32]$value))
            } elseif ($value -is [UInt64]) {
                $byteList.AddRange([BitConverter]::GetBytes([UInt64]$value))
            } elseif ($value -is [Int64]) {
                $byteList.AddRange([BitConverter]::GetBytes([Int64]$value))
            } else {
                throw "Unsupported type: $($value.GetType().FullName)"
            }
        }

        return $byteList.ToArray()
    }

     # Convert byte array to an array of specified types (UInt16, Int16, UInt32, Int32, UInt64, Int64)
    static [Array] ToArrayOfType([Type] $type, [Byte[]] $bytes) {
        # Determine the size of each type in bytes
        $typeName = $type.FullName
        $size = switch ($typeName) {
            "System.UInt16" { 2 }
            "System.Int16"  { 2 }
            "System.UInt32" { 4 }
            "System.Int32"  { 4 }
            "System.UInt64" { 8 }
            "System.Int64"  { 8 }
            default { throw "Unsupported type: $type" }
        }
        
        # Validate byte array length
        if ($bytes.Length % $size -ne 0) {
            throw "Byte array length must be a multiple of $size for conversion to $type."
        }

        # Prepare result list
        $count = [math]::Floor($bytes.Length / $size)
        $result = New-Object 'System.Collections.Generic.List[Object]'

        # Convert bytes to the specified type
        for ($i = 0; $i -lt $count; $i++) {
            $index = $i * $size
            if ($typeName -eq "System.UInt16") {
                $result.Add([BitConverter]::ToUInt16($bytes, $index))
            } elseif ($typeName -eq "System.Int16") {
                $result.Add([BitConverter]::ToInt16($bytes, $index))
            } elseif ($typeName -eq "System.UInt32") {
                $result.Add([BitConverter]::ToUInt32($bytes, $index))
            } elseif ($typeName -eq "System.Int32") {
                $result.Add([BitConverter]::ToInt32($bytes, $index))
            } elseif ($typeName -eq "System.UInt64") {
                $result.Add([BitConverter]::ToUInt64($bytes, $index))
            } elseif ($typeName -eq "System.Int64") {
                $result.Add([BitConverter]::ToInt64($bytes, $index))
            }
        }

        return $result.ToArray()
    }
}

function Hash([UINT128u]$key) {
    $hash = -1
    for ($i = 0; $i -lt 16; $i++) {
        $index = (($hash -shr 24) -bxor $key.u8[$i]) -band 0xff
        $hash  = (($hash -shl 8) -bxor $crc32_table[$index]) -band 0xFFFFFFFF
    }
    return (-bnot $hash) -band 0x3ff
}
function SetHash {
    param (
        [UINT128u]$key3,
        [ref]$key2,
        [ref]$check
    )

    # Copy $key3 to $key2
    $key2.Value = [UINT128u]::new()
    [Array]::Copy($key3.u8, $key2.Value.u8, 16)

    # Compute the hash and set it in $check
    $check.Value.u8 = [BitConverter]::GetBytes([UINT32](Hash($key2.Value)))

    # Update $key2 with values from $check
    $key2.Value.u8[12] = [Byte]($key2.Value.u8[12] -bor ($check.Value.u8[0] -shl 7))
    $key2.Value.u8[13] = [Byte](($check.Value.u8[0] -shr 1) -bor ($check.Value.u8[1] -shl 7))
    $key2.Value.u8[14] = [Byte]($key2.Value.u8[14] -bor (($check.Value.u8[1] -shr 1) -band 0x1))
}
function SetInfo {
    param (
        [UINT32u]$groupid,
        [UINT32u]$keyid,
        [UINT64u]$secret,
        [ref]$key3
    )

    # Set bytes using groupid
    0..1 | % { $key3.Value.u8[$_] = [BYTE]$groupid.u8[$_] }
    $key3.Value.u8[2] = [BYTE]($key3.Value.u8[2] -bor ($groupid.u8[2] -band 0x0F))

    # Set bytes using keyid
    $key3.Value.u8[2] = [BYTE]($key3.Value.u8[2] -bor ($keyid.u8[0] -shl 4))
    3..5 | % { $key3.Value.u8[$_] = [BYTE](($keyid.u8[$_ - 3 + 1] -shl 4) -bor ($keyid.u8[$_ - 3] -shr 4) -band 0xFF) }
    $key3.Value.u8[6] = [BYTE]($key3.Value.u8[6] -bor (($keyid.u8[3] -shr 4) -band 0x03))

    # Set bytes using secret
    $key3.Value.u8[6] = [BYTE]($key3.Value.u8[6] -bor ($secret.u8[0] -shl 2))
    7..11 | % { $key3.Value.u8[$_] = [BYTE](($secret.u8[$_ - 7 + 1] -shl 2) -bor ($secret.u8[$_ - 7] -shr 6)) }
    $key3.Value.u8[12] = [BYTE](($key3.Value.u8[12] -bor (($secret.u8[6] -shl 2) -bor ($secret.u8[5] -shr 6))) -band 0x7F)
}
function Encode {
    param (
        [UINT128u]$key2,
        [ref]$key1
    )
    $data = 0..3 | % { [BitConverter]::ToUInt32($key2.u8, $_ * 4) }
    for ($i = 25; $i -gt 0; $i--) {
        for ($j = 3; $j -ge 0; $j--) {
            $tmp = if ($j -eq 3) { [UInt64]$data[$j] } else { ([UInt64]$last -shl 32) -bor [UInt64]$data[$j] }
            $data[$j], $last = [math]::Floor($tmp / 24), [UInt32]($tmp % 24)
        }
        $key1.Value[$i - 1] = [byte]$last }
}
function UnconvertChars([byte[]]$key1, [ref]$key0) {
    $n = $key1[0]
    $n += [math]::Floor($n / 5)

    $j = 1
    for ($i = 0; $i -lt 29; $i++) {
        if ($i -eq $n) {
            $key0.Value[$i] = 'N'
        }
        elseif ($i -eq 5 -or $i -eq 11 -or $i -eq 17 -or $i -eq 23) {
            $key0.Value[$i] = '-'
        }
        else {
            switch ($key1[$j++]) {
                0x00 { $key0.Value[$i] = 'B' }
                0x01 { $key0.Value[$i] = 'C' }
                0x02 { $key0.Value[$i] = 'D' }
                0x03 { $key0.Value[$i] = 'F' }
                0x04 { $key0.Value[$i] = 'G' }
                0x05 { $key0.Value[$i] = 'H' }
                0x06 { $key0.Value[$i] = 'J' }
                0x07 { $key0.Value[$i] = 'K' }
                0x08 { $key0.Value[$i] = 'M' }
                0x09 { $key0.Value[$i] = 'P' }
                0x0A { $key0.Value[$i] = 'Q' }
                0x0B { $key0.Value[$i] = 'R' }
                0x0C { $key0.Value[$i] = 'T' }
                0x0D { $key0.Value[$i] = 'V' }
                0x0E { $key0.Value[$i] = 'W' }
                0x0F { $key0.Value[$i] = 'X' }
                0x10 { $key0.Value[$i] = 'Y' }
                0x11 { $key0.Value[$i] = '2' }
                0x12 { $key0.Value[$i] = '3' }
                0x13 { $key0.Value[$i] = '4' }
                0x14 { $key0.Value[$i] = '6' }
                0x15 { $key0.Value[$i] = '7' }
                0x16 { $key0.Value[$i] = '8' }
                0x17 { $key0.Value[$i] = '9' }
                default { $key0.Value[$i] = '?' }
            }
        }
    }
}
function KeyEncode {
    param (
        # 'sgroupid' must be either a hexadecimal (e.g., 0xABC123) or an integer (e.g., 123456)
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^(0x[0-9A-Fa-f]+|\d+)$')]
        [string]$sgroupid,

        [UInt32]$skeyid,
        [UInt64]$sunk
    )
   
    $sgroupid_f = if ($sgroupid -match '^0x') { [Convert]::ToUInt32($sgroupid.Substring(2), 16) } else { [UInt32]$sgroupid }

    if ($sgroupid_f -gt 0xffffff) {
        Write-Host "GroupId must be in the range 0-ffffff"
        return -1
    }
    if ($skeyid -gt 0x3fffffff) {
        Write-Host "KeyId must be in the range 0-3fffffff"
        return -1
    }
    if ($sunk -gt 0x1fffffffffffff) {
        Write-Host "Secret must be in the range 0-1fffffffffffff"
        return -1
    }

    $keyid     = [UINT32u]::new()
    $secret     = [UINT64u]::new()
    $groupid     = [UINT32u]::new()

    $secret.u8  = [BitConverter]::GetBytes($sunk)
    $keyid.u8  = [BitConverter]::GetBytes($skeyid)
    $groupid.u8  = [BitConverter]::GetBytes($sgroupid_f)

    $key3 = [UINT128u]::new()
    SetInfo -groupid $groupid -keyid $keyid -secret $secret -key3 ([ref]$key3)

    $key2 = [UINT128u]::new()
    $check = [UINT32u]::new()
    SetHash -key3 $key3 -key2 ([ref]$key2) -check ([ref]$check)

    $key1 = New-Object Byte[] 25
    Encode -key2 $key2 -key1 ([ref]$key1)

    $key0 = New-Object Char[] 29
    UnconvertChars -key1 $key1 -key0 ([ref]$key0)
   
    return (-join $key0)
}

function Get-Info {
    param (
        [Parameter(Mandatory=$true)]
        [UINT128u]$key3,

        [Parameter(Mandatory=$true)]
        [ref]$groupid,

        [Parameter(Mandatory=$true)]
        [ref]$keyid,

        [Parameter(Mandatory=$true)]
        [ref]$secret
    )

    $groupid.Value.u32 = 0
    $keyid.Value.u32 = 0
    $secret.Value.u64 = 0

    $groupid.Value.u8[0] = $key3.u8[0]
    $groupid.Value.u8[1] = $key3.u8[1]
    $groupid.Value.u8[2] = $key3.u8[2] -band 0x0f

    $keyid.Value.u8[0] = ($key3.u8[2] -shr 4) -bor ($key3.u8[3] -shl 4)
    $keyid.Value.u8[1] = ($key3.u8[3] -shr 4) -bor ($key3.u8[4] -shl 4)
    $keyid.Value.u8[2] = ($key3.u8[4] -shr 4) -bor ($key3.u8[5] -shl 4)
    $keyid.Value.u8[3] = (($key3.u8[5] -shr 4) -bor ($key3.u8[6] -shl 4)) -band 0x3f

    $secret.Value.u8[0] = ($key3.u8[6] -shr 2) -bor ($key3.u8[7] -shl 6)
    $secret.Value.u8[1] = ($key3.u8[7] -shr 2) -bor ($key3.u8[8] -shl 6)
    $secret.Value.u8[2] = ($key3.u8[8] -shr 2) -bor ($key3.u8[9] -shl 6)
    $secret.Value.u8[3] = ($key3.u8[9] -shr 2) -bor ($key3.u8[10] -shl 6)
    $secret.Value.u8[4] = ($key3.u8[10] -shr 2) -bor ($key3.u8[11] -shl 6)
    $secret.Value.u8[5] = ($key3.u8[11] -shr 2) -bor ($key3.u8[12] -shl 6)
    $secret.Value.u8[6] = ($key3.u8[12] -shr 2) -band 0x1f

    $groupid.Value.Sync([SyncSource]::U8)
    $keyid.Value.Sync([SyncSource]::U8)
    $secret.Value.Sync([SyncSource]::U8)

    return $true
}
function Check-Hash {
    param (
        [Parameter(Mandatory=$true)]
        [UINT128u]$key2,

        [Parameter(Mandatory=$true)]
        [ref]$key3,

        [Parameter(Mandatory=$true)]
        [ref]$check
    )

    # Reset the check value
    $check.Value.u32 = 0

    # Copy key2 to key3
    [Array]::Copy($key2.u8, $key3.Value.u8, $key2.u8.Length)

    # Modify key3 bytes
    $key3.Value.u8[12] = $key3.Value.u8[12] -band 0x7f
    $key3.Value.u8[13] = 0
    $key3.Value.u8[14] = $key3.Value.u8[14] -band 0xfe

    # Compute check bytes
    $check.Value.u8[0] = ($key2.u8[13] -shl 1) -bor ($key2.u8[12] -shr 7)
    $check.Value.u8[1] = (($key2.u8[14] -shl 1) -bor ($key2.u8[13] -shr 7)) -band 3

    # Compute hash
    $hash = Hash($key3.Value)
    $key3.Value.Sync([SyncSource]::U8)
    $check.Value.Sync([SyncSource]::U8)

    # Compare hash with check value
    if ($hash -ne $check.Value.u32) {
        Write-Output "Invalid key. The hash is incorrect."
        return $false
    }

    return $true
}
function ConvertTo-UInt32 {
    param (
        [Parameter(Mandatory = $true)]
        [BigInteger]$value
    )

    # Convert BigInteger to uint32 with proper masking
    return [uint32]($value % [BigInteger]0x100000000)
}
function Decode {
    param (
        [Parameter(Mandatory = $true)]
        [byte[]]$key1,

        [ref]$key2
    )

    # Initialize key2
    $key2.Value.u64[0] = 0
    $key2.Value.u64[1] = 0

    for ($ikey = 0; $ikey -lt 25; $ikey++) {
        $res = [BigInteger]24 * [BigInteger]$key2.Value.u32[0] + $key1[$ikey]
        $key2.Value.u32[0] = ConvertTo-UInt32 -value $res
        $res = [BigInteger]($res / [BigInteger]0x100000000)  # Handle overflow

        for ($i = 1; $i -lt 4; $i++) {
            $res += [BigInteger]24 * [BigInteger]$key2.Value.u32[$i]
            $key2.Value.u32[$i] = ConvertTo-UInt32 -value $res
            $res = [BigInteger]($res / [BigInteger]0x100000000)  # Handle overflow
        }
    }

    $key2.Value.Sync([SyncSource]::U32)

    return $true
}
function ConvertChars {
    param (
        [Parameter(Mandatory=$true)]
        [char[]]$key0,

        [ref]$key1
    )

    if ($key0.Length -ne 29) {
        Write-Output "Your key must be 29 characters long."
        return $false
    }

    if ($key0[5] -ne '-' -or $key0[11] -ne '-' -or $key0[17] -ne '-' -or $key0[23] -ne '-') {
        Write-Output "Incorrect hyphens."
        return $false
    }

    if ($key0[28] -eq 'N') {
        Write-Output "The last character must not be an N."
        return $false
    }

    $n = $false
    $j = 1
    $i = 0

    while ($j -lt 25 -and $i -lt $key0.Length) {
        switch ($key0[$i++]) {
            'N' {
                if ($n) {
                    throw "There may only be one N in a key."
                    return $false
                }
                $n = $true
                $key1.Value[0] = $j - 1
            }
            'B' { if ($j -lt 25) { $key1.Value[$j++] = 0x00 } }
            'C' { if ($j -lt 25) { $key1.Value[$j++] = 0x01 } }
            'D' { if ($j -lt 25) { $key1.Value[$j++] = 0x02 } }
            'F' { if ($j -lt 25) { $key1.Value[$j++] = 0x03 } }
            'G' { if ($j -lt 25) { $key1.Value[$j++] = 0x04 } }
            'H' { if ($j -lt 25) { $key1.Value[$j++] = 0x05 } }
            'J' { if ($j -lt 25) { $key1.Value[$j++] = 0x06 } }
            'K' { if ($j -lt 25) { $key1.Value[$j++] = 0x07 } }
            'M' { if ($j -lt 25) { $key1.Value[$j++] = 0x08 } }
            'P' { if ($j -lt 25) { $key1.Value[$j++] = 0x09 } }
            'Q' { if ($j -lt 25) { $key1.Value[$j++] = 0x0a } }
            'R' { if ($j -lt 25) { $key1.Value[$j++] = 0x0b } }
            'T' { if ($j -lt 25) { $key1.Value[$j++] = 0x0c } }
            'V' { if ($j -lt 25) { $key1.Value[$j++] = 0x0d } }
            'W' { if ($j -lt 25) { $key1.Value[$j++] = 0x0e } }
            'X' { if ($j -lt 25) { $key1.Value[$j++] = 0x0f } }
            'Y' { if ($j -lt 25) { $key1.Value[$j++] = 0x10 } }
            '2' { if ($j -lt 25) { $key1.Value[$j++] = 0x11 } }
            '3' { if ($j -lt 25) { $key1.Value[$j++] = 0x12 } }
            '4' { if ($j -lt 25) { $key1.Value[$j++] = 0x13 } }
            '6' { if ($j -lt 25) { $key1.Value[$j++] = 0x14 } }
            '7' { if ($j -lt 25) { $key1.Value[$j++] = 0x15 } }
            '8' { if ($j -lt 25) { $key1.Value[$j++] = 0x16 } }
            '9' { if ($j -lt 25) { $key1.Value[$j++] = 0x17 } }
            '-' { }
            default {
                throw "Invalid character in key."
                return $false
            }
        }
    }

    if (-not $n) {
        throw "The character N must be in the product key."
        return $false
    }

    return $true
}
function KeyDecode {
    param (
        [Parameter(Mandatory=$true)]
        [string]$key0
    )

    # Convert the string to a character array
    $key0Chars = $key0.ToCharArray()

    # Initialize $key1 array
    $key1 = New-Object byte[] 25
    
    # Convert characters to bytes
    if (-not (ConvertChars -key0 $key0Chars -key1 ([ref]$key1))) {
        return -1
    }
    
    # Initialize UINT128u structures
    $key2 = [UINT128u]::new()
    $key3 = [UINT128u]::new()
    $hash = [UINT32u]::new()
    
    # Decode the key
    if (-not (Decode -key1 $key1 -key2 ([ref]$key2))) {
        return -1
    }

    # Check the hash
    if (-not (Check-Hash -key2 $key2 -key3 ([ref]$key3) -check ([ref]$hash))) {
        return -1
    }
    
    # Initialize UINT32u and UINT64u structures
    $groupid = [UINT32u]::new()
    $keyid = [UINT32u]::new()
    $secret = [UINT64u]::new()
    
    # Get information
    if (-not (Get-Info -key3 $key3 -groupid ([ref]$groupid) -keyid ([ref]$keyid) -secret ([ref]$secret))) {
        return -1
    }
    
    return @(
    @{ Property = "KeyId";   Value = $keyid.u32 },
    @{ Property = "Hash";    Value = $hash.u32 },
    @{ Property = "GroupId"; Value = $groupid.u32 },
    @{ Property = "Secret";  Value = $secret.u64}
    )
}

# Adaption of "Licensing Stuff" from =awuctl=, "KeyInfo" from Bob65536
# https://github.com/awuctl/licensing-stuff/blob/main/keycutter.py
# https://forums.mydigitallife.net/threads/how-get-oem-key-system-key.87962/#post-1825092
# https://forums.mydigitallife.net/threads/we8industry-pro-wes8-activation.45312/#post-771802
# https://web.archive.org/web/20121026081005/http://forums.mydigitallife.info/threads/37590-Windows-8-Product-Key-Decoding

function Encode-Key {
    param(
        [Parameter(Mandatory=$true)]
        [UInt64]$group,

        [Parameter(Mandatory=$false)]
        [UInt64]$serial = 0,

        [Parameter(Mandatory=$false)]
        [UInt64]$security = 0,

        [Parameter(Mandatory=$false)]
        [int]$upgrade = 0,

        [Parameter(Mandatory=$false)]
        [int]$extra = 0,

        [Parameter(Mandatory=$false)]
        [int]$checksum = -1
    )

    # Alphabet used for encoding base24 digits (excluding 'N')
    $ALPHABET = 'BCDFGHJKMPQRTVWXY2346789'.ToCharArray()

    # Validate input ranges (equivalent to Python BOUNDS)
    if ($group -gt 0xFFFFF) {
        throw "Group value ($group) out of bounds (max 0xFFFFF)"
    }
    if ($serial -gt 0x3FFFFFFF) {
        throw "Serial value ($serial) out of bounds (max 0x3FFFFFFF)"
    }
    if ($security -gt 0x1FFFFFFFFFFFFF) {
        throw "Security value ($security) out of bounds (max 0x1FFFFFFFFFFFFF)"
    }
    if ($checksum -ne -1 -and $checksum -gt 0x3FF) {
        throw "Checksum value ($checksum) out of bounds (max 0x3FF)"
    }
    if ($upgrade -notin @(0, 1)) {
        throw "Upgrade value must be either 0 or 1"
    }
    if ($extra -notin @(0, 1)) {
        throw "Extra value must be either 0 or 1"
    }

    function Get-Checksum {
        param([byte[]]$data)

        [uint32]$crc = [uint32]::MaxValue
        foreach ($b in $data) {
            $index = (($crc -shr 24) -bxor $b) -band 0xFF
            $crc = ((($crc -shl 8) -bxor $crc32_table[$index]) -band 0xFFFFFFFF)
        }
        $crc = (-bnot $crc) -band 0xFFFFFFFF
        return $crc -band 0x3FF  # 10 bits checksum mask
    }
    function Encode-Base24 {
        param([System.Numerics.BigInteger]$num)
        $digits = New-Object byte[] 25
        for ($i = 24; $i -ge 0; $i--) {
            $digits[$i] = [byte]($num % 24)
            $num = [System.Numerics.BigInteger]::Divide($num, 24)
        }
        return $digits
    }
    function Format-5x5 {
        param([byte[]]$digits)

        # Calculate position for inserting 'N'
        $pos = $digits[0] #+ [math]::Floor($digits[0] / 5)

        $ALPHABET = @('B','C','D','F','G','H','J','K','M','P','Q','R','T','V','W','X','Y','2','3','4','6','7','8','9')

        $chars = @()
        for ($i = 1; $i -lt 25; $i++) {
            $chars += $ALPHABET[$digits[$i]]
        }

        # Insert 'N' at the calculated position
        if ($pos -le 0) {
            $chars = @('N') + $chars
        }
        elseif ($pos -ge $chars.Count) {
            $chars += 'N'
        }
        else {
            $chars = $chars[0..($pos - 1)] + 'N' + $chars[$pos..($chars.Count - 1)]
        }

        # Insert dashes every 5 characters to form groups
        return -join (
            ($chars[0..4] -join ''), '-',
            ($chars[5..9] -join ''), '-',
            ($chars[10..14] -join ''), '-',
            ($chars[15..19] -join ''), '-',
            ($chars[20..24] -join '')
        )
    }

    # Validate input ranges to avoid overflow
    if ($group -gt 0xFFFFF -or $serial -gt 0x3FFFFFFF -or $security -gt 0x1FFFFFFFFFFFFF) {
        throw "Field values out of range"
    }

    # Compose the key bits using BigInteger (64+ bit shifts)
    $key = [System.Numerics.BigInteger]::Zero
    $key = $key -bor ([System.Numerics.BigInteger]$extra -shl 114)
    $key = $key -bor ([System.Numerics.BigInteger]$upgrade -shl 113)
    $key = $key -bor ([System.Numerics.BigInteger]$security -shl 50)
    $key = $key -bor ([System.Numerics.BigInteger]$serial -shl 20)
    $key = $key -bor ([System.Numerics.BigInteger]$group)

    # Calculate checksum if not provided
    if ($checksum -lt 0) {
        $keyBytes = $key.ToByteArray()

        # Remove extra sign byte if present (BigInteger uses signed representation)
        if ($keyBytes.Length -gt 16) {
            if ($keyBytes[-1] -eq 0x00) {
                # Remove the last byte (sign byte)
                $keyBytes = $keyBytes[0..($keyBytes.Length - 2)]
            }
            else {
                throw "Key bytes length greater than 16 with unexpected data"
            }
        }

        # Pad with trailing zeros to get exactly 16 bytes (little-endian)
        if ($keyBytes.Length -lt 16) {
            $keyBytes += ,0 * (16 - $keyBytes.Length)
        }

        # No reversal needed ? checksum function expects little-endian bytes
        # [array]::Reverse($keyBytes)  # <-- removed

        $checksum = Get-Checksum $keyBytes
    }

    # Insert checksum bits at bit position 103
    $key = $key -bor ([System.Numerics.BigInteger]$checksum -shl 103)

    # Encode the final key to base24 digits
    $base24 = Encode-Base24 $key

    # Format into the 5x5 grouped string with 'N' insertion and dashes
    return Format-5x5 $base24
}
function Decode-Key {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )

    $ALPHABET = 'BCDFGHJKMPQRTVWXY2346789'.ToCharArray()

    # Remove hyphens and uppercase
    $k = $Key.Replace('-','').ToUpper()

    # Find 'N' position
    $ni = $k.IndexOf('N')
    if ($ni -lt 0) { throw "Invalid key (missing 'N')." }

    # Start digits array with position of 'N'
    $digits = @($ni)

    # Remove 'N' from key
    $rest = $k.Replace('N','')

    # Convert each character to index in alphabet
    foreach ($ch in $rest.ToCharArray()) {
        $idx = $Alphabet.IndexOf($ch)
        if ($idx -lt 0) { throw "Invalid character '$ch' in key." }
        $digits += $idx
    }

    [bigint]$value = 0
    foreach ($d in $digits) {
        $value = ($value * 24) + $d
    }

    # Extract bit fields
    $group    = [int]($value -band 0xfffff)                          # 20 bits decimal
    $serial   = [int](($value -shr 20) -band 0x3fffffff)             # 30 bits decimal
    $security = [bigint](($value -shr 50) -band 0x1fffffffffffff)    # 53 bits decimal (bigint)
    $checksum = [int](($value -shr 103) -band 0x3ff)                 # 10 bits decimal
    $upgrade  = [int](($value -shr 113) -band 0x1)                   # 1 bit decimal
    $extra    = [int](($value -shr 114) -band 0x1)                   # 1 bit decimal

    return [pscustomobject]@{
        Key      = $Key
        Integer  = $value
        Group    = $group
        Serial   = $serial
        Security = $security
        Checksum = $checksum
        Upgrade  = $upgrade
        Extra    = $extra
    }
}

<#
Generates product keys using:

1. Template mode:
   - Use -template (e.g. "NBBBB-BBBBB-") to find matching keys.
   - Stops when keys no longer match the given prefix.

2. Brute-force mode:
   - If no -template is given, generates up to -MaxTries.
   - Collects keys starting with "NBBBB".
   - If no valid keys are found, automatically retries up to 5 times,
     each time increasing the MaxTries limit by 5000.
     Stops once at least one key is found or the retry limit is reached.

Based on abbodi1406's logic:
https://forums.mydigitallife.net/threads/88595/page-6#post-1882091

Examples:
    Brute-force mode
    List-Keys -RefGroupId 2048
    List-Keys -RefGroupId 2048 -OffsetLimit 200000
    List-Keys -RefGroupId 2048 -StartAtOffset 120000 -KeysLimit 2
    List-Keys -RefGroupId 2048 -StartAtOffset 120000 -OffsetLimit 20000

    Template mode
    List-Keys -RefGroupId 2077 -template JDHD7-DHN6R-JDHD7
    List-Keys -RefGroupId 2048 -template NBBBB-BBBBB-BBBBB -KeysLimit 2
    List-Keys -RefGroupId 2048 -template NBBBB-BBBBB-BBBBB -OffsetLimit 20000
#>
function List-Keys {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript( { $_ -gt 0 } )]
        [int32]$RefGroupId,

        [Parameter(Mandatory=$false)]
        [string]$Template,

        [Parameter(Mandatory=$false)]
        [ValidateScript( { $_ -gt 0 } )]
        [int32]$OffsetLimit = 10000,

        [Parameter(Mandatory=$false)]
        [ValidateScript( { $_ -ge 0 } )]
        [int32]$KeysLimit = 0,

        [Parameter(Mandatory=$false)]
        [ValidateScript( { $_ -ge 0 } )]
        [int32]$StartAtOffset = 0
    )

    if ($template) {
        if ($template.Length -gt 21) {
            throw "Template too long"
        }        
        $paddingTemplate = 'NBBBB-BBBBB-BBBBB-BBBBB-BBBBB'

        # Pad the template to full length with padding string starting from template length
        $paddedTemplate = $template + $paddingTemplate.Substring($template.Length)

        # Decode the padded template into components
        $templateKey = Decode-Key -Key $paddedTemplate
        $serialIter = $templateKey.Serial
        $serialEdgeOffset = $serialIter + $OffsetLimit

    } 
    if (-not $template) {
        $serialIter = $StartAtOffset
    }

    # Initialize variables
    $keyArray = @()
    $attemptCount = 0

    while ($true) {
        if ($template) {   
            # ----- > Begin
            if ($serialIter -ge $serialEdgeOffset) {
                return $keyArray
            }
            $key = Encode-Key -group $RefGroupId -serial $serialIter -security $templateKey.Security -upgrade $templateKey.Upgrade -extra $templateKey.Extra
            $decodedKey = Decode-Key -Key $key
            if ($decodedKey.Checksum -ne $templateKey.Checksum) {
                $serialIter++
                continue
            }
            if (($key.Substring(0, $template.Length) -ne $template)) {
                break
            }
            # ----- > End
        }

        if (-not $template) {
            # ----- > Begin
            if ($serialIter -ge ($OffsetLimit+$StartAtOffset)) {
                if ($keyArray.Count -gt 0) {
                    return $keyArray
                }
                elseif ($attemptCount -lt 5) {
                    $OffsetLimit += 5000
                    $attemptCount++
                    continue 
                } else {
                    return $keyArray
                }
            }
            $key = Encode-Key -group $RefGroupId -serial $serialIter -security 0
            if ($key -notmatch "NBBBB") {
                $serialIter++
                continue 
            }
            # ----- > End
        }

        $keyArray += $key
        Write-Warning "StartAtOffset: $serialIter, Key: $key"

        # Check if MaxKeys is set and if we've reached the limit
        if ($KeysLimit -gt 0 -and $keyArray.Count -ge $KeysLimit) {
            return $keyArray
        }

        $serialIter++
    }

    # Just in case.
    # Should not arrived here.
    return $keyArray
}
#endregion
#region "KMS"
# define $Global's
$Global:LocalKms = $false
$Global:ConvertedMode = $true
$Global:Windows_7_Or_Earlier = $false
$Global:SupportedBuildYear = @('2019', '2021', '2024')
$Global:IP_ADDRESS = "192.168.$(Get-Random -Minimum 1 -Maximum 256).$(Get-Random -Minimum 1 -Maximum 256)"

# define Csv Data
$Global:Windows_Keys_List = @'
ID, KEY
00091344-1ea4-4f37-b789-01750ba6988c,W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9
01ef176b-3e0d-422a-b4f8-4ea880035e8f,4DWFP-JF3DJ-B7DTH-78FJB-PDRHK
034d3cbb-5d4b-4245-b3f8-f84571314078,WVDHN-86M7X-466P6-VHXV7-YY726
096ce63d-4fac-48a9-82a9-61ae9e800e5f,789NJ-TQK6T-6XTH8-J39CJ-J8D3P
0ab82d54-47f4-4acb-818c-cc5bf0ecb649,NMMPB-38DD4-R2823-62W8D-VXKJB
0df4f814-3f57-4b8b-9a9d-fddadcd69fac,NBTWJ-3DR69-3C4V8-C26MC-GQ9M6
10018baf-ce21-4060-80bd-47fe74ed4dab,RYXVT-BNQG7-VD29F-DBMRY-HT73M
113e705c-fa49-48a4-beea-7dd879b46b14,TT4HM-HN7YT-62K67-RGRQJ-JFFXW
18db1848-12e0-4167-b9d7-da7fcda507db,NKB3R-R2F8T-3XCDP-7Q2KW-XWYQ2
197390a0-65f6-4a95-bdc4-55d58a3b0253,8N2M2-HWPGY-7PGT9-HGDD8-GVGGY
1cb6d605-11b3-4e14-bb30-da91c8e3983a,YDRBP-3D83W-TY26F-D46B2-XCKRJ
21c56779-b449-4d20-adfc-eece0e1ad74b,CB7KF-BWN84-R7R2Y-793K2-8XDDG
21db6ba4-9a7b-4a14-9e29-64a60c59301d,KNC87-3J2TX-XB4WP-VCPJV-M4FWM
2401e3d0-c50a-4b58-87b2-7e794b7d2607,W7VD6-7JFBR-RX26B-YKQ3Y-6FFFJ
2b5a1b0f-a5ab-4c54-ac2f-a6d94824a283,JCKRF-N37P4-C2D82-9YXRT-4M63B
2c682dc2-8b68-4f63-a165-ae291d4cf138,HMBQG-8H2RH-C77VX-27R82-VMQBT
2d5a5a60-3040-48bf-beb0-fcd770c20ce0,DCPHK-NFMTC-H88MJ-PFHPY-QJ4BJ
2de67392-b7a7-462a-b1ca-108dd189f588,W269N-WFGWX-YVC9B-4J6C9-T83GX
32d2fab3-e4a8-42c2-923b-4bf4fd13e6ee,M7XTQ-FN8P6-TTKYV-9D4CC-J462D
34e1ae55-27f8-4950-8877-7a03be5fb181,WMDGN-G9PQG-XVVXX-R3X43-63DFG
3c102355-d027-42c6-ad23-2e7ef8a02585,2WH4N-8QGBV-H22JP-CT43Q-MDWWJ
3dbf341b-5f6c-4fa7-b936-699dce9e263f,VP34G-4NPPG-79JTQ-864T4-R3MQX
3f1afc82-f8ac-4f6c-8005-1d233e606eee,6TP4R-GNPTD-KYYHQ-7B7DP-J447Y
43d9af6e-5e86-4be8-a797-d072a046896c,K9FYF-G6NCK-73M32-XMVPY-F9DRR
458e1bec-837a-45f6-b9d5-925ed5d299de,32JNW-9KQ84-P47T8-D8GGY-CWCK7
46bbed08-9c7b-48fc-a614-95250573f4ea,C29WB-22CC8-VJ326-GHFJW-H9DH4
4b1571d3-bafb-4b40-8087-a961be2caf65,9FNHH-K3HBT-3W4TD-6383H-6XYWF
4f3d1606-3fea-4c01-be3c-8d671c401e3b,YFKBB-PQJJV-G996G-VWGXY-2V3X8
5300b18c-2e33-4dc2-8291-47ffcec746dd,YVWGF-BXNMC-HTQYQ-CPQ99-66QFC
54a09a0d-d57b-4c10-8b69-a842d6590ad5,MRPKT-YTG23-K7D7T-X2JMM-QY7MG
58e97c99-f377-4ef1-81d5-4ad5522b5fd8,TX9XD-98N7V-6WMQ6-BX7FG-H8Q99
59eb965c-9150-42b7-a0ec-22151b9897c5,KBN8V-HFGQ4-MGXVD-347P6-PDQGT
59eb965c-9150-42b7-a0ec-22151b9897c5,KBN8V-HFGQ4-MGXVD-347P6-PDQGT
5a041529-fef8-4d07-b06f-b59b573b32d2,W82YF-2Q76Y-63HXB-FGJG9-GF7QX
61c5ef22-f14f-4553-a824-c4b31e84b100,PTXN8-JFHJM-4WC78-MPCBR-9W4KR
620e2b3d-09e7-42fd-802a-17a13652fe7a,489J6-VHDMP-X63PK-3K798-CPX3Y
68531fb9-5511-4989-97be-d11a0f55633f,YC6KT-GKW9T-YTKYR-T4X34-R7VHC
68b6e220-cf09-466b-92d3-45cd964b9509,7M67G-PC374-GR742-YH8V4-TCBY3
7103a333-b8c8-49cc-93ce-d37c09687f92,92NFX-8DJQP-P6BBQ-THF9C-7CG2H
73111121-5638-40f6-bc11-f1d7b0d64300,NPPR9-FWDCX-D2C8J-H872K-2YT43
73e3957c-fc0c-400d-9184-5f7b6f2eb409,N2KJX-J94YW-TQVFB-DG9YT-724CC
7476d79f-8e48-49b4-ab63-4d0b813a16e4,HMCNV-VVBFX-7HMBH-CTY9B-B4FXY
7482e61b-c589-4b7f-8ecc-46d455ac3b87,74YFP-3QFB3-KQT8W-PMXWJ-7M648
78558a64-dc19-43fe-a0d0-8075b2a370a3,7B9N3-D94CG-YTVHR-QBPX3-RJP64
7afb1156-2c1d-40fc-b260-aab7442b62fe,RCTX3-KWVHP-BR6TB-RB6DM-6X7HP
7b4433f4-b1e7-4788-895a-c45378d38253,QN4C6-GBJD2-FB422-GHWJK-GJG2R
7b51a46c-0c04-4e8f-9af4-8496cca90d5e,WNMTR-4C88C-JK8YV-HQ7T2-76DF9
7b9e1751-a8da-4f75-9560-5fadfe3d8e38,3KHY7-WNT83-DGQKR-F7HPR-844BM
7d5486c7-e120-4771-b7f1-7b56c6d3170c,HM7DN-YVMH3-46JC3-XYTG7-CYQJJ
81671aaf-79d1-4eb1-b004-8cbbe173afea,MHF9N-XY6XB-WVXMC-BTDCT-MKKG7
8198490a-add0-47b2-b3ba-316b12d647b4,39BXF-X8Q23-P2WWT-38T2F-G3FPG
82bbc092-bc50-4e16-8e18-b74fc486aec3,NRG8B-VKK3Q-CXVCJ-9G2XF-6Q84J
87b838b7-41b6-4590-8318-5797951d8529,2F77B-TNFGY-69QQF-B8YKP-D69TJ
8860fcd4-a77b-4a20-9045-a150ff11d609,2WN2H-YGCQR-KFX6K-CD6TF-84YXQ
8a26851c-1c7e-48d3-a687-fbca9b9ac16b,GT63C-RJFQ3-4GMB6-BRFB9-CB83V
8c1c5410-9f39-4805-8c9d-63a07706358f,WC2BQ-8NRM3-FDDYY-2BFGV-KHKQY
8c8f0ad3-9a43-4e05-b840-93b8d1475cbc,6N379-GGTMK-23C6M-XVVTC-CKFRQ
8de8eb62-bbe0-40ac-ac17-f75595071ea3,GRFBW-QNDC4-6QBHG-CCK3B-2PR88
90c362e5-0da1-4bfd-b53b-b87d309ade43,6NMRW-2C8FM-D24W7-TQWMY-CWH2D
95fd1c83-7df5-494a-be8b-1300e1c9d1cd,XNH6W-2V9GX-RGJ4K-Y8X6F-QGJ2G
9bd77860-9b31-4b7b-96ad-2564017315bf,VDYBN-27WPP-V4HQT-9VMD4-VMK7H
9d5584a2-2d85-419a-982c-a00888bb9ddf,4K36P-JN4VD-GDC6V-KDT89-DYFKP
9f776d83-7156-45b2-8a5c-359b9c9f22a3,QFFDN-GRT3P-VKWWX-X7T3R-8B639
a00018a3-f20f-4632-bf7c-8daa5351c914,GNBB8-YVD74-QJHX6-27H4K-8QHDG
a78b8bd9-8017-4df5-b86a-09f756affa7c,6TPJF-RBVHG-WBW2R-86QPH-6RTM4
a80b5abf-76ad-428b-b05d-a47d2dffeebf,MH37W-N47XK-V7XM9-C7227-GCQG9
a9107544-f4a0-4053-a96a-1479abdef912,PVMJN-6DFY6-9CCP6-7BKTT-D3WVR
a98bcd6d-5343-4603-8afe-5908e4611112,NG4HW-VH26C-733KW-K6F98-J8CK4
a99cc1f0-7719-4306-9645-294102fbff95,FDNH6-VW9RW-BXPJ7-4XTYG-239TB
aa6dd3aa-c2b4-40e2-a544-a6bbb3f5c395,73KQT-CD9G6-K7TQG-66MRP-CQ22C
ad2542d4-9154-4c6d-8a44-30f11ee96989,TM24T-X9RMF-VWXK6-X8JC9-BFGM2
ae2ee509-1b34-41c0-acb7-6d4650168915,33PXH-7Y6KF-2VJC9-XBBR8-HVTHH
af35d7b7-5035-4b63-8972-f0b747b9f4dc,DXHJF-N9KQX-MFPVR-GHGQK-Y7RKV
b3ca044e-a358-4d68-9883-aaa2941aca99,D2N9P-3P6X9-2R39C-7RTCD-MDVJX
b743a2be-68d4-4dd3-af32-92425b7bb623,3NPTF-33KPT-GGBPR-YX76B-39KDD
b8f5e3a3-ed33-4608-81e1-37d6c9dcfd9c,KF37N-VDV38-GRRTV-XH8X6-6F3BB
b92e9980-b9d5-4821-9c94-140f632f6312,FJ82H-XT6CR-J8D7P-XQJJ2-GPDD4
ba998212-460a-44db-bfb5-71bf09d1c68b,R962J-37N87-9VVK2-WJ74P-XTMHR
c04ed6bf-55c8-4b47-9f8e-5a1f31ceee60,BN3D2-R7TKB-3YPBD-8DRP2-27GG4
c06b6981-d7fd-4a35-b7b4-054742b7af67,GCRJD-8NW9H-F2CDX-CCM8D-9D6T9
c1af4d90-d1bc-44ca-85d4-003ba33db3b9,YQGMW-MPWTJ-34KDK-48M3W-X4Q6V
c6ddecd6-2354-4c19-909b-306a3058484e,Q6HTR-N24GM-PMJFP-69CD8-2GXKR
c72c6a1d-f252-4e7e-bdd1-3fca342acb35,BB6NG-PQ82V-VRDPW-8XVD2-V8P66
ca7df2e3-5ea0-47b8-9ac1-b1be4d8edd69,37D7F-N49CB-WQR8W-TBJ73-FM8RX
ca7df2e3-5ea0-47b8-9ac1-b1be4d8edd69,37D7F-N49CB-WQR8W-TBJ73-FM8RX
cab491c7-a918-4f60-b502-dab75e334f40,TNFGH-2R6PB-8XM3K-QYHX2-J4296
cd4e2d9f-5059-4a50-a92d-05d5bb1267c7,FNFKF-PWTVT-9RC8H-32HB2-JB34X
cd918a57-a41b-4c82-8dce-1a538e221a83,7HNRX-D7KGG-3K4RQ-4WPJ4-YTDFH
cda18cf3-c196-46ad-b289-60c072869994,TT8MH-CG224-D3D7Q-498W2-9QCTX
cfd8ff08-c0d7-452b-9f60-ef5c70c32094,VKK3X-68KWM-X2YGT-QR4M6-4BWMV
d30136fc-cb4b-416e-a23d-87207abc44a9,6XN7V-PCBDC-BDBRH-8DQY7-G6R44
d3643d60-0c42-412d-a7d6-52e6635327f6,48HP8-DN98B-MYWDG-T2DCC-8W83P
d4f54950-26f2-4fb4-ba21-ffab16afcade,VTC42-BM838-43QHV-84HX6-XJXKV
db537896-376f-48ae-a492-53d0547773d0,YBYF6-BHCR3-JPKRB-CDW7B-F9BK4
db78b74f-ef1c-4892-abfe-1e66b8231df6,NCTT7-2RGK8-WMHRF-RY7YQ-JTXG3
ddfa9f7c-f09e-40b9-8c1a-be877a9a7f4b,WYR28-R7TFJ-3X2YQ-YCY4H-M249D
de32eafd-aaee-4662-9444-c1befb41bde2,N69G4-B89J2-4G8F4-WWYCC-J464C
e0b2d383-d112-413f-8a80-97f373a5820c,YYVX9-NTFWV-6MDM3-9PT4T-4M68B
e0c42288-980c-4788-a014-c080d2e1926e,NW6C2-QMPVW-D7KKK-3GKT6-VCFB2
e14997e7-800a-4cf7-ad10-de4b45b578db,JMNMF-RHW7P-DMY6X-RF3DR-X2BQT
e1a8296a-db37-44d1-8cce-7bc961d59c54,XGY72-BRBBT-FF8MH-2GG8H-W7KCW
e272e3e2-732f-4c65-a8f0-484747d0d947,DPH2V-TTNVB-4X9Q3-TJR4H-KHJW4
e38454fb-41a4-4f59-a5dc-25080e354730,44RPN-FTY23-9VTTB-MP9BX-T84FV
e49c08e7-da82-42f8-bde2-b570fbcae76c,2HXDN-KRXHB-GPYC7-YCKFJ-7FVDG
e4db50ea-bda1-4566-b047-0ca50abc6f07,7NBT4-WGBQX-MP4H7-QXFF8-YP3KX
e58d87b5-8126-4580-80fb-861b22f79296,MX3RK-9HNGX-K3QKC-6PJ3F-W8D7B
e9942b32-2e55-4197-b0bd-5ff58cba8860,3PY8R-QHNP9-W7XQD-G6DPH-3J2C9
ebf245c1-29a8-4daf-9cb1-38dfc608a8c8,XCVCF-2NXM9-723PB-MHCB7-2RYQQ
ec868e65-fadf-4759-b23e-93fe37f2cc29,CPWHC-NT2C7-VYW78-DHDB2-PG3GK
ef6cfc9f-8c5d-44ac-9aad-de6a2ea0ae03,WX4NM-KYWYW-QJJR4-XV3QB-6VM33
f0f5ec41-0d55-4732-af02-440a44a3cf0f,XC9B7-NBPP2-83J2H-RHMBY-92BT4
f772515c-0e87-48d5-a676-e6962c3e1195,736RG-XDKJK-V34PF-BHK87-J6X3K
f7e88590-dfc7-4c78-bccb-6f3865b99d1a,VHXM3-NR6FT-RY6RT-CK882-KW2CJ
fd09ef77-5647-4eff-809c-af2b64659a45,22XQ2-VRXRG-P8D42-K34TD-G3QQC
fe1c3238-432a-43a1-8e25-97e7d1ef10f3,M9Q9P-WNJJT-6PXPY-DWX8H-6XWKK
ffee456a-cd87-4390-8e07-16146c672fd0,XYTND-K6QKT-K2MRH-66RTM-43JKP
7dc26449-db21-4e09-ba37-28f2958506a6,TVRH6-WHNXV-R9WG3-9XRFY-MY832
c052f164-cdf6-409a-a0cb-853ba0f0f55a,D764K-2NDRG-47T6Q-P8T8W-YP6DF
45b5aff2-60a0-42f2-bc4b-ec6e5f7b527e,FCNV3-279Q9-BQB46-FTKXX-9HPRH
c2e946d1-cfa2-4523-8c87-30bc696ee584,XGN3F-F394H-FD2MY-PP6FD-8MCRC
f57b5b6b-80c2-46e4-ae9d-9fe98e032cb7,GFMWN-WDHVB-4Y4XP-42WKM-RC6CQ
b1b1ef19-a088-4962-aedb-2a647a891104,XN3XP-QGKM4-KT7HM-6HC6T-H8V6F
1a716f14-0607-425f-a097-5f2f1f091315,QCQ4R-N2J93-PWMTK-G2BGF-BY82T
8f365ba6-c1b9-4223-98fc-282a0756a3ed,HTDQM-NBMMG-KGYDT-2DTKT-J2MPV
'@ | ConvertFrom-Csv
$Global:Office_Keys_List = @'
Product,Year,Key
Excel,2010,H62QG-HXVKF-PP4HP-66KMR-CW9BM
Excel,2013,VGPNG-Y7HQW-9RHP7-TKPV3-BG7GB
Excel,2016,9C2PK-NWTVB-JMPW8-BFT28-7FTBF
Excel,2019,TMJWT-YYNMB-3BKTF-644FC-RVXBD
Excel,2021,NWG3X-87C9K-TC7YY-BC2G7-G6RVC
Excel,2024,F4DYN-89BP2-WQTWJ-GR8YC-CKGJG
PowerPoint,2010,RC8FX-88JRY-3PF7C-X8P67-P4VTT
PowerPoint,2013,4NT99-8RJFH-Q2VDH-KYG2C-4RD4F
PowerPoint,2016,J7MQP-HNJ4Y-WJ7YM-PFYGF-BY6C6
PowerPoint,2019,RRNCX-C64HY-W2MM7-MCH9G-TJHMQ
PowerPoint,2021,TY7XF-NFRBR-KJ44C-G83KF-GX27K
PowerPoint,2024,CW94N-K6GJH-9CTXY-MG2VC-FYCWP
ProPlus,2010,VYBBJ-TRJPB-QFQRF-QFT4D-H3GVB
ProPlus,2013,YC7DK-G2NP3-2QQC3-J6H88-GVGXT
ProPlus,2016,XQNVK-8JYDB-WJ9W3-YJ8YR-WFG99
ProPlus,2019,NMMKJ-6RK4F-KMJVX-8D9MJ-6MWKP
ProPlus,2021,FXYTK-NJJ8C-GB6DW-3DYQT-6F7TH
ProPlus,2024,XJ2XN-FW8RK-P4HMP-DKDBV-GCVGB
ProjectPro,2010,YGX6F-PGV49-PGW3J-9BTGG-VHKC6
ProjectPro,2013,FN8TT-7WMH6-2D4X9-M337T-2342K
ProjectPro,2016,YG9NW-3K39V-2T3HJ-93F3Q-G83KT
ProjectPro,2019,B4NPR-3FKK7-T2MBV-FRQ4W-PKD2B
ProjectPro,2021,FTNWT-C6WBT-8HMGF-K9PRX-QV9H8
ProjectPro,2024,FQQ23-N4YCY-73HQ3-FM9WC-76HF4
ProjectStd,2010,4HP3K-88W3F-W2K3D-6677X-F9PGB
ProjectStd,2013,6NTH3-CW976-3G3Y2-JK3TX-8QHTT
ProjectStd,2016,GNFHQ-F6YQM-KQDGJ-327XX-KQBVC
ProjectStd,2019,C4F7P-NCP8C-6CQPT-MQHV9-JXD2M
ProjectStd,2021,J2JDC-NJCYY-9RGQ4-YXWMH-T3D4T
ProjectStd,2024,PD3TT-NTHQQ-VC7CY-MFXK3-G87F8
Publisher,2010,BFK7F-9MYHM-V68C7-DRQ66-83YTP
Publisher,2013,PN2WF-29XG2-T9HJ7-JQPJR-FCXK4
Publisher,2016,F47MM-N3XJP-TQXJ9-BP99D-8K837
Publisher,2019,G2KWX-3NW6P-PY93R-JXK2T-C9Y9V
Publisher,2021,2MW9D-N4BXM-9VBPG-Q7W6M-KFBGQ
SkypeforBusiness,2016,869NQ-FJ69K-466HW-QYCP2-DDBV6
SkypeforBusiness,2019,NCJ33-JHBBY-HTK98-MYCV8-HMKHJ
SkypeforBusiness,2021,HWCXN-K3WBT-WJBKY-R8BD9-XK29P
SkypeforBusiness,2024,4NKHF-9HBQF-Q3B6C-7YV34-F64P3
SmallBusBasics,2010,D6QFG-VBYP2-XQHM7-J97RH-VVRCK
Standard,2010,V7QKV-4XVVR-XYV4D-F7DFM-8R6BM
Standard,2013,KBKQT-2NMXY-JJWGP-M62JB-92CD4
Standard,2016,JNRGM-WHDWX-FJJG3-K47QV-DRTFM
Standard,2019,6NWWJ-YQWMR-QKGCB-6TMB3-9D9HK
Standard,2021,KDX7X-BNVR8-TXXGX-4Q7Y8-78VT3
Standard,2024,V28N4-JG22K-W66P8-VTMGK-H6HGR
VisioPrem,2010,D9DWC-HPYVV-JGF4P-BTWQB-WX8BJ
VisioPro,2010,D9DWC-HPYVV-JGF4P-BTWQB-WX8BJ
VisioPro,2013,C2FG9-N6J68-H8BTJ-BW3QX-RM3B3
VisioPro,2016,PD3PC-RHNGV-FXJ29-8JK7D-RJRJK
VisioPro,2019,9BGNQ-K37YR-RQHF2-38RQ3-7VCBB
VisioPro,2021,KNH8D-FGHT4-T8RK3-CTDYJ-K2HT4
VisioPro,2024,B7TN8-FJ8V3-7QYCP-HQPMV-YY89G
VisioStd,2010,767HD-QGMWX-8QTDB-9G3R2-KHFGJ
VisioStd,2013,J484Y-4NKBF-W2HMG-DBMJC-PGWR7
VisioStd,2016,7WHWN-4T7MP-G96JF-G33KR-W8GF4
VisioStd,2019,7TQNQ-K3YQQ-3PFH7-CCPPM-X4VQ2
VisioStd,2021,MJVNY-BYWPY-CWV6J-2RKRT-4M8QG
VisioStd,2024,JMMVY-XFNQC-KK4HK-9H7R3-WQQTV
Word,2010,HVHB3-C6FV7-KQX9W-YQG79-CRY7T
Word,2013,6Q7VD-NX8JD-WJ2VH-88V73-4GBJ7
Word,2016,WXY84-JN2Q9-RBCCQ-3Q3J3-3PFJ6
access,2010,V7Y44-9T38C-R2VJK-666HK-T7DDX
access,2013,NG2JY-H4JBT-HQXYP-78QH9-4JM2D
access,2016,GNH9Y-D2J4T-FJHGG-QRVH7-QPFDW
access,2019,9N9PT-27V4Y-VJ2PD-YXFMF-YTFQT
access,2021,WM8YG-YNGDD-4JHDC-PG3F4-FC4T4
access,2024,82FTR-NCHR7-W3944-MGRHM-JMCWD
mondo,2010,7TC2V-WXF6P-TD7RT-BQRXR-B8K32
mondo,2013,42QTK-RN8M7-J3C4G-BBGYM-88CYV
mondo,2016,HFTND-W9MK4-8B7MJ-B6C4G-XQBR2
outlook,2010,7YDC2-CWM8M-RRTJC-8MDVC-X3DWQ
outlook,2013,QPN8Q-BJBTJ-334K3-93TGY-2PMBT
outlook,2016,R69KK-NTPKF-7M3Q4-QYBHW-6MT9B
outlook,2019,7HD7K-N4PVK-BHBCQ-YWQRW-XW4VK
outlook,2021,C9FM6-3N72F-HFJXB-TM3V9-T86R9
outlook,2024,D2F8D-N3Q3B-J28PV-X27HD-RJWB9
word,2019,PBX3G-NWMT6-Q7XBW-PYJGG-WXD33
word,2021,TN8H9-M34D3-Y64V9-TR72V-X79KV
word,2024,MQ84N-7VYDM-FXV7C-6K7CC-VFW9J
'@ | ConvertFrom-Csv
$Global:Kms_Servers_List = @'
Site
kms.digiboy.ir
hq1.chinancce.com
kms.cnlic.com
kms.chinancce.com
kms.ddns.net
franklv.ddns.net
k.zpale.com
m.zpale.com
mvg.zpale.com
kms.shuax.com
kensol263.imwork.net
annychen.pw
heu168.6655.la
xykz.f3322.org
kms789.com
dimanyakms.sytes.net
kms.03k.org
kms.lotro.cc
kms.didichuxing.com
zh.us.to
kms.aglc.cckms.aglc.cc
kms.xspace.in
winkms.tk
kms.srv.crsoo.com
kms.loli.beer
kms8.MSGuides.com
kms9.MSGuides.com
kms.zhuxiaole.org
kms.lolico.moe
kms.moeclub.org
'@ | ConvertFrom-Csv

# Base Ps1 operation
function Query-Basic {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PropertyList,
        [Parameter(Mandatory = $true)]
        [string]$ClassName
    )
    try {
        $value = @($PropertyList).Replace(' ', '')
        $wmi_Object = Get-WmiObject -Query "SELECT $($value) FROM $($ClassName)" -ea 0
        if (-not $wmi_Object) { 
            return "Error:WMI_SEARCH_FAILURE"
        }
        return $wmi_Object
    }
    catch {
        return $null
    }
}
function Query-Advanced {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PropertyList,
        [Parameter(Mandatory = $true)]
        [string]$ClassName,
        [Parameter(Mandatory = $true)]
        [string]$Filter
    )
    
    try {
        $value = @($PropertyList).Replace(' ', '')
        $Global:DBG = "SELECT $($value) FROM $($ClassName) WHERE ($($Filter))"
        $wmi_Object = Get-WmiObject -Query "SELECT $($value) FROM $($ClassName) WHERE ($($Filter))" -ea 0
        if (-not $wmi_Object) { 
            return "Error:WMI_SEARCH_FAILURE"
        }
        return $wmi_Object
    }
    catch {
        return $null
    }
}
function Activate-Class {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Class,
        [Parameter(Mandatory = $true)]
        [string]$Id
    )
    $Global:lastErr = $null
    try {
        (gwmi $Class -Filter "ID='$($Id)'").Activate()
        $Global:lastErr = 0
    }
    catch {
        $HResult = "0x{0:x}" -f @($_.Exception.InnerException).HResult
        $Global:lastErr = $HResult
    }
}
function Uninstall-ProductKey {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Class,
        [Parameter(Mandatory = $true)]
        [string]$Filter
    )
    try {
        Invoke-CimMethod -MethodName UninstallProductKey -Query "SELECT * FROM $($Class) WHERE ($($Filter))"
        $Global:lastErr = 0
    }
    catch {
        $HResult = "0x{0:x}" -f @($_.Exception.InnerException).HResult
        $Global:lastErr = $HResult
    }
}
function Install-ProductKey {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProductKey
    )
    $ErrorActionPreference = "Stop"
    try {
        Invoke-CimMethod -MethodName InstallProductKey -Query "SELECT * FROM SoftwareLicensingService" -Arguments @{ ProductKey = $ProductKey }
        $Global:lastErr = 0
    }
    catch {
        $HResult = "0x{0:x}" -f @($_.Exception.InnerException).HResult
        $Global:lastErr = $HResult
    }
}
function Set-DefinedEntities {

    # --- Detect x64 paths ---
    if (Test-Path "$env:windir\SysWOW64\cscript.exe") {
        $global:cscript = "$env:windir\SysWOW64\cscript.exe"
    }
    if (Test-Path "$env:windir\SysWOW64\slmgr.vbs") {
        $global:slmgr = "$env:windir\SysWOW64\slmgr.vbs"
    }
    if (Test-Path "$env:ProgramFiles(x86)\Microsoft Office\office14\OSPP.vbs") {
        $global:OSPP_14 = "$env:ProgramFiles(x86)\Microsoft Office\office14\OSPP.vbs"
    }
    if (Test-Path "$env:ProgramFiles(x86)\Microsoft Office\office15\OSPP.vbs") {
        $global:OSPP_15 = "$env:ProgramFiles(x86)\Microsoft Office\office15\OSPP.vbs"
        $global:OSPP = $global:OSPP_15
    }
    if (Test-Path "$env:ProgramFiles(x86)\Microsoft Office\Office16\OSPP.vbs") {
        $global:OSPP_16 = "$env:ProgramFiles(x86)\Microsoft Office\Office16\OSPP.vbs"
        $global:OSPP = $global:OSPP_16
    }
    if (Test-Path "$env:ProgramFiles(x86)\Microsoft Office\Root\Office16\OSPP.vbs") {
        $global:OSPP_16 = "$env:ProgramFiles(x86)\Microsoft Office\Root\Office16\OSPP.vbs"
        $global:OSPP = $global:OSPP_16
    }
    if (Test-Path "$env:ProgramFiles(x86)\Microsoft Office\root\Licenses16") {
        $global:licenceDir = "$env:ProgramFiles(x86)\Microsoft Office\root\Licenses16"
    }
    if (Test-Path "$env:ProgramFiles(x86)\Microsoft Office\root") {
        $global:root = "$env:ProgramFiles(x86)\Microsoft Office\root"
    }

    # Registry path checks (x64)
    $regPaths64 = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\propertyBag",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\16.0\ClickToRunStore",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration"
    )
    foreach ($path in $regPaths64) {
        if (Get-ItemProperty -Path $path -Name ProductReleaseIds -ea 0) {
            $global:Key = $path
        }
    }

    if ($pkg = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun" -Name PackageGUID -ea 0) {
        $global:guid = $pkg.PackageGUID
    }

    # --- Detect x86 paths ---
    if (Test-Path "$env:windir\System32\cscript.exe") {
        $global:cscript = "$env:windir\System32\cscript.exe"
    }
    if (Test-Path "$env:windir\System32\slmgr.vbs") {
        $global:slmgr = "$env:windir\System32\slmgr.vbs"
    }
    if (Test-Path "$env:ProgramFiles\Microsoft Office\office14\OSPP.vbs") {
        $global:OSPP_14 = "$env:ProgramFiles\Microsoft Office\office14\OSPP.vbs"
    }
    if (Test-Path "$env:ProgramFiles\Microsoft Office\Office15\OSPP.vbs") {
        $global:OSPP_15 = "$env:ProgramFiles\Microsoft Office\Office15\OSPP.vbs"
        $global:OSPP = $global:OSPP_15
    }
    if (Test-Path "$env:ProgramFiles\Microsoft Office\Office16\OSPP.vbs") {
        $global:OSPP_16 = "$env:ProgramFiles\Microsoft Office\Office16\OSPP.vbs"
        $global:OSPP = $global:OSPP_16
    }
    if (Test-Path "$env:ProgramFiles\Microsoft Office\root\Office16\OSPP.vbs") {
        $global:OSPP_16 = "$env:ProgramFiles\Microsoft Office\root\Office16\OSPP.vbs"
        $global:OSPP = $global:OSPP_16
    }
    if (Test-Path "$env:ProgramFiles\Microsoft Office\root\Licenses16") {
        $global:licenceDir = "$env:ProgramFiles\Microsoft Office\root\Licenses16"
    }
    if (Test-Path "$env:ProgramFiles\Microsoft Office\root") {
        $global:root = "$env:ProgramFiles\Microsoft Office\root"
    }

    # Registry path checks (x86)
    $regPaths86 = @(
        "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\propertyBag",
        "HKLM:\SOFTWARE\Microsoft\Office\16.0\ClickToRunStore",
        "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
    )
    foreach ($path in $regPaths86) {
        if (Get-ItemProperty -Path $path -Name ProductReleaseIds -ea 0) {
            $global:Key = $path
        }
    }

    if ($pkg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun" -Name PackageGUID -ea 0) {
        $global:guid = $pkg.PackageGUID
    }

    # --- Registry constants ---
    $global:OSPP_HKLM     = 'HKLM:\SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform'
    $global:OSPP_USER     = 'HKU\S-1-5-20\SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform'
    $global:XSPP_HKLM_X32 = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform'
    $global:XSPP_HKLM_X64 = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform'
    $global:XSPP_USER     = 'HKU\S-1-5-20\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform'
}
function Clean-RegistryKeys {
    $ErrorActionPreference = 'SilentlyContinue'

    # List of value names to delete
    $valuesToDelete = @(
        'KeyManagementServiceName',
        'KeyManagementServicePort',
        'DisableDnsPublishing',
        'DisableKeyManagementServiceHostCaching'
    )

    # Delete values from OSPP paths
    foreach ($name in $valuesToDelete) {
        Remove-ItemProperty -Path $global:OSPP_USER -Name $name -Force
        Remove-ItemProperty -Path $global:OSPP_HKLM -Name $name -Force
    }

    # Delete values from XSPP paths (SLMGR.VBS)
    foreach ($name in $valuesToDelete) {
        Remove-ItemProperty -Path $global:XSPP_USER -Name $name -Force
        Remove-ItemProperty -Path $global:XSPP_HKLM_X32 -Name $name -Force
        Remove-ItemProperty -Path $global:XSPP_HKLM_X64 -Name $name -Force
    }

    # WMI Nethood subkeys to delete
    $subKeys = @(
        '55c92734-d682-4d71-983e-d6ec3f16059f',
        '0ff1ce15-a989-479d-af46-f275c6370663',
        '59a52881-a989-479d-af46-f275c6370663'
    )

    foreach ($subKey in $subKeys) {
        Remove-Item -Path "$global:XSPP_USER\$subKey" -Recurse -Force
        Remove-Item -Path "$global:XSPP_HKLM_X32\$subKey" -Recurse -Force
        Remove-Item -Path "$global:XSPP_HKLM_X64\$subKey" -Recurse -Force
    }

    $ErrorActionPreference = 'Continue'
}
function Update-RegistryKeys {
    param (
        [Parameter(Mandatory = $true)]
        [string]$KmsHost,
        [Parameter(Mandatory = $true)]
        [string]$KmsPort,

        [string]$SubKey,
        [string]$Id
    )

    # remove KMS38 lock --> From MAS PROJECT, KMS38_Activation.cmd
    $SID = New-Object SecurityIdentifier('S-1-5-32-544')
    $Admin = ($SID.Translate([NTAccount])).Value
    $ruleArgs = @("$Admin", "FullControl", "Allow")
    $path = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform\55c92734-d682-4d71-983e-d6ec3f16059f'
    $regKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64').OpenSubKey($path, 'ReadWriteSubTree', 'ChangePermissions')
    if ($regKey) {
        $acl = $regKey.GetAccessControl()
        $rule = [RegistryAccessRule]::new.Invoke($ruleArgs)
        $acl.ResetAccessRule($rule)
        $regKey.SetAccessControl($acl)
    }

    $osppPaths = @(
        'HKCU:\Software\Microsoft\OfficeSoftwareProtectionPlatform',
        'HKLM:\Software\Microsoft\OfficeSoftwareProtectionPlatform'
    )

    $xsppPaths = @(
        'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform',
        'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform'
    )

    # Apply to OSPP paths (Office)
    foreach ($path in $osppPaths) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null}
        New-ItemProperty -Path $path -Name 'KeyManagementServiceName' -Value $KmsHost -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $path -Name 'KeyManagementServicePort' -Value $KmsPort -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $path -Name 'DisableDnsPublishing' -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $path -Name 'DisableKeyManagementServiceHostCaching' -Value 0 -PropertyType DWord -Force | Out-Null
    }

    # Apply to XSPP paths (Windows)
    foreach ($path in $xsppPaths) {
        New-Item -Path $path -Force -ea 0 | Out-Null
        New-ItemProperty -Path $path -Name 'KeyManagementServiceName' -Value $KmsHost -PropertyType String -Force -ea 0 | Out-Null
        New-ItemProperty -Path $path -Name 'KeyManagementServicePort' -Value $KmsPort -PropertyType String -Force -ea 0 | Out-Null
        New-ItemProperty -Path $path -Name 'DisableDnsPublishing' -Value 0 -PropertyType DWord -Force -ea 0 | Out-Null
        New-ItemProperty -Path $path -Name 'DisableKeyManagementServiceHostCaching' -Value 0 -PropertyType DWord -Force -ea 0 | Out-Null
    }
    if (!$SubKey -or !$Id) {
        return
    }
    # WMI Subkey paths (XSPP + subkey + id)
    foreach ($base in $xsppPaths) {
        $wmiPath = Join-Path -Path $base -ChildPath "$SubKey\$Id"
        try {
            if (-not (Test-Path $wmiPath)) {
               New-Item -Path $wmiPath -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -Path $wmiPath -Name 'KeyManagementServiceName' -Value $KmsHost -PropertyType String -Force -ea 0 | Out-Null
            New-ItemProperty -Path $wmiPath -Name 'KeyManagementServicePort' -Value $KmsPort -PropertyType String -Force -ea 0 | Out-Null
        }
        catch { 
            # should i do something here ?
        }
    }
}
function Update-Year {
    param (
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d{4}$')]
        [string]$Year
    )

    $Global:ProductYear = $Year
}
function Get-ProductYear {

    $Global:OfficeC2R = $null
    $Global:OfficeMsi16 = $null

    if (-not $Global:key) {
        $uninstallPaths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )

        foreach ($path in $uninstallPaths) {
            if (Get-ChildItem -Path $path -ea 0 | Where-Object { $_.PSChildName -like '*Office16*' }) {
                $Global:OfficeMsi16 = $true
                Update-Year 2016
                return
            }
        }

        return
    }

    # Extract ProductReleaseIds
    try {
        $productRelease = (Get-ItemProperty -Path $Global:key -Name ProductReleaseIds -ErrorAction Stop).ProductReleaseIds
        if (-not $productRelease) { return }
        $Global:OfficeC2R = $true

        foreach ($year in $Global:SupportedBuildYear) {
            if ($productRelease -like "*$year*") {
                Update-Year $year
                return
            }
        }
    } catch {
        return
    }

    # Default to 2016 if nothing matched
    Update-Year 2016
}
function Wmi-Activation {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [string]$Grace,
        [Parameter(Mandatory = $true)]
        [string]$Ks,
        [Parameter(Mandatory = $true)]
        [string]$Kp,
        [Parameter(Mandatory = $true)]
        [string]$Km
    )

    # Wmi based activation
    # using SoftwareLicensingProduct class for office
    # using SoftwareLicensingService class for windows
    # using OfficeSoftwareProtectionProduct class for specific win7 case

    $subKey        = $null
    $SPP_ACT_CLASS = $null
    $SPP_KMS_Class = $null
    $SPP_KMS_Where = $null

    if ($Km -match 'Windows') {
        $subKey = '55c92734-d682-4d71-983e-d6ec3f16059f'
        $SPP_KMS_Class = 'SoftwareLicensingService'
        $SPP_KMS_Where = 'version is not null'
        $SPP_ACT_CLASS = 'SoftwareLicensingProduct'
    }

    if ($Km -match 'office') {
        $subKey = '0ff1ce15-a989-479d-af46-f275c6370663'

        if ($Global:Windows_7_Or_Earlier) {

            # Office in windows Windows 7 and less use 2 classes
  	        # OfficeSoftwareProtectionService for KMS settings 
  	        # OfficeSoftwareProtectionProduct for activation

            $SPP_KMS_Class = 'OfficeSoftwareProtectionService'
            $SPP_KMS_Where = 'version is not null'
            $SPP_ACT_CLASS = 'OfficeSoftwareProtectionProduct'
        }

        if ($Global:14_X_Mode) {

            # Office 2010 Classes
  	        # OfficeSoftwareProtectionService for KMS settings 
  	        # OfficeSoftwareProtectionProduct for activation

            $subKey = '59a52881-a989-479d-af46-f275c6370663'
            $SPP_KMS_Class = 'OfficeSoftwareProtectionService'
            $SPP_KMS_Where = 'version is not null'
            $SPP_ACT_CLASS = 'OfficeSoftwareProtectionProduct'
        }
    }

    if (-not $SPP_ACT_CLASS) {
        $SPP_ACT_CLASS = 'SoftwareLicensingProduct'
    }
    $Product_Licensing_Class = $SPP_ACT_CLASS
    $Product_Licensing_Where = "Id like '%$Id%'"
    if (-not $SPP_KMS_Class) {
        $SPP_KMS_Class = $Product_Licensing_Class
        $SPP_KMS_Where = $Product_Licensing_Where
    }

    Update-RegistryKeys -KmsHost $ks -KmsPort $Kp -SubKey $subKey -Id $Id
    Write-Host '+++ Activating +++'
    Write-Host '...................'
    $null = Activate-Class -Class $Product_Licensing_Class -Id $Id
    $wmi_Object = Query-Advanced -PropertyList 'GracePeriodRemaining' -ClassName $Product_Licensing_Class -Filter $Product_Licensing_Where
    if ($wmi_Object -and $wmi_Object.GracePeriodRemaining) {
        Write-Host "Old Grace               = $Grace"
        Write-Host "New Grace               = $($wmi_Object.GracePeriodRemaining)"
    }
    if ($Global:lastErr -eq 0 ) {
        Write-Host "Status                  = Succeeded (Error 0x$lastErr)"
    } else {
        Write-Host "Status                  = Failed (Error 0x$lastErr)"
    }
}
function Check-Activation {
    param (
        [Parameter(Mandatory=$true)]
        [string]$product,
        [Parameter(Mandatory=$true)]
        [string]$licenceType
    )

    $Global:ProductIsActivated = $false
    $LicensingProductClass = 'SoftwareLicensingProduct'
    if ($product -match 'Office' -and $Global:Windows_7_Or_Earlier) {
        $LicensingProductClass = 'OfficeSoftwareProtectionProduct'
    }
    $wmiSearch = "Name like '%$product%' and Description like '%$licenceType%' and PARTIALPRODUCTKEY IS NOT NULL and GenuineStatus = 0 and LicenseStatus = 1"
    $output = Query-Advanced -PropertyList "name" -ClassName $LicensingProductClass -Filter $wmiSearch

    # Evaluate output conditions
    if (-not $output -or ($output -is [string])) {
        return }

    if ($product -ieq 'Windows') {
        Write-Host "=== $product is $licenceType activated ==="
    } else {
        Write-Host "=== Office $product is $licenceType activated ==="
    }
    $Global:ProductIsActivated = $true
    Write-Host
}
function Search_VL_Products {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProductName
    )

    $ApplicationId = $null
    $LicensingProductClass = 'SoftwareLicensingProduct'

    if ($ProductName -match 'Office') {
        $ApplicationId = '0ff1ce15-a989-479d-af46-f275c6370663'
        if ($Global:Windows_7_Or_Earlier) {
            $LicensingProductClass = 'OfficeSoftwareProtectionProduct'
        }
    }
    elseif ($ProductName -match 'windows') {
        $ApplicationId = '55c92734-d682-4d71-983e-d6ec3f16059f'
    }

    $PropertyList = 'ID,LicenseStatus,PartialProductKey,GenuineStatus,Name,GracePeriodRemaining'
    $Filter = "ApplicationId like '%$ApplicationId%' and Description like '%KMSCLIENT%'"
    if (-not $Global:Windows_7_Or_Earlier -and ($ProductName -notmatch 'Office')) {
        $Filter += " and PartialProductKey is not null and LicenseFamily is not null and LicenseDependsOn is NULL"
    }

    # Assuming Query-Advanced is defined elsewhere in your script, you call it here:
    return Query-Advanced -PropertyList $PropertyList -ClassName $LicensingProductClass -Filter $Filter
}
function Search_14_X_VL_Products {
    $ApplicationId = '59a52881-a989-479d-af46-f275c6370663'
    $LicensingProductClass = 'OfficeSoftwareProtectionProduct'
    $PropertyList = 'ID,LicenseStatus,PartialProductKey,GenuineStatus,Name,GracePeriodRemaining'
    $Filter = "ApplicationId like '%$ApplicationId%' and Description like '%KMSCLIENT%' and PartialProductKey is not null"

    # Call your query function
    return Query-Advanced -PropertyList $PropertyList -ClassName $LicensingProductClass -Filter $Filter
}
function Search_Office_VL_Products {
    param (
        [Parameter(Mandatory=$true)]
        [string]$T_Year,
        [Parameter(Mandatory=$true)]
        [string]$T_Name
    )

    $LicensingProductClass = 'SoftwareLicensingProduct'
    $ApplicationId = '0ff1ce15-a989-479d-af46-f275c6370663'
    if ($Global:Windows_7_Or_Earlier) {
        $LicensingProductClass = 'OfficeSoftwareProtectionProduct'
    }

    # Extract last two digits of year
    $yearPart = $T_Year.Substring($T_Year.Length - 2)

    $Filter = "ApplicationId like '%$ApplicationId%' and Description like '%KMSCLIENT%' and PartialProductKey is not null"
    $filter += " and Name like '%office $yearPart%' and Name like '%$T_Name%'"
    return Query-Advanced -PropertyList "Name" -ClassName $LicensingProductClass -Filter $Filter
}
function Uninstall-PartialProductKey {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PartialKey,
        [Parameter(Mandatory = $true)]
        [bool]$IsWindows7OrEarlier = $false
    )

    $LicensingProductClass = if ($IsWindows7OrEarlier) {
        'OfficeSoftwareProtectionProduct'
    } else {
        'SoftwareLicensingProduct'
    }

    # Create a WQL-compatible filter
    $Filter = "PartialProductKey LIKE '%$PartialKey%'"

    # Call the function to uninstall
    Uninstall-ProductKey -Class $LicensingProductClass -Filter $Filter
}
function Remove_Office_Products {
    param (
        [Parameter(Mandatory = $true)]
        [string]$T_Year,
        [Parameter(Mandatory = $true)]
        [string]$T_Name
    )

    $LicensingProductClass = 'SoftwareLicensingProduct'
    if ($Global:Windows_7_Or_Earlier) {
        $LicensingProductClass = 'OfficeSoftwareProtectionProduct'
    }

    $PropertyList = 'ID,LicenseStatus,PartialProductKey,GenuineStatus,Name,GracePeriodRemaining'

    # Extract last 2 digits of year
    $yearPart = $T_Year.Substring($T_Year.Length - 2)

    # Construct WMI filter
    $Filter = "PartialProductKey is not null and Name like '%office $yearPart%' and Name like '%$T_Name%'"

    # Call helper function to uninstall product keys matching filter
    Uninstall-ProductKey -Class $LicensingProductClass -Filter $Filter
}
function Integrate-License {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Product,

        [string]$Year
    )

    if (-not $global:root) {
        Write-Host "Root path not defined."
        return
    }

    # Determine product name
    if ($Year -match '2016') {
        $FinalProduct = "${Product}Volume.16"
    } else {
        $FinalProduct = "${Product}${Year}Volume.16"
    }

    # Construct the integrator path
    $IntegratorPath = Join-Path -Path $global:root -ChildPath "Integration\integrator.exe"

    # Build argument list
    $args = @(
        '/I',
        '/License',
        "PRIDName=$FinalProduct",
        "PackageGUID=$global:Guid",
        '/Global',
        '/C2R',
        "PackageRoot=$Root"
    )

    # Execute
    & $IntegratorPath @args
}
Function Service-Check {

    if ($Global:LocalKms) {

        # if defined LocalKms (
        #  set "bin=A64.dll,x64.dll,x86.dll"
        #  for %%# in (!bin!) do if not exist "%fs%\%%#" set "LocalKms="
        #  if not defined LocalKms (
        #  	echo.
        #  	echo Local Activation files Is Missing, Switch back to Online KMS
        #  	timeout 5
        #  	Clear-host
        #  )
        #)

    }

    try {
        # Query the Winmgmt service "Start" registry value
        $startValue = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Winmgmt" -Name "Start" -ErrorAction Stop).Start

    }
    catch {
        # If registry key not found or error occurs, just continue (no action)
        $startValue = $null
    }

    if ($startValue -eq 4) {
        # Start type 4 means "Disabled" - try to set to automatic
        $result = sc.exe config Winmgmt start=auto 2>&1

        if ($LASTEXITCODE -ne 0) {
            Clear-Host
            Write-Host ""
            Write-Host "#### ERROR:: WMI FAILURE"
            Write-Host ""
            Write-Host "- winmgmt service is not working"
            Write-Host ""
            Pause
            exit 1
        }
    }

    $wmi_check = (gwmi Win32_Processor -ea 0).AddressWidth -match "32|64"
    if ($wmi_check -eq $false) {
        Write-Host "#### ERROR:: WMI FAILURE"
        Write-Host ""
        Write-Host "- The WMI repository is broken"
        Write-Host "- winmgmt service is not working"
        Write-Host "- Script run in a sandbox/limited environment"
    }

    # Check if Windows 7 or earlier
    if ($Global:osVersion.Build -le 7601) {
        $Global:Windows_7_Or_Earlier = $true
    } else {
        $Global:Windows_7_Or_Earlier = $false
    }

    # Check if unsupported build (less than 2600)
    if ($Global:osVersion.Build -lt 2600) {
        Write-Host ""
        Write-Host "ERROR ### System not supported"
        Write-Host ""
        Read-Host -Prompt "Press Enter to exit"
        exit
    }

    $Global:xBit = if ([Environment]::Is64BitOperatingSystem) { 64 } else { 32 }

    #fix for IoTEnterpriseS new key
    #https://forums.mydigitallife.net/threads/windows-11-ltsc.87144/#post-1795872
}
Function LetsActivate {
    
    $Global:KmsServer = $null
    if ($Global:LocalKms -eq $false) {
        Write-Host "Start Activation Process"
        Write-Host "........................"
        Write-Host "Look For Online Kms Servers"
        foreach ($server in $Global:Kms_Servers_List.Site) {
            write-host "Check if $($server):1688 is Online"
            $connection = Test-NetConnection -ComputerName $server -Port 1688 -InformationAction SilentlyContinue
            if ($connection.TcpTestSucceeded) {
                $Global:KmsServer = $server
                break
            }
        }
        $ProgressPreference = 'Continue'
    }

    if (($Global:LocalKms -eq $false) -and (
    -not $Global:KmsServer)) {
        Write-Host
        write-host "ERROR ##### didnt found any available online kms server"
        Write-Host
        return
    }

    if (($Global:LocalKms -eq $false) -and $Global:KmsServer) {
        write-host "Winner Winner Chicken dinner"
        write-host
        Update-RegistryKeys -KmsHost $Global:KmsServer -KmsPort 1688 
    }
    if ($Global:LocalKms -eq $true) {
        #StartKMSActivation
    }

    WindowsHelper
    OfficeHelper

    if ($Global:LocalKms -eq $true) {
        #StopKMSActivation
    }
}
Function WindowsHelper {
    if (-not $global:slmgr) {
        Write-Host "ERROR ##### didnt found any Windows products / SLMGR.VBS IS Missing"
        Write-Host
        return
    }

    $global:VL_Product_Not_Found = $false
    $output = Search_VL_Products -ProductName windows
    if (-not $output -or ($output -is [string])) {
        $global:VL_Product_Not_Found = $true
    }

    if ($global:VL_Product_Not_Found) {
        
        $null = Check-Activation Windows RETAIL
        if ($global:ProductIsActivated) {
            return
        }

        $null = Check-Activation Windows MAK
        if ($global:ProductIsActivated) {
            return
        }

        $null = Check-Activation Windows OEM
        if ($global:ProductIsActivated) {
            return
        }
        
        Windows_Licence_Worker
        if (-not $global:serial) {
            return
        }
        $global:VL_Product_Not_Found = $false
        $null = Install-ProductKey -ProductKey $global:serial
        Write-Host
        $output = Search_VL_Products -ProductName windows
        if (-not $output -or ($output -is [string])) {
            Write-Host "ERROR ##### didnt found any windows volume products"
            Write-Host
        }
    }

    if ($output -and ($output -isnot [string])) {
      
      Write-Host $output.Name
      Write-Host "...................................."
      Write-Host "License / Genuine 	= $($output.LicenseStatus) / $($($output.GenuineStatus))"
      Write-Host "Period Remaining 	= $([Math]::Floor($output.GracePeriodRemaining/60/24))"
      Write-Host "Product ID 	        = $($output.ID)"

      if ($output.GracePeriodRemaining -gt 259200) {
        Write-Host
        Write-Host "=== Windows is KMS38/KMS4K activated ==="
        Write-Host
      }

      if ($output.GracePeriodRemaining -le 259200) {
        if ($Global:LocalKms -eq $false) {
           Write-Host
           Wmi-Activation -Id $output.ID -Grace $output.GracePeriodRemaining -Ks $Global:KmsServer -Kp 1688 -Km windows
        }
        if ($Global:LocalKms -eq $true) {
           Write-Host
           Wmi-Activation -Id $output.ID -Grace $output.GracePeriodRemaining -Ks $Global:IP_ADDRESS -Kp 1688 -Km windows
        }
      }
    }
}
Function OfficeHelper {
    param (
        [bool]$Is14XMode = $false
    )

    $Global:14_X_Mode = [bool]$Is14XMode
    if (!$global:OSPP_14 -and !$global:OSPP_15 -and !$global:OSPP_16 ) {
        Write-Host
        Write-Host "ERROR ##### didnt found any Office products / OSPP.VBS IS Missing"
        Write-Host
        return
    }

    $ohook_found = $false
    $paths = @(
        "$env:ProgramFiles\Microsoft Office\Office15\sppc*.dll",
        "$env:ProgramFiles\Microsoft Office\Office16\sppc*.dll",
        "$env:ProgramW6432\Microsoft Office\Office15\sppc*.dll",
        "$env:ProgramW6432\Microsoft Office\Office16\sppc*.dll",
        "$env:ProgramFiles(x86)\Microsoft Office\Office15\sppc*.dll",
        "$env:ProgramFiles(x86)\Microsoft Office\Office16\sppc*.dll"
    )

    foreach ($path in $paths) {
        if (Get-ChildItem -Path $path -Filter 'sppc*.dll' -Attributes ReparsePoint -ea 0) {
            $ohook_found = $true
            break
        }
    }

    # Also check the root\vfs paths
    $vfsPaths = @(
        "$env:ProgramFiles\Microsoft Office 15\root\vfs\System\sppc*.dll",
        "$env:ProgramFiles\Microsoft Office 15\root\vfs\SystemX86\sppc*.dll",
        "$env:ProgramFiles\Microsoft Office\root\vfs\System\sppc*.dll",
        "$env:ProgramFiles\Microsoft Office\root\vfs\SystemX86\sppc*.dll",
        "$env:ProgramW6432\Microsoft Office 15\root\vfs\System\sppc*.dll",
        "$env:ProgramW6432\Microsoft Office 15\root\vfs\SystemX86\sppc*.dll",
        "$env:ProgramW6432\Microsoft Office\root\vfs\System\sppc*.dll",
        "$env:ProgramW6432\Microsoft Office\root\vfs\SystemX86\sppc*.dll",
        "$env:ProgramFiles(x86)\Microsoft Office 15\root\vfs\System\sppc*.dll",
        "$env:ProgramFiles(x86)\Microsoft Office 15\root\vfs\SystemX86\sppc*.dll",
        "$env:ProgramFiles(x86)\Microsoft Office\root\vfs\System\sppc*.dll",
        "$env:ProgramFiles(x86)\Microsoft Office\root\vfs\SystemX86\sppc*.dll"
    )

    foreach ($path in $vfsPaths) {
        if (Get-ChildItem -Path $path -Filter 'sppc*.dll' -Attributes ReparsePoint -ea 0) {
            $ohook_found = $true
            break
        }
    }

    if ($ohook_found) {
        Write-Host
        Write-Host "=== Office is Ohook activated ==="
        Write-Host
        return
    }
    if (!$Is14XMode) {
       Office_Licence_Worker
    }

    $global:VL_Product_Not_Found = $false
    if ($Is14XMode) {
      $output = Search_14_X_VL_Products -ProductName office
    } else {
      $output = Search_VL_Products -ProductName office
    }

    if (-not $output -or ($output -is [string])) {
        $global:VL_Product_Not_Found = $true
    }

    if ($Global:VL_Product_Not_Found) {
        if ($Global:14_X_Mode) {
            Write-Host "ERROR ##### didn't find any Office 14.X volume products"
            return
        }

        if ($Global:OSPP_14) {
            Write-Host "ERROR ##### didn't find any Office 15.X 16.X volume products"
            Write-Host
            OfficeHelper -Is14XMode $true
            return
        }

        if (-not $Global:OSPP_14) {
            Write-Host "ERROR ##### didn't find any Office 14.X 15.X 16.X volume products"
            return
        }

        Write-Host "ERROR ##### Wtf happened now ??"
        return
    }

    if ($output -and ($output -isnot [string])) {
      foreach ($wmi_object in $output) {
          Write-Host
          Write-Host $wmi_object.Name
          Write-Host "...................................."
          Write-Host "License / Genuine 	= $($wmi_object.LicenseStatus) / $($($wmi_object.GenuineStatus))"
          Write-Host "Period Remaining 	= $([Math]::Floor($wmi_object.GracePeriodRemaining/60/24))"
          Write-Host "Product ID 	        = $($wmi_object.ID)"

          if ($wmi_object.GracePeriodRemaining -gt 259200) {
            Write-Host
            Write-Host "=== Office is KMS4K activated ==="
            Write-Host
          }

          if ($wmi_object.GracePeriodRemaining -le 259200) {
            if ($Global:LocalKms -eq $false) {
               Write-Host
               Wmi-Activation -Id $wmi_object.ID -Grace $wmi_object.GracePeriodRemaining -Ks $Global:KmsServer -Kp 1688 -Km windows
            }
            if ($Global:LocalKms -eq $true) {
               Write-Host
               Wmi-Activation -Id $wmi_object.ID -Grace $wmi_object.GracePeriodRemaining -Ks $Global:IP_ADDRESS -Kp 1688 -Km windows
            }
          }
      }
    }

    if (-not $Is14XMode -and ($Global:OSPP_14)) {
      OfficeHelper -Is14XMode $true
      return
    }

    write-host
    write-host "Search for 14.X Products"
    write-host "........................"
    write-host "--- 404 not found"
    return
}
Function Windows_Licence_Worker {

    $Global:serial = $null
    $EditionID = Get-ProductID
    $Global:VL_Product_Not_Found = $false
    $LicensingProductClass = 'SoftwareLicensingProduct'

    # fix for IoTEnterpriseS new key
    # https://forums.mydigitallife.net/threads/windows-11-ltsc.87144/#post-1795872

    if ($EditionID -eq 'ProfessionalSingleLanguage') {
        $EditionID = 'Professional' }
    elseif ($EditionID -eq 'ProfessionalCountrySpecific') {
        $EditionID = 'Professional' }
    elseif ($EditionID -eq 'IoTEnterprise') {
        $EditionID = 'Enterprise' }
    elseif ($EditionID -eq 'IoTEnterpriseK') {
        $EditionID = 'Enterprise' }
    elseif ($EditionID -eq 'IoTEnterpriseSK') {
        $EditionID = 'EnterpriseS' }
    elseif ($EditionID -eq 'IoTEnterpriseS') {
        if ($Global:osVersion.Build -lt 22610) {
            $EditionID = 'EnterpriseS'
            if ($Global:osVersion.Build -ge 19041 -and $Global:osVersion.UBR -ge 2788) {
                $EditionID = 'IoTEnterpriseS'
            }
        }
    }

    $wmiSearch = "Name like '%$EditionID%' and Description like '%VOLUME_KMSCLIENT%' and ApplicationId like '%55c92734-d682-4d71-983e-d6ec3f16059f%'"
    $output = Query-Advanced -PropertyList "ID" -ClassName $LicensingProductClass -Filter $wmiSearch

    # Evaluate output conditions
    if (-not $output -or ($output -is [string])) {
        Write-Host "ERROR ##### Couldn't find Any windows Supported ID"
        Write-Host
        return
    }

    # Blacklist IDs but you want to exclude these from output, so invert logic
    $blacklist = @(
        'b71515d9-89a2-4c60-88c8-656fbcca7f3a','af43f7f0-3b1e-4266-a123-1fdb53f4323b','075aca1f-05d7-42e5-a3ce-e349e7be7078',
        '11a37f09-fb7f-4002-bd84-f3ae71d11e90','43f2ab05-7c87-4d56-b27c-44d0f9a3dabd','2cf5af84-abab-4ff0-83f8-f040fb2576eb',
        '6ae51eeb-c268-4a21-9aae-df74c38b586d','ff808201-fec6-4fd4-ae16-abbddade5706','34260150-69ac-49a3-8a0d-4a403ab55763',
        '4dfd543d-caa6-4f69-a95f-5ddfe2b89567','5fe40dd6-cf1f-4cf2-8729-92121ac2e997','903663f7-d2ab-49c9-8942-14aa9e0a9c72',
        '2cc171ef-db48-4adc-af09-7c574b37f139','5b2add49-b8f4-42e0-a77c-adad4efeeeb1'
    )

    # Filter output to exclude blacklisted IDs
    $Vol_Products = $output | Where-Object { $blacklist -notcontains $_.ID }

    if (-not $Vol_Products) {
        Write-Host "ERROR ##### Couldn't find Any windows Supported ID"
        Write-Host
        return
    }

    $idLookup = @{}
    $Vol_Products | ForEach-Object { $idLookup[$_.ID] = $true }
    $MatchedIDs = $Global:Windows_Keys_List | Where-Object { $idLookup.ContainsKey($_.ID) }
    if (-not $MatchedIDs) {
        Write-Host "ERROR ##### Couldn't find Any windows Supported ID"
        Write-Host
        return
    }

    $Global:serial = $MatchedIDs[0].KEY
}
Function Office_Licence_Worker {
  Get-ProductYear
  if (-not $Global:ProductYear) {
    return
  }
  if ($Global:Officec2r) {
    $Global:ProductReleaseIds = (Get-ItemProperty -Path $Global:key -Name ProductReleaseIds -ea 0).ProductReleaseIds
  }
  if (!$Global:OfficeMsi16 -and !$Global:ProductReleaseIds) {
    return
  }
  $Global:ProductReleaseIds_ = $Global:ProductReleaseIds -split ','
  $ProductList = ("365","HOME","Professional","Private")
  
  $ConvertToMondo = $false
  $ConvertToMondo_ = $false
  $Global:Office_Product_Not_Found = $false

  # $ProductList Check [1]
  foreach ($product in $ProductList) {
    
    $SelectedX = $false

    # Start Loop #
    if ($Global:ProductReleaseIds -match $product) {
      $SelectedX = $true
    }
    if ($Global:OfficeMsi16) {
        # Query the registry for Office16 in both 64-bit and 32-bit paths
        $office16KeyPath1 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
        $office16KeyPath2 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"

        # Check for matches in the 64-bit registry path
        $matchFound = Get-ItemProperty -Path $office16KeyPath1 -ea 0 | ? { $_.DisplayName -like "*Office16.$product*" }
        if ($matchFound) {
            $SelectedX = $true
        }

        # Check for matches in the 32-bit registry path
        if (-not $matchFound) {
            $matchFound = Get-ItemProperty -Path $office16KeyPath2 -ea 0 | ? { $_.DisplayName -like "*Office16.$product*" }
            if ($matchFound) {
                $SelectedX = $true
            }
        }
    }
    if ($SelectedX -eq $true) {
      # $SelectedX Start
      $MoveToNext = $false
      if ($product -match 'HOME') {
        $Global:ProductReleaseIds_ | % {
          if (($_ -match "HOME") -and ($_ -match "365")) {
            $MoveToNext = $true
          }
        }
      }
      if (!$MoveToNext) {
        $Global:Office_Product_Not_Found = $true
        
        Check-Activation -product $product -licenceType RETAIL
        if ($Global:ProductIsActivated) {
          $Global:Office_Product_Not_Found = $false
        }

        Check-Activation -product $product -licenceType MAK
        if ($Global:ProductIsActivated) {
          $Global:Office_Product_Not_Found = $false
        }

        if ($Global:Office_Product_Not_Found -eq $true) {
          $ConvertToMondo = $true
          Remove_Office_Products -T_Year $Global:ProductYear -T_Name $product
        }
      }
      # $SelectedX End
    }
    # END Loop #
  }

  # Convert to mondo if needed.!
  if ($ConvertToMondo) {
    $tYear = '2016'
    $ProductYear = '2016'
    $tProduct = 'Mondo'
    
    $global:VL_Product_Not_Found = $false
    $output = Search_Office_VL_Products -T_Year $tYear -T_Name $tProduct
    if (-not $output -or ($output -is [string])) {
      $global:VL_Product_Not_Found = $true
    }

    if ($global:VL_Product_Not_Found) {
      Check-Activation -product $tProduct -licenceType RETAIL
      if ($global:ProductIsActivated) {
        $global:VL_Product_Not_Found = $false
      }
    }

    if ($global:VL_Product_Not_Found) {
      Check-Activation -product $tProduct -licenceType MAK
      if ($global:ProductIsActivated) {
        $global:VL_Product_Not_Found = $false
      }
    }

    if ($global:VL_Product_Not_Found) {
      Integrate-License -Product $tProduct -Year $ProductYear
      $files = Get-ChildItem -Path "$licenceDir\$tProduct*VL_KMS*.xrm-ms" -File -ea 0

      if ($files -and $files.FullName) {
          write-host
          Manage-SLHandle -Release | Out-null
          SL-InstallLicense -LicenseInput $files.FullName | Out-Null
      }
      $pInfo = $global:Office_Keys_List | ? Product -eq $tProduct | ? Year -EQ $tYear
      if ($pInfo) {
          write-host
          Manage-SLHandle -Release | Out-null
          SL-InstallProductKey -Keys ($pInfo.Key) | Out-Null
      }

    }
    $ConvertToMondo_ = $true
  }

  # $ProductList Check [2]
  if ($ConvertToMondo_) {
    $ProductList = @("publisher", "ProjectPro", "ProjectStd", "VisioStd", "VisioPro")
  } else {
    $ProductList = @("proplus", "Standard", "mondo", "word", "excel", "powerpoint", "Skype", "access", "outlook", "publisher", "ProjectPro", "ProjectStd", "VisioStd", "VisioPro", "OneNote")
  }
  foreach ($product in $ProductList) {
    # >> Start <<
    $SelectedX = $false
    if ($Global:OfficeMsi16) {
        # Query the registry for Office16 in both 64-bit and 32-bit paths
        $office16KeyPath1 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
        $office16KeyPath2 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"

        # Check for matches in the 64-bit registry path
        $matchFound = Get-ItemProperty -Path $office16KeyPath1 -ea 0 | ? { $_.DisplayName -like "*Office16.$product*" }
        if ($matchFound) {
            $SelectedX = $true
        }

        # Check for matches in the 32-bit registry path
        if (-not $matchFound) {
            $matchFound = Get-ItemProperty -Path $office16KeyPath2 -ea 0 | ? { $_.DisplayName -like "*Office16.$product*" }
            if ($matchFound) {
                $SelectedX = $true
            }
        }
    }
    if ($Global:Officec2r) {
        if ($Global:ProductReleaseIds -match $product) {
          $SelectedX = $true
          if (!$ConvertToMondo) {
            $Global:ProductReleaseIds_ | % {
                if ($_ -match $product) {
                  $ProductYear = $null
                  if ($_ -match '2024') {
                      $ProductYear = 2024
                  }
                  elseif ($_ -match '2021') {
                      $ProductYear = 2021
                  }
                  elseif ($_ -match '2019') {
                      $ProductYear = 2019
                  }
                  if (!$ProductYear -or ($product -eq "OneNote")) {
                      $ProductYear = 2016
                  }
               }
            }
          }
        }
    }

    if ($SelectedX) {

        ## >> Start
        $global:VL_Product_Not_Found = $false
        $output = Search_Office_VL_Products -T_Year $ProductYear -T_Name $product
        if (-not $output -or ($output -is [string])) {
          $global:VL_Product_Not_Found = $true
        }

        if ($global:VL_Product_Not_Found) {
          Check-Activation -product $product -licenceType RETAIL
          if ($global:ProductIsActivated) {
            $global:VL_Product_Not_Found = $false
          }
        }

        if ($global:VL_Product_Not_Found) {
          Check-Activation -product $product -licenceType MAK
          if ($global:ProductIsActivated) {
            $global:VL_Product_Not_Found = $false
          }
        }
        if ($global:VL_Product_Not_Found -eq $true) {
          @(2016, 2019, 2021, 2024) | % {
            Remove_Office_Products -T_Year $_ -T_Name $product
          }
          $year = if ($ProductYear -ne '2016') { $ProductYear } else { '2016' }
          $Client = Get-ChildItem -Path "$licenceDir\Client*.xrm-ms" -File -ErrorAction SilentlyContinue
          $Pkey = Get-ChildItem -Path "$licenceDir\pkeyconfig*.xrm-ms" -File -ErrorAction SilentlyContinue
          $productLicense = Get-ChildItem -Path "$licenceDir\$product*$year*VL_KMS*.xrm-ms" -File -ErrorAction SilentlyContinue | ? { $_.Name -notlike '*preview*' }
          $files = ($Client,$Pkey,$productLicense)

          # it also install preview, which i don't want
          # Integrate-License -Product $product -Year $year

          if ($files -and $files.FullName) {
            write-host
            Manage-SLHandle -Release | Out-null
            SL-InstallLicense -LicenseInput $files.FullName | Out-Null
          }
          $pInfo = $global:Office_Keys_List | ? Product -eq $product | ? Year -EQ $year
          if ($pInfo) {
            write-host
            Manage-SLHandle -Release | Out-null
            SL-InstallProductKey -Keys ($pInfo.Key) | Out-Null
          }
        }
        ## >> End
    }
    # >> End <<
  }
}
#endregion
#region Tsforge
if (!([PSTypeName]'LibTSforge.SPP.ProductConfig').Type) {
$tsforgeDll = @'
H4sIAAAAAAAEAOS9CXgcxdEw3DO7O7OndmdX2tW9K59rryTrPoxtrBOEL2HJxieybK0tGVkrZmUMGDkmQMJpcLjNZQgkQAgEwg0JkBASEkjIwZEEDLyQQBJykBBCCLH/quq5VloZ8v1fvv/5n8+P1dPVXd1dXVVdXd3T07ts3WXMxhizw9+RI4w9zPi/xezT/+2Fv5zooznsftfzZQ8LS58v6x0cSsdG1dQ2tX9HbEv/yEhqLLY5G
VN3jsSGRmLtK3piO1IDyUqfzz1Dq6O7g7Glgo099MHJB/V632DTYh6hirGYwJjE0y5shHgMCRMQDFBc5HQzZj7ZXoHS8Z+NLT4PUfG/+TQe9K8R6l3BeL1Vtiyd3CQwLzyWNgis9zPwxPgH9DktoBPg4y1w5Vjy9DF4flSq9Stm0m2pYlOlmla3QJxow75jR6cJGXiL4X+lmhxOAaJXo5nqmjUJr3Uimac0chykTWQOZr8J4lczJk
xE/Iz/QkDopYzKK9FZlyyE2MwXdgPZcT9j7r0yxGI3Qr6Wc5aR48Sct82c040cF+bYBSNn3MhxQ2w6FDl85MjrLXEQq9sdZHEFszyQFa2KVqWDCAFX7HOBNjubTv1kChNTIchJ5UIw5OaAlLRF1vZtj6TyAJg1l/oyk6EeAX48DImiLRXBUvkQRC4B1RXyUwUQDx9wJ5g0l/pvZ8VmG4WWNnj1cQfq9NzVTAzb4tCpRBxQE6kSwGF
z9zExXgoxWyqKBSlRtNtSoAnutVpJzmPIQlVQmA1ZIUHtOra0b8hEBVyBhXVcTs8Y0CekypBbnOgiqK8LcByI8wLQVBSfBrnx6YgiEdc9ckEchqzby8SLESEoxmdiv+OzsFF2yMMgZTbFX5V9CebCtoUA8iHG8puYh+uGyIAAHNJASzpO1YupOcge4qsnwWTkQXh7mMtAtO0b2p6aSx2zhQFIJYhPvK7iTNlYpJIq13uHvCrS+8/x
VOjAaLwCGRw1mIB4WwFPRrw8aM4T9iaWyc79Pia5ovmb+93hkD1RziQQBdvbFz5sCzkUR3kOkyKbYw+VPGXvd7OEhBCwQLFH1oTsir30sD0kKVLFs8wZWeN1yvuGar4ubQ3JCabIWh+AULQTClOB+6P58Uokax5xRq1FOsEMuitsUsKhHgsgcQjLnQ3lXNSnaixRg0EtFYvtBckctocPg9DK7YXexHopNgrcrfFJsTQ8D4uQlRDCP
le5Hfq4UIp9o4Tn3ldi5iL55faIN1Eixf4CinBYoP7a870Jj3ocUJKug9bOdM7V5AriQuErbI8PmA11uKVyWYzXk7imifEGTW5FgPsg4HoQN90IqekmIjuSaiYx7w5qw1vySMAwnirJXLshGwaqPTUfVTGxHHTuGIj5WNAWX4Aai8VCdoAWGpBDUuxGNYrDjNp5lZCm1Q21LUJm33HIHxQPh0GzilLHYs6rUtyJVUkgNxwvXK+PZe
sPML9u805jZHthPKYXY6e4cqdaUIv5wyNKchwqlcaxh4kaxpO9/OGTnJQZsksuHnHwvip2ILCVCJRMkwVDoXTtdk29Hpiriuk2SB3HAhqvYcCguoMVWJklE3TIwTbAQPDRWNxdjFzFgbgHytihYq+z3NG0COcRyovOMIYkwdQ/D5NT7ZjGH+6wr+kQ8oODITt/RlB1tCRJe8ra0xkm6xJyKY6QW3GXL4Gy2EdFisbWjGgtargexaP
IhwVQrZBX8ZZ7mXoJqmEHqqEcjZEBmSUrMkVCLr0mezTXqEncXYS0AwOlmXLs80AqF0gOpM6USzngR0BxjQfo6RhXkDWdxDVXZI3PtQfqtwPnfYpvvnLkyBHejqS3wSS0DTlKzvxDMC3NLQI+/wbqzTH03S2RxofsYCb25GLlx2HlABQgUMIBy8yBA690DUjaQcJZE5LDIWfTLTjBK07epRRM326gCXkYYjxNcaa6OCcS8xn1GVmo
CgIbpQ7rcT/Fw9RPeJJAqPOKB8pqlCgOXf6kj82cyLAe4TiSBUfSsxTXbqy5whZOCJEsiSJIbGJqXsIFcaRBH66fnold4iKVUespDbtWqsNWjkpabaRJo0YHZLMDGcLI1h4mxGcITJqApIN7CqeQpgxSi6whLdpYIStOUBe0t6BOzd9nWWQaUALlUVMOhWssXNZYl00Ce/KRQIel76YMSY+isbV88OVISk5YT0qdQMVzqGshv1GUq
x4gWFr3a92TJ2soo06GnBmdoT6v1/q+DrqmKMr8pn8fOQIFtVmeHfLBvOOEZjXLS36KRy7EsZmQozPidnSZHLrfRGR6ZbK5bs00NZE5JQsVCmr2K5xpviSydbxJlxIs5F4d701QtyUuJ08BBCXITS+5KoVrLehIcBAIDmoE43zYUsfdb5wcIkD3LBvZWfqH6WMAo0//siV9kTZqbdzUzDXh5QTjvLmV16kwLS+1gtyXY8Dn7ebmmE
aBjXyG8hyZ9N9OEGgYWPSAVlBOnYgdPFTEoOhKnPMehzmPHQ5L5pxnzHM57PjVfJ5DP/F8RusnsGU92LiVEk9icVAgSrzMaaWkwGmhpNzjpKFnOCEwBTs1+8qgPJHzEJAjZJAj8oakuIRSB/1KjCM8l9OYy5b16zSKTGXEpIl8WvyZ+ZQHGBqNQKCYkOSQ/VDMYNZDk5iVC74hDDMLz5atN30DXFsFaZ61qTYwuegoSwYQR/ddyj0
sQMPA1nycnGzkI3hYAvxLsirouElAOLnWuMa4FuvGOsPuRK/WT4kMviejd2Fr78qdvF+8l/lMdpCh10rLqdXYmUQ7eLFrwDG3WiGfq+KAdfaM0HQBdNLUaeeTJq9NU+A7RdIQkpLpkhQWhOMnYXIxJU/T10K41pB0P2QNM3389dr4KNibqy8d9+ZhLAZDfi9aGzI5ezBt/V40LNGte9H0RVdFY+b6ai+a89idUDojtVBbF4qsVPdf
xd0x5F5Vjk3cXYYzveYQ0zLBdGRRrl+EMrm8TALpXgtZ3O0G58QDsk2vQ+dE3D2X6xLw3K3h+hIreGTP55BzFZFZe/ZgY9I8sGdp6LR75l7MQcczEQdHPwHOpFY/uebQwhxB98IlvuIKVUlsKdCURzShxCV3eiOqhCTz0qmTMejDISo7qaNO6mRqE9pMF1hJTqzoTDeTM0pabXHfYXxJ7HKwwWG+9uxDtRR3V5JR6adKwG/cCQhyH
OqUvM70Zu7spLfgEyYKsO0DZGgdqSQ801vJMVQk1S2yUTUAQWob5UvqykkpqzFlg5niSA1icXD71LshFdyOIYSd8e04azlTp8AjPsy0Jbt70vTCqXNp1IH7pLg06twW6tBv2mWDlnfbjJbd6lsAKJ7UDsTwArzRbsI+gL9rgXPSI/jwp1P4CKRHUcJqhYONhlOnYn0z1SQAEQ6EFKbkpFSawBLLYW5JQ3RsJk7WIaaE1BscVDN2lf
dwDFFzFb+SC1NqSH1gQn5qJwancQ0PpnYxWuWEleDOQqwzT8kDnuRpPGGKjzcdbvoQDWnY0nqEKRH1xQm1h/KVgJKfOl3TzkKlEOwYJqXPQJQzqdn0PDQbUPpf2Wgfj5GzHVH9UrbcMi03OiF3fJqW0TwxY7qWcdKEjNRuCNSUpC2sx2egE1hA9J+FGlOQGudcChOX5h8GHx4YFc7OKC9nVFFTG253FVkYVcyUYvWMCY2HSoKlSkl
8DzZUrF6brauhKNBSEoylPocTtBKDaSFUppSVS6zpdRRGjBuB6qC4uwJd9NLUXs52dCGnKdOaaf8WFCEanJ46G+tI1xDjo+MziSXF6kMTeTVLy/j5xIzZWoYgT8iIT5ExkbtzCG/6+Fx6xsYT9CwdL0euz9C7oMxIfZ5P/8BC4vq9nOtFWbkOQ9gFsEt3DDTjcw63UC1ncR8L91UugL8HWKbvlQRJ4ZzypEA2zEh/A2AX/P1OzEx3
gY+2GtL77JnpP4S/uyHvdLtZP/oeOEFFNN8Du5c6F/lyHjkg/eBAfEFzQFAaNpoSwOGW+fzxRbSfiWjQFj+faQtEe6qS9gIUB6iAHJIOteJexwU4gF8BL8R2OBwwvRD0MuIXYt5V3EPxm3nqbJBV+iKcLfgeRjH2o5mVJ7mfIoI3MXK26UPBJM7yqR+2+ABuPVxMXSiCFi6hLjBRjtfSXt4hB2jQIWp8Hzb+Km9cyfQli2kWZ96Zz
IEg+kgwq1B7Z4rpS1FdkF9i+jKMVppeA5+fZxl7mLurcF7cD1ni7mo9aq4IaJ6eZdnnkNi/qWWmGG5IjoP4P16DrdjGa/FhH6/Dh2O8Hh859vEGekq70caMN2oA2pV82mKcGY7Ov2FmJHrMDakv4RA8MN5EOI7dOJ7GmzUAh8r4fA1AvR8/hlqLHQHWbO+L1my2bY8dOXLkWIjnbt4k7kaaMMUPuZvGq4imCli/JMTI9mj1Zns0Z6
AM8I+AgWCAUE2MAvIk3P+WYkdAJ/vcImeNNBKdvZnjzNV80Tp9z1S9ExRC3I29LI/wZ6RSVn8FqQmH+nv++EDWdkq1vVSZ3Q/lC7F8YdonoOO6G8yWveASMKTizHBagrSZ+eOn4kBXD0Pp1IeoIzPF1OU4Dj5C4JaZEcKDVR0hymqVU0eUtf2HNKbfMjM/s8KTnWaF8fmolbzC1BUoVynlBGRaEUYDtF4khUhfie5OgjlJFyK4ew3
0p6uQetCmBVBz7mEbOVU5GhxyNP0FdxIyt1Y9ohxjIM95M2XaY50XlmlrdJ6s7nMSuw7wx1f44z54jGN16rchFr8KbeMrGLsaCXLGr4FHORhyVBX1PewaOPWwAomgN1TuMWhJbJPUv2A5GFESR6cqxvei/xY/AFHpsFSNjuN1OBRAwxM+F/YJ3KLyGBNdEV1jF3JljRxI3YAVYP1mM+BNcR9yBHhUzMfaQs4dt1Tu0yBP04m4K8j3
jhbS6qFBd2+bK/C1kYh7sZJP3I2DRhVd2myAmwHlzYwSQnau6PnrowMbYwGYaNaJu3EYxg5+QWDr1+DmpwFuDEkssYJpKYtb/Wx9yBV0qW6s+UaylJa8jVjWrPtd0IN15ARTlBzgNVBhOCSzoCN+E7l94ZAnMQN8P0/qIDlzTJGD3vjN+qSM+xmKJ7KGtiDd9DKm5qclilyycW1IFtUA0FF0SYA47ALlVuyguIrjYnD+hVtmFiiyF
itUJB6L34LMX8iZTzzFXX3z3VnJxL3x2K2Qqu1bF2hPEfe4pWg+Logl1Avss563G20RDAKeFx3m+0B8G9sjxz3G9gnajK3xW7GnRqJX0jY+OL6+trCx54CK0km0fWQ3aCs0aFuMtmivsRsHFKHZ8+CivhTfz6A1sOYDrQ4NEfU75hQtRdEi6yYwdRu1EO028LGrmU3Nn5TSOCGFOqbZBAfND1G+ZlpA79IsmuaxqpY37qVV0QTDEH
LEv0IKHnTGv4oRyYRvx4jMKcD1RciluMwxUREAqNWApIQz35dwFvgS9jCwXe2GnKhLUy0JVItLWdOnfF2xCpy6hrm0SJFiv3gjxYoNRSzR1W9mqa6SpIig+6Dd+vzwFqP3zrC2i2grTdyJokkpOmezuBsnyWgUJypky/YIxqzy2YS+Ck3JIanparQGFmZaObvRY2qRV5uHZPUFF5nOQjcb9Tld6T3EvaAcv4PpG25Oq6Y7tW1mp7Y
R6tSIsWw2OznNXG+cGS9y0NYNg8Uqo/kQDZqbVx5jPzxwjGaR1qTvJNtvWrnyNqYOAIFukFGcSXvm4VwVzedrazIg9qCdWw+aOvlrg6LDdmRNxY9Z07PEFppxgcdg7JsfQjcITBKfyUPOaH7IldgBKe5oDsinBpabMXylvo6WqE7Fs39NiJ6KO5q//mfX42MjqRdZqrVoqcL0DhB3uCueJBqVCdRJGnmKCwqAWmoFfIqv4jwposip
r+GMtQ96KilyZI1Ehk+R10bWUk78LipdFMpJhJmk5KhfAszU13mVOcVr8B0ILwM99yv+il9JoQAwPjC3Ur0KUPciTXNxP+Ex6Pw0sis1NClLu2FqtPvZnruhcG5QCIrx5eRpOuP3oIuMb2KHmEux//xwMchYXLfmVHwge3d/CccZsBR3maQ930A672V8h6BcTFRAxkbiMMxFYqLUVuGFMpdzSeASCtiA+32KFHIfiuuvcbfLI9AFY
GnFhYyqhEyPVC5LmnuruOdq+34y+8rX+btu3CuFDuJ5A6NfuR69Z0EhvgTIKLflJgTZm1GZ06yraJpel0RnT2ZM4lHEzwqJP8vQULsqJJmWghEauG6NWMehIo1zp6LtBTiDeMdcvb1jO/X27AymZDz7MEkmNnt8KU4iGXXIJs2hQl7HLBbGzVZp1lxOfxWlTa5P/QGoAnYBljUnIj7LqNmgrWSGyVe0VbMn1aW+ATX5Wbw3Sy3MoC
9S+hl4Gv5v8FSifeB4Nh7A3DsKHBA0HmBL4ZocxR4L/sX+JL3yRN2cso3a+Z/WpwI/y//v9AnfY8zJ1qcFngy5YksVklNrFh1cvVn50PSgwxW/D4cqbY044idjATmzeYuOLV9l6iksd1EfYO42Bzt4qx51wKPvvxJluObWxh6StJLx97R8YZ0LC+sOJ38bZge7EnbGv8n4Sz17dAFO+gn+3gndI5j+aXPRTluKUNIjl8uyTqZ5PqC
MrT/L5NPiqWT/4GTZm2KfWgYwJxh1QzmWyFb3u6YMuibJwOx6Huc+dsXamGSe4ZHZgjazvR6+vzLZNkzoR4VXLnc5I5oCf7YW9fYWdZjt4dmKis8wP9DWgU/T4ZAdRkyiDKcJxWFMFDQ/8L0iWO6AeQeauHnHgxQ/Y64samfQ1D9o2qCp7KNfiPd8FvuI/QKSWKWlDtJgbY4Q8YyLxJfNYehj/Dj0WCfOFCZtM8v1ekU6szbZPoJp
PD6raTTqCBaYdWyG5zy+j2Xd/2k09n9kmmG9TnPY0auysMwnWDQsYsLpjG+jmVvfG3oy696Q9s6sfSXfD2pVP8LBi8Zg7yJt7wJ5vgY8oCoa6+AptnrJU+yGBxCTfoDGfepBRgdO8C3Ea+W4GD0UC9mZugGw5PhDfNg+rHtm6UfQPKgXGpnxEBIb9qLmDGKnsboCPhLRZAHXHqXlR2Q6bfgt/tzi+GPo9T1OCnUoAcydCy6YeidUC
Q6U0RKvOPYBUBT/FuIeskW8mgI6KzyKI9Zkx0NbaObBNak4BwcpOSOKmuvTyUt/m+id78ukV6yQ4zBEJCyMB0AamToCKFpn4ru0kx/g3ukHZ66A7PQTVNl3DEw2V4hjpxRWUsliFXSEcxurPcDslXr8RjYb01EWRwCzmmRBZ72a3yOGkDhIFh6ZmFeoyeLnmHuoEGXxCbSYRQqVOQbJOv95FfkW/supJ5F7cuGn8H9lzn/K/0EhO/
896qNQl8b53xo0svhafsKS88zHyipZIefZela7T+cZxL+k80xkpwJmDZ3Zo8J7nkL/utQPXvN3yGsGhfsusi7sTSRk5wEfc6l1mPs0mTMYUAFI6fRrG0UwN8wwzxX+JHNYqyf4je1ehznGI6xljX4W085gxcNqSYY+l9cZaRATs6Iz499Dqv4NxePPIOd8MLfMrJBm0fooZG96HsV8VYCNqssUCDA1/gNAHGuBRuLP0jBUt0BW/Id
kzeI/wnHvkWm7yzIR7GKFl7TQwlbdCdiwuFUvoGe+ehs9C9Tv4jMkwVqNjjwlmhVZcR4IuZhGpeKiNiyt8VZoFDhkWCVMN46hKMikJ/CIJqZ71N8pBn/s+rndcAY/yp0JYG9lSaJBTQShAeyaujCoNQWceBc5YWb93pL1mZh0R+j/JJPM1j47k54IZTAJ9wdguY57yLhXsoP2SrxO8H+AVXKk0pvIlWzpH9OeUR7E/kwxj2QT0/fo
G0l4HhlGEKvndYzQ4Yd0AqdM2gRDnw7WkKyBn21w5NL79JDWXMAWcYvofsEIdGhMc1iYBlKLMPVfQLZDXZILHcY1Ku8BFCiIROjwAQws3CSFSQoGlU2Mz8Jt4+e4CfG4ymX91ZJ6IlRhNyvShv6hkPZGxgVUncK/UODzKL1TWcuKd/IxJrLlbMm11F2av6CzrBH7ZddIt1tIB6cVSL+UWrwjk3Stx6ItnuKnQOzx59HqXc7JsfqfG
kHq87m6pbKcV1W69bEv4xoBZQkygBU6ezJMvlQBf8TTUDCCgtT3/Z3QE4b+isJUXx5UPYZyi8R/Qtobc25ie6lkWI4ERV7HTvQ15PgL1EGbT47/lGbO1M/w4TLOy2Ddq6Du+RPqLtTqhsktZj/I9iYcMXbQaKVwQis/R6lmb8JyeAF1DzwP/v5D3L0MN9JzsDHs5HzkL54YHsf0uRNwl0+Bu5zjini+h94xabjh+C907hEy7rByZD
aJjhVT1L0iS90rpqqbkBeJ4fGl1jdnk9rqmaKtnixt9UzVVk/2fvROUXdvlrp7p6q716hbZP1M+2cTd3cz/aAsACdaAaRm35AB9maCKyei8l1EDVH77IJx2zYEz2P4dxJ0npk/PPzh5Q+fqB1uFp38oLFDdPGIlD6Ib9qlcSR1pjyORM5U7OMrGT9H3ENPzg7tE4AJ5+I/hvYXTNxfF3evMggFYDUCL+LofwkDfvzTmvwyktyEr75
h0fAKo082KNuZ+iXS79QOyWcci9frd6V+ZdQqFeKaFwyMK/Vr6miiOOiIv0pdhdlGSt1IW+k6FuS9hkbt1+DhOw6H8y2vpYGQQxCbf8qRI0f4wb7wpLP1+jcR3IZezeY8qb+XbmXXHzLP0sHYZgsnnrMXpVKSwTiyqukqxJW47MCVOlOL+yQuKFJR6D+XowM6IPKzZ8gkxZ5+HTnwBtIWDkmJOUYGsU/CN0ZS6k2NQVQSmBHBw6/S
dsWBK0lZkfUvPvjSEmbW+bug7xMO8BfSAX5wMucvh8y53AcBg6+fQ8NmbakzsL3/4dMEzBEFGRkWYjMLIK1cH227T8C3zqSUtt1LMH4ij6Ol4NppI5vFNdRGNoa0lHdzLukm+K1sET8PkHqLhq0ipd5GFuNBgC8THyR+suid7HtvLlYyy1w/H4DnsdZ+IsVovFHXPIlNoDOvkvI6UyBPiZ9fhKVEJ0ufg91ykkUYx75BHHs0voTIN
204pGOPyOxCHHtEZpKf5RS4ul7NFdKirhPPcobZjnPM869XH53ujRa6r0G6af3zv5voA1MTrdO8fa85ZtCOLp5Ec9iTqMYPa36D5E7gcog5HaQCkuxM/RZbSOSCh7fGA2JFCwF6i/s7T2oVSlwFdTt68lTtVVraM7nzGRv77oTGOmHOsDuIc/jWTTJS6G1mRgrh3D4J53bNP0K57gGaW6w0a0MOnCsbS2zNJm1vYnZQJGmDQ2nhHy
3VPGhM3wFoVsKNXxaR3F7gXxZZ5DaJgVx+5axuk6lzu49K25bstM2w0KbxemrCfv6phOl0VW/U9crBktr0LGqHNtD6iul30RCvZllP/Z6EyeJufJAHDpIg5/sWboEx3Typ7xhfw+hgzlpmnl/BfalWzgvETv2OJsnyE8EVvxk3zHYjsrgbS8ZnC3Q4FfHkffpnhBMa4bn48lsngB8/1r+zhPUgazPbI6ozGkH63RNq1dYyWB7P4/L
vNCeRppWSjkqaNJm0ubhGAgmydvIVfs/4OfyJLsCtU7oA+oxuTwwG7XxGd+BRWlRhG99bwN2WE2B+IbOlOCx2CwDTcDnxdKfEMNG0WgAYZiv1B8YP9tu5ol0KimbP7h10Z/UOdMeA+wUL2c77dL+ggD30gj5G7OztT+XHzZ+BH8kMfuCwsWlbT/8NZnxpamb0HI0ZOi/Ue0xe3P+8Pi4zfPINU/jkG7L45Bum8sk3ZPf3N05R98Ys
dW+cqu6NFn/f+L4exso6q9++3gpsYOaXWDZeswXcYHXxN5ouPo5FGH+sI5t/T99h8odP9+vtul/vwJ1S9OvXcb9+vebXb9D8emxEO1EwwZ/fBu11TvbnTzaoAsb0IfAe+Q6FIPw/ct9BSn0r07kW4n9CjXmN60TJRPeZn9HhNnoWm73MnPvxXc1xZH/2DbktPrNHlDWfGclJFGukyPFvox/3Z0a7rJp/K5tuqxTNXUtfh1b8mH9P3
6bLjJfnvNJ8znUWn3O9xc/cYPEzSUR//qx+5nf+Qz9TZFcwuttAyeC1O7E5yIjX+AnrA8bM7XWWH89dNZ9LJhWkYQ7x9food2lz3TKevkEf6BDfqI9zl/61EMnsSv7Ko2Sys6a/90iNm+du92ent89C70N8Nv+vEHvNlMQy8z3N8JmZ+tWlfYd0jEazlPoLozcAGZylz4020hRISHLqffL1IvrnRtTdvzLtc6Nv8vmz21J/08T6TU
78h5U/mOEZPjPJM8xIIZzvT8LhKSgz3L86YbLM5k6lYwF9sKX+xozP8Ij9z09iv5XvjR2mnqzM3ubsrHoydYMvZGtQb6+u1fT1zprg651Mvt4HaED6svt6mzDZps7OY6PqPAhSf4dUI7efu3abuUO4yXAIw9whfIo7PZusDhHZ8K+a/t8m3f8r94m7+3UAP9WSms8hWuNPkre2mSYfzRvclOkN9meCGQ3yXAu4yeor9luBTYZ3ppG
iO5FIc6XpQxod1anS3MeMdiXLedA9Fv/R7IdWQsrsh/Sf9EOy9kM6ej+0NdJtQMuSDB/LMnvtMGcv0nbuSMLyrkfznHD14TTtFAKGoVLsFkuFOYapQsCwVYrpQmkT4oWTJ0T9JLOux7nszH3mWuqWo/Vhu6UPD3Hn77/dgUuO0gGd/l0XZfXtklP4X0k2ef966xS4W7P4alun8tW2ZvcDt01R97YsdW+bqu5tFj9w1OIHbrG6fgNW
IJnp+G3NBLdlgkmrW7jVCmzL9BHT0OzST/UR6ZFtD1gECVNMTr/BvcYt3Gsc0LzFJOO7wFvpKVO/Q04QuNP0HnXfcdlk33HQ6jsOIfCh4Tv+Q/cdD030HT+y+I7R/52+46DuOw6RMXwdfbN/fmbfcYXpO2J5zjHNd9xi8R0HeByHFuef5kdutfiRJMZ/flY/8q3/eL/yIDyXa/OtwXd3YhQm0n9o8+0v0GLo35Tj9rxk/aa8Q9sDl
Eml+fJRJo3mq0eZdJTvAcqkonwBKZOGkvXwHYrixE3S/CKfuC3SzCVB6nP3+EWmzbshO+07stMOftUr3HP4rxB+4RSEW/ycM883dRDaQT0h/2+pRr+U+pj7f0fnOPmE28gnHOI+4b8yfULixSe6T3jLXH2vVG+v6yjtTeTSf9jYbRnO5TuTnMuMFMJ5dxLOu9r2JdPvhuieLONjPrN+BvRRnPq36SOSxB6fJDGLj2jeDSHSWdAsND
R9Nj2bmoAnshCgt9/RM7WPOkg+6mE0VEPZfdTtR/VRT+E+6jD3UbcbPmqE+6j/w12m7UfzUbdbfdRTsvqob5I3iI1EdB91e6ZTekommNEgz7WA261u6SlWYLvFtzvlKD6q0VGdKs1HzWh3Kh/V7IdWQsrsh/Sf9EOy9kM6ej/m8n3A64GWEzP8O8ssOWDOkqT/ho9q7O45LUbOaTFyTouRc1qMnNM0chbPjrT28snzbca6P5edep6
5f3nt0ejut9D9iuGX/jeIvmpKoi3+9Mjns/qj6hR+oJrFH01PgZvO4jOmp/IZCTnjfIdI7554OTQjkhtU8lTTawwbDqGa6R+mraBk+Jiq1VNMm54ibwt0HdfhoPfcV+SPWfzh4Q8vf/hs2r1kdpvhM0r0VSt4jMQhEZxDbIHT7TIPPXqZ2gimKX0ESp1p8NHCG/qIT7+e5DDT74jkc0IGL8yOWXhydF5k8KCUu5QZvNATtTZ3ZuXJ
RGboe6xQmNxEm77XqieI8lGYI03FHG39gOc4eib6zmHj20iz71Jm36XMvkvWvkvWPnPHmfhOZjCD7/wdVW82vznRACLbyfSLhdwsLeL1VSzhZPShsxc/ZPuEWzn8rNqZYgIOzwwnOkDHBvCN6H3aPvMZ0N6qCf3VakgJArbbCOMbmqIXH2b7CnOOTYchLaGvgvcq+SFhhiUBzYJN0I5tg1mITTq2McE2FLD2jaY/gP79as0fMIhxJ
6IwryMx6A/83fAH8MJBJmueIjX6Cp/2Y5M8RX3uL5+fuVY5ybIPOUZ+m10gvy2jFfDU7FyZOJKccggZnhqRCuIw9iH1Pb41k/syd6q+BDQ8OSULhjdD3Xp+Urey7fHtE9NOwB4fszou9vGd5LDEoU7QtpFsODbCIT8EHBR856Ew9dQ8/Tig+nP0dXrCbNSWwg+I4y7sPE/dRqmLJqReQKnHmqlfD2s15NKZVv55eLslPaNmSp1UM6
VOrJnZ6NNdtSmifRBb7hL1r0fCHhkkp66ELNWTz0Yj9AWrVo7GgZO95GBsnX4mXTu9PTtfvyTJbvkaEM++etSb8o1PhBoYfShhT2lXWgRnoXe8AdeI9TyFSXSfhz0opNwoURmvZvEonvKZ6qwCNmoPeYNey8fNanuBfoaTWpBT1VCP105fTfhcnBaPQFcF+cplF/9Owml8FZqj5JQfz5zxrTjK/OrpUJtT8dNHvfTxP5em4g9rNwS
CIXwVcNJegQ7TF+rybnoarLN6oQE7OYvfK9RZLInap4+KogBP7EU6v0S64AENDSly1PVpdzw4s9zxYOANF1nw8CtrHU+74qFQw7vMirfQgleQifegFW+R7jrcMrMwE+1VK9qxJlpRJnVisYlGDNJbLc7Em2HFa7bglWQ0K+JNGr3F9IHKhZYitG+kk1BKRUJBJchLKUHLPRhK0HIRhhLUbrjgGhlyOFPH4DNT40KgsPTpjWxXvw2N
xrcw+tDVsQe/oSG9L5cVWfuYMKSEyvH+rPggqXfmEeNQLiSMYiSPqc8V67oj5lf6xYJKj1gI3cMz7dC9WSVsNBRWwmpliXZVSCgyRZOlSmn5MFObAFFxctSokqdE8RthKRRTYnTfrfr5ErrHi6681dO+DWl+0dJZLRtK0yV6SgyXDXRZJJDpjOegfWTqR1hVhDeVD8j5vKkCpYBfrSs56Ssro7J8XlmBpbKJ41qvrhDQC3l1RUwp4
tcSw4Bxp3JwUJcl5gXL4n6MTmPKNLWhVP+OY7oyvTyol1CmpQKCdhSnLK7g9PADmB7KDoenmdODhqt2lloYo6X1WtOAIt6BIksH1O2I4rgYe2CnkOxHqFjJVYqh6D5St1y+kojwRQQI2JafcMREsB18KaEU64cbJLwoCyN2um6FryK+QHyn0/z0oYF6fqm2mA6VKCX8e4MZyoxyJwBBMtmHfJNudcoFOFeD7fF1RPztpZZz7C0DfH
2P3yDgPfftjO5VpGNTeCfTuXY6P8uetPO7N2l9jfu5eAcIRL7iyLwLqg3S0xB50GG9w8lG74zX8+8TaFSoHxtUaAMEZrC6KBv1gPNwBU5fOXhtBizOQgLe4BQL2uK5At3ghEdr8UAmPHajSIjbeIVTHsr6ZX6F03TLAZCMvUj9NH931OACP/vRyCoG9LMfRWz9aeY+JV7ZtsH8LitjBpyyOx6WDgt4Id0z0FAqggKaqf7ViHtpTeq
D/uVTr8CDs8cLBDom45IVh8mDVCEJF7KLdA/Ofjg809I/F/EoJAGTJM4kmeGlzcQkOYNJkskkaSKTLJ88qKUx67cOceTJBlZ+vs6fg6zieT1eye59XeeVzPCupI30PcYE16CckQGLxMHrkwKiNRtnfJhr1ZjOVMan9Phm1H3yXIoFuhCQvrR71MDjttsdrfFEC7x78HcQfKq7jI1KfEw+ROshfm+IL+iLlxB7teuxJe2p3Y4UcpqO
fshFzg64C83fxn4prmg5IWm32brC4VQpmhjFpd+z7Io9ebt+ZQugx4xYroHq/FkqKmjZWRLD+TwtHPInqgGOx5DaQDBguadDcSmOqFvxR9as2742VUZ6gRBeBeHkd/9WPA1FaRnhZE24AcLCoSBVSEWDlqLZ22CIgzMoVggzmlmhZOUQ9CKewZPCbB3Nz5KonU2f2hDgTInfkcMM2FxKlx9xrymiRMhrKs5wmnSvJFZm+AQuzRvg7
hLMUvkR7g3kaw6ASoCMW9Bgp/N1h2lKzBhz377IxC44OrbTxCw0MAuzYSrcb0HMok/BlHVM7rUoEZopQMhieVBdmqnz4ELcCCmhPJiO7DAdTDUdhfEDIHM6suvTUZ4+HTktM5H6LlTJL8WxfCc7cY7RrOtc1lLM54OFEHwdhPh7m3U+sDMY0LivdNT5QORXw+SBEaibBtI1TKKHJapE/klyHv16hJulrrRkhqDEngklcMHPLe0YmN
JcbmlFfc+jgH6zgAymw2owE53YDt10ErWijMOjlOv/RRyxZGINWvb52qrfzi3vOdx8Wyyv+uNpxhewE+7pIB6q7Oy/mfPS3wOCcU/DmXiHoj4vAaOmWJkBl6q48XVL2cyvdvUtmd9puNRhCZfmFrs1S+yZerA6uDckTXKGgA+KlHE5Fd7bKCEv9WXeLKYWT8+yzts7XV/n0R6UItP7SBEXYqDyaIGkmTn8qsGZOQ66a3BmjkSXDc5
00CWDM8N05yBY8gnLBrrix624+LIBl50wNCYSqjhpdGmyAxV3gIo7dHmdO33Sd4B72Fv9gk/fo8E7jDd9Bt2GGTcAmvoM1hcm7zpRg+pGWx0S2mYWj/D0QsALzNDxJHWrEWfq4zOy648xFjmNRWztmP6too3e5fYDjel6unFQHIe5Alyr3fiwmeNGOiw14CV409ELnyHo+7S8/GYs36iVP8DLH6DyV1rKN00qj7pbLdB97f//1F3c
BoFW3TP1VidoqOJUGyAv5flf0K5NUFAOuYNuSwnL9/bmvtYedp6N65z+uz0DxE8yO9od1aALM5Hp/F425DtwBL8xUBi+gcJPG2yp2YQRScXpmZ+aQ08pNRee4WjA8oNKCdr6E8PivqFUOW59On0ZGucy7+RoO8G8T+b/VZsV/ytt2vBeGNyrV1i6krcppuZRG7ZwqgqrnHCZiF5HbtFnq6P6M9Uh0vnobdnqwHtEoGPqM6gotTTW6
wQ6OG9L1dO2csZ307Iz1UDTV+ZVKnyfmOaJOcxbr38jLbP2JWY/YM5mg1lpaLTQ0PQZaLCnmqcgIhsNHUvN36jKhecQ6Wd6PhIh8Ra0316y0Qfdblo3wOCM4atgv37xLJWHSZ5tJx1CCt2AZNxOiytGopbfPTihrmmZdaFMopB/CtW1QOdHfRZxGnrlCfJ+vBTrFY1fTDuT6b+YdhrErDlnGDm7GNO/8Ud/Z5jeX1TIezA94diDBd
2i5V0GfycRDehvbGW6X5Fe43gtcZ/kcsbBm5bCpi16wbBFkgtXS1LILsuWH9iIBYAA/iMbCq0k6XN7652uaPQAxjuZormWZFiMRuOWq5qcdnTOcUk3gykSXnAQL9No0RZyubP0t0csMU3Hma7haIu4000cxRnyJZjio99gAMrYDtLVhbh6hlXRIlo6R4q0SH5EixToWYUFPOKewFoP3Smlvg0t0Y+SeaF3sMKWfLITl4LIIWBFKbH
CXuFyiaQrCRkiqIDmClGRXaRtikSPcPxYQbsdWTS1ENGc8ULuoWQslCR7arGgfwEM6x+iSpqtUWWu7IyY3Yg59RhfNIEK4714uM5WQEAjNJ4KK11igWVHH5gbm51lKoVJtlKfSsOTp1Kfa8IafNJEypfj587Wl+Pa3HvZ7E/dCznqRKv+DCpQZ8SBHzjHap/jt9A2hp77hWy5TpxZ1T9ly3LhhR1rFNeakDveigmhYIgv/0FF6W7c
7RtC3j0eHLka5NNWmbDqn3z9cihXydXWZbnWdVmu4qF7OfniLNdYcgJ6fjZ0tXUOUPsRX48Zy84psbut2NrCL4cv/PzBvMN5MJrFYF54+3g74AfzFPd4B494xzt5xDd+HFaVFwqoe+dkE4CiPpM1PYjMVRRt7YjxoB7Pv6SAc8a6nrQuJCV9IanoC0k/LSSRPVSmgJcpnIgf1PED+B44wQvhFe6T/SR+3Y8UX08a551rccmNtSeeG
WqHyB9E69rTyfJg0KYm7FHBwKk8iqMJg+czjQ56B4Sjgw+n1XM/fWzYpxobjvD2kMTVF9xBrr5O0llY1ujvmCJkdEN43yr/cVQwW9tDMkucwRT7UYaWV8/NOrR8eMFb9qGVo3gV3xolZw2MTqc+eJyKS4+6+KLar/ibo7h5E8w9nJePepqrOMePR63MpT6Md5GOg2LeOjerYiIJhgJCPPNdBSVb7GxQCe5xWg4aaKD++1O0OagD3J
iGFHumJmtaGda00jFJiwN4W3giU5Uj2QtlEquVD2UodNMg6igRFsoTcU8/VKwUR9Z22LWtdPQ5crW/RBF1JxROlOxx8UjuHjePeNSP5k54wahvlWUasVKlVDNipVY7U6qEuf0qNewXYOZnw1RnJQyLVDrpPaNlC07J43tw3GiJhaARUSVafirTCMufSFj25jZkNPdpxJ1uxeYtGxtl+cGYZi9jisTtZUyRub2MgWZ28oiL28tYqED
9fCKbWhaqP8yaXkTqWmiqq1Kkx7Payyz7b4bCFeoKk5/VbIqRSlshzPUTixXpxQomW8+JP9Kj7Q3o9jNYns1+4j7GNqDvT5bf45iWcQ+Oje5bHCU/xLYHfxE4vgZtorquHJm0MXOzEG8H5Q7K9ZDN76ibq703+Aq0ceoEm2xd/GfxWDIW/1mscj/jHideKwVovyg3Xxusxn0Bbre9FlPKr1C1y/GEYHmBm8Vmy9q4dao1Fbh/lQez
cdblurqyAi8WtCScBgnOqQuQ8Qwr4fISJvNDyhN/ewF/fLKZdiVhlJcrVjTMKmUy/RgvlwZdsWXNn2KucYPD5A6KkzY8YHLBDY98Jd/crMukfdJmnce6FeKl/hQoBc0v0psUr3oN9D/lgjw6+4UnNWL4M920wODXyRs95bfKFALGwaNiFClFxq8xVOi/xhAsjrfRq4dipADfk4MO3F+h/7op0FJoFJqlF6KftQrH23GiK4ExA33+0
CiilCjFI9E5mzfR+1e6jt3HEg0kCjRuEeweHU2wdI8l8jC5d2IypM2vNLaIJjJf8Vq2iCyzHDinisuY4iCuTWk5itOSqq8acvhE5/9MFfgsqb7MCgJ4N+iaStpD3QSPkCKW25wJwR4KqoMAK4oStOhSSH1ycmIu9lEJaTYR47l6PKt91K2bW7duoSl8yanwc41Ze6IbKYMdNO52sx6HwvMSmeM/w0iG51nfm9dxezgk0p21bJ/mYw
a09+boez4GerrZYjsrcf9F2os/SmcesV1po1/DUTfP0+6gBFrM3AabuHsvui6YM3e1cSLtLLx9Nt5OxKxmIl1GG+8gAxLv0LZZwa4K5Dzwf2K8Fnt1yCniqDHvAaeTds4M275V1PaB8XWGzfI+xCRsj6ht9XKUie9D5rb2nACeK//FezxXcFpNZVVlfVVjTSOmOOic73O1jE0HbjQBL18BB3Z6z5g6NLINPxdjATDRw/MgbVUPO+s
84iubftyqLjyfcDHAj4MrNr11OLVZ7x00fdKRW4514Y8OfizU4g9LYetYWQv84d1ITZBwv8AdK2AS/d47ogvaH5h0uk8U50v8XaqElg5ipLuJ87Q8gXrA5YpxRXsCVUH+dLO2nJ8WSOwXFM7yY5ifM7MgxN4vwDp8/mdyJfZADoarKUxT+AGF5RQ+lPtykcSuzcHwsO+eMok9GKoNSWxrCYZPU7wycp5DYg9T+CcPppzrvg/aej+I
KaNCTO5jY/jrl6wf4hJLuhGngOKe0HmOlJYbcmH65VTnW76fFrjZOgHj06HmHJYqfSmYw/ZGMPyGC8N49KUg1Jb/t6I+9gqo2Je1ej7Ow1LnASVBdl0kWSyxF/Iw7g1j/JFYuSCxr7mPL4SeMqTtXSj7I62sB6hys7sL3opJ7EAIw9YIhr+k8G6GoZKP4Z0UXyFieLwfW5xZjBwWYxi/hPr4TgBDJYR8+BeFfYELo/hj8rUh6J37L
fypUS/iPEr4ySDy7U0PhltKMeVzxOe5xJPWXAwvpd7NJj7/nuLTPFhz2oXhumIMHV4Mw8S3Bjfyqr0UeSVHEb+XuHpbHuI8F8F4F6U8lo9c+lUxcikUxpTbnfUBCfiG8RHCv7isXJgnrI8gr8rLMGWPguFBkHiYnUk4jxFVItU5n3h4hQvD8ylcRikfED8HKF5J/PyNrZbu0/wWKjrDUYu32M7KzXcvJOhsMBTnFue7W2CEcKg3ip
APRh1CAxpkJ2hMg1wEdWqQm6DbijjkJeiKCIdCUGuArSkb97awHLBYCP1KQigIY+5mgC73jntxIVRAeZ1hzMtl04jO00KXOhbCWK6kvH+5LnW0sJgG5QUQmsmqCJpOUAWrJeiGGELzWCPR8mUFoUWsnaCrihA6lm0nTFbCoTS19y9PwrsQoDOYCzDviyS8J0IpDn2doOMBwnLvKAmg8wSAsA/t3oQXv+U6l9MSxLxudhXUGWA1YYR
WAR7m/ZnKrWMPUN7bEkInsycp7ynK28J+QXkfiggNsjeJso+Ish3s7+xswPwRYZ4KEJb7B9RyPhtjRwg6Kcwhm4DQb/2IOcZkAft+TTBQ3MJOYzkEXVvCoQBBd/s4pBDkdnMoSNCdGmaIoK8VcSiXoO9o5fIIukmD8jlUdGUYoQKCFpdwaCZBXw0jdDqbRdD9Sl0xQnGi+jENmkN5ITuHEjTpPGNDq386qxBsZQFWLCO0ByHAjNKM
sJdVAcTYL+149+HZrIagHxN0EUAewPzEgd8PfQnzoL1bo1juGsIM4F27AF3L6gk6gaADrFHIE/hvU5/IrmPNBLVlQM4MCGcLE7pa1CFJOk260bd67xHpZghtNgy/RuEyP4Zbwzf7GtgvlNsgbPdhuJLCTRS+HL0DwpD9Ll+YHRO9xyexEz13QZiTi+EL0m0QvujU02dByn2+arbJ8SiEuY4bIXRRWEXhx3YM73XcBuHTEAqspPBbv
jJW7PmeT6fzXuFZCL9hexbq/KD0RginuTC8j9r1RDB0u7DFdiemt+VhSkkYw8uCGP6F6DkzhDWECp+HMO78kmMW2138IrR1ctHr0HpAugviP4PelTGvcgfgvBzG2nYEMXywDFNOcOn1zKLWZ1Hrs6jFWdTWLKpZYC3yXdCX84S7gFdF9i85sC+PQi+etb8D4Uc2DP9C8W873oE6R8NYf0zA8EIKi6jFCzxmnHkRs6voUcLH8KkYcn
uv/zaD85NxzFyBvV14G/TuBekPEB5yfw/C1tybIazIu2dC2cmlzi/6CEKlDEs5KJxcaiI9ZlmWk6WsxpMCyZmzem/UgWEPxCX2LQ+G1trOL/LlcGob2JkO1MM5UH+t0G8L59QKq8UiCHMofFSIQfhNNhPCB8S5OQ3sEdu8nDDrY3VQZ3PsLkOvBh2LoMVKCcO77Rj+D4WLKeV3lPtTCpdTWArpetmn7G2Qsk7C8ByKL6F4ksJWRxu
0tQM0QWJPFiNnRjwYhkownENyuSX3DtCWl90XII73+BweduOrSLY//7z8pTkCe4+gq9jfQ90AFZdx6PzASTk21l2m552c42Cna9DKwMk5MtunQTcHkjkudr8G/UtI5njZGxr0t8IdOX5mn8ahT6JjOQE2rEHPFp6Vo7AvadBLhefkBMnz3Muuih22XZSTa0D+vEsBeljDvC9wRU4ee0ODngjcawsz53QOzRIO5ETYWRr0N++V9nx2
vwYtyD2Yk8/aZ3Bon6dZyGdJgr6Q/7l8AWbmUQ6xb/hvwm+WcFEEdvVR/4UAPTNTx7yQFbK3ZprlijT//RnHo34r9I0MqK3sthwTKiz8Wk6xAS0tu85WYkBbAIoa0FjZfTllBtRQ9kjOdAMaL3siZwb7iGj5rYCtz2abZnPoGwSdn+AQtj6bXaNB2Hqc3a5B2PocVl7OIWw9wV7QIGy9gm2q4BC2Po/dr0HYehVbW6lzIgBeybmVP
O80GJV17PpKU8/qmH0e5+6Pi74PUOU8k4P1rGke57W38Lmcevachrky9iJAM6qsmFUcYu7AryBvaT2HHi56A8ZgbgOHVhT9KqeJndtglmtmt3LIKRXdBNBLGXlvGNA7Oc3svUZeyx1KnnAsK2/i0AXOD3KOZe9p0B9tmBeYz6FxAaGLj+HQZcJN4FvhbwZSLQTh5cQI/cuJmN5FHPqB9E+o8xOCnmHPBfKExWxsscmzxZqk98deCz
G/CY34FsgtFN8L0H675G81IJvP5283oGJfof8EA7okd5p/qQHtKKn1rzSgW+U2/1oDekde5t9gQIXRk/ybjNZX5g75txp5/QW7/MMG9EDJOf5RA1KhvVMNqNG3y7/LpDp2vn+3Ad1Qerl/D9tLXQT7Yr/efzZb08KhufZb/eewWzVo1H6n/1yW28qhBfZ7/eexNRr0zeKlOeezAQ1a73nEfz77hgZ9sfQR/wXsIw2qd94Jo3qwjUN
S7hP+i9hzGrROvtN/MVvQzqFTALqEPa5B+4pv9e9jAx0cOtX9hP9S9qQGXRC81X8Zq+rk0Hfyv+ffzw5qUFPBc/7LWd1xHLo89rL/Cna6Bp0Se91/FXtBg8Zjj/ivZrnHc6ii5BH/NeyK402duJbdruXd6PiN/1pWdwKHvgLQATa4hEO3x/7gv459pEFzlD8D5FzGoZMAup6VL+fQQ96/+29goxp0k/ffYPsu06Cve+2Bg2xwBYfK
vL7AraaeefICX2UfUN5+9rIrFrjbyHszODtwD5vRzcsNBv7gf5jt1SCppCHwMHuTID7+HmHvccgpF+QJjzDXiRzKLQhAXr4G/S4/T3iU1WvQR2BtHmXtGpRX+pDwGNusQTNK3wVoTIOeh3KPs/0a9Gso9zg7qEH/LHlI+Bb7tgbJUO5b7PkTTcq+ren8M455wWMCVqg18KQBfax0Bb5jQGcWrQh814Cagk/kPG2B1gW+b4H6Az+0Q
IOB5y3QaOAFC7Qr8HMDsgWvs71kgfYEXjEgnLl+ZUA4c5nQ3dGb2K8N6MHohRbo3KJzA69aoEsDr7E3LJw/xP5t4fwh5l1pcv51NnelyfnX2YKVJuffYGtXmpx/gw2uNDn/JvvCSpPzb7JrOMR+5DoQ+B/mxE93QV8edh0MvMXGe0ypvM3OJwjnuJsAuquXQ9jbt9nFqziEUvkNm7GaQyiV37IxDUJpvsPKT9Kh1sDv2BsahBL7A+
teo0ODgT+xRw1oXeB99pwB9Qc+YIcMaDTwD/YXA9oV+JjZ13IIJfZvdtCA9gSOsKZ1eo++GhCEu9bxPJw37ULxeg6hxOzCBg1CidmF+zUIJeYQnt6gQ5cGJOGFjabEZOGPG02JycInG02JOYXCk02JOYXyk02JuYSuk02JuYQ1J5sScwunnWxKzC2cT9A5JDGP8C5Bl4PE7gl4hWV9psR8wpo+U2I+4dU+U2I+YcEmU2I5wsWbTIn
5hVc3mRILCBf3mxILCgs2mxLLFa43oMFARPjIgNYFCgX3FlNiJUKxAY0GYkKlAe0KTBcWbzElNku434D2BOLCjAG9Rw8G5gp3DZgSKxc2JU2JlQvXJ02JlQvxrabEKoT3DOjSQKVw1zaNn2D55gnPahBavnnCK9tMaVYJf99mSrNKsA+a0qwWpg2a0qwW6gZNadYIJw6a0qwRNg2a0qwV9gya0qwVLhs0pVkneId0aT4eqBcuGjKl
2SBcMWRKs0HI325Ks0E4fbspzUbhF9tNaTYJM04xpdksvGFArYFjhOuHTWkuFLw7TGkuFs4woHWBNuEiA+oPdAo3GNBooEu4x4B2BZYKT+8wpblCOH7ElOaJwg9GTGn2CN0pU5qrBPuoKc1VwuJRU5qrhOdGTWmuFs491ZTmScIC1ZTmGmGtakpzjTComtJcK5ynmtJcK1yhmtJcJ9ynmtJcxzfjwSajVNYb0MOu7wY2GNAHtoeEj
cJTVO5cktFG4TmCniFpbhSa0hzCcicL39AgLNcnPJ82ZdsnvJI2y/UJS8fMcpuEF8bMcv1Cx06zXL/QTRBfLfULT/I8WkltFtacxqF5wWcDm4WnNagp+EJgizBjF4dswQBLCtfs0ut8ObBVeNyAXg8MCq8QtJ+VFv0mMCT84HSErmLO2B8DpwiBz3HonpIPAyPCcxr0E9+HgVHho70cUtx/DKhC7DwTc6cw8AUOPV3078Au4ZMvcm
hh0YeBPcLB83l7f/V7lL3CGxr0b39Q+bwQu4BjfkH+Y+BcYfRCDi2OCd4vCtdo0O9KC5TzBe9FHPo5QBcKezXoBwBdLDytQYcA2ic4L+bQ26EC5TLhYg16yTtN+ZIQuIRD70HelUKVBr0Sm6ZcLXRr0Ncg74Bwlgb9EPKuF67XoKBSrtwkvEIQ9yMPCoF9PK/HW6scFJou5dAgQF8WNl3Goat8fwx8Rbj+chO6Q3j1GlPudwnvXsP
58lrJQuUuoepaE/NuIf9Gs717hRk3muXuFSoIOocNsnblXqHVknefsETL28Nus98nrLXkfVNIEcRH6jeF8wl6mv3Yj9DDGZhPabVcxLoC3xR+bcm7X3hby7se8u6nXcxj8GQNezpsxn8Wwvj3LOk8/ktLelkBvlt7/igpAntRwnB+kR6KWsqHuWYultLjX/eYcR5+oQzDmYUYrvZgDXdGPy1uTbH9b64nqWC4h3iy1Inha2HEGQti
fBGlYFxkT5RhqZV43oudG8J3jpV4PQ6zuxHnhFx8d/uujRnhImprr19PEZkawhpeD2ANt+Dvu7EH8I5GNuY0cazxtBPx53tEwH8MQgfr84uAP2ipM0k4eySs8zKqc28Y61yWj29Q/dGJmE/LE1O+J9O3QpZ2f+HB9AN4xI09Q+12FWC7qwpMnCE74iQJ53jC+WYp4vyg2Fq/CDjjBUj/JVT29PDE1o/euyUy1vAbN+J84J5YdreF5
pWUcqWsS01krztNmZqhyF6REbPAkr5oEmaHbMY/Z4lfbqnnC/7MsqKW+72YiclzT8idOhRZU162FBtbrCBva5Vs6QKbR9p1QjGmnEU6eWMhSn8N3ovALihE6eeQzre56HMNend4jEuAUusgtLGhCPjn7HI/cn6MPmy72Y/fVzzsFJiT/YAo/7iUxpr/aOEzMZMb1ngLjaBLizLT9XH3fyIlM261Qkwxw6n6xS3eMRa7l71HU8X/v+
vpqGJqywm5/7f0epfR6/+kv/+39dra06niZouT2+W5YhY7xu2e1VItdWamTBU/OibP1efc12h2wxlZphk5s9STXow7AhPjk9ving/vi7VfPD47Zvo2nx63sd95TV5Z5WXN/U2JmWvGbeyxkMlzTsPEkZuZcjS+2TJmupOnyJ1OczH3zbietwS9bIj5WBX8DbFC+CsGb7YYnqXwLIVnDJ4xeM6HPxdDz1OB0MEKKF4GoZtVM3xz0kx
hC4VdFJ5I4VoKhyDMY6dSKUHA8GzyeN8X3ovG2AXsm4VzIRwtqmIu8XP5deCNfxJcxBRxSV4VhMcF21mZ+ISrG9KfKFwN8RcDGwDz5ZLN7FrCrBaXlmyHkMXOgpTXfBcCzixHN4R/K7wMMM9RrmJvMha7iTWLz7nvZV3iy/5H2R3sGPkpCNeV/BBS7sr/McR/BrPkfqDzVWj3HAVb36e8BeFrvnehnn2hv0DYUfIhWyu2uX2CS6wt
zYPwyrICYa2YnztHGBKrcucJp4r5rqvYGSL2/WwR39SdTX1/k8JrqX6k04G3peafLBSz3aWjwgwWiX0ewlX+L0LK2dGLhZ8yXCVgqQuBqm7hKsAvC10n5FI9+9kC4SHhAmqlnN3v/I6Adb4rlLM7Sq+ClPzQHwVF/LLzb0K1ON39LwifD2PYUZIjlrO/umZDeGr+IrEOWv88lLrYvxzi2G451V8tPlWaI1aLddFTALMsdIO4X3w9d
KuoiKNA1QJq5UQBW28H/BcB0+/9tfhPKvtPdl7UbVtANGDcb1vKfly0XLyXqC0gHSgQ7nF+0VYgxN37bGWQcgWEla7rIGVF6c22OcJNrq/aysRbbN1sjnBVNE94VtwVuBfSWeFDtl5qZQOFA1p4v/M6oVo4Nf81W7Owu/Qt20/Fs33v2AaAhvcAH/kGcoDebWB9seXiAq0GTHeJG/PzIB0xFxAn3ye93cBO9f/NNkz4vVoc8ZcSzj
ALFUXtY8DDevtZwMMvCguIn+cSP88lTp5F4S+p10sp92LKvZjSh4mGpVw3QFcH7KjVI/az6V3aFSSj90n6a8VpZVdCbk/Jtfb94s3FByH+46LbIH5W4Z326zX+/77kYTtqaZ7wU/G5wJt2DFE/peLf2udo8Z6SP9irxS/6/m3HFv0O1JlSx1rhiWgdhB+Fr2JrhT9D+D57I3oT+yeNd5f4p8DJDtT8AQhZ9BTH++Jl4Qsg/FHJxY7
32QtlX4LwyrKrHF3iQ+F3IWRlHzv+KRzy26R+0pB+4fbiUyVsfZck2H7ryhOGtPSfhQUY+zcUzIX4X4vHJZft++EvSIqN9MTGcT4oBWtjO+i5UzpDqIzdA+GOwgehtmuU2+xrxS7leanaNlD4Cwk58GupzDbmf1daK1YU/llqtl3j+RDo/0HZQeDVS4V+eb/4bOG9trOh9Wlyl7g0WANhu78RwrXBBXKLDXW7S+wWlshviscJ3fKt
bEbJlfJdpO13gQTvlu8nCd5K2vI4pT9Okn2a0p8myd5P4eMk2VtJZx4nnbmVdOk5wP+H/AvCf5zGyOM0vh6nMXgrt7TiS76LhVcp/iqVfZtaeY9KvUf1v62lYw1vUw1vEz1vUz1vU1mXOMv1c+cHVPYTKvsJlf2Ayn5AZT+gsh9Q2Q+o7AdUtov4fwVhXkE12AWswU7j6AoqewWVvYLKXkFlr+Czg23c/6RrmEbN++xm0I0TqbZc4
qdXQE7mUm25VCqX6twv/sTXDL3Gtoopt5jSZ5DFmCEgJTMEzC2n3Fe5HSMcl3gz2mHhTE8VWNfjghe4Ubf3u99nAddVFH+LCURDnYDj5VX2UeB19z/ZJ4UXsjuES31Fnn5bNHYh67dtd5VBvDMQhzACs0a/7fr8eZ57BX+wGVIuhvgjRM8jQo58IYQvlZ4AKe9B+BSkb/acbesPBdizUOeQ5wJbiZKClGe8Kc9PKXc/5e63/dJ7nu
eXAo7uanF38ErPm4D/qGcB1bxAQGuGI1TwLhBQ094UbxYS3rXC92Gc/k7c47vT+6Z4jXCv91rbM/6HvU5Yvf0EQi/7BYQB9ksIc9khCPPZWxCeTrlnQS4sG4WfQGgXMO4UfgmhVzgE4cOU8jilPClgKadIdYpUp0h1ilSniLnF4rsQxsQ/QjhD/CuEcfEfEFZRqToq1USlFlCpxVSqHUrNxtOT3krmoTDETlIqWRHbBOF09jkIE+x
8CGvZNRAew74MYRv7BoRLKL0HwsVUdhOFeyk8h8KDFH6Zwicp/C6Fb1D4FoVMwDBG4WIKN1F4jnQKlqXwuxRukTE8h8I+4XqfE7zQT7x82zrC+DMfnrMYHpAQGG7KLWIC/WrjsQzfhDG2GJ54M0EL9HA+2PoDYA9eZJ8A56NCvbBIuEz4svADoUbsFc8SLxKvFL8pfizm2Rz2lfbt9p328+0/tf/VnueY7pjvON5xquNGx1cc9zke
cTzt+KHjZccfHT6pSJojtUlLpfXSRdKN0mPSB9JhyS6H5WI5LrfIJ8lJ+UX5LdnlLHEmnIuc7c4lzj3Oi5y3O+9xPuH8vvOXzg+cdleZa56r0dXm2uAadI24znBd7rrV9XXXY67vu3Ldde4+93Xu+9w/dP/U/Xv3X9wOT46n1bPSc5rnEs/tnvs8T3p+7ZG9jd6093RvkOEpJLznRmYlwOso87Np9P2Du+gEWJvkF6yA8JN8DOOlP
RC+TnEPxf/T9KPXNjEXbxe0MbxV2gFUngmhyHbTaeqzIBTZOHi4AtsDocg+B7QLDPVKBE/VB/HP00nrq6A/ArsaQpFdA74w+nIKxA/Q+enrIBTZ9SwP4jdAKLIHSEsehFBkD9HJ6YeJP48AhwT2KIQieww4JcAMUoJ7cMAx8P4hFNlL4F8L7GUIRfYKjAtYvUAosl+xmRD/NYQizAuzIf4ahCL7O5sD8Q8hFNk/YAQJ7CMIRZjBKy
D+MYTz2aBYwr4avD/4o+Dd7CSYgXcLjwnHid8TnxP32p6yPWt70faJLWFvsS+xb7TvtX/DfoF8s/yo/H35x/KfZcG5y3nAebMz5Cp0XeSyu73uCnePe637Zfc/gVkF7DAe3hWKmD8P9f4C9lpIhOdFbMSHz0vYfjs+L2U2gvezYnpezi7JxeeVbEeJDZ5Xs1tlhK9l79DzOlYYxecNbCXhgS3GnUXhZvZACT6/zFRKv401Un1fZft
j+LyD3VAqsk7hHWbzCPD8A3szKLDLGgWwhKc3CaAFL8xHLYgvFEALuheiFvwFwnFm38u0ka3/y3fzbzH1f9/yOvAzFdAmhyUtDz+xmYD3UnBi2jPeZPFkPH72vx7sdgMLgp6GWBP8NcPffPg7Bnz5BfC3kNWBdakDy1IHVqUOLEod2Z8QK5caoV/N8Hc1/F0Lf9fB3x1sq/g1+HuE/R2efxebheftxwmnsyH4uxTiX2Nx9y7xdGix
BkbuCNi1EzlBfX09Y/1jQ1taVLX/jK6RobHeM0aTPUNnJhfWNFSxBYu29PW1D6VHh/vPaBvuT6drqvuypGZNrKHE5r6+JowclxzrPiV5xsr+kW3J9KLNZuqy7jYEAWhPDifHkp3D/du0hJ7kmAkdv6ylref4lmrWWtfaUdPc3t5UV93W1NrZ3NLZVt/UVN1U09bW3FjVWdPRWtfc2lBd29Le0FZfVVXXUdNQ01LT0llV19Te0N5Rz
bo6RnbuSKr9m4eTm6pZy5axodTIJjN5LKUCtHQoPQaP3qEdyWrWtrKttoYtG9qiptKprWOVJw2NALwy2T+wqmtkDKK9KS2CaTzWuXNky6YatiR5xur+4Z3J7v4hFcD2IWquXz0DAOTJ0EANG8UAW9KTarUKG+ogwp88o451L+lYW1NVVc+aWjpbqjpbm2rrWhuqmlvqGxvrm6vq69vaO5pbq6qrWhsbq1o6azvbqprr6xobOzrb69
s765obO6trG2sbqhrr2UnqEHB76PTkAP8OrLqB1be3ttTXtDQ3NLVXN3dWAdPamuvra5qr2qqb6muagOcd9VWNzR1QeX1rTX1dczvwu7Glsb6ptr6htbaBgYBq6qGe+tamppr2ls6G9va21vaOzo7aprbGuvqGpo6q6s7mxurqzrqm2vaahtbWpqrW5rqa2ubGWmigsaW1tbm5qeEoWlnf3MBAuk3QmYaqNiCktaMWZN/UAd1uamz
rbKmr6mzqbGipq2usranqbGxoqW7qrKup6mipaWhsbWjvbGlrYN2DZ6SHtvQP94CskyDMxqMNg5qmo+TWHi2zur6J1dV0NLbWNtbXdta2NTZW1zfXV9W117W1VdfX17Y31jY1t0BOdWd7c21VY21LdWNzbXttWwsIqQ44Ud3exLYlx/pW9XY2MaCzSRd/M44stmBZamDncHIRW9CtDp3WP5bs2jE6nNyRHEF6UiPtybH+oeH0InZc
GxvsWdrG+GhDbWbLW5Z1tGNCzxnpseSO9uTW/p3DY0vbutrZuqSawudJXcvbV5zU09fS3d3XRbhdI+mx/uFhqhxS2pOjqfTQWFtqZOuQukNPBTytNhxZp+nJoy2joxm1JAfQHkBSz9K+9pbelr72k1asRAhQoKsDqV3prpGtKa1iPRMo6Vva1daxvKejr7NraYdRevmK5QhgvHdtN0a72rWIpQxr6e1d2dW6qreDtS5d0bakr7ulv
a+na50OUrRjee/KtTzaA9jLjyMZtPS0dXVRXldHT193x8o+KmIQ0LNqmdZWT++KlR19vSuWdCxnqztW9nStWK7lACuBkJZeTOleuaJ9VRtFuQwqu1aA1dnc2wOd3pas7OnuZkuGhofxuTIJLFPHMNq2YnlvT9/xHS3tHStZb9cyCHlS54oVvQBoDS1dmsGmnsnplMTj0EUguqV3VQ9rWdp9fEtrRy9b1bW8V+ddS08v6+3o0WGN8r
6eJav0FNBKgxGtXctbVppgzzojumzV0t4uTDgNLWJfH9uyGbSiZzS5ZWjr0Jb2/rF+NnraxJQtm7vBhmYiTU5C8ziYGkkSMIBBb+qU5MgyGAKZo3012PV+HAKtw6ktp3BoR3pLSh0e2sxg/KTUsbb0KH3pCjOaLpq2FCgsWe505XHJkaQ6tIW1DEMNbMfoFjY8tKVrgI0uHdqSHEmDSR1OAggUTUpAjafhsk1L28offOZbNTJ06k4
EcaxAnXzoDNCQGMGJKbli69bhoZFkxjgE9NFd6TMnpA1lgjAw+GDVasgYs1ADVDAhaUsmaBnL1BMczQOsn8Lj1NROgraMaXV1nAY2SKMCk7pVMFRbxnpO2UkQCM+SyiGNO5iuPU7cmVQxglMq6x1U8bE0BUHLwAAbHm09YyyZXpkc26mOJBFecVpSHQaCAOhOje6ErieRgC3DOweSGvWQAP7HQGoHGGdqseP0seTIAFiioQEGszSE
y5O7jtsJTxzxrTuHhgdYxwiSAF7NliS2vLx/RzI9isBge/I0EDAb4I9Vo9vU/oEk26k9B3Z1pYCnY2pquC0FcBpqXIYRFD1FBnb1DParPN7dPzAAczDF24ZGB5MqRXuSqHY9kDOcXI4Ja3YM07M9uQUfNDmMDFG8Y4QenWoSqgBujZHi9fRv5WjLkul0/zbqAzlh6JnwiMrBZT3Hp9JjbUASQKYhYr39p/AasOu96DURFQaAfBw5b
UhNjeDMs7pfHaJk08liXegWptI8nqZxqkmEV9B2PEgFIit3joyBF9Q5lBwe0JKQfEsUe5SJjJOtlgKEINSppnZoKb09WICNbtlsGYowXjJAk1dssDcJM6gOkQVJcxwY+Cl4Do8iiH0nPSfPzoBWDm0bHCNoBIOVya1qMj3Yq+4EEzKA7h1I/DgVVIfivSmsiqJgtHiEXLKlMD6hwR2b8bk0BYZrWf+WQQRw5LIOUG3sJhslY0fRJB
8HXQMc0kYOATpzCSB6KaYbQAJIT1AV2UmgeEnT6KlJGnFkOK1zU4ZFZV2ZIKimesboWGYiKOfkREuNxGutOkscRWpC7Tt3jBrpPJKmkIuwZ2jbSD/wAVjf07IabPTWM8yktBFD66UCQ8dgZCEMngI3lv9Pe18CH2V19X1nssxMQobMYDAIgSCiUMlOFigUskFSEhKYhKUNhUlmkoyZTMZZCFGoE18oWHfrWhWXWu2rtYqWulUtrVZ
qW5VXLWBFRcXKq75o3RXx+59z7zPzTDIJar/fr9/v+75J8jx3Pffcc8492zOZgT7q62zqbA6j1xmkDhytkbpi6p1OzvrZMNH+Pq1WGlcri9bghHn7cJfnATIQGGh2BoIkK9BeQW0jmraFUlEmQRoIOrI4nzitEIse1dbi7PWDaS6KlIKqjU5rtdPH4kSi5AeDA5oRcVWG4O+3hxn8eiITH1hSUrGeGnd7uKuL2mNtlcGgu7fdO9Di
CembWYkGYRmGjyTBAiMSd+q8O6d32CiHuyMM9Aea3YFeTzAxBGlKwwGGEeuWG+bG5W6vcwOXgsOnK/uTCG6v3+kbiHUoXcPtIU+7xwvEdL2wTGSNyEOvwgFj8vNRI82jCn5VAMshOrLs0ArsDwFOb996KI96X1W4s9MdoBhC+JrCIV3VAX7BUJ1FHApGy46w3w9dA13lUw24NHWKehi3DbhrSrnK2SViUbZQ8bXopAsddElQoQij1
ZZoTot0Cro0/SBtMmwT2zZlwaQO0ypsk6hQH3T4MQ2E9FGVdHQVDlLZbBl7Mg2Xhr3eFmK3j6RUdQyNUpXlUxVp81SlpU8VWDtwidQy+4qy6gi3B2VpUV+gFlpVUt7hduJci55uKHAVwtY5g90sSGAwl8k/cTQ7Q93CDVVGgs2VTq2A/kV9Xpc7oNWk9eBaSFeUN3/A0+ukw48ySUuD29eFIhiilcjfD670ULGh0u9hreXt6msNeE
TlisbK2T2kWnCl6JU1eVSlk9IgbeL01q2sr5FNzQ55Z39XFuEHyIIUCFlugS8QpGPJkiTbyBEJ+GQZWMiCQyu0q6q7RzrEdYvhOju97IZo5UbouG7cpfAKKbeoQbX5Oty1Z4ZRI/oq9eZzU9XHbqJUv6IHGLi9JcX5LlSC3g6+68yHanZvCHFRCSjcFCGdtKgrJm1dCILbK308CKGqNuL4BQZ0ffWAwaLNhSY/aU/IjgSONXp73RC
mDmILhLS7F/pjeBsIRfITa9BEMtbijJZaIBbKRRX11WQw+6Icgf/jDUE4HeFe9q1ER7e7oyeIArkODigs0Q7hEb3ODXTz4s/RAKR9ZA3JDsoMGhUqvXQlnjUFPF0eH04npKHPF1PlvP8mh9LKEB+txKpNlWvcZEK12np115lGIlYIRlcfyMt+XUAwrIvZHms8s589c2jc2g1+T0CNVNZBJu80fsPjUlGa9HRiURtbzlhtZV9/2exF
wVofKcXlbpcnoO+QzWqMvldhTUV/rFgL3DTSNFOMRRVXP5tyylywrZet9U21Gzrcfln2rad9kQ8Xa1zaFyJdjiDU7Yq1ss/ZB/0S9uladUHiMKhKWPU9i5iiuumBrjA57LEWkqO+sK4BJqYj4JHl7gBUdJCIoHfhpG4QMR9NNWi6SFWhpFSp1dfj6+v3ibC6+3WBJZjOySf9wZaHgBdl+Fo9FNC0fWUYdYfX7fYLR48Hl1CfX4ako
ouvSjjgVp/JPFoNbc+FGudAUyfXKOhBCBYILQ33trsDQkImm4RKC7SKKlZ5KHOrKgF5w+mSSEG7kaqBkKz3UAfnJ5xeaRUQOWhmnWJVzaZrkRRHlI1OHwK0ACxxF90UPKW44MBJ7U1c0jBh4xgQ/fJWxbk4nMOQRKt5SbWjKOoBS/5TV0xNJegcNq/G3TnaTH03q7ZA34YBQp0o19fQ14+7LrMuo8VoLb9DXvkmnV8VPkTrKnLoY6
6E2WVv6QP/IeohulFS0x1yolMxNeSsDFItGFeL+mSxTl2VekknR/tiFfwpCarxOLt8CJE9HUE2x7qUSFD4fVoMhrI/VmadFkt56lIeNGdI3R9fJy+p0eP1eoLweXxoqHQHo7pOuqT5oAKOjF8Jy7BuzfmP9kvHXqUagirBsJTLcY9oyD+oheR5UHSrOxQwbFOCYD849NlIfixuZ7ikwbgADwybY5Fnnw8+A8W7QShMDmAqfbHwJIi
TElX0sUZJFR+XNdc7CkxW+FxEa80Bdx2fVVklH4YLS3GwZUmxP1Zh0VBwiCb0xGW5uwvnLzCg+jqDynOSARhjz0401pXuMvBHVea5tRYC3uKB3Y76X9iQx6cV2+XN0dzcGvJ4g0JqFlmGJ1FfXwMt5ewFvZ2hjm5VRocqka5wImTVpECjXn4sigomSGnKeBE6MKhXvRAQhIaw6lr4U+f2+t3xY9QZ6AsQA2EuYCpdlR2QsyAbLVWM
YqMpSG5Vss5Y43j4QkFdzpR24qam2g0gusRQ+hJaXkUNVI1+/xCXY7j6VO0rnR5YUq3maAZyQg3iEAUbaenDaeVMDUxEVDqCIpoOqOSMgDqpPB12mLKEUFjK0BJ/A02dzR64s66m9jNAavLkVWCvZosEZ6mF8m8hwcuDbZ4+13JEegTdGeiVRUcDkQxKVD0n4cST6POvxQGFS+DBCNxD2gMagVAAaHkCwVBTQD2b0elKaBCdrqSaT
ldqnbpqS1+rH3JAngYwRgNsWK187CSh9nVIx0K16fZIQ7VuKXThQIDKQI456ZbpDRcnkLFPapdlHg0HKAStKXkna9JbIbOlDIeorHVoRbQq80GtWpFjK8FPVGBEEI2EhLKbop/NVzP8L6m46SkSPQnW8q5chlmjWx2sPAw5IkRdUAEPOs5LiNWlreY61Aw/LKRKI0J+UkTRoJrKHH1AcAJcY3aHqEQwlzv7pV6iAqdl++S9NdRBxR
4vLuwkNDo3ANfoaoKeTcqEgaxXO4OIUrU+FmwVdmkir5lCgWiSbhROSA1Ozz3opiWVZNAiW0KxiqaQqBzLsqmDI/TpNa3N0QB1psRC1yxjDdVODZo2pjI9MdDCI5n341hHFYfqQqlTuwJOfzch6B8QLQ4HG1hwCeVmGZsLDjckKdRDUg4EECNqPgfZxwHNUA4ocyDL7BHrm1t9/j6/bGAXiAoOreDmq7YlPskUFANbKtf73FptyF7
AH1WoD1L2pClQ2+tHTcgPUc1rFstFk6gWtcKBnybU1opKXKtFnagXLWivxrUVLbVCpFeKRlEjyuidJqZV8l7bKnzCKdqFV7hFroCSwdUpwlzKEy60hvDXgWuuWI8SHCbhQZ+P/5fAJzpRNgRrMCeEv1yGg1AJtW41QkLt4fYgah08O8T1EI8JqpGyJ8gtsf5+1CU02RIQAyKf3tZj2iB66XNvc5Yy1rTCAO4B4EEYuAEF4yIvO4Sf
t+ABsh6UXBhUyVvyYEtOvssN1YM8GkJhXGOEoX4vg6cNB3BfySi7UOvn8ZWoDTCsXp7RilW7GBkiYj5amhmWE6PdCr6biZ2LmQQ/DzDpQyuPh51PkYcg5wtDSoC+EKsyjLV8Yi5Wp9126UrFogi1YlGInxKUClHPY5Fo4HueWArhMSQFhEgJ0ZcFLesGfOhhjC3ATz//5KPHA7wCwCaIv06MyGeW9WJMDeA04r4K/Y2AW4xyC7esp
6+2izxRIAKMlJeBSFlwi8UMLoylqH9or2zrY+6T5NUreSsQhObcqPy1RBkVHNbXoKRpaHsVl74vFrL8E8vmi5OBh5SiaiY5iUuX0GT7ZPoe3iS/EF3fnDzNYgnIvhol/QphFhON0QUgWD6YJAYIOq3SzFBdGEdisWQYhkPn05yR+4PHHSHc/8rKctRy3SlM3C48/8oqzWhtV/IiZwRH7BHlvegljswFJOKHE/1dfJClbunluZL3Be
qolH7DeXOEODFf4RKT73r6NsEpWnvlMDjcP13rXw6InUoN6CnBo8ZpoxwslwFcxVitrZaVkpgQq4exlhNnZIDVgcjJj9JJzl2KEb2gGJ2wGOb12PkK3q+H4FlI74Zpvm4PCbHLid/DEApMjOHl4r1LnnJfXn5CeahhGepgWvljMjo98WjJ8ehuI4OLsAkPKwdX1MB1Kt2di0H6ybkgBAlaB1jiYTHNxdKEvJ8J4U44RzM8fiaoVCY
hZSphgAq+nhCJsWSSe9gm9NNGLVGxskQFs8jBODWrWVVqPxLnRAQReaPNaGQl2RFVdaJgtNHDhVekl9KHIcKhKEKZMJyNw1DGZXIzClV7CWpFZA8mnI22TaINUPpY9NrE2ejZBOEOMvWI5qQ+O8m2JX1bCJucka/GzYcL0wQhaoTNqgFcUST781Q/3YtBcXJ3NqFcotpmc1spaoaMFVjby8IPQTlHP18bE4OizS+JwoxBK1a1Uq7N
VrWyaC2fuUY/1F4ehXe2qIiOMdSXYQZRqxzwasUijC1HP/E9DyOq0VKDUgVjNpvbisCXcrTTtQQ9c/BXAUhVuFJLEUbOwV8eOFaMcWU8qwQwq7itHL0EnSAs4msF5lTyGjTfMLMO41ehVCNGL4mkpfjLE4aiKmBaA1iL0ftdyF4jZGgZVEELlMlKjF4NTEowr4x3R6qyhRWL9GhcGCf9J7F46Klxs/vpY1OudxOkTAZZbqWr2h01M
aQsSX34eawLo5roRJ2WyMw3xLkerJCWxbcNdV01Z5YUrEt5caQP2nlsgOU4wFpjPeMCXVAU21UQswrA6VasTI5BHXBbijqVW8GLBuBQDW1QrfbjAww4u/V00jpAuWLm0Wx20stAy2Lmrgut5N2RLJRghuwlqpRg3SKWMZKKTsh/kM94ENh14HQSPqqclzgo6GBaBHnf8rTMpc+lmOLgEQRL05naWaUf4VnJetGnemnO8Bl6XEg/x3
T2LB0tB9R48qZruE2OC0pMpifS9UG1loaVKJH3WI9fjQ+yxtT22Ml89cpgY3or+/997HPrcQ6y46F2mpdo/bBupn6OmBMrx486LjZFx+dPjJtMmWkxVyGGvTZCYd+VmE8jzfrGXDp9JC7JlfRriHL9erExx6VQlgOaxsEBcCNsy0qcqUrYENJsFBIXoraIbFJSM1yEHYkQ0mLg+AhYM/Uh5V/MUizVwkvpBnQzU0l1kKnXBC3AzNI
gxKLagqhDkatCywJeMcgrOjlukkZKKh2Kaa8qh4YoxjkuY71dyF/CUI5aFWuBOSjT2a9iy1vM+qAa7WSja5XdKGENkie+Jegf8srRW8H6pJTtBFmMCmV7SnB3se0pYpuSx1qEdAnBqFE+SSV9KURkZ52KcNZCgVFmohL3tWBCpcpJkIpr41zFIrBnJWcrqKVxWPTUNizEXooZbYBD8UBA0WNFXE6CIMvZ/Uw5t3KGNA7KUc3sEYdU
KA/3JaslmqFwRHklbC7lDuULWSLnhNRFm46jYuLwtjYtgssZ3rc2ylsxfbTeKIzKRNJJqqJDGbzRJQ7SYpsOShLla3BdTt+uFLnDwWRbr+ybJFKnWiaIxZey2PczkB4RP7oNTCPENW+xDUD72O+V5z4xM4cyRm9btXn6RFGU6JGH//3IfhUpGgH9rISt3z4+V2PzhvCzKSajuXw63Hw6NPfDLTaonEcuw5ItfoW7FsI4lfY5TRhST
qM00vx4qGGVPhpN0Wp4A8YE/WyNN9wz7bTjYIm1FzQMMX2JYI2i7ie0gfr5zDc/mxyN+8KUhzOEFXAvovscyiGtj8a1udAmlC3VMpXrmd8enXFtR5lMmXCuVAGPZgoJvy61hwBTQ9MXIycJE4eOygCf8+/VnWJcfODILvDUGnaOPbwvr0gwYtrxRszGET7vf+fW6pUPHmCfmMhYywLuVUIT4EOuZ44utTVBH/VREswBMjQAOxG5L4
ZkK5prAcTBSOWxS02GjwLw/9Osl2HiEkFhRR2vHp+REf0tnMoIsky6eV5YnSxP3HnU0hx9OgdLpp2H7mOFIqsTfoqma90s7TI9UcEeypbRcti9KuLTYiW9C6VlWbQj1MWkcisujp6B0XLjTlYNQCNnNCxESWz7nRzHyZyQVAXNCRKRgNhRH7eGpgy+Dpb6+EMyREZUlHdYRRHKskTGIX5vX2dFYP19x4gqnJSun0XHE4XztWA7l4i
hD1404dLS3VreitzlDhY/p06RUhzRE+ccxxwvVownxp/ZxdqJ7VoUnam1DcU99qjqmwl7Oa0/bfTcWTPF6dNHz8iRsSn+SqNKvtIoKNWp8aPi8wSsmkfN4iVIwJbGj28GxD6Gl+gURXOFJfGzHDyL6FrJIVS3UnUe5dpQn8hYpFwwkkGxeqhplRI/eiDlVKd1JDeJJce0Fko7Txgsa1VWVtTrMzB+fvAUg1DAYVmM/wVDpF7ukOhf
ABcufizpiV6WKZ/acTyFNfowped8vbkOzA3LmfNHx1/TWjS2lanaCErJHAfoPtavw2It+KCviyx9TXtwJnIcgNrMdrKa87Qyc6vytVM6OPPQza52rBx1dJd9Pc0T0wUj6ps5Q6UlPoMY78bG6ZGJQ7Nv2tNaUCY8Mp4BbnMrh1rTvgHeq14S3cqxDMdpHkl5jwrwYytyIH96Im7KEeR4BnlHBThJVV95LOVfhWP03fQCm/VR69Idp
3v1+VMtJOkhXBfLx+zO6NOQDp2b7BzRzgbjrCuFL0uFfNo9kif2Ve27zKkashLJpzhdaqV4nRefz41qsGXDKdvDLlUB6zL5+FiG4wU6HVOgsr+aN0rj1er11XCDFnF2ZhFnmvI4205v1Mjj5yGU0af8TBHnZCgHP0fl44tUZreG5xmWOJTkSb4EFF9iK2vaMuZVjBgm1Zfz2pTdp2sFZ3Jmc+aHsGrHyp2cKyrk3E4efyxJOX80SR
k/uyErXg2MDU1roT2m4SfmKNeCB/JdBbJlBa41PIbGnoIf6qvkB+F5gNKEueQSU4+h8eudPulBkPObO4wH5KMl8p+6FIyRZGt48DayTMN3TMI6lSNjrWFcr8aP8GywnjJ2taA/PS8r5exdLShdzc9/ZmNchcrGlXHGkoKQCuZFLUtINWbIp0aG1m/KkWrFlxbuJUlsQG2x5Mu/ALWJe5YngjoKtzvUe2QCQ7RTiGnnV4FG7GkP6dC
lyltIzNc43TMz3ldp5Wz3mfxgu56fPmmWVLi/ugbVQ9HkQ5OhkbBSUmRxIGyrpEx0dSKZdXFUFOBkc+g4HtFIcr9e2R+ZnK5TMbd8P9Jo/pX0mDu4HmB/mVI1ouf4a0gPgKxGkLX7N15rai/btaCytuuVX0F2Nhe6Gp7yBKlDlrN8tvBfk3yzW0cl5I/2mjvkTUVBkavkKxYPOPmMeziw1iyaxsFQNICO5yXwS1+B9eitEpXQBTGr
prV9TTu2LPFZo5Y2Pjdrh506ed4oAUpv7aO+ZuZuLZ9F4fwmp3cxZ2iqOEOTp9MO9fx8Mo9LtBaf5K5/fYUWfs65RGcR8nBvjl/H8U3WaeURGpw8fvbTgHqlhJmhSchsiiULCtkqz1GpntgTe61UxHqYNDH9GGqH+wweTom0K4+jgBOOQz0GaaULNO/5a0CJeY7DoNTHx2fyZIajeXV6P6G2057RPYTGxL7Z4m/mmTlG9rcLGKLM2
3lE/Nu7VkASGsC9Rn4aPmSv/Gw6UfwuPUB9Og37Kf0q773p5qiPaD1bPnKZOLLeEZYyfuo2J+4dCkO9xhj3EnmNQ3b0teCMIgWLjycF9G4Mx/FloLImLi4bnqWpVtZraP6qUMtflY9ky2JQh8PDymtiGYehWjv2rlzfN9XWU0bOBcpn5PGZvYRjpjYPkX8t9xUdMVGLwKtYhmgP2ttWRSXJu3z3iCsqtZKW3TxaniP94wktyeuUe6
jW1kvkc3xFGDnxPtAKPn8hjlq9QpjK5Rkwlcn7yph0xufGYvIX4xpFn1oGgKS2Tp2sqmgcGZXW1n8FbizLob0hWEFdcrwz8D0+O306GR7xHJjku7Hxqv18/KRg25dLH/jommd2HjkpVyTlCkNyrsFgTsHFlkVFKxeLkk0GW61FGA32yBe2QUOKQDUDw9NSco2GJHOSieYI+6DFlGtMS7MNZqDFmiLQYgOAnBSCaM1JQW+ONSfJnJF
pMGbZI48bJovJwpyUZkhBiyFnslCNtGhOCs+0YhUzls9JSc4VOSkWU7I5J8XWmpNixExhsA/m2AanpgqDGSWzMNpaJ9kGZ2JOdqpIMkzKNqaajPb6nJRUQAR6tKU0U24SoSRxSkoRRqvVmm4yWwhNs9FoSTahxUTNtsEigMJGjKhYTKlmow0DjLyxUt7wHGzUmCxAqGyTyd6Yk5Jlc2Jsls2Na04K/aRm2degkpYrqG+cGGdIlYO4
xa210ARscZygiwHLGtMAsd5sNlutRhDOQOPGmcZa7PVGs8VosQBfowXYYKgFa/Qa7DOIbuPEFNM4+5m0sr3R3oj5ZvsMI36N1GQENYgIFgwdJ8wghZlIYY8xRN3M2cOa1C0N07k4TqSbkrJsYSwM8GbaTRiNqbIJC2BrNlOyRC06LjkN98xMgtEbA2o1pURHAFmwGcVZRvssExhObamggHmcsIpk+2rwpdE2uMw22GrDNAI/z2hUd
0mJeWbA3WJEnQR0UvaERJvZAhFidOaN1cDYN2GqvQ4UIvEwgnZnmKZbbQNWoz1ynj1yoT1yqT1yBf9Gq9fIX+Ky2VbBzJbAuGirsEeuxwSz3SMLViClSrYBs4Y9hi1k1G0DLKqR81i81ki5XUO7sFq5yWnJNTKYyKU4hjggXL+G6iaFQ7oOCZPCguZGroesTIK0mq2AO44EINcIJmWOM5hpmG3AvnCCyZRli/ycy/aFRmbKPEJ5YX
ouEe0mllcLl2gMtdJ42arNlDIwL83EAGwD2JUsMMrpODQWYEC6IM2UZI9cbo9cYhswMcaRbWNMZntkH4m9FdIthBVH2WqdRIgbcURwISg4osxDq/EEMHcYX6FUrGNNGei2WsFGo9lqTsJcOmNQWKl0unMmpUHMGuUptWUqqY4pIULVYgZ+jbYBUj8GQ3qmaQxBs+DPFrkTegOqAIUME52yRqsxHYAGskw2q32T0ZxkNPLhgsowA+d
cI6byVqyyYj3RNMYeedOSPdYWeR3wXrcN4DjTJTUbi481ZCelgiqC2nAnQr1JmiqVJ1nQSsoNZdpG5E1b5BVLdooJFHxzjByDFgzLJHLKXguA2wZAR2v2GJOcmw2dYDWLZEM2oWoBKc05pJUzoHy0WUarrCmA1gkM0ZIt5ZWxN8qymZG0DVjUeSbEaUNZpgx7ZAfYaY/sNNPFSDSBTNoGN7ECngRJNKBiqyVlarab0jBqh3487/vh
HJDNaEymIgQIV9KZOVabKR3a2mxDJ4SKxsAkQE1cAUZDUqxjwN0oY8GDSViRyAClnszz7N0p0Pr2wjRTKlCzrwZVMJVsFtqN1IvFdtExzDZaTCkoZ4OtAJFtxiUlm7DO1jrM1GaGBTKSTYFwWCysrqGRvdNAu0ack7+qA+pVtxyp/7xU0p1frzx1f+LzNYZLug4CIzt0AFO1G8PLMKXZ6y1mi9VClivdRGpwj8HusrtMTA67y8Ir7
IE2MKm+cUodejWUjHZXhtZmRtVo12rG6BCiE4ydic3M6Sap2VwJdhqdodaX+LogkBacK6ZSyEoHkweG7CE2oRgSklsKpZqSzDCCY5XJwAgj74csRYj2mBRtp3NmtZ5kStWwiY5Xi4/FonSapRKwb4wtvNG+UVt4o1x4YwaMmeoyqvU2xtaj1mxFF1e0Ra2TTruTMkCUsjfi0KZgF1B3ON6QG7loZBs1wFFStUy1omzHn5kWpTkZal
XZA5cFWgMeD+R6nmm6vQbKuw6KOHI52S6rUisWOk+XQJrthaCKfRb9otc+S3IJZaNJipjVpJogCvZuq25PIDSZTJckiWuyCcezm/p1g8j/kUOZGlbmk3WmaQIUBChtTVPUbiS8InfCZA0YCQxZWTIF5ESa4USSyk1JhoYdGI9T0y0XMBo14EbjiaYMqV9oMpowu87KejHJ3g0/jQ7t29jS4J2YIP0WFMcJ7nj3BFP6kNlG1mDAbFN
OyhhSqs/bI/sJVfL4Is+TMbYN7pS3B9jucq85N4lvZtapB6SfS5weSwrhgD1yECAjhzQv9GGGdogMIAZZ1ZjDPIY8PZ7LoN5BGzTyENfFQkr2UHTQewq9904yQV2Rs6v/we4Inol1ik0T9NgP2T+T6mOLZ55mGs9EIaqkpaWl4wXSwLC1QcVG7iRT3QbVBiaaIQm2tjLTVI2INJYYimlG2zorwbat41WiAEjXQgZtbTR3HeTWYiwi
AFZtTaYJc0Mihxp6VTcUdjpLOoqZFtzSCQvo3knm+85qWzFh9ivnme9esPYc2/Npc5MpxqFvtxDJ9En2yfSfxcnUmEwfiZ+cShf6jPxkMy6R7fmGyOZRPn4if5QP9puVq30S76xc9bFS84vzC+lnVm512Euf/TLf5w6HAk7vrNzmcLvXQ/+Ezv9rPb+9vNxZ2lFaVjSnZLa7sGJOlqHFmEmfCMT/Bq4+KMkAIUg1wx3AH5mmdGMqT
JzRpGILY6pFqbgZSan21RhXoerzLKmaZ2dS/iV6V41J1ZkYNTSk7huTU22RzeZU5Y1R7Sgug8lU+oAun1BVkBF+jsBLR5s6XqTLK0Chm75olgwoAhjyteTNgHDEBCUFTwlVA/HXRHFfCtlkqq420SAYX0y3kLuHUIttsDBAdZIm4NDUPoMOUg7dECuQN2WAJqOwjmIu8hDNFI3w/uEe2Os4iB2g0QvN5jG5qQZzOnvc3M0eN6STxN
+QyVbbmmkeI1It2RC3nJRM9sEs2bhnUiPu1kxsM9OSmT1WmLhBniWrySKS5ECrRSTLoVYbTQJtUKErZmWIVAP1ZVuplq5GUhl7tljSNCDQRlS0SgxYVxE9gLBgzwq0tNAKhDi71qT6QG20pQmD5LZEnu5ERJCCxprpm2kZFPiBM4eoFiDthdABODGoUfybxIU0Ycq2WuAEWrJpSGSX1SrII9tlyTZnmzPNhLKZojO7y2qVNwvzyBW
NE2EsmDVWebMwoyykDekuWy0WDnEsmKTmWGNFCbCR1vfa63k61BVVQ/Z6nsfob6QKBtazZ7iNsFFJB8leEgLaL672OrPcHxOMChnCJOu2CrM5nYW12ypvFrMwSgaDvarE8soNrGRtLN6gO0W9kKoZAjI8Q1jxZ+FvraXXZAN/zc74lQGnf6nuI85augN9/UEDxplIW4mxBpGm+xxjkWYQKfzxR0KMwZgiqVlke5Es8mvB4+MOCUNj
M2k7P/5uLDOIG7MN0e/woBJ9icdp+MssN4jMCbE+emWK+NdyR43DfOeHV7uOvN6w+X9W3H3y7QuP0ozquW2tQai5tkpXr8dHH/1An6TTVuMO9oT6/G0K77xeJ5RpoC22k7a+9jPaeCNtPneopFTXle93tWtfwqCWvK5GLYltuX/d+cQHget2P/bKXa8/vrY8hvYAlXNFwldPuX57a6v7AjVeb6PT45Ofm+6Wn77Iry+nA0gmfYvnI
1d+mtxy4oK7XjM3v3Xyg45H/3nG2X9Kydk54eWrXz2zUTgPX5/0edGnU/LXrX4iuPvN3xw8fc4fS63dZ93eNGOaPfu12zcP+s59d8F+z3++/ODaJ4tb7ln+7e/saXP/9jurM7JuKH+78Lq/TJyTMbV45s0Hntjl+Wdggbh68ic/HahZMz1y9ocHN3ZPvz2j6+pDq69N3jWtpO7zGc+sf9mw4h9vP3rSzSfPeHLHrxsKT+j7r3zDt5
Jfe/i2yoI/HXH8zl/33j2/+e9/jD0ra8+tx6btfv+gcfuNSx/+8L8doYtCN9308COdjwUvPuW2bxW8tv+DGfs/+dlPkrbPvIN2ayIBuYX4W1kskkkuDGLsI/33H2gpO9D13Imdj43bs2Dy+DHjS+/onT972TsLVp7wm/vMh/efFbl37bVzv9hePtcR6Lps3R+O7Lxo8tPXX/fsJYcOfPD39//mvnfXw56D66/YX37/D56cf/XR5ra
rf/XaxobT/vDMUxtSl3VPe8P/ycZflT1SufLVP+TdNXXHvVmDE07tybz38J7aqf3XfXTwwG82XJ9T7Pzt6X//0eemUzInNFl6ky557geFWx5f9cM1v7rB9ZPkcy3WSZ2/uOLSZfe889Nw8tbmX/4lN7X2gbOrHD/dM/PokQcWjw97Urae/ueW66bmNV9kf+nZnrcvu2nH4SWP9vy04olxn224ad7khyqKHhpzg/+kIrH3ez/ffMp5
kQ+3/b4o+0VHyprPBl88+NQttz9oemFGk8u6+drUl3Zv6Cw4cfovrrvm6G83Gar2lj464aMFufuvvnbNgTmPDIr0l/pOePKHn/zu1F/k7Bm/zbW1rLa8+QXvW1t2Vs/c1ldw7EL7+YH7vvfnzt/n52yquvWDY6euadnen3PV79//Yt29J2978rRrXt69Y+8fW25tfqDlw5eOHRy8+ZHBG+q+LLj/lntP3LfrgTVT59/8zqQrO/9ny
uKn2z/7266t33/s0H5zxcmfTX34n9teePWU6VPeS8/7VfIjt54TvmD/VQefLH3gaJ+h2/Zsd/Ezuzw/e/razNc9tz198Ni3TNt3lW/uPvT4HdPf3rQpdMae5xv3Htz0UuGSN9b89dLVH0W++OO8A5efk3X9kQLRvveFB+7df+Gbe+ddWbtmcvPnt1c/u7h/8HDX68derhr48213rqn78L7QlfZpqf6q7rNqjt5YdE73kzefsOZnT1
dNu2PxR/cc7X1vJLmaufXBBcsvWbnPfmpPxT3f/rTL3HTg/A9fs93vnFtStcyd8qPJovKlxw/UrFsx/4Q591W7D398+s/f/Zm7+/Dr57cl5ZUdm9GwZ978XZeEP/UZX1l11RlPRoxVC7xZWxr/Y9oZV2yvWL664oxr3t35V8cPzRt3Lnv24p9l3PjZhVvnHV09dV/+/qvOX7hux97T03zrdjb/Zd6Ola/f9+L3Gg+2vXJ5ww9mfPl
Z5IxxjuV/fz/5suqKBybu39Jy9glPnDf+x0vOvclsvGZa3YHwdbt3PXX33on7Ps+7LX/xbdlLPprpqSksefC2KU9duX3hwep3X8lIK/71/9z0hx9c+8Q5H16/759j9198ZzhNPD+9+uNfLTvnvpfuu/Pzp/7j4OCXB27uP/bWaVMyPzu3/IMf/uXVm1btvivnpMEi3wfnd8x+P2Xswb9kvXjLjLO2v9W+b98FW/aatl5S8PGkFVsK
jhSXm+64+42dxgmld/39uZuvK4v88cVzza/8bu281bcvPTVp5r3tqypXzy2vLn3thtmv3pR8lf36C+78+PMLbrr58OtH9j9+6GXro9995azJmc2rOpYdfO7Yyru3733hgnc2nfvLgumr0la9ccsHK5fcMtH9wHe3LnrrgrE/rbvk0xvWe5IC/W/vqmrY+vf0ec+Fjhya/Upx7d2f3PH8qVP3/tfVLRe7tuWefsJr5z7/rSUXLy3NP
feHE499NmvA6+u8/KG0tx7c73ceXrzz3KPZ8zrnWvKnOENP/vmjs5aX5/zywg7P5oue8K8+kHfp5I93rHjnrNTrv1+SdaDomTfGm679+eWpm3Yd/tvuu349OW9b6m0d9z+9+2bf5nsvPLT4jXEdF+0557nBmopHSa5OZR09KbGWl5ZNfd9dsmjHNfaP+vIxdzG/lSiP/7WviN8cVirkP/bLESXcR/cSfpuYfFt3ftzDcppTzI/LS7
DCSxOMT08pvWrpjy++37Tjsp07r6p6e+76zc8bitG3AX/rYGIfm3z7+QfG3NF6xlN3/fKctQ8fJvxSRcuzC83v/zXpyO6srdufzN/y+RsfBTs/f+Ghs3f89m+ftlXeeOxg6LGHLj30Uu9c2/NHu3939rn3nLJny4O1j7536mc//6PT7/H4xqavu2/+m+8tTnd/cVvh5I9ueWbgsVUXDn5x2z8c73VteHfsuot3jy89+fK6P4+96J6
cj78zo6q1x/Tam8ue/+zkMT9yZyw4cOG1E//07P1z337PNmH6x5u/25C2s+jy8vVP/eOO//S8fMufTvZO+7Ln6Asb9j12ceihU1PE1dceevXOjJVXRDovqg5t/cmUD+6Zlbt233UNK+5dWdPefeHtC23Xb263Vv84591J9ftWHGl41vVgxpGtO2dtez/7y7kXfHjrhrb217Y3/KYoLzVy2W/zL7t1xZWjMPH/8ZeB/a9shKJD20m2
CxO006sOf6sWGsRzui9re85I37m2QjjEWvVmNYd6m8ta/pekRSjT6+HkI8ckHEMczAWqRrGy/jvg6FXDo1bwW40WqYfh0QfBeJ3Cs1rUP00E4x44y9fdybONBIPe0BxQDzCHQ8rkMYXRH3obJ/m5Zfyth9oby2mNAexIvgGRXvRW2HZ+y5R8PNyl2r/D87R1RvjslVHmF9LDxuj8If9hhpd8O4v2R+vRtzDq/6WLHkPHME20Dr0Zg
x7T0msGKE/fukz/7kUzacd+7JUw7hL0SU3S713E6zSpdo9aR8PT95XXk3SNfxvAV6FrIUXuQ+YNpU6Rji4VTMdKfizt5s/nkW8+HHmOnPd/5avQIOgLGS8o/3cj8v9f/47X/wJFtkDlACgBAA==
'@
Load-FileData $tsforgeDll -Mode Assembly -SelfCheck 'LibTSforge.SPP.ProductConfig'
}
Function GetRandomKey([String] $ProductID) {
    try {
        $guid = [Guid]::Parse($ProductID)
        $pkc = [LibTSforge.SPP.PKeyConfig]::new()
        try {
          $pkc.LoadConfig($guid) | Out-Null
        } catch {
          $pkc.LoadAllConfigs([LibTSforge.SPP.SLApi]::GetAppId($guid)) | Out-Null
        }
        $config = [LibTSforge.SPP.ProductConfig]::new()
        $refConfig = [ref] $config
        $pkc.Products.TryGetValue($guid, $refConfig) | Out-Null
        return $config.GetRandomKey().ToString()
    } catch {
        Write-Warning "Failed to retrieve key for Product ID: $ProductID"
        return $null
    }
}
function Activate-License([string]$desc, [string]$ver, [string]$prod, [string]$tsactid) {
    if ($desc -match 'KMS|KMSCLIENT') {
        [LibTSforge.Activators.KMS4k]::Activate($ver, $prod, $tsactid)
    }
    elseif ($desc -match 'VIRTUAL_MACHINE_ACTIVATION') {
        [LibTSforge.Activators.AVMA4K]::Activate($ver, $prod, $tsactid)
    }
    elseif ($desc -match 'MAK|RETAIL|OEM|KMS_R2|WS12|WS12_R2|WS16|WS19|WS22|WS25') {
        
        $isInsiderBuild = $Global:osVersion.Build -ge 26100 -and $Global:osVersion.UBR -ge 4188
        $serverAvailable = Test-Connection -ComputerName "activation.sls.microsoft.com" -Count 1 -Quiet

        Write-Warning "Insider build detected: $isInsiderBuild"
        Write-Warning "Activation server reachable: $serverAvailable"

        if ($isInsiderBuild -and $serverAvailable) {
            
            Write-Warning "Selected activation mode: Static_Cid"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $attempts = @(
                @(100055, 1000043, 1338662172562478),
                @(1345, 1003020, 6311608238084405)
            )
            foreach ($params in $attempts) {
                Write-Warning "$ver, $prod, $tsactid"
                [LibTSforge.Modifiers.SetIIDParams]::SetParams($ver, $prod, $tsactid, [LibTSforge.SPP.PKeyAlgorithm]::PKEY2009, $params[0], $params[1], $params[2])
                $instId = [LibTSforge.SPP.SLApi]::GetInstallationID($tsactid)
                Write-Warning "GetInstallationID, $instId"
                $confId = Call-WebService -requestType 1 -installationId $instId -extendedProductId "31337-42069-123-456789-04-1337-2600.0000-2542001"
                Write-Warning "Call-WebService, $confId"
                $result = [LibTSforge.SPP.SLApi]::DepositConfirmationID($tsactid, $instId, $confId)
                Write-Warning "DepositConfirmationID, $result"
                if ($result -eq 0) { break }
            }
            [LibTSforge.SPP.SPPUtils]::RestartSPP($ver)
        } 
        else {
            if ($isInsiderBuild) {
                Write-Host
                Write-Host "Activation could fail, you should select Vol' products instead" -ForegroundColor Green
                Write-Host
            }
            Write-Warning "Selected activation mode: Zero_Cid"
            [LibTSforge.Activators.ZeroCID]::Activate($ver, $prod, $tsactid)
        }
    }
    else {
        Write-Warning "Unknown license type: $desc"
        return
    }

    $ProductInfo = gwmi SoftwareLicensingProduct -ErrorAction SilentlyContinue -Filter "ID='$tsactid'"
    if (-not $ProductInfo) {
        Write-Warning "Product not found"
        return
    }

    if ($desc -match 'KMS|KMSCLIENT') {
        if ($ProductInfo.GracePeriodRemaining -gt 259200) {
            if ($desc -match 'KMS' -and (
                $desc -notmatch 'CLIENT')) {
                [LibTSforge.Modifiers.KMSHostCharge]::Charge($ver, $prod, $tsactid)
            }
            return
        }

        Write-Warning "KMS4K activation failed"
        return
    }

    if ($desc -notmatch 'KMS|KMSCLIENT') {
        if ($ProductInfo.LicenseStatus -ne 1) {
            Write-Warning "Activation Failed [ZeroCid/StaticCid/AVMA4K]"   
            return
        }
    }

}

<#
typedef struct {
    CHAR m_productId2[24];
} DigitalProductId2;

typedef struct {
    DWORD m_length;
    WORD  m_versionMajor;
    WORD  m_versionMinor;
    BYTE  m_productId2[24];
    DWORD m_keyIdx;
    CHAR m_sku[16];
    BYTE  m_abCdKey[16];
    DWORD m_cloneStatus;
    DWORD m_time;
    DWORD m_random;
    DWORD m_lt;
    DWORD m_licenseData[2];
    CHAR m_oemId[8];
    DWORD m_bundleId;
    CHAR m_hardwareIdStatic[8];
    DWORD m_hardwareIdTypeStatic;
    DWORD m_biosChecksumStatic;
    DWORD m_volSerStatic;
    DWORD m_totalRamStatic;
    DWORD m_videoBiosChecksumStatic;
    CHAR m_hardwareIdDynamic[8];
    DWORD m_hardwareIdTypeDynamic;
    DWORD m_biosChecksumDynamic;
    DWORD m_volSerDynamic;
    DWORD m_totalRamDynamic;
    DWORD m_videoBiosChecksumDynamic;
    DWORD m_crc32;
} DigitalProductId3;

typedef struct {
    DWORD m_length;
    WORD  m_versionMajor;
    WORD  m_versionMinor;
    WCHAR m_productId2Ex[64];
    WCHAR m_sku[64];
    WCHAR m_oemId[8];
    WCHAR m_editionId[260];
    BYTE  m_isUpgrade;
    BYTE  m_reserved[7];
    BYTE  m_abCdKey[16];
    BYTE  m_abCdKeySHA256Hash[32];
    BYTE  m_abSHA256Hash[32];
    WCHAR m_partNumber[64];
    WCHAR m_productKeyType[64];
    WCHAR m_eulaType[64];
} DigitalProductId4;

// Simplified overview of SPPWINOB.dll license processing

// Handles SPP notifications for license installation
__int64 __fastcall HandleSppNotification(
    __int64 context,
    const wchar_t *notification,
    SppInterface ***iface,
    __int64 *extra)
{
    if (wcscmp(notification, L"msft:spp/notifications/common/installproofofpurchase/epilog") == 0)
    {
        if (!iface) return ERROR;

        // Call internal SPP methods to get notification info
        auto notifData = (*iface)->GetNotificationData();
        auto pkeyId = notifData->Get(L"SppNotificationPKeyId");

        // If the notification indicates a key binding, process it
        if (notifData->type == 2)
        {
            ProcessKeyBinding(context - 16, notifData);
        }
    }

    return SUCCESS;
}

// Extracts SPP product key bindings and validates them
__int64 __fastcall ProcessKeyBinding(_QWORD *store, NotificationData *data)
{
    // Fetch key binding fields
    auto pid2 = data->Get(L"SppPkeyBindingPid2");
    auto pid3 = data->Get(L"SppPkeyBindingPid3");
    auto pid4 = data->Get(L"SppPkeyBindingPid4");
    auto nullKeyField = data->Get(L"SppPkeyBindingNullKeyField");

    // Validate fields and check channel/magic values
    if (ValidateBinding(pid2, pid3, pid4, nullKeyField))
    {
        // Fetch additional family info
        auto family = store[10]->GetFamily();

        // Write license data to the registry
        WriteLicenseToRegistry(pid2, pid3, pid4, family);
    }

    return SUCCESS_OR_ERROR;
}

// Writes license information to the Windows registry
__int64 __fastcall WriteLicenseToRegistry(
    BYTE *productId,
    BYTE *digitalId,
    BYTE *digitalId4,
    BYTE *family)
{
    HKEY hKey;
    RegCreateKeyExW(HKEY_LOCAL_MACHINE,
                    L"Software\\Microsoft\\Windows NT\\CurrentVersion",
                    &hKey);

    RegSetValueExW(hKey, L"ProductId", productId);
    RegSetValueExW(hKey, L"DigitalProductId", digitalId);
    RegSetValueExW(hKey, L"DigitalProductId4", digitalId4);

    return SUCCESS;
}
#>
function Get-SppStoreLicense {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Office", "Windows")]
        [string]$SkuType,

        [switch]$IgnoreEsu,
        [switch]$Dump,
        [switch]$Export
    )

# Tsforge, GetPhoneData Function
function Parse-PhoneData {
    param (
        [Parameter(Mandatory=$true)]
        [byte[]]$Data
    )

    try {
        $guid = [Activator]::CreateInstance([guid], ([byte[]]$Data[0..15]))
        $group = [BitConverter]::ToInt32($Data, 16)
        $serialHigh = [BitConverter]::ToInt32($Data, 20)
        $serialLow  = [BitConverter]::ToInt32($Data, 24)
        $totalSerial = ([int64]$serialHigh * 1000000) + $serialLow
        $upgrade = [BitConverter]::ToInt32($Data, 28)
        $security = [BitConverter]::ToInt64($Data, 32)
        return "GUID: $($guid.ToString().ToUpper()) =======================, < Group: $group, Serial: $totalSerial, Security: $security, Upgrade: $upgrade >"
    }
    catch {
        Write-Error "Failed to parse PhoneData: $_"
    }
}

# https://github.com/WitherOrNot/winkeycheck
function Parse-Token {
    param (
        [ValidateNotNullOrEmpty()]
        [string]$Token
    ) 

    if ($Token -match '&(?<base64>.*)$') {
        $base64Data = $Matches['base64']
    } else {
        Write-Error "Invalid Token Format"
        return
    }

    try {
        $bytes = [Convert]::FromBase64String($base64Data)
        $hash = [System.Numerics.BigInteger]::new($bytes)
    } catch {
        Write-Error "Failed to decode Base64 data"
        return
    }

    $mask30 = ([System.Numerics.BigInteger]1 -shl 30) - 1
    $mask20 = ([System.Numerics.BigInteger]1 -shl 20) - 1
    $mask53 = ([System.Numerics.BigInteger]1 -shl 53) - 1

    $upgrade  = [int]($hash -band 1)
    $serial   = [long](($hash -shr 1) -band $mask30)
    $group    = [long](($hash -shr 31) -band $mask20)
    $security = [long](($hash -shr 51) -band $mask53)

    return [string]::Format("{0}, < Group: {1}, Serial: {2}, Security: {3}, Upgrade: {4} >", $Token, $Group, $serial, $security, $upgrade)
}

# LicensingDiagSpp.dll, LicensingWinRT.dll, SppComApi.dll, SppWinOb.dll
# __int64 __fastcall CProductKeyUtilsT<CEmptyType>::BinaryDecode(__m128i *a1, __int64 a2, unsigned __int16 **a3)
function Parse-abCdKey {
    param (
        [Parameter(Mandatory=$true)]
        [byte[]]$bCDKeyArray,

        [Parameter(Mandatory=$false)]
        [switch]$Log
    )

    # Clone input to v21 (like C++ __m128i copy)
    $keyData = $bCDKeyArray.Clone()

    # +2 for N` Logic Shift right [else fail]
    $Src = New-Object char[] 27

    # Character set for base-24 decoding
    $charset = "BCDFGHJKMPQRTVWXY2346789"

    # Validate input length
    if ($keyData.Length -lt 15 -or $keyData.Length -gt 16) {
        throw "Input data must be a 15 or 16 byte array."
    }

    # Win.8 key check
    if (($keyData[14] -band 0xF0) -ne 0) {
        throw "Failed to decode.!"
    }

    # N-flag
    $T = 0
    $BYTE14 = [byte]$keyData[14]
    $flag = (($BYTE14 -band 0x08) -ne 0)

    # BYTE14(v22) = (4 * (((BYTE14(v22) & 8) != 0) & 2)) | BYTE14(v22) & 0xF7;
    $keyData[14] = (4 * (([int](($BYTE14 -band 8) -ne 0)) -band 2)) -bor ($BYTE14 -band 0xF7)

    # BYTE14(v22) ^= (BYTE14(v22) ^ (4 * ((BYTE14(v22) & 8) != 0))) & 8;
    #$keyData[14] = $BYTE14 -bxor (($BYTE14 -bxor (4 * ([int](($BYTE14 -band 8) -ne 0)))) -band 8)

    # Base-24 decoding loop
    for ($idx = 24; $idx -ge 0; $idx--) {
        $last = 0
        for ($j = 14; $j -ge 0; $j--) {
            $val = $keyData[$j] + ($last -shl 8)
            $keyData[$j] = [math]::Floor($val / 0x18)
            $last = $val % 0x18
        }
        $Src[$idx] = $charset[$last]
    }

    if ($keyData[0] -ne 0) {
        throw "Invalid product key data"
    }

    # Handle N-flag
    $rev = $last -gt 13
    $pos = if ($rev) {25} else {-1}
    if ($Log) {
        $Output = (0..4 | % { -join $Src[(5*$_)..((5*$_)+4)] }) -join '-'
        Write-Warning "Before, $Output"
    }

    # Shift Left, Insert N, At position 0 >> $Src[0]=`N`
    if ($flag -and ($last -le 0)) {
        $Src[0] = [Char]78
    }
    # Shift right, Insert N, Count 1-25 [27 Base,0-24 & 2` Spacer's]
    elseif ($flag -and $rev) {
        while ($pos-- -gt $last){$Src[$pos + 1]=$Src[$pos]}
        $T, $Src[$last+1] = 1, [char]78
    }
    # Shift left, Insert N,
    elseif ($flag -and !$rev) {
        while (++$pos -lt $last){$Src[$pos] = $Src[$pos + 1]}
        $Src[$last] = [char]78
    }

    # Dynamically format 5x5 with dashes
    $Output = (0..4 | % { -join $Src[((5*$_)+$T)..((5*$_)+4+$T)] }) -join '-'
    if ($Log) {
        Write-Warning "After,  $Output"
    }
    return $Output
}

    if (-not ([PSTypeName]'LibTSforge.SPP.ProductConfig').Type) {
        Write-Error "Required assembly 'LibTSforge' not loaded."
        return
    }

    $version    = [LibTSforge.Utils]::DetectVersion()
    $production = [LibTSforge.SPP.SPPUtils]::DetectCurrentKey()
    $psPath     = [LibTSforge.SPP.SPPUtils]::GetPSPath($version)
    $tsPath     = [LibTSforge.SPP.SPPUtils]::GetTokensPath($version)
    $psTmpFile  = [System.IO.Path]::GetTempFileName()
    $tsTmpFile  = [System.IO.Path]::GetTempFileName()

    [File]::Copy($psPath, $psTmpFile, $true) | Out-Null
    [File]::Copy($tsPath, $tsTmpFile, $true) | Out-Null

    try {
        $mappedData    = @{}
        $TokenStore    = [LibTSforge.TokenStore.TokenStoreModern]::new($tsTmpFile)
        $PhysicalStore = [LibTSforge.PhysicalStore.PhysicalStoreModern]::new($psTmpFile, $production, $version)
        if (!$PhysicalStore -or !$TokenStore ) {
            Write-Error "Invalid Store Object"
            return
        }
    } catch {
        return
    }

    $AppID      = if ($SkuType -eq 'Office') { '0ff1ce15-a989-479d-af46-f275c6370663' } else { '55c92734-d682-4d71-983e-d6ec3f16059f' }
    $SkuIDList  = [Guid[]](Get-SLLicensingStatus -ApplicationID $AppID | ? eStatus -NE 0 | select -ExpandProperty SkuId)
    if ($IgnoreEsu) {
        $SkuIDList = $SkuIDList | ? {
            $TokenInfo = Retrieve-TokenSKUInfo -SkuId $_ -Mode MetaData -Store $TokenStore -KeepAlive
            $TokenInfo.productName -notmatch 'Esu' -and $TokenInfo.productDescription -notmatch 'Esu'
            #$Name          = Get-ProductSkuInformation -ActConfigId ($_.Guid) -pwszValueName 'productName'
            #$Description   = Get-ProductSkuInformation -ActConfigId ($_.Guid) -pwszValueName 'Description'
            #$Name -notmatch 'Esu' -and $Description -notmatch 'Esu'
        }
    }
    if (-not $SkuIDList) {
        Write-Error "Invalid Sku List Object"
        return
    }
    $Results = New-Object System.Collections.Generic.List[PSCustomObject]
    try {
        foreach ($Item in $SkuIDList) {
            try {
                # Get SkuID->Pkey From TokenStore
                try {
                  $pkeyID = ''
                  $SkuID = $Item.ToString()
                  $Entry = $TokenStore.GetEntry(($SkuID -split '_')[0] + "_--_met", "xml")
                  if ($Entry) {
                    $pkeyID = ([LibTSforge.TokenStore.TokenMeta]::new($Entry.Data)).Data.pkeyId
                  }
                } catch {
                    write-error $_
                }
                if ([string]::IsNullOrEmpty($pkeyID)) {
                  Write-Error "Could not resolve PKeyID for SkuID: $SkuID"
                  return
                }

                # Get SkuID BLock From TokenStore PhysicalStore
                try {
                  $block = $PhysicalStore.GetBlock("SPPSVC\$AppId\$SkuId", $pkeyId)
                  if (-not $block) { throw "Blob not found for $SkuId" }
                } catch {
                    $bindingFlags = [Reflection.BindingFlags]"NonPublic, Instance"
                    $fieldInfo = $PhysicalStore.GetType().GetField("Data", $bindingFlags)
                    $privateData = $fieldInfo.GetValue($PhysicalStore)
                    $realKey = $privateData.Keys | Where-Object { $_ -eq "SPPSVC\$AppId\$SkuId" }
                    $block = $privateData[$realKey] | ? ValueAsStr -Match $pkeyId
                }
                if (-not $block) { throw "Blob not found for $SkuId" }

                if ($Dump.IsPresent) {
                    $bindingFlags = [Reflection.BindingFlags]"NonPublic, Instance"
                    $fieldInfo = $PhysicalStore.GetType().GetField("Data", $bindingFlags)
                    $privateData = $fieldInfo.GetValue($PhysicalStore)
                    $realKey = $privateData.Keys | Where-Object { $_ -eq "SPPSVC\$AppId\$SkuId" }
                    $block = $privateData[$realKey]
                    $DataBlocks = $block | % {
                        [PsOBject]@{
                            Value = $_.ValueAsStr
                            Data  = [BitConverter]::ToString($_.Data)
                            Raw   = $_.Data
                        }
                    }
                    return $DataBlocks
                }
        
                $blob = $block.Data
                $ms = [MemoryStream]::new($blob)
                $br = [BinaryReader]::new($ms)

                while ($ms.Position + 16 -le $ms.Length) {
                    [void]$br.ReadInt64() # Skip Header ID
                    $nSize = $br.ReadInt32()
                    $dSize = $br.ReadInt32()

                    $name = [Encoding]::Unicode.GetString($br.ReadBytes($nSize)).TrimEnd("`0")
                    $ms.Position = ($ms.Position + 7) -band -8

                    if ($ms.Position + $dSize -le $ms.Length) {
                        $mappedData[$name] = $br.ReadBytes($dSize)
                    }
                    $ms.Position = ($ms.Position + 7) -band -8
                }

                [Byte[]]$RawBlob = $mappedData["SppPkeyBindingPid3"]
                $pid3Obj = [PSCustomObject]@{
	                MajorVersion = [BitConverter]::ToUInt16($RawBlob, 4)
	                MinorVersion = [BitConverter]::ToUInt16($RawBlob, 6)
	                ProductId    = [Encoding]::ASCII.GetString($RawBlob[8..31]).TrimEnd("`0")
	                KeyIdx       = [BitConverter]::ToUInt32($RawBlob, 32)
	                EditionId    = [Encoding]::ASCII.GetString($RawBlob[36..51]).TrimEnd("`0")
	                CDKey        = Parse-abCdKey($RawBlob[52..67])
                }
                $pid3txt = ("DPID v{0}.{1}: {2}, Group: {3}, PFN: {4}, Key: {5}" -f 
                    $pid3Obj.MajorVersion, 
                    $pid3Obj.MinorVersion, 
                    $pid3Obj.ProductId, 
                    $pid3Obj.KeyIdx, 
                    $pid3Obj.EditionId, 
                    $pid3Obj.CDKey
                )

                [Byte[]]$RawBlob = $mappedData["SppPkeyBindingPid4"]
                $pid4Obj = [PSCustomObject]@{
	                MajorVersion = [BitConverter]::ToUInt16($RawBlob, 4)
	                MinorVersion = [BitConverter]::ToUInt16($RawBlob, 6)
	                AdvancedPid  = [Encoding]::Unicode.GetString($RawBlob[8..135]).TrimEnd("`0")
	                ActivationId = [Encoding]::Unicode.GetString($RawBlob[136..263]).TrimEnd("`0")
	                OemId        = [Encoding]::Unicode.GetString($RawBlob[264..279]).TrimEnd("`0")
	                EditionId    = [Encoding]::Unicode.GetString($RawBlob[280..799]).TrimEnd("`0")
	                CDKey        = Parse-abCdKey($RawBlob[808..823])
	                PartNumber   = [Encoding]::Unicode.GetString($RawBlob[888..1015]).TrimEnd("`0")
	                KeyType      = [Encoding]::Unicode.GetString($RawBlob[1016..1143]).TrimEnd("`0")
	                EulaType     = [Encoding]::Unicode.GetString($RawBlob[1144..1271]).TrimEnd("`0")
                }
                $pid4txt = ("DPID v{0}.{1}: {2}, Edition: {3}, Type: {4}, Eula: {5}, Key: {6}" -f 
                    $pid4Obj.MajorVersion, 
                    $pid4Obj.MinorVersion, 
                    $pid4Obj.AdvancedPid, 
                    $pid4Obj.EditionId, 
                    $pid4Obj.KeyType, 
                    $pid4Obj.EulaType, 
                    $pid4Obj.CDKey
                )
            }
            catch {
                Write-Error "Failed to extract/parse blob: $($_.Exception.Message)"
            }

            if ($Export.IsPresent) {
                return (
                    [PSObject][ordered]@{
                        AppId                        = $AppId
                        SkuId                        = $SkuID
                        PkeyId                       = $pkeyId
                        SppPkeyBindingProductKey     = [BitConverter]::ToString($mappedData["SppPkeyBindingProductKey"]) -replace ('-','')
                        SppPkeyBindingMPC            = [BitConverter]::ToString($mappedData["SppPkeyBindingMPC"]) -replace ('-','')
                        SppPkeyBindingPid2           = [BitConverter]::ToString($mappedData["SppPkeyBindingPid2"]) -replace ('-','')
                        SppPkeyBindingPid3           = [BitConverter]::ToString($mappedData["SppPkeyBindingPid3"]) -replace ('-','')
                        SppPkeyBindingPid4           = [BitConverter]::ToString($mappedData["SppPkeyBindingPid4"]) -replace ('-','')
                        SppPkeyChannelId             = [BitConverter]::ToString($mappedData["SppPkeyChannelId"]) -replace ('-','')
                        SppPkeyUniqueIdToken         = [BitConverter]::ToString($mappedData["SppPkeyUniqueIdToken"]) -replace ('-','')
                        SppPkeyBindingEditionId      = [BitConverter]::ToString($mappedData["SppPkeyBindingEditionId"]) -replace ('-','')
                        SppPkeyPhoneActivationData   = [BitConverter]::ToString($mappedData["SppPkeyPhoneActivationData"]) -replace ('-','')
                        SppPkeyBindingMiscData       = [BitConverter]::ToString($mappedData["SppPkeyBindingMiscData"]) -replace ('-','')
                    }
                )
            }

            if ($mappedData.Count -gt 0) {
                $Results.Add(
                [PSCustomObject]@{
                    MPC               = [Encoding]::Unicode.GetString($mappedData["SppPkeyBindingMPC"]).TrimEnd("`0")
                    Channel           = [Encoding]::Unicode.GetString($mappedData["SppPkeyChannelId"]).TrimEnd("`0")
                    EditionId         = [Encoding]::Unicode.GetString($mappedData["SppPkeyBindingEditionId"]).TrimEnd("`0")
                    ProductId         = [Encoding]::Unicode.GetString($mappedData["SppPkeyBindingPid2"]).TrimEnd("`0")
                    ProductKey        = [Encoding]::Unicode.GetString($mappedData["SppPkeyBindingProductKey"]).TrimEnd("`0")
                    AppId             = $AppId
                    SkuId             = $SkuId
                    PkeyId            = $pkeyId
                    DigitalProductId  = $pid3txt
                    DigitalProductId4 = $pid4txt
                    PhoneData         = Parse-PhoneData ($mappedData["SppPkeyPhoneActivationData"])
                   #MiscData          = ($mappedData["SppPkeyBindingMiscData"] | ForEach-Object { "{0:X2}" -f $_ }) -join ' '
                    Token             = Parse-Token(([Encoding]::Unicode.GetString($mappedData["SppPkeyUniqueIdToken"]).TrimEnd("`0")))
                })
            }
        }
    }
    finally {
        if ($br)            { $br.Dispose() }
        if ($ms)            { $ms.Dispose() }
        if ($TokenStore)    { $TokenStore.Dispose() }
        if ($PhysicalStore) { $PhysicalStore.Dispose() }
        $PhysicalStore = $null; $TokenStore = $null
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [File]::Delete($tsTmpFile)  | Out-Null
        [File]::Delete($psTmpFile) | Out-Null
    }

    return $Results
}

function Capture-ConsoleOutput {
    param (
        [ScriptBlock]$ScriptBlock
    )

    $stringWriter = New-Object StringWriter
    $originalOut = [Console]::Out
    $originalErr = [Console]::Error

    try {
        [Console]::SetOut($stringWriter)
        [Console]::SetError($stringWriter)

        & $ScriptBlock
    }
    finally {
        [Console]::SetOut($originalOut)
        [Console]::SetError($originalErr)
    }

    return $stringWriter.ToString()
}
#endregion
#region ActivationWs
<#
This code is adapted from the ActivationWs project.
Original Repository: https://github.com/dadorner-msft/activationws

MIT License

Copyright (c) Daniel Dorner

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is furnished
to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT, OR OTHERWISE, ARISING FROM,
OUT OF, OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>
function Call-WebService {
    param (
        [int]$requestType,
        [string]$installationId,
        [string]$extendedProductId
    )

function Parse-SoapResponse {
    param (
        [Parameter(Mandatory=$true)]
        [string]$soapResponse
    )

    # Unescape the HTML-encoded XML content
    $unescapedXml = [System.Net.WebUtility]::HtmlDecode($soapResponse)

    # Check for ErrorCode in the unescaped XML
    if ($unescapedXml -match "<ErrorCode>(.*?)</ErrorCode>") {
        $errorCode = $matches[1]

        # Handle known error codes
        switch ($errorCode) {
            "0x7F" { throw [System.Exception]::new("The Multiple Activation Key has exceeded its limit.") }
            "0x67" { throw [System.Exception]::new("The product key has been blocked.") }
            "0x68" { throw [System.Exception]::new("Invalid product key.") }
            "0x86" { throw [System.Exception]::new("Invalid key type.") }
            "0x90" { throw [System.Exception]::new("Please check the Installation ID and try again.") }
            default { throw [System.Exception]::new("The remote server reported an error ($errorCode).") }
        }
    }

    # Check for ResponseType in the unescaped XML and handle it
    if ($unescapedXml -match "<ResponseType>(.*?)</ResponseType>") {
        $responseType = $matches[1]

        switch ($responseType) {
            "1" {
                # Extract the CID value
                if ($unescapedXml -match "<CID>(.*?)</CID>") {
                    return $matches[1]
                } else {
                    throw "CID not found in the XML."
                }
            }
            "2" {
                # Extract the ActivationRemaining value
                if ($unescapedXml -match "<ActivationRemaining>(.*?)</ActivationRemaining>") {
                    return "$($matches[1]) Activation left"
                } else {
                    throw "ActivationRemaining not found in the XML."
                }
            }
            default {
                throw "The remote server returned an unrecognized response."
            }
        }
    } else {
        throw "ResponseType not found in the XML."
    }
}
function Create-WebRequest {
    param (
        [Parameter(Mandatory=$true)]
        [string]$soapRequest  # Expecting raw XML text as input
    )
    
    # Define the URI and the SOAPAction
    $Uri = New-Object Uri("https://activation.sls.microsoft.com/BatchActivation/BatchActivation.asmx")
    $Action = "http://www.microsoft.com/BatchActivationService/BatchActivate"  # Correct SOAPAction URL
    
    # Create the web request
    $webRequest = [System.Net.HttpWebRequest]::Create($Uri)
    
    # Set necessary headers and content type
    $webRequest.Accept = "text/xml"
    $webRequest.ContentType = "text/xml; charset=`"utf-8`""
    $webRequest.Headers.Add("SOAPAction", $Action)
    $webRequest.Host = "activation.sls.microsoft.com"
    $webRequest.Method = "POST"
    
    try {
        # Convert the string to a byte array and insert into the request stream
        $byteArray = [Encoding]::UTF8.GetBytes($soapRequest)
        $webRequest.ContentLength = $byteArray.Length
        
        $stream = $webRequest.GetRequestStream()
        $stream.Write($byteArray, 0, $byteArray.Length)  # Write the byte array to the stream
        $stream.Close()  # Close the stream after writing
        
        return $webRequest  # Return the webRequest object
        
    } catch {
        throw $_  # Catch any exceptions and rethrow
    }
}
function Create-SoapRequest {
    param (
        [int]$requestType,
        [string]$installationId,
        [string]$extendedProductId
    )

    $activationRequestXml = @"
<ActivationRequest xmlns="http://www.microsoft.com/DRM/SL/BatchActivationRequest/1.0">
  <VersionNumber>2.0</VersionNumber>
  <RequestType>$requestType</RequestType>
  <Requests>
    <Request>
      <PID>$extendedProductId</PID>
      <IID>$installationId</IID>
    </Request>
  </Requests>
</ActivationRequest>
"@
    
    if ($requestType -ne 1) {
        $activationRequestXml = $activationRequestXml -replace '\s*<IID>.*?</IID>\s*', ''
    }

    # Convert string to Base64-encoded Unicode bytes
    $base64RequestXml = [Convert]::ToBase64String([Encoding]::Unicode.GetBytes($activationRequestXml))

    # HMACSHA256 calculation with hardcoded MacKey
    $hmacSHA = New-Object System.Security.Cryptography.HMACSHA256
    $hmacSHA.Key = [byte[]]@(
        254, 49, 152, 117, 251, 72, 132, 134, 156, 243, 241, 206, 153, 168, 144, 100, 
        171, 87, 31, 202, 71, 4, 80, 88, 48, 36, 226, 20, 98, 135, 121, 160, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
    $digest = [Convert]::ToBase64String($hmacSHA.ComputeHash([Encoding]::Unicode.GetBytes($activationRequestXml)))

    # Create SOAP envelope with the necessary values
    return @"
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <soap:Body>
    <BatchActivate xmlns="http://www.microsoft.com/BatchActivationService">
      <request>
        <Digest>$digest</Digest>
        <RequestXml>$base64RequestXml</RequestXml>
      </request>
    </BatchActivate>
  </soap:Body>
</soap:Envelope>
"@
}

    # Create SOAP request
    #Write-Warning "$requestType, $installationId, $extendedProductId"
    $soapRequest = Create-SoapRequest -requestType ([int]$requestType) -installationId $installationId -extendedProductId $extendedProductId

    # Create Web Request
    $webRequest = Create-WebRequest -soapRequest $soapRequest

    try {
        # Send the web request and get the response synchronously
        $webResponse = $webRequest.GetResponse()
        $streamReader = New-Object StreamReader($webResponse.GetResponseStream())
        $soapResponse = $streamReader.ReadToEnd()

        # Parse and return the response
        $Response = Parse-SoapResponse -soapResponse $soapResponse
        return $Response

    } catch {
       return "$_"
    }
    
    return 0
}
#endregion
#region "Validate"
<#
Based on idea from ->

# Old source, work on W7
# GetSLCertify.cs by laomms
# https://forums.mydigitallife.net/threads/open-source-windows-7-product-key-checker.10858/page-14#post-1531837

# new source, work on Windows 8 & up, N key's
# keycheck.py by WitherOrNot
# https://github.com/WitherOrNot/winkeycheck
#>
function Validate-ProductKey {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProductKey,

        [Parameter(Mandatory = $false)]
        [Guid]$SkuID = [guid]::Empty
    )

    $IndexN = ([string]::IsNullOrEmpty($ProductKey) -or (
        $ProductKey.LastIndexOf("n",[StringComparison]::InvariantCultureIgnoreCase) -lt 0))
    $keyInfo = Decode-Key -Key $ProductKey
    if ($SkuID -eq [guid]::Empty) {
        $SkuID = Retrieve-ProductKeyInfo -CdKey $ProductKey | select -ExpandProperty SkuID
    }
    if (!$SkuId -or !$keyInfo -or $IndexN) {
        Clear-Host
        Write-Host
        Write-Host "** Verified process Failure:" -ForegroundColor Red
        Write-host "** Product Key, N Index, Not found." -ForegroundColor Green
        Write-host "** Possible Error: Failed to decode product key." -ForegroundColor Green
        Write-host "** Possible Error: SkuId not found for the product key." -ForegroundColor Green
        Write-Host
        return
    }

    [long]$group    = $keyInfo.Group
    [long]$serial   = $keyInfo.Serial
    [long]$security = $keyInfo.Security
    [int32]$upgrade = $keyInfo.Upgrade

    [System.Numerics.BigInteger]$act_hash = [BigInteger]$upgrade -band 1
    $act_hash = $act_hash -bor (([BigInteger]$serial -band ((1L -shl 30) - 1)) -shl 1)
    $act_hash = $act_hash -bor (([BigInteger]$group -band ((1L -shl 20) - 1)) -shl 31)
    $act_hash = $act_hash -bor (([BigInteger]$security -band ((1L -shl 53) - 1)) -shl 51)
    $bytes = $act_hash.ToByteArray()
    $KeyData = New-Object 'Byte[]' 13
    [Array]::Copy($bytes, 0, $KeyData, 0, [Math]::Min(13, $bytes.Length))
    $act_data = [Convert]::ToBase64String($KeyData)

    $value = [HttpUtility]::HtmlEncode("msft2009:$SkuID&$act_data")
    $requestXml = @"
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope
    xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/"
    xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:xsd="http://www.w3.org/2001/XMLSchema"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <soap:Body>
        <RequestSecurityToken
            xmlns="http://schemas.xmlsoap.org/ws/2004/04/security/trust">
            <TokenType>PKC</TokenType>
            <RequestType>http://schemas.xmlsoap.org/ws/2004/04/security/trust/Issue</RequestType>
            <UseKey>
                <Values xsi:nil="1"/>
            </UseKey>
            <Claims>
                <Values
                    xmlns:q1="http://schemas.xmlsoap.org/ws/2004/04/security/trust" soapenc:arrayType="q1:TokenEntry[3]">
                    <TokenEntry>
                        <Name>ProductKey</Name>
                        <Value>$ProductKey</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>ProductKeyType</Name>
                        <Value>msft:rm/algorithm/pkey/2009</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>ProductKeyActConfigId</Name>
                        <Value>$value</Value>
                    </TokenEntry>
                </Values>
            </Claims>
        </RequestSecurityToken>
    </soap:Body>
</soap:Envelope>
"@

    try {
        $response = $null
        $webRequest = [System.Net.HttpWebRequest]::Create('https://activation.sls.microsoft.com/slpkc/SLCertifyProduct.asmx')
        $webRequest.Method      = "POST"
        $webRequest.Accept      = 'text/*'
        $webRequest.UserAgent   = 'SLSSoapClient'
        $webRequest.ContentType = 'text/xml; charset=utf-8'
        $webRequest.Headers.Add("SOAPAction", "http://microsoft.com/SL/ProductCertificationService/IssueToken");

        try {
            $byteArray = [System.Text.Encoding]::UTF8.GetBytes($requestXml)
            $webRequest.ContentLength = $byteArray.Length
            $stream = $webRequest.GetRequestStream()
            $stream.Write($byteArray, 0, $byteArray.Length)
            $stream.Close()
            $httpResponse = $webRequest.GetResponse()
            $streamReader = New-Object System.IO.StreamReader($httpResponse.GetResponseStream())
            $response = $streamReader.ReadToEnd()
            $streamReader.Close()
        }
        catch [System.Net.WebException] {
            if ($_.Exception) {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $response = $reader.ReadToEnd().ToString()
                $reader.Close()
            }
        }
        catch {
            Write-Error "Error: $($_.Exception.Message)"
            $global:error = $_
            return $null
        }

    }
    catch {
        Write-Error "Error: $($_.Exception.Message)"
        return $null
    }

    if ($response -ne $null) {
        try {
            [xml]$xmlResponse = $response
        } catch { }
        if ([string]::IsNullOrEmpty($xmlResponse)) {
            return "ERROR: Fail to get response"
        }
        if ($xmlResponse.Envelope.Body.Fault -eq $null) {
            return "Valid Key"
        } else {
            return Parse-ErrorMessage -MessageId ($xmlResponse.Envelope.Body.Fault.detail.HRESULT) -Flags ACTIVATION
        }
    }

    return "Error: No response received.", "", $false
}

<#
Based on idea from ->

# Old source, work on W7
# GetSLCertify.cs by laomms
# https://forums.mydigitallife.net/threads/open-source-windows-7-product-key-checker.10858/page-14#post-1531837

# new source, work on Windows 8 & up, N key's
# keycheck.py by WitherOrNot
# https://github.com/WitherOrNot/winkeycheck
#>
function Consume-ProductKey {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProductKey,

        [Parameter(Mandatory = $false)]
        [Guid]$SkuID = [guid]::Empty
    )
    $IndexN = ([string]::IsNullOrEmpty($ProductKey) -or `
        ($ProductKey.LastIndexOf("n",[StringComparison]::InvariantCultureIgnoreCase) -lt 0))
    if ($IndexN) {
        return
    }
    $keyInfo = Decode-Key -Key $ProductKey
    if ($SkuID -eq [guid]::Empty) {
        $SkuID = Retrieve-ProductKeyInfo -CdKey $ProductKey | select -ExpandProperty SkuID
    }
    if ($SkuID -eq $null -or $SkuID -eq [guid]::Empty) {
        return
    }
    $LicenseURL  = Get-ProductSkuInformation -ActConfigId $SkuID -pwszValueName PAUrl ## GetUseLicenseURL
    if (!$LicenseURL) {
        return
    }
    $LicenseXML  = Get-LicenseData -SkuID $SkuID -Mode License
    if (!$LicenseXML) {
        return
    }
    if ($LicenseXML[0] -eq [char]0xFEFF) {
        $LicenseXML = $LicenseXML.Substring(1)
    }
    $LicenseData = [HttpUtility]::HtmlEncode($LicenseXML)

    if (!$SkuID -or !$keyInfo -or !$LicenseXML -or !$LicenseURL -or $IndexN) {
        <#
        Clear-Host
        Write-Host
        Write-Host "** Consume process Failure:" -ForegroundColor Red
        Write-host "** Couldn't find N. Index" -ForegroundColor Green
        Write-host "** Possible Error: Failed to decode product key." -ForegroundColor Green
        Write-host "** Possible Error: SkuID not found for the product key." -ForegroundColor Green
        Write-host "** Possible Error: Failed to Accuire License File for SKU Guid." -ForegroundColor Green
        Write-host "** Possible Error: Can't find License URL." -ForegroundColor Green
        Write-Host
        #>
        return
    }

    [long]$group    = $keyInfo.Group
    [long]$serial   = $keyInfo.Serial
    [long]$security = $keyInfo.Security
    [int32]$upgrade = $keyInfo.Upgrade
    [System.Numerics.BigInteger]$act_hash = [BigInteger]$upgrade -band 1
    $act_hash = $act_hash -bor (([BigInteger]$serial -band ((1L -shl 30) - 1)) -shl 1)
    $act_hash = $act_hash -bor (([BigInteger]$group -band ((1L -shl 20) - 1)) -shl 31)
    $act_hash = $act_hash -bor (([BigInteger]$security -band ((1L -shl 53) - 1)) -shl 51)
    $bytes = $act_hash.ToByteArray()
    $KeyData = New-Object 'Byte[]' 13
    [Array]::Copy($bytes, 0, $KeyData, 0, [Math]::Min(13, $bytes.Length))
    $act_data = [Convert]::ToBase64String($KeyData)

    $Hex = "2A0000000100020001000100000000000000010001000100"
    [byte[]]$Binding = @(
        for ($i=0; $i -lt $Hex.Length; $i+=2) {
            [byte]::Parse($Hex.Substring($i, 2), 'HexNumber')
        }
    )
    [byte[]]$RandomBytes = New-Object byte[] 18
    (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($RandomBytes)
    $bindingData = [System.Convert]::ToBase64String((@($Binding) + @($RandomBytes)))

    $secure_store_id = [guid]::NewGuid()
    $act_config_id = [HttpUtility]::HtmlEncode("msft2009:$SkuID&$act_data")
    $systime = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:sszzz", [System.Globalization.CultureInfo]::InvariantCulture)
    $utctime = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:sszzz", [System.Globalization.CultureInfo]::InvariantCulture)
    $requestXml = @"
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope
    xmlns:soapenc="http://schemas.xmlsoap.org/soap/encoding/"
    xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:xsd="http://www.w3.org/2001/XMLSchema"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <soap:Body>
        <RequestSecurityToken
            xmlns="http://schemas.xmlsoap.org/ws/2004/04/security/trust">
            <TokenType>ProductActivation</TokenType>
            <RequestType>http://schemas.xmlsoap.org/ws/2004/04/security/trust/Issue</RequestType>
            <UseKey>
                <Values
                    xmlns:q1="http://schemas.xmlsoap.org/ws/2004/04/security/trust" soapenc:arrayType="q1:TokenEntry[1]">
                    <TokenEntry>
                        <Name>PublishLicense</Name>
                        <Value>$LicenseData</Value>
                    </TokenEntry>
                </Values>
            </UseKey>
            <Claims>
                <Values
                    xmlns:q1="http://schemas.xmlsoap.org/ws/2004/04/security/trust" soapenc:arrayType="q1:TokenEntry[14]">
                    <TokenEntry>
                        <Name>BindingType</Name>
                        <Value>msft:rm/algorithm/hwid/4.0</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>Binding</Name>
                        <Value>$bindingData</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>ProductKey</Name>
                        <Value>$ProductKey</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>ProductKeyType</Name>
                        <Value>msft:rm/algorithm/pkey/2009</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>ProductKeyActConfigId</Name>
                        <Value>$act_config_id</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>otherInfoPublic.licenseCategory</Name>
                        <Value>msft:sl/EUL/ACTIVATED/PUBLIC</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>otherInfoPrivate.licenseCategory</Name>
                        <Value>msft:sl/EUL/ACTIVATED/PRIVATE</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>otherInfoPublic.sysprepAction</Name>
                        <Value>rearm</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>otherInfoPrivate.sysprepAction</Name>
                        <Value>rearm</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>ClientInformation</Name>
                        <Value>SystemUILanguageId=1033;UserUILanguageId=1033;GeoId=244</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>ClientSystemTime</Name>
                        <Value>$($systime)Z</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>ClientSystemTimeUtc</Name>
                        <Value>$($utctime)Z</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>otherInfoPublic.secureStoreId</Name>
                        <Value>$secure_store_id</Value>
                    </TokenEntry>
                    <TokenEntry>
                        <Name>otherInfoPrivate.secureStoreId</Name>
                        <Value>$secure_store_id</Value>
                    </TokenEntry>
                </Values>
            </Claims>
        </RequestSecurityToken>
    </soap:Body>
</soap:Envelope>
"@
    try {
        $response = $null
        $webRequest = [System.Net.HttpWebRequest]::Create($LicenseURL)
        $webRequest.Method      = "POST"
        $webRequest.Accept      = 'text/*'
        $webRequest.UserAgent   = 'SLSSoapClient'
        $webRequest.ContentType = 'text/xml; charset=utf-8'
        $webRequest.Headers.Add("SOAPAction", "http://microsoft.com/SL/ProductActivationService/IssueToken");

        try {
            $byteArray = [System.Text.Encoding]::UTF8.GetBytes($requestXml)
            $webRequest.ContentLength = $byteArray.Length
            $stream = $webRequest.GetRequestStream()
            $stream.Write($byteArray, 0, $byteArray.Length)
            $stream.Close()
            $httpResponse = $webRequest.GetResponse()
            $streamReader = New-Object System.IO.StreamReader($httpResponse.GetResponseStream())
            $response = $streamReader.ReadToEnd()
            $streamReader.Close()
        }
        catch [System.Net.WebException] {
            if ($_.Exception) {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $response = $reader.ReadToEnd().ToString()
                $reader.Close()
            }
        }
        catch {
            Write-Error "Error: $($_.Exception.Message)"
            $global:error = $_
            return $null
        }

    }
    catch {
        Write-Error "Error: $($_.Exception.Message)"
        return $null
    }

    if ($response -ne $null) {
        try {
            [xml]$xmlResponse = $response
        } catch { }
        if ([string]::IsNullOrEmpty($xmlResponse)) {
            return "ERROR: Fail to get response"
        }
        if ($xmlResponse.Envelope.Body.Fault -eq $null) {
            return "Valid Key"
        } else {
            return Parse-ErrorMessage -MessageId ($xmlResponse.Envelope.Body.Fault.detail.HRESULT) -Flags ACTIVATION
        }
    }

    return "Error: No response received.", "", $false
}

<#
Validate Key Helper.
For Keys who matching local System Pkeyconfig file Only.!
example usage.

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

v1 -- PIDGENX, PIDGENX2
v2 -- GetPKeyData

# pidgenx, GetPKeyData, reversed by WitherOrNot
# https://github.com/WitherOrNot/chacha/blob/main/chacha.cmd
# https://forums.mydigitallife.net/threads/enable-active-directory-based-activation.89790/

# https://www.52pojie.cn/thread-2096183-1-1.html
# https://blog.csdn.net/wpyok168/article/details/157768690
# https://pastebin.com/m1FKZqPL?source=public_pastes

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Clear-Host
$Pattern = "`nProductKey:        {0}`nBatchActivation:   {1}`nSLCertifyProduct:  {2}`nSLActivateProduct: {3}"
(Lookup-ProductKey `
    -ProductKey @(
        "XQ8WW-N6WGD-67K88-74XDH-RGG2T",
        "GD4TT-HKNR7-PT36K-FF64G-PDQCT",
        "7F6DW-3NH9Q-H46WY-8VTXC-MP46G",
        "DH9CD-TKNQH-W3H7G-GD6JT-9K3CT",
        "NC6G4-8B8VK-6V9JR-MFQ2R-4YCGG",
        "PFFMJ-JNFFD-KDBF9-JFCTJ-GVPGG",
        "NQJWP-FG6GT-HBP7G-K3M2R-KBXPT",
        "DBCP8-RCNTK-H6KMC-MC674-WFKPT") `
    -Consume) | % { 
        ($Pattern -f $_.ProductKey, $_.BatchActivation, $_.SLCertifyProduct, $_.SLActivateProduct)
    }
Write-Host

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Import-Module NativeInteropLib -ErrorAction Stop

Clear-Host
Write-Host

Write-Host "** DigitalProductId4 Info" -ForegroundColor Green
#Write-Host

$Pid4 = Parse-DigitalProductId4
$Pid4

Write-Host "** ProductKey Info" -ForegroundColor Green
Write-Host

$pkeyInfo = Decode-Key $pid4.DigitalKey
$pkeyInfo

Write-Host "** Xrm-MS Info" -ForegroundColor Green
Write-Host
Init-XMLInfo | ? RefGroupId -Match $pkeyInfo.Group

$PKey       = $Pid4.DigitalKey
$extPid     = $Pid4.AdvancedPID
$ActId      = $Pid4.ActivationID
$PKeyConfig = "C:\windows\System32\spp\tokens\pkeyconfig\pkeyconfig.xrm-ms"

Write-Host "** SLGenerateOfflineInstallationIdEx Info" -ForegroundColor Green
Write-Host

$hSLC = Manage-SLHandle
$ppwszInstallation = $null
$ppwszInstallationIdPtr = [IntPtr]::Zero
$pProductSkuId = $ActId
$null = $Global:SLC::SLGenerateOfflineInstallationIdEx(
    $hSLC, [ref]$pProductSkuId, 0, [ref]$ppwszInstallationIdPtr)
if ($ppwszInstallationIdPtr -ne [IntPtr]::Zero) {
    $ppwszInstallation = [marshal]::PtrToStringAuto($ppwszInstallationIdPtr)
    Write-Host "IID     : $ppwszInstallation"
}

#Write-Host
#Call-WebService -requestType 1 -installationId $ppwszInstallation -extendedProductId $extPid

Write-Host
Write-Host "** PidGenX2 Info" -ForegroundColor Green
Write-Host

Get-PidGenX -key $PKey -configPath $PKeyConfig -AsObject

Write-Host "** GetPKeyData Info" -ForegroundColor Green
Write-Host

Get-PKeyData -key $PKey -configPath $PKeyConfig -AsObject

#Write-Host
#Call-WebService -requestType 1 -installationId $IID -extendedProductId $extPid
#>
function Get-PidGenX {
    param (
        [string]$key,
        [string]$configPath,
        [switch]$AsObject
    )

    try {
        # Validate input
        if ([string]::IsNullOrWhiteSpace($key) -or [string]::IsNullOrWhiteSpace($configPath)) {
            throw "KEY and CONFIG PATH cannot be empty."
        }

        <#
        sppcomapi.dll
        __int64 __fastcall GetWindowsPKeyInfo(_WORD *a1, __int64 a2, __int64 a3, __int64 a4)
        { 
            __int128 v46[3]; // __m128 v46[3], 48 bytes total
            int v47[44];
            int v48[320];
            memset(v46, 0, sizeof(v46)); // size of structure 2
            memset_0(v47, 0, 0xA4ui64);
            memset_0(v48, 0, 0x4F8ui64);
            v47[0] = 164;   // size of structure 3
            v48[0] = 1272;  // size of structure 4
        }
        #>

        # Allocate unmanaged memory for PID, DPID, and DPID4
        $PIDPtr   = New-IntPtr -Size 0x30  -WriteSizeAtZero
        $DPIDPtr  = New-IntPtr -Size 0xB0  -InitialValue 0xA4
        $DPID4Ptr = New-IntPtr -Size 0x500 -InitialValue 0x4F8

        try {
            try {
                # Call the function with appropriate parameters
                $result = $Global:PIDGENX::PidGenX2(
                    # Most important Roles
                    $key, $configPath,
                    # Default value for MSPID, 03612 ?? 00000 ?
                    # PIDGENX2 -> v26 = L"00000" // SPPCOMAPI, GetWindowsPKeyInfo -> L"03612"
                    "00000",
                    # Unknown1 / [Unknown2, Added in PidGenX2!]
                    0,0,
                    # Structs
                    $PIDPtr, $DPIDPtr, $DPID4Ptr
                )

            } catch {
                
				<#
                >>> .InnerException Class <<<
                -----------------------------

                ErrorCode      : -1979645951
                Message        : Exception from HRESULT: 0x8A010001
                Data           : {}
                InnerException : 
                TargetSite     : Int32 PidGenX(System.String, System.String, System.String, Int32, IntPtr, IntPtr, IntPtr)
                StackTrace     :    at 0.PidGenX(String , String , String , Int32 , IntPtr , IntPtr , IntPtr )
								                at CallSite.Target(Closure , CallSite , Object , String , String , String , Int32 , IntPtr , IntPtr , Object )
                HelpLink       : 
                Source         : 4
                HResult        : -1979645951
                #>

                $innerException = $_.Exception.InnerException
                $HResult   = $innerException.HResult
                $ErrorCode = $innerException.ErrorCode
                $ErrorText = switch ($HResult) {
                    -2147024809 { "The parameter is incorrect." }                   # PGX_MALFORMEDKEY
                    -1979645695 { "Specified key is not valid." }                   # PGX_INVALIDKEY
                    -1979645951 { "Specified key is valid but can't be verified." } # (Add appropriate message if needed)
                    -2147024894 { "Can't find specified pkeyconfig file." }         # PGX_PKEYMISSING
                    -2147024893 { "Specified pkeyconfig path does not exist." }     # (Already exists)
                    -2147483633 { "Specified key is BlackListed." }                 # PGX_BLACKLISTEDKEY
                        default { "Unhandled HResult" }                             # any other error
                }

                $HResultHex = "0x{0:X8}" -f $HResult
                throw "HRESULT: $ErrorText ($HResultHex)"
            }

            $offsets = @{
                AdvancedPid    = 8     # 128/2
                ActivationId   = 136   # 128/2
                EditionType    = 280   # 520/2
                EditionId      = 888   # 128/2
                KeyType        = 1016  # 128/2
                EULA           = 1144  # 128/2
            }

            function Read-WCHARArray {
                param (
                    [IntPtr]$ptr,
                    [int]$size
                )
                $bytes = New-Object byte[] ($size * 2)
                [Marshal]::Copy($ptr, $bytes, 0, $bytes.Length)
                return [Encoding]::Unicode.GetString($bytes).TrimEnd([char]0)
            }

            $results = @()

            # Extract KeyGroup value from DigitalProductId3
            $keyGroupOffset = 32
            $keyGroup = [UInt32][Marshal]::ReadInt32([IntPtr]::Add($DPIDPtr, $keyGroupOffset))

            if ($keyGroup) {
                
                #V2
				try {
                    $ProductDescription = $KeysText[[INT]$keyGroup]
                }
                catch {}

                
                #V1
                if (-not $ProductDescription) {
                  $list = GenerateConfigList -pkeyconfig $configPath -SkipKey $true -SkipKeyRange $true
                  $data = $list | ? RefGroupId -eq $keyGroup
                  if ($data -and (-not [STRING]::IsNullOrWhiteSpace($data.ProductDescription))) {
                    $ProductDescription = $data.ProductDescription
            }}}

            $pidString = [marshal]::PtrToStringUni($pidPtr, 0x30/2)
            foreach ($key in $offsets.Keys) {
                $offset = $offsets[$key]
                $size = if ($key -eq "EditionType") { (520/2) } else { (128/2) }
                $value = if ($key -eq "IsUpgrade") { [Marshal]::ReadByte([IntPtr]::Add($DPID4Ptr, $offset)) } else { Read-WCHARArray ([IntPtr]::Add($DPID4Ptr, $offset)) $size }
                
				switch ($key) 
                {
                  'EULA'         {$EULA=$value}
				  'KeyType'      {$KeyType=$value}
				  'EditionId'    {$EditionId=$value}
				  'AdvancedPid'  {$AdvancedPid=$value}
                  'EditionType'  {$EditionType=$value}
				  'ActivationId' {$ActivationId=$value}
                }
            }

            if ($AsObject) {
                return (
                    [PSObject]@{
                        EditionType = $EditionType
                        EditionId = $EditionId
                        KeyType = $KeyType
                        ProductID = $pidString
                        ActivationId = $ActivationId
                        AdvancedPid = $AdvancedPid
                        Description = $ProductDescription
                    }
                )
            } else {
              # $results += @{ Property = "KeyGroup"; Value = $keyGroup }
                $results += @{ Property = "EditionType"; Value = $EditionType }
                $results += @{ Property = "EditionId"; Value = $EditionId }
                $results += @{ Property = "KeyType"; Value = $KeyType }
                $results += @{ Property = "ProductID"; Value = $pidString }
                $results += @{ Property = "ActivationId"; Value = $ActivationId }
                $results += @{ Property = "AdvancedPid"; Value = $AdvancedPid }
                $results += @{ Property = "Description"; Value = $ProductDescription }
                return $results
            }

        } finally {
            [Marshal]::FreeHGlobal($PIDPtr)
            [Marshal]::FreeHGlobal($DPIDPtr)
            [Marshal]::FreeHGlobal($DPID4Ptr)
        }
    } catch {
        if ($AsObject) {
            return (
                [PSObject]@{
                    Error = "$($_.Exception.Message)"
                }
            )
        } else {
            return (
                @{ Property = "Error"; Value = "$($_.Exception.Message)" }
            )
        }
    }
}
function Get-PKeyData {
    param (
        [string]$key,
        [string]$configPath,
        [Int64]$HWID = 0L,
        [switch]$AsObject
    )

    $MPC        = [IntPtr]::Zero
    $IID        = ""
    $Edition    = ""
    $Channel    = ""
    $Partnum    = ""

    # for the right way to calculate IID
    # use SLGenerateOfflineInstallationIdEx
    # cause we dont know the hwid value

    # to receive the confirmation ID ........
    # you will have to have the extended product id too.
    #Call-WebService -requestType 1 -installationId $ppwszInstallation -extendedProductId $extPid

    $results = @()

    try {
        # Validate input
        if ([string]::IsNullOrWhiteSpace($key) -or [string]::IsNullOrWhiteSpace($configPath)) {
            throw "KEY and CONFIG PATH cannot be empty."
        }
            
        try {
            
            $ret = $Global:PIDGENX::GetPKeyData(
                $key, $configPath, $Mpc, [IntPtr]::Zero, $HWID,
                [ref]$IID, [ref]$Edition, [ref]$Channel, [ref]$Partnum,
                [IntPtr]::Zero
            )

        } catch {
                
			<#
            >>> .InnerException Class <<<
            -----------------------------

            ErrorCode      : -1979645951
            Message        : Exception from HRESULT: 0x8A010001
            Data           : {}
            InnerException : 
            TargetSite     : Int32 PidGenX(System.String, System.String, System.String, Int32, IntPtr, IntPtr, IntPtr)
            StackTrace     :    at 0.PidGenX(String , String , String , Int32 , IntPtr , IntPtr , IntPtr )
								            at CallSite.Target(Closure , CallSite , Object , String , String , String , Int32 , IntPtr , IntPtr , Object )
            HelpLink       : 
            Source         : 4
            HResult        : -1979645951
            #>

            # Access the inner exception
            $innerException = $_.Exception.InnerException

            # Get the HResult directly
            $HResult   = $innerException.HResult
            $ErrorCode = $innerException.ErrorCode

            # Convert HResult to hexadecimal
            $HResultHex = "0x{0:X8}" -f $HResult

            throw "HRESULT: $ErrorText ($HResultHex)"
        }

        if ($ret -ne 0x0) {

            $HResultHex = "0x{0:X8}" -f $ret
            $ErrorText = Parse-ErrorMessage -MessageId $HResultHex
            throw "HRESULT: $ErrorText ($HResultHex)"
        }

        if ($AsObject) {
            return (
                [PSObject]@{
                    Edition = $Edition
                    Channel = $Channel
                    Partnum = $Partnum
                    IID     = $IID
                }
            )
        } else {
            $results += @{ Property = "Edition"; Value = $Edition }
            $results += @{ Property = "Channel"; Value = $Channel }
            $results += @{ Property = "Partnum"; Value = $Partnum }
            $results += @{ Property = "IID";     Value = $IID }
            return $results
        }
    } catch {
        if ($AsObject) {
            return (
                [PSObject]@{
                    Error = "$($_.Exception.Message)"
                }
            )
        } else {
            return (
                @{ Property = "Error"; Value = "$($_.Exception.Message)" }
            )
        }
    }
}
function Lookup-ProductKey {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ProductKey,

        [Parameter(Mandatory = $false)]
        [switch]$Consume
    )

    $results = @()
    foreach ($key in $ProductKey) {
        # Validate product key format and ensure exactly one 'N'
        if (!($key -match '^\w{5}(-\w{5}){4}$' -and
              ($key.IndexOf("n",[StringComparison]::InvariantCultureIgnoreCase) -eq
               $key.LastIndexOf("n",[StringComparison]::InvariantCultureIgnoreCase) -and
               $key.IndexOf("n",[StringComparison]::InvariantCultureIgnoreCase) -ge 0))) {
            Write-Warning "Product key $key is either not in the correct 5X5 format or does not contain exactly one 'N.'"
            continue
        }

        $pkeyInfo = $null
        $pkey = $key.Substring(0,29)

        $paths = @(
            "C:\Windows\System32\spp\tokens\pkeyconfig\pkeyconfig.xrm-ms",
            "C:\Windows\System32\spp\tokens\pkeyconfig\pkeyconfig-csvlk.xrm-ms",
            "C:\Windows\System32\spp\tokens\pkeyconfig\pkeyconfig-downlevel.xrm-ms",
            "C:\Program Files\Microsoft Office\root\Licenses16\pkeyconfig-office.xrm-ms"
        )
        foreach ($path in $paths) {
            try {
                $result = Get-PidGenX -key $pkey -configPath $path
                if ($result.GetValue(1).Property -ne 'Error') {
                    $pkeyInfo = $result
                    break
                }
            } catch {}
        }
        if (!$pkeyInfo) {
            continue
        }
        $BatchActivation  = try {
            Call-WebService -requestType 2 -extendedProductId $pkeyInfo.GetValue(5).Value
        } catch {
            "Error: Call-WebService Api call fail"
        }
        $SLCertifyProduct = try {
            ((Validate-ProductKey -ProductKey $pkey) -split "`r?`n" | Select-Object -First 1).Trim()
        } catch {
            "Error: Validate-ProductKey Api call fail"
        }
        $resultObject = if ($Consume) {
        $SLActivateProduct = try {
            ((Consume-ProductKey -ProductKey $pkey) -split "`r?`n" | Select-Object -First 1).Trim()
        } catch {
            "{License file not found. Failed to acquire URI and XML.}"
        }

        [PSCustomObject]@{
            ProductKey        = $pkey
            BatchActivation   = $BatchActivation
            SLCertifyProduct  = $SLCertifyProduct
            SLActivateProduct = $SLActivateProduct
        }
    } else {
        [PSCustomObject]@{
            ProductKey        = $pkey
            BatchActivation   = $BatchActivation
            SLCertifyProduct  = $SLCertifyProduct
        }
    }
    $results += $resultObject
    Start-sleep -Milliseconds 500
    }
    return $results
}
#endregion
#region "oHook"
$KeyBlock = @'
SKU,KEY
O365BusinessRetail,Y9NF9-M2QWD-FF6RJ-QJW36-RRF2T
O365EduCloudRetail,W62NQ-267QR-RTF74-PF2MH-JQMTH
O365HomePremRetail,3NMDC-G7C3W-68RGP-CB4MH-4CXCH
O365ProPlusRetail,H8DN8-Y2YP3-CR9JT-DHDR9-C7GP3
O365SmallBusPremRetail,2QCNB-RMDKJ-GC8PB-7QGQV-7QTQJ
O365AppsBasicRetail,3HYJN-9KG99-F8VG9-V3DT8-JFMHV
AccessRetail,WHK4N-YQGHB-XWXCC-G3HYC-6JF94
AccessRuntimeRetail,RNB7V-P48F4-3FYY6-2P3R3-63BQV
ExcelRetail,RKJBN-VWTM2-BDKXX-RKQFD-JTYQ2
HomeBusinessPipcRetail,2WQNF-GBK4B-XVG6F-BBMX7-M4F2Y
HomeBusinessRetail,HM6FM-NVF78-KV9PM-F36B8-D9MXD
HomeStudentARMRetail,PBQPJ-NC22K-69MXD-KWMRF-WFG77
HomeStudentPlusARMRetail,6F2NY-7RTX4-MD9KM-TJ43H-94TBT
HomeStudentRetail,PNPRV-F2627-Q8JVC-3DGR9-WTYRK
HomeStudentVNextRetail,YWD4R-CNKVT-VG8VJ-9333B-RC3B8
MondoRetail,VNWHF-FKFBW-Q2RGD-HYHWF-R3HH2
OneNoteFreeRetail,XYNTG-R96FY-369HX-YFPHY-F9CPM
OneNoteRetail,FXF6F-CNC26-W643C-K6KB7-6XXW3
OutlookRetail,7N4KG-P2QDH-86V9C-DJFVF-369W9
PersonalPipcRetail,9CYB3-NFMRW-YFDG6-XC7TF-BY36J
PersonalRetail,FT7VF-XBN92-HPDJV-RHMBY-6VKBF
PowerPointRetail,N7GCB-WQT7K-QRHWG-TTPYD-7T9XF
ProPlusRetail,GM43N-F742Q-6JDDK-M622J-J8GDV
ProfessionalPipcRetail,CF9DD-6CNW2-BJWJQ-CVCFX-Y7TXD
ProfessionalRetail,NXFTK-YD9Y7-X9MMJ-9BWM6-J2QVH
ProjectProRetail,WPY8N-PDPY4-FC7TF-KMP7P-KWYFY
ProjectStdRetail,NTHQT-VKK6W-BRB87-HV346-Y96W8
PublisherRetail,WKWND-X6G9G-CDMTV-CPGYJ-6MVBF
SkypeServiceBypassRetail,6MDN4-WF3FV-4WH3Q-W699V-RGCMY
SkypeforBusinessEntryRetail,4N4D8-3J7Y3-YYW7C-73HD2-V8RHY
SkypeforBusinessRetail,PBJ79-77NY4-VRGFG-Y8WYC-CKCRC
StandardRetail,2FPWN-4H6CM-KD8QQ-8HCHC-P9XYW
VisioProRetail,NVK2G-2MY4G-7JX2P-7D6F2-VFQBR
VisioStdRetail,NCRB7-VP48F-43FYY-62P3R-367WK
WordRetail,P8K82-NQ7GG-JKY8T-6VHVY-88GGD
Access2019Retail,WRYJ6-G3NP7-7VH94-8X7KP-JB7HC
AccessRuntime2019Retail,FGQNJ-JWJCG-7Q8MG-RMRGJ-9TQVF
Excel2019Retail,KBPNW-64CMM-8KWCB-23F44-8B7HM
HomeBusiness2019Retail,QBN2Y-9B284-9KW78-K48PB-R62YT
HomeStudentARM2019Retail,DJTNY-4HDWM-TDWB2-8PWC2-W2RRT
HomeStudentPlusARM2019Retail,NM8WT-CFHB2-QBGXK-J8W6J-GVK8F
HomeStudent2019Retail,XNWPM-32XQC-Y7QJC-QGGBV-YY7JK
Outlook2019Retail,WR43D-NMWQQ-HCQR2-VKXDR-37B7H
Personal2019Retail,NMBY8-V3CV7-BX6K6-2922Y-43M7T
PowerPoint2019Retail,HN27K-JHJ8R-7T7KK-WJYC3-FM7MM
ProPlus2019Retail,BN4XJ-R9DYY-96W48-YK8DM-MY7PY
Professional2019Retail,9NXDK-MRY98-2VJV8-GF73J-TQ9FK
ProjectPro2019Retail,JDTNC-PP77T-T9H2W-G4J2J-VH8JK
ProjectStd2019Retail,R3JNT-8PBDP-MTWCK-VD2V8-HMKF9
Publisher2019Retail,4QC36-NW3YH-D2Y9D-RJPC7-VVB9D
SkypeforBusiness2019Retail,JBDKF-6NCD6-49K3G-2TV79-BKP73
SkypeforBusinessEntry2019Retail,N9722-BV9H6-WTJTT-FPB93-978MK
Standard2019Retail,NDGVM-MD27H-2XHVC-KDDX2-YKP74
VisioPro2019Retail,2NWVW-QGF4T-9CPMB-WYDQ9-7XP79
VisioStd2019Retail,263WK-3N797-7R437-28BKG-3V8M8
Word2019Retail,JXR8H-NJ3MK-X66W8-78CWD-QRVR2
Access2021Retail,P286B-N3XYP-36QRQ-29CMP-RVX9M
AccessRuntime2021Retail,MNX9D-PB834-VCGY2-K2RW2-2DP3D
Excel2021Retail,V6QFB-7N7G9-PF7W9-M8FQM-MY8G9
HomeBusiness2021Retail,JM99N-4MMD8-DQCGJ-VMYFY-R63YK
HomeStudent2021Retail,N3CWD-38XVH-KRX2Y-YRP74-6RBB2
OneNoteFree2021Retail,CNM3W-V94GB-QJQHH-BDQ3J-33Y8H
OneNote2021Retail,NB2TQ-3Y79C-77C6M-QMY7H-7QY8P
Outlook2021Retail,4NCWR-9V92Y-34VB2-RPTHR-YTGR7
Personal2021Retail,RRRYB-DN749-GCPW4-9H6VK-HCHPT
PowerPoint2021Retail,3KXXQ-PVN2C-8P7YY-HCV88-GVM96
ProPlus2021Retail,8WXTP-MN628-KY44G-VJWCK-C7PCF
Professional2021Retail,DJPHV-NCJV6-GWPT6-K26JX-C7PBG
ProjectPro2021Retail,QKHNX-M9GGH-T3QMW-YPK4Q-QRWMV
ProjectStd2021Retail,2B96V-X9NJY-WFBRC-Q8MP2-7CHRR
Publisher2021Retail,CDNFG-77T8D-VKQJX-B7KT3-KK28V
SkypeforBusiness2021Retail,DVBXN-HFT43-CVPRQ-J89TF-VMMHG
Standard2021Retail,HXNXB-J4JGM-TCF44-2X2CV-FJVVH
VisioPro2021Retail,T6P26-NJVBR-76BK8-WBCDY-TX3BC
VisioStd2021Retail,89NYY-KB93R-7X22F-93QDF-DJ6YM
Word2021Retail,VNCC4-CJQVK-BKX34-77Y8H-CYXMR
Access2024Retail,P6NMW-JMTRC-R6MQ6-HH3F2-BTHKB
Excel2024Retail,82CNJ-W82TW-BY23W-BVJ6W-W48GP
Home2024Retail,N69X7-73KPT-899FD-P8HQ4-QGTP4
HomeBusiness2024Retail,PRKQM-YNPQR-77QT6-328D7-BD223
Outlook2024Retail,2CFK4-N44KG-7XG89-CWDG6-P7P27
PowerPoint2024Retail,CT2KT-GTNWH-9HFGW-J2PWJ-XW7KJ
ProjectPro2024Retail,GNJ6P-Y4RBM-C32WW-2VJKJ-MTHKK
ProjectStd2024Retail,C2PNM-2GQFC-CY3XR-WXCP4-GX3XM
ProPlus2024Retail,VWCNX-7FKBD-FHJYG-XBR4B-88KC6
VisioPro2024Retail,HGRBX-N68QF-6DY8J-CGX4W-XW7KP
VisioStd2024Retail,VBXPJ-38NR3-C4DKF-C8RT7-RGHKQ
Word2024Retail,XN33R-RP676-GMY2F-T3MH7-GCVKR
ExcelVolume,9C2PK-NWTVB-JMPW8-BFT28-7FTBF
Excel2019Volume,TMJWT-YYNMB-3BKTF-644FC-RVXBD
Excel2021Volume,NWG3X-87C9K-TC7YY-BC2G7-G6RVC
Excel2024Volume,F4DYN-89BP2-WQTWJ-GR8YC-CKGJG
PowerPointVolume,J7MQP-HNJ4Y-WJ7YM-PFYGF-BY6C6
PowerPoint2019Volume,RRNCX-C64HY-W2MM7-MCH9G-TJHMQ
PowerPoint2021Volume,TY7XF-NFRBR-KJ44C-G83KF-GX27K
PowerPoint2024Volume,CW94N-K6GJH-9CTXY-MG2VC-FYCWP
ProPlusVolume,XQNVK-8JYDB-WJ9W3-YJ8YR-WFG99
ProPlus2019Volume,NMMKJ-6RK4F-KMJVX-8D9MJ-6MWKP
ProPlus2021Volume,FXYTK-NJJ8C-GB6DW-3DYQT-6F7TH
ProPlus2024Volume,XJ2XN-FW8RK-P4HMP-DKDBV-GCVGB
ProjectProVolume,YG9NW-3K39V-2T3HJ-93F3Q-G83KT
ProjectPro2019Volume,B4NPR-3FKK7-T2MBV-FRQ4W-PKD2B
ProjectPro2021Volume,FTNWT-C6WBT-8HMGF-K9PRX-QV9H8
ProjectPro2024Volume,FQQ23-N4YCY-73HQ3-FM9WC-76HF4
ProjectStdVolume,GNFHQ-F6YQM-KQDGJ-327XX-KQBVC
ProjectStd2019Volume,C4F7P-NCP8C-6CQPT-MQHV9-JXD2M
ProjectStd2021Volume,J2JDC-NJCYY-9RGQ4-YXWMH-T3D4T
ProjectStd2024Volume,PD3TT-NTHQQ-VC7CY-MFXK3-G87F8
PublisherVolume,F47MM-N3XJP-TQXJ9-BP99D-8K837
Publisher2019Volume,G2KWX-3NW6P-PY93R-JXK2T-C9Y9V
Publisher2021Volume,2MW9D-N4BXM-9VBPG-Q7W6M-KFBGQ
SkypeforBusinessVolume,869NQ-FJ69K-466HW-QYCP2-DDBV6
SkypeforBusiness2019Volume,NCJ33-JHBBY-HTK98-MYCV8-HMKHJ
SkypeforBusiness2021Volume,HWCXN-K3WBT-WJBKY-R8BD9-XK29P
SkypeforBusiness2024Volume,4NKHF-9HBQF-Q3B6C-7YV34-F64P3
StandardVolume,JNRGM-WHDWX-FJJG3-K47QV-DRTFM
Standard2019Volume,6NWWJ-YQWMR-QKGCB-6TMB3-9D9HK
Standard2021Volume,KDX7X-BNVR8-TXXGX-4Q7Y8-78VT3
Standard2024Volume,V28N4-JG22K-W66P8-VTMGK-H6HGR
VisioProVolume,PD3PC-RHNGV-FXJ29-8JK7D-RJRJK
VisioPro2019Volume,9BGNQ-K37YR-RQHF2-38RQ3-7VCBB
VisioPro2021Volume,KNH8D-FGHT4-T8RK3-CTDYJ-K2HT4
VisioPro2024Volume,B7TN8-FJ8V3-7QYCP-HQPMV-YY89G
VisioStdVolume,7WHWN-4T7MP-G96JF-G33KR-W8GF4
VisioStd2019Volume,7TQNQ-K3YQQ-3PFH7-CCPPM-X4VQ2
VisioStd2021Volume,MJVNY-BYWPY-CWV6J-2RKRT-4M8QG
VisioStd2024Volume,JMMVY-XFNQC-KK4HK-9H7R3-WQQTV
WordVolume,WXY84-JN2Q9-RBCCQ-3Q3J3-3PFJ6
accessVolume,GNH9Y-D2J4T-FJHGG-QRVH7-QPFDW
access2019Volume,9N9PT-27V4Y-VJ2PD-YXFMF-YTFQT
access2021Volume,WM8YG-YNGDD-4JHDC-PG3F4-FC4T4
access2024Volume,82FTR-NCHR7-W3944-MGRHM-JMCWD
mondoVolume,HFTND-W9MK4-8B7MJ-B6C4G-XQBR2
outlookVolume,R69KK-NTPKF-7M3Q4-QYBHW-6MT9B
outlook2019Volume,7HD7K-N4PVK-BHBCQ-YWQRW-XW4VK
outlook2021Volume,C9FM6-3N72F-HFJXB-TM3V9-T86R9
outlook2024Volume,D2F8D-N3Q3B-J28PV-X27HD-RJWB9
word2019Volume,PBX3G-NWMT6-Q7XBW-PYJGG-WXD33
word2021Volume,TN8H9-M34D3-Y64V9-TR72V-X79KV
word2024Volume,MQ84N-7VYDM-FXV7C-6K7CC-VFW9J
ProjectProXVolume,WGT24-HCNMF-FQ7XH-6M8K7-DRTW9
ProjectStdVolume,GNFHQ-F6YQM-KQDGJ-327XX-KQBVC
ProjectStdXVolume,D8NRQ-JTYM3-7J2DX-646CT-6836M
VisioProXVolume,69WXN-MBYV6-22PQG-3WGHK-RM6XC
VisioStdVolume,7WHWN-4T7MP-G96JF-G33KR-W8GF4
VisioStdXVolume,NY48V-PPYYH-3F4PX-XJRKJ-W4423
ProPlusSPLA2021Volume,JRJNJ-33M7C-R73X3-P9XF7-R9F6M
StandardSPLA2021Volume,BQWDW-NJ9YF-P7Y79-H6DCT-MKQ9C
'@ | ConvertFrom-Csv
function Install {

# Define registry path and value
$regPath = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"

# Get ProductReleaseIds registry value and process it
try {
    $productReleaseIds = (Get-ItemProperty -Path $regPath -ea 0).ProductReleaseIds
} catch {
    Write-Host "Error accessing registry: $_"
    return
}
if ($productReleaseIds) {
    
    $productReleaseIds -split ',' | ForEach-Object {
        $productKey = $_.Trim()
        $pKey = $KeyBlock | ? SKU -EQ $productKey | Select -ExpandProperty KEY
        if ($pKey) {
            write-host
            SL-InstallProductKey -Keys ($pKey)
        }
    }
} else {
    Write-Host
    Write-Host "ERROR: ProductReleaseIds not found." -ForegroundColor Red
    return
}

$base64 = @'
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
'@

# Decode the Base64 string back into a byte array
$compressedDllBytes = [Convert]::FromBase64String($base64)

# Step 2: Create a MemoryStream from the byte array
$compressedStream = [MemoryStream]::new($compressedDllBytes)

# Step 3: Decompress the byte array using GZip
$gzipStream = New-Object Compression.GZipStream($compressedStream, [Compression.CompressionMode]::Decompress)
$decompressedStream = New-Object MemoryStream

# Copy the decompressed data to a new MemoryStream
$gzipStream.CopyTo($decompressedStream)
$gzipStream.Close()

# Step 4: Get the decompressed byte array
$decompressedDllBytes = $decompressedStream.ToArray()
    
# Define the output file path with ProgramFiles environment variable
$sppc = [Path]::Combine($env:ProgramFiles, "Microsoft Office\root\vfs\System\sppc.dll")

# Define paths for symbolic link and target
$sppcs = [Path]::Combine($env:ProgramFiles, "Microsoft Office\root\vfs\System\sppcs.dll")
$System32 = [Path]::Combine($env:windir, "System32\sppc.dll")

# Step 1: Check if the symbolic link exists and remove it if necessary
if (Test-Path -Path $sppcs) {
    Write-Host "Symbolic link already exists at $sppcs. Attempting to remove..."

    try {
        # Remove the existing symbolic link
        Remove-Item -Path $sppcs -Force
        Write-Host "Existing symbolic link removed successfully."
    } catch {
        Write-Host "Failed to remove existing symbolic link: $_"
    }
} else {
    Write-Host "No symbolic link found at $sppcs."
}

try {
    # Attempt to write byte array to the file
    [System.IO.File]::WriteAllBytes($sppc, $decompressedDllBytes)
    Write-Host "Byte array written successfully to $sppc."
} 
catch {
    Write-Host "Failed to write byte array to ${sppc}: $_"

    # Inner try-catch to handle the case where the file is in use
    try {
        Write-Host "File is in use or locked. Attempting to move it to a temp file..."

        # Generate a random name for the temporary file in the temp folder
        $tempDir = [Path]::GetTempPath()
        $tempFileName = [Path]::Combine($tempDir, [Guid]::NewGuid().ToString() + ".bak")

        # Move the file to the temp location with a random name
        Move-Item -Path $sppc -Destination $tempFileName -Force
        Write-Host "Moved file to temporary location: $tempFileName"

        # Retry the write operation after moving the file
        [System.IO.File]::WriteAllBytes($sppc, $decompressedDllBytes)
        Write-Host "Byte array written successfully to $sppc after moving the file."

    } catch {
        Write-Host "Failed to move the file or retry the write operation: $_"
    }
}

# Step 3: Check if the symbolic link exists and create it if necessary
try {
    if (-not (Test-Path -Path $sppcs)) {
        # Create symbolic link only if it doesn't already exist
        New-Item -Path $sppcs -ItemType SymbolicLink -Target $System32 | Out-Null
        Write-Host "Symbolic link created successfully at $sppcs."
    } else {
        Write-Host "Symbolic link already exists at $sppcs."
    }
} catch {
    Write-Host "Failed to create symbolic link at ${sppcs}: $_"
}
	
# Define the target registry key path
$RegPath = "HKCU:\Software\Microsoft\Office\16.0\Common\Licensing\Resiliency"

# Define the value name and data
$ValueName = "TimeOfLastHeartbeatFailure"
$ValueData = "2040-01-01T00:00:00Z"

# Check if the registry key exists. If not, create it.
# The -Force parameter on New-Item ensures the full path is created if necessary.
if (-not (Test-Path -Path $RegPath)) {
	Write-host "Registry key '$RegPath' not found. Creating it."
	# Use -Force to create the key and any missing parent keys
	# Out-Null is used to suppress the output object from New-Item
	New-Item -Path $RegPath -Force | Out-Null
}

# Set the registry value within the existing (or newly created) key.
# The -Force parameter on Set-ItemProperty ensures the value is created if it doesn't exist
# or updated if it does exist.
Write-host "Setting registry value '$ValueName' at '$RegPath'."
Set-ItemProperty -Path $RegPath -Name $ValueName -Value $ValueData -Type String -Force
}
function Remove {
# Remove the symbolic link if it exists
$sppcs = [Path]::Combine($env:ProgramFiles, "Microsoft Office\root\vfs\System\sppcs.dll")
if (Test-Path -Path $sppcs) {
    try {
        Remove-Item -Path $sppcs -Force
        Write-Host "Symbolic link '$sppcs' removed successfully."
    } catch {
        Write-Host "Failed to remove symbolic link '$sppcs': $_"
    }
} else {
    Write-Host "No symbolic link found at '$sppcs'."
}

# Remove the actual DLL file if it exists
$sppc = [Path]::Combine($env:ProgramFiles, "Microsoft Office\root\vfs\System\sppc.dll")
if (Test-Path -Path $sppc) {
    try {
        # Try to remove the file and handle any errors if they occur
        Remove-Item -Path $sppc -Force -ErrorAction Stop
        Write-Host "DLL file '$sppc' removed successfully."
    } catch {
        Write-Host "Failed to remove DLL file '$sppc': $_"
            
        # If removal failed, try to move the file to a temporary location
        try {
            # Generate a random name for the file in the temp directory
            $tempDir = [Path]::GetTempPath()
            $tempFileName = [Path]::Combine($tempDir, [Guid]::NewGuid().ToString() + ".bak")
            
            # Attempt to move the file to the temp directory with a random name
            Move-Item -Path $sppc -Destination $tempFileName -Force -ErrorAction Stop
            Write-Host "DLL file moved to Temp folder."
        } catch {
            Write-Host "Failed to move DLL file '$sppc' to temporary location: $_"
        }
    }
} else {
    Write-Host "No DLL file found at '$sppc'."
}
}
#endregion
#region "XML"
$prefixes = [ordered]@{
  VisualStudio = 'ns1:'
  Office = 'pkc:'
  None = '' # keep last.
}
$validConfigTypes = @(
  'Office',
  'Windows',
  'VisualStudio'
)
Class KeyRange {
  [string] $RefActConfigId
  [string] $PartNumber
  [string] $EulaType
  [bool]   $IsValid
  [int]    $Start
  [int]    $End
}
Class Range {
  [KeyRange[]] $Ranges

  [String] ToString() {
    $output = $null
    $this.Ranges | Sort-Object -Property @{Expression = "Start"; Descending = $false } | Select-First 1 | % { 
      $keyInfo = $_ -as [KeyRange]
      $output += "[$($keyInfo.Start), $($keyInfo.End)], Number:$($keyInfo.PartNumber), Type:$($keyInfo.EulaType), IsValid:$($keyInfo.IsValid)`n" }
    return $output
  }
}
Class INFO_DATA {
  [string] $ActConfigId
  [int]    $RefGroupId
  [string] $EditionId
  [string] $ProductDescription
  [string] $ProductKeyType
  [bool]   $IsRandomized
  [Range]  $KeyRanges
  [string] $ProductKey
  [string] $Command

  [String] ToString() {
    $output = $null
    $GroupId = [String]::Format("{0:X}",$this.RefGroupId)
    $output  = " Ref: $($this.RefGroupId)`nType: $($this.ProductKeyType)`nEdit: $($this.EditionId)`n  ID: $($this.ActConfigId)`nName: $($this.ProductDescription)`n"
    $output += " Gen: (gwmi SoftwareLicensingService).InstallProductKey((KeyInfo $($GroupId) 0 0))`n"
    ($this.KeyRanges).Ranges | Sort-Object -Property @{Expression = "Start"; Descending = $false } | % { 
      $keyInfo = $_ -as [KeyRange]
      $output += "* Key Range: [$($keyInfo.Start)] => [$($keyInfo.End)], Number: $($keyInfo.PartNumber), Type: $($keyInfo.EulaType), IsValid: $($keyInfo.IsValid)`n" }
    return $output
  }
}
Function GenerateConfigList {
    param (
        [ValidateNotNullOrEmpty()]
        [Parameter(ValueFromPipeline)]
        [string] $pkeyconfig = "$env:windir\System32\spp\tokens\pkeyconfig\pkeyconfig.xrm-ms",

        [Parameter(Mandatory=$false)]
        [bool] $IgnoreAPI = $false,

        [Parameter(Mandatory=$false)]
        [bool] $SkipKey = $false,

        [Parameter(Mandatory=$false)]
        [bool] $SkipKeyRange = $false
    )

    function Get-XmlValue {
        param (
            [string]$Source,
            [string]$TagName
        )
    
        $startTag = "<$TagName>"
        $endTag = "</$TagName>"
        $iStart = $Source.IndexOf($startTag) + $startTag.Length
        $iEnd = $Source.IndexOf($endTag) - $iStart
        if ($iStart -ge 0 -and $iEnd -ge 0) {
            return $Source.Substring($iStart, $iEnd)
        }
        Write-Debug $TagName
        return $null
    }
    function Get-XmlSection {
        param (
            [string] $XmlContent,
            [string] $StartTag,
            [string] $EndTag,
            [string] $Delimiter
        )
    
        $iStart = $XmlContent.IndexOf($StartTag) + $StartTag.Length
        $iEnd = $XmlContent.IndexOf($EndTag)
        if ($iStart -ge $iEnd -or $iEnd -lt 0) {
            return @()
        }

        $length = $iEnd - $iStart
        $section = $XmlContent.Substring($iStart, $length)
        return ($section -split $Delimiter)
    }
    function Get-ConfigTags {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'FromContent', HelpMessage = "Content source string.")]
            [ValidateNotNullOrEmpty()]
            [string]$Source,

            [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'FromType', HelpMessage = "Type of configuration.")]
            [ValidateScript({
                if ($_ -notin $validConfigTypes) {
                    throw "ERROR: Invalid ConfigType '$_'."
                }
                return $true
            })]
            [string]$ConfigType
        )

        # Initialize prefix
        $prefix = $prefixes.None

        # Determine the prefix based on the parameter set
        switch ($PSCmdlet.ParameterSetName) {
            'FromType' {
                $prefix = $prefixes[$ConfigType]
            }
            'FromContent' {
                if ($Source -match "r:grant|sl:policy") {
                    throw "ERROR: Source must contain valid content."
                }

                # Dynamically check for patterns, excluding None
                foreach ($key in $prefixes.Keys.Where({ $_ -ne 'None' })) {
                    if ($Source -match "$($prefixes[$key])ActConfigId") {
                        $prefix = $prefixes[$key]
                        break  # Exit loop on first match
                    }
                }
            }
        }

        # Create base tags using the determined prefix
        $baseConfigTag = "${prefix}Configuration"
        $baseKeyRangeTag = "${prefix}KeyRange"

        # Build and return XML tags as a custom object
        return [PSCustomObject]@{
            StartTagConfig    = "<${baseConfigTag}s>"
            EndTagConfig      = "</${baseConfigTag}s>"
            DelimiterConfig    = "<${baseConfigTag}>"
            StartTagKeyRange  = "<${baseKeyRangeTag}s>"
            EndTagKeyRange    = "</${baseKeyRangeTag}s>"
            DelimiterKeyRange  = "<${baseKeyRangeTag}>"
            TagPrefix          = $prefix
        }
    }

    if (-not [IO.FILE]::Exists($pkeyconfig)) {
        throw "ERROR: File not exist" }

    $data = Get-Content -Path $pkeyconfig
    $iStart = $data.IndexOf('<tm:infoBin name="pkeyConfigData">')
    if ($iStart -le 0) {
        throw "ERROR: FILE NOT SUPPORTED" }

    $iEnd = $data.Substring($iStart+34).IndexOf('</tm:infoBin>')
    $Conf = [Encoding]::UTF8.GetString(
      [Convert]::FromBase64String(
        $data.Substring(($iStart+34), $iEnd)))

    # Get configuration based on ConfigType
    $Config = Get-ConfigTags -Source $Conf

    # Process Configurations
    $Output = @{}
    $Configurations = Get-XmlSection -XmlContent $Conf -StartTag $Config.StartTagConfig -EndTag $Config.EndTagConfig -Delimiter $Config.DelimiterConfig
    $KeyRanges = Get-XmlSection -XmlContent $Conf -StartTag $Config.StartTagKeyRange -EndTag $Config.EndTagKeyRange -Delimiter $Config.DelimiterKeyRange

    $Configurations | ForEach-Object {
        
        try {
          $length = 0
          $Source = $_ | Out-String
          $length = $Source.Length
        }
        catch {
          # just in case of
          $length = 0
        }

        $ActConfigId = $null
        $RefGroupId = $null
        $EditionId = $null
        $ProductDescription = $null
        $ProductKeyType = $null
        $IsRandomized = $null

        if ($length -ge 5) {
          $ActConfigId = Get-XmlValue -Source $Source -TagName "$($Config.TagPrefix)ActConfigId"
          $RefGroupId = Get-XmlValue -Source $Source -TagName "$($Config.TagPrefix)RefGroupId"
          $EditionId = Get-XmlValue -Source $Source -TagName "$($Config.TagPrefix)EditionId"
          $ProductDescription = Get-XmlValue -Source $Source -TagName "$($Config.TagPrefix)ProductDescription"
          $ProductKeyType = Get-XmlValue -Source $Source -TagName "$($Config.TagPrefix)ProductKeyType"
          $IsRandomized = Get-XmlValue -Source $Source -TagName "$($Config.TagPrefix)IsRandomized" -as [BOOL]
        }

        if ($ActConfigId) {
            $cInfo = [INFO_DATA]::new()
            $cInfo.ActConfigId = $ActConfigId
            $cInfo.IsRandomized = $IsRandomized
            $cInfo.ProductDescription = $ProductDescription
            $cInfo.RefGroupId = $RefGroupId
            $cInfo.ProductKeyType = $ProductKeyType
            $cInfo.EditionId = $EditionId

            <#
            # Attempt to set ProductKey from the reference array
            if (-not $SkipKey) {
			    if ($Config.TagPrefix -and ($Config.TagPrefix -eq 'pkc:')) {
				    $cInfo.ProductKey = $OfficeOnlyKeys[[int]$RefGroupId]
			    } elseif ($Config.TagPrefix -and ($Config.TagPrefix -eq 'ns1:')){
                    $cInfo.ProductKey = ($VSOnlyKeys | ? { $_.Key -eq [int]$RefGroupId } | Get-Random -Count 1).Value
			    } else {
                    $cInfo.ProductKey = ($KeysRef | ? { $_.Key -eq [int]$RefGroupId } | Get-Random -Count 1).Value
                }
            }
            #>
            
            # Check if ProductKey is empty
            if (-not $SkipKey -and ([STRING]::IsNullOrEmpty($cInfo.ProductKey) -and ($RefGroupId -ne '999999'))) {
                # Check if ProductKeyType matches one of the groups
                if (![string]::IsNullOrEmpty($Config.TagPrefix)) {
                    # CASE OF --> Office & VS
                    $IgnoreAPI = $true }

                if (-not $IgnoreAPI -and ($groups -contains $ProductKeyType)) {
                    
                    # i don't think i need it any longer,
                    # since i extract all key's from pkhelper.dll

                    $value = Get-ProductKeys -EditionID $EditionId -ProductKeyType $ProductKeyType
                    if ($value) {
                        # Set ProductKey based on the result of Get-ProductKeys
                        $RefInfo = $null
                        try { $RefInfo = KeyDecode -key0 $value.ProductKey}
                        catch {}
                        if ($value -and $RefInfo -and ($RefInfo[2].Value -match $RefGroupId)) {
                          $cInfo.ProductKey = $value.ProductKey }}}}

            # Call Encode-Key only if ProductKey is still empty after the checks
            if (-not $SkipKey -and ([STRING]::IsNullOrEmpty($cInfo.ProductKey)-and ($RefGroupId -ne '999999'))) {
                $cInfo.ProductKey = Encode-Key $RefGroupId 0 0
            }
            # Call LibTSForge Generate key function only if ProductKey is still empty after the checks
            if (-not $SkipKey -and ([STRING]::IsNullOrEmpty($cInfo.ProductKey)-and ($RefGroupId -ne '999999'))) {
              $cInfo.ProductKey = GetRandomKey -ProductID (
                ([GUID]::Parse($cInfo.ActConfigId)).ToString())
            }

            $cInfo.Command = "(gwmi SoftwareLicensingService).InstallProductKey(""$($cInfo.ProductKey)"")"
            $cInfo.KeyRanges = [Range]::new()
            $Output[$ActConfigId] = $cInfo
        }
    }

    # Process Key Ranges
    if ($KeyRanges -and (-not $SkipKeyRange)) {
        $KeyRanges | ForEach-Object {
            $Source = $_ | Out-String
            $RefActConfigId = Get-XmlValue -Source $Source -TagName "$($Config.TagPrefix)RefActConfigId"
            $PartNumber = Get-XmlValue -Source $Source -TagName "$($Config.TagPrefix)PartNumber"
            $EulaType = Get-XmlValue -Source $Source -TagName "$($Config.TagPrefix)EulaType"
            $IsValid = Get-XmlValue -Source $Source -TagName "$($Config.TagPrefix)IsValid" -as [BOOL]
            $Start = Get-XmlValue -Source $Source -TagName "$($Config.TagPrefix)Start" -as [INT]
            $End = Get-XmlValue -Source $Source -TagName "$($Config.TagPrefix)End" -as [INT]

            if ($RefActConfigId) {
                $kRange = [KeyRange]::new()
                $kRange.End = $End
                $kRange.Start = $Start
                $kRange.IsValid = $IsValid
                $kRange.EulaType = $EulaType
                $kRange.PartNumber = $PartNumber
                $kRange.RefActConfigId = $RefActConfigId

                if ($Output[$RefActConfigId]) {
                    $cInfo = $Output[$RefActConfigId] -as [INFO_DATA]
                    $iInfo = $cInfo.KeyRanges -as [Range]
                    $iInfo.Ranges += $kRange
                }
            }
        }
    }

    return $Output.Values
}
#endregion
#region "Pfn"
<#

Source

EditionUpgradeHelper.dll
__int64 __fastcall CEditionUpgradeHelper::GetOsProductContentId(CEditionUpgradeHelper *this, PBYTE *a2)

EditionUpgradeManagerObj.dll, 
GetContentId
GetContentId(ushort const *,_GUID *)
CClipLicense::EnsureModernLicenseForCurrentOsProductWithUserTicket(int,int,ushort *,long *)

LicensingWinRT.dll
GetContentId(const WCHAR *a1, __int64 a2, struct _GUID *a3)
GetContentId(LPCWSTR lpSrcStr, struct _GUID *a2)

Demo

// Get-ContentIdInfo From Current Installed OS
Get-ContentIdInfo -FromOS
Export-LicenseTable -Expend | Out-GridView
Export-LicenseTable | ? EditionPfn -EQ (Get-CurrentPfn)

// just a demo function
$EditionPfnList = Export-LicenseTable | select EditionPfn, ContentID
$EditionPfnList | ? { ($_).EditionPfn -match '191.' } | % { 
    Write-Warning ("pfn: {0}" -f ($_).EditionPfn)
    Write-Warning ("cID: {0}" -f ($_).ContentID)
    Write-Host
    Get-ContentIdInfo -Pfn       ($_).EditionPfn
    Get-ContentIdInfo -ContentID ($_).ContentID
}
#>
if (!([PSTypeName]'LicenseInfo.LicenseManager').Type) {
$LicenseManager = @'
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
'@
Load-FileData $LicenseManager -Mode Type -SelfCheck 'LicenseInfo.LicenseManager'
}
function Get-CurrentPfn {
    $BrandingInfo = Get-WindowsInformation -pwszValueName Kernel-BrandingInfo # AKA Get-ProductPolicy
    $EditionID    = Parse-DigitalProductId4 -FromRegistry | select -ExpandProperty EditionID
    $EditionPfn   = [string]::Format(
        "Microsoft.Windows.{0}.{1}_8wekyb3d8bbwe",
        $BrandingInfo,
        $EditionID.Substring(4)
    )
    return $EditionPfn
}
function Convert-PfnFormat {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$Pfn,

        [Parameter(ParameterSetName = 'ToShort')]
        [switch]$Short,

        [Parameter(ParameterSetName = 'ToFull')]
        [switch]$Full
    )

    switch ($PSCmdlet.ParameterSetName) {
        'ToShort' {
            # Regex: Matches the middle part between the prefix and suffix
            if ($Pfn -match '^Microsoft\.Windows\.(.+)_8wekyb3d8bbwe$') {
                return $matches[1]
            }
            return $Pfn # Return as-is if already short or not matching
        }

        'ToFull' {
            # Regex: Matches the short pattern (digits.alphanumeric-ID)
            if ($Pfn -match '^\d+\.[A-Z0-9\-]+$') {
                return "Microsoft.Windows.$($Pfn)_8wekyb3d8bbwe"
            }
            return $Pfn # Return as-is if already full
        }

        Default {
            # Optional: Automatic toggle if no switch is provided
            if ($Pfn -like "Microsoft.*") { $Pfn -replace '^Microsoft\.Windows\.|_8wekyb3d8bbwe$', '' }
            else { "Microsoft.Windows.$($Pfn)_8wekyb3d8bbwe" }
        }
    }
}
function Get-ContentIdInfo {
    param (
        [string]$Pfn = '',
        [Guid]$ContentID = [Guid]::Empty,
        [switch]$FromOS
    )

    try {
        $OSOptions          = Get-Item -Path 'HKLM:SYSTEM\CurrentControlSet\Control\ProductOptions'
        $OSProductPfn       = $OSOptions.GetValue('OSProductPfn')
        $OSProductContentId = $OSOptions.GetValue('OSProductContentId')
    } catch {}

    if (!$OSProductPfn -or !$OSProductContentId) {
 
        # EditionUpgradeHelper.dll, CEditionUpgradeHelper::GetOsProductContentId
        $OSProductContentId = Get-WindowsInformation -pwszValueName Kernel-OsProduct-ContentId
        #$OSProductContentId = Get-ProductPolicy -Filter 'Kernel-OsProduct-ContentId' -UseApi | select -ExpandProperty value

        $BrandingInfo = Get-WindowsInformation -pwszValueName Kernel-BrandingInfo # AKA Get-ProductPolicy
        $EditionID    = Parse-DigitalProductId4 -FromRegistry | select -ExpandProperty EditionID
        $OSProductPfn = [string]::Format(
            "Microsoft.Windows.{0}.{1}_8wekyb3d8bbwe",
            $BrandingInfo,
            $EditionID.Substring(4))
    }

    if (![string]::IsNullOrEmpty($Pfn)) {
        $FullPfn = Convert-PfnFormat -Pfn $Pfn -Full
        [LicenseInfo.LicenseManager]::GetLicenseInfo($FullPfn, $null)
    } elseif ($ContentID -ne [Guid]::Empty) {
        [LicenseInfo.LicenseManager]::GetLicenseInfo($null, $ContentID)
    } elseif ($FromOS.IsPresent) {
        if (![string]::IsNullOrEmpty($OSProductPfn)) {
            [LicenseInfo.LicenseManager]::GetLicenseInfo($OSProductPfn, $null)
        } elseif (![string]::IsNullOrEmpty($OSProductContentId)) {
            [LicenseInfo.LicenseManager]::GetLicenseInfo($null, $OSProductContentId)
        }
    } else {
        [LicenseInfo.LicenseManager]::GetLicenseInfo($null, $null)
    }
}
function Export-LicenseTable {
    param (
        [ValidateSet("pkeyhelper.dll", "LicensingWinRT.dll")]
        $DllPath,

        [switch]$Expend
    )
            
    $Table        = @()
    $marker       = 0x0
    $pfnPattern   = "Microsoft.Windows*"
    $guidPattern  = "^[a-f0-9\-]{36}$"
    $cdKeyPattern = "^[A-Z0-9]{5}-"

    $RawStrings = Get-Strings -Path "$env:windir\system32\$DllPath" -MinimumLength 29

    $DbLookup = @{}
    if ($Global:PKeyDatabase) {
        foreach ($item in $Global:PKeyDatabase) { $DbLookup[$item.RefGroupId] = $item }
    }

    for ($i = 0; $i -lt $RawStrings.Count - 3; $i++) {
        if ($RawStrings[$i] -like $pfnPattern) {
            if ($RawStrings[$i+1] -match $guidPattern) {
                
                $keyFlag = $false
                if ($marker -le 0x0) { $marker = 0x01 }
                
                if ($RawStrings[$i+2] -match $cdKeyPattern) {
                    $ProductKey = $RawStrings[$i+2]
                } else {
                    $ProductKey = 'N\A'
                    $keyFlag = $true
                }

                $parts = $RawStrings[$i] -split '\.|_'
                $ShortPfn = if ($parts.Count -ge 4) { "$($parts[2]).$($parts[3])" } else { $RawStrings[$i] }

                $licenseObj = [PSCustomObject]@{
                    EditionPfn = $ShortPfn #$RawStrings[$i]
                    ContentID  = $RawStrings[$i+1]
                    ProductKey = $ProductKey
                }

                if ($Expend.IsPresent -and $ProductKey -ne 'N\A') {
                    try {
                        $decoded = Decode-Key -Key $ProductKey
                        $RefGroupId = $decoded.Group            
                        
                        if ($RefGroupId -and $DbLookup.ContainsKey("$RefGroupId")) {
                            $Match = $DbLookup["$RefGroupId"]
                            $RawSkuID = $Match.ActConfigId

                            $licenseObj = [PSCustomObject]@{
                                Group      = $RefGroupId
                                EditionPfn = $ShortPfn
                                ProductKey = $ProductKey
                                SkuID      = if ($RawSkuID) { $RawSkuID.Substring(1, 36) } else { "N/A" }
                                ContentID  = $RawStrings[$i+1]
                            }
                        }
                    } catch { }
                }

                $Table += $licenseObj
                
                $i += if ($keyFlag) { 1 } else { 2 }
                continue
            }
        }

        if ($marker -gt 0x0) {
            if (1 -eq ($i - $marker)) { 
                break 
            }
            $marker = $i
        }
    }
    
    return $Table
}
#endregion
#region "License"

<#
TSforge
https://github.com/massgravel/TSforge

Open-source slc.dll patch for Windows 8 Milestone builds (7850, 795x, 7989)
Useful if you want to enable things such as Modern Task Manager, Ribbon Explorer, etc.
https://github.com/LBBNetwork/openredpill/blob/master/private.c

Open-source slc.dll patch for Windows 8 Milestone builds (7850, 795x, 7989)
https://github.com/LBBNetwork/openredpill/blob/master/slpublic.h

slpublic.h header
https://learn.microsoft.com/en-us/windows/win32/api/slpublic/
#>

<#
.SYNOPSIS
Opens or closes the global SLC handle,
and optionally closes a specified $hSLC handle.

#>
function Manage-SLHandle {
    [CmdletBinding()]
    param(
        [IntPtr]$hSLC = [IntPtr]::Zero,
        [switch]$Create,
        [switch]$Release,
        [switch]$Force
    )

    # Initialize global variables
    if (-not $global:Status_)      { $global:Status_ = 0 }
    if (-not $global:hSLC_)        { $global:hSLC_   = [IntPtr]::Zero }
    if (-not $global:TrackedSLCs)  { $global:TrackedSLCs = [System.Collections.Generic.HashSet[IntPtr]]::new() }
    if (-not $global:SLC_Lock)     { $global:SLC_Lock = New-Object Object }


    # Helper: Check if handle is tracked
    function Is-HandleTracked([IntPtr]$handle) {
        return $global:TrackedSLCs.Contains($handle)
    }

    # Create new handle
    [System.Threading.Monitor]::Enter($global:SLC_Lock)
    try {
        if ($Create) {
            $newHandle = [IntPtr]::Zero
            $hr = $Global:SLC::SLOpen([ref]$newHandle)
            if ($hr -ne 0) {
                throw "SLOpen failed with HRESULT 0x{0:X8}" -f $hr
            }
            $global:TrackedSLCs.Add($newHandle) | Out-Null
            Write-Verbose "New handle created and tracked."
            return $newHandle
        }

        # Release handle
        if ($Release) {
            # Release specific handle if valid
            if ($hSLC -and $hSLC -ne [IntPtr]::Zero) {
                if (-not (Is-HandleTracked $hSLC) -and -not $Force) {
                    Write-Warning "Handle not tracked or already released. Use -Force to override."
                    return
                }
                Write-Verbose "Releasing specified handle."
                Free-IntPtr -handle $hSLC -Method License
                $global:TrackedSLCs.Remove($hSLC) | Out-Null
                return $hr
            }

            # Release global handle
            if ($global:Status_ -eq 0 -and -not $Force) {
                Write-Warning "Global handle already closed. Use -Force to override."
                return
            }

            Write-Verbose "Releasing global handle."
            Free-IntPtr -handle $hSLC_ -Method License
            $global:TrackedSLCs.Remove($global:hSLC_) | Out-Null
            $global:hSLC_ = [IntPtr]::Zero
            $global:Status_ = 0
            return $hr
        }

        # Return existing global handle if already open
        if ($global:Status_ -eq 1 -and $global:hSLC_ -ne [IntPtr]::Zero -and -not $Force) {
            Write-Verbose "Returning existing global handle."
            return $global:hSLC_
        }

        # Open or reopen global handle
        if ($Force -and $global:hSLC_ -ne [IntPtr]::Zero) {
            Write-Verbose "Force-closing previously open global handle."
            Free-IntPtr -handle $hSLC_ -Method License
            $global:TrackedSLCs.Remove($global:hSLC_) | Out-Null
        }

        Write-Verbose "Opening new global handle."
        $global:hSLC_ = [IntPtr]::Zero
        $hr = $Global:SLC::SLOpen([ref]$global:hSLC_)
        if ($hr -ne 0) {
            throw "SLOpen failed with HRESULT 0x{0:X8}" -f $hr
        }
        $global:TrackedSLCs.Add($global:hSLC_) | Out-Null
        $global:Status_ = 1
        return $global:hSLC_
    }
    finally {
        [System.Threading.Monitor]::Exit($global:SLC_Lock)
    }
}

<#
typedef enum _tagSLDATATYPE {

SL_DATA_NONE = REG_NONE,      // 0
SL_DATA_SZ = REG_SZ,          // 1
SL_DATA_DWORD = REG_DWORD,    // 4
SL_DATA_BINARY = REG_BINARY,  // 3
SL_DATA_MULTI_SZ,             // 7
SL_DATA_SUM = 100             // 100

} SLDATATYPE;

#define REG_NONE		0	/* no type */
#define REG_SZ			1	/* string type (ASCII) */
#define REG_EXPAND_SZ	2	/* string, includes %ENVVAR% (expanded by caller) (ASCII) */
#define REG_BINARY		3	/* binary format, callerspecific */
#define REG_DWORD		4	/* DWORD in little endian format */
#define REG_DWORD_LITTLE_ENDIAN	4	/* DWORD in little endian format */
#define REG_DWORD_BIG_ENDIAN	5	/* DWORD in big endian format  */
#define REG_LINK		6	/* symbolic link (UNICODE) */
#define REG_MULTI_SZ	7	/* multiple strings, delimited by \0, terminated by \0\0 (ASCII) */
#define REG_RESOURCE_LIST	8	/* resource list? huh? */
#define REG_FULL_RESOURCE_DESCRIPTOR	9	/* full resource descriptor? huh? */
#define REG_RESOURCE_REQUIREMENTS_LIST	10
#define REG_QWORD		11	/* QWORD in little endian format */
#>
$SLDATATYPE = @{
    SL_DATA_NONE       = 0   # REG_NONE
    SL_DATA_SZ         = 1   # REG_SZ
    SL_DATA_DWORD      = 4   # REG_DWORD
    SL_DATA_BINARY     = 3   # REG_BINARY
    SL_DATA_MULTI_SZ   = 7   # REG_MULTI_SZ
    SL_DATA_SUM        = 100 # Custom value
}
function Parse-RegistryData {
    param (
        # Data type (e.g., $SLDATATYPE.SL_DATA_NONE, $SLDATATYPE.SL_DATA_SZ, etc.)
        [Parameter(Mandatory=$true)]
        [int]$dataType,

        # Pointer to the data (e.g., registry value pointer)
        [Parameter(Mandatory=$false)]
        [IntPtr]$ptr,

        # Size of the data (in bytes)
        [Parameter(Mandatory=$true)]
        [int]$valueSize,

        # Optional, for special cases (e.g., ProductSkuId)
        [Parameter(Mandatory=$false)]
        [string]$valueName,

        [Parameter(Mandatory=$false)]
        [byte[]]$blob,

        [Parameter(Mandatory=$false)]
        [int]$dataOffset = 0
    )

    # Treat IntPtr.Zero as null for XOR logic
    $ptrIsSet = ($ptr -ne [IntPtr]::Zero) -and ($ptr -ne $null)
    $blobIsSet = ($blob -ne $null)

    if (-not ($ptrIsSet -xor $blobIsSet)) {
        Write-Warning "Exactly one of 'ptr' or 'blob' must be provided, not both or neither."
        return $null
    }

    if ($valueSize -le 0) {
        Write-Warning "Data size is zero or negative for valueName '$valueName'. Returning null."
        return $null
    }

    if ($blobIsSet) {
        if ($dataOffset -lt 0 -or ($dataOffset + $valueSize) -gt $blob.Length) {
            Write-Warning "Invalid dataOffset ($dataOffset) or valueSize ($valueSize) exceeds blob length ($($blob.Length)) for valueName '$valueName'. Returning null."
            return $null
        }
    }

    $result = $null

    $uint32Names = @(
        'SL_LAST_ACT_ATTEMPT_HRESULT',
        'SL_LAST_ACT_ATTEMPT_SERVER_FLAGS',
        'Security-SPP-LastWindowsActivationHResult'
    )

    $datetimeNames = @(
        'SL_LAST_ACT_ATTEMPT_TIME',
        'EvaluationEndDate',
        'TrustedTime',
        'Security-SPP-LastWindowsActivationTime'
    )

    switch ($dataType) {
        $SLDATATYPE.SL_DATA_NONE { 
            $result = $null 
        }

        $SLDATATYPE.SL_DATA_SZ {
            # SL_DATA_SZ = Unicode string
            if ($ptr) {
                # PtrToStringUni expects length in characters, valueSize is in bytes, so divide by 2
                $result = [Marshal]::PtrToStringUni($ptr, $valueSize / 2).TrimEnd([char]0)
            }
            else {
                $buffer = New-Object byte[] $valueSize
                [Buffer]::BlockCopy($blob, $dataOffset, $buffer, 0, $valueSize)
                $result = [Encoding]::Unicode.GetString($buffer).TrimEnd([char]0)
            }
        }

        $SLDATATYPE.SL_DATA_DWORD {
            # SL_DATA_DWORD = DWORD (4 bytes)
            if ($valueSize -ne 4) {
                $result = $null
            }
            elseif ($ptr) {
                # Allocate 4-byte array
                $bytes = New-Object byte[] 4
                [Marshal]::Copy($ptr, $bytes, 0, 4)
                $result = [BitConverter]::ToInt32($bytes, 0)    # instead ToUInt32
            }
            else {
                $buffer = New-Object byte[] $valueSize
                [Buffer]::BlockCopy($blob, $dataOffset, $buffer, 0, $valueSize)
                $result = [BitConverter]::ToInt32($buffer, 0)  # instead ToUInt32
            }
        }

        $SLDATATYPE.SL_DATA_BINARY {
            # SL_DATA_BINARY = Binary blob
            if ($valueName -eq 'ProductSkuId' -and $valueSize -eq 16) {
                # If it's ProductSkuId and the buffer is 16 bytes, treat it as a GUID
                $bytes = New-Object byte[] 16
                if ($ptr) {
                    [Marshal]::Copy($ptr, $bytes, 0, 16)
                }
                else {
                    [Buffer]::BlockCopy($blob, $dataOffset, $bytes, 0, $valueSize)
                }
                $result = [Guid]::new($bytes)
            }
            elseif ($datetimeNames -contains $valueName -and $valueSize -eq 8) {
                $bytes = New-Object byte[] 8
                if ($ptr) {
                    [Marshal]::Copy($ptr, $bytes, 0, 8)
                }
                else {
                    [Buffer]::BlockCopy($blob, $dataOffset, $bytes, 0, 8)
                }
                $fileTime = [BitConverter]::ToInt64($bytes, 0)
                $result = [DateTime]::FromFileTimeUtc($fileTime)
            }
            elseif ($valueName -eq 'Kernel-ExpirationDate' -and $valueSize -eq 16) {
                $bytes = New-Object byte[] 8
                if ($ptr) {
                    [Marshal]::Copy($ptr, $bytes, 0, 8)
                }
                else {
                    [Buffer]::BlockCopy($blob, $dataOffset, $bytes, 0, 8)
                }
                $fileTime = [BitConverter]::ToInt64($bytes, 0)
                $result = [DateTime]::FromFileTimeUtc($fileTime)
            }
            elseif ($uint32Names -contains $valueName -and $valueSize -eq 4) {
                $bytes = New-Object byte[] 4
                if ($ptr) {
                    [Marshal]::Copy($ptr, $bytes, 0, 4)
                }
                else {
                    [Buffer]::BlockCopy($blob, $dataOffset, $bytes, 0, 4)
                }
                $result = [BitConverter]::ToInt32($bytes, 0) # instead ToUInt32
            }
            else {
                # Otherwise, just copy the binary data
                $result = New-Object byte[] $valueSize
                if ($ptr) {
                    [Marshal]::Copy($ptr, $result, 0, $valueSize)
                    $result = ($result | ForEach-Object { $_.ToString("X2") }) -join "-"
                }
                else {
                    [Buffer]::BlockCopy($blob, $dataOffset, $result, 0, $valueSize)
                }
            }
        }

        $SLDATATYPE.SL_DATA_MULTI_SZ {
            # SL_DATA_MULTI_SZ = Multi-string
            if ($ptr) {
               $raw = [Marshal]::PtrToStringUni($ptr, $valueSize / 2)
               $result = $raw -split "`0" | Where-Object { $_ -ne '' }
            }
            else {
               $buffer = New-Object byte[] $valueSize
               [Buffer]::BlockCopy($blob, $dataOffset, $buffer, 0, $valueSize)
               $raw = [Encoding]::Unicode.GetString($buffer)
               $result = $raw -split "`0" | Where-Object { $_ -ne '' }
            }
        }

        $SLDATATYPE.SL_DATA_SUM { # SL_DATA_SUM = Custom (100)
            # Handle this case accordingly (based on your logic)
            $result = $null
        }

        default {
            # Return null for any unsupported data types
            $result = $null
        }
    }

    return $result
}

<#
SLpCheckProductKey
Parameter 1, Pointer to DigitalProductId4 struct
Parameter 2, Pointer to value to store the results

typedef struct {
    DWORD m_length;
    WORD  m_versionMajor;
    WORD  m_versionMinor;
    WCHAR m_productId2Ex[64];
    WCHAR m_sku[64];
    WCHAR m_oemId[8];
    WCHAR m_editionId[260];
    BYTE  m_isUpgrade;
    BYTE  m_reserved[7];
    BYTE  m_abCdKey[16];
    BYTE  m_abCdKeySHA256Hash[32];
    BYTE  m_abSHA256Hash[32];
    WCHAR m_partNumber[64];
    WCHAR m_productKeyType[64];
    WCHAR m_eulaType[64];
} DigitalProductId4;

Example.

write-host "* Is Windows Genuine Local"
SL-IsWindowsGenuineLocal | Format-Table
#>
function SL-CheckProductKey {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [byte[]]$DigitalProductId4,

        [Parameter(ValueFromRemainingArguments)]
        $pid4 = [IntPtr]::Zero,

        [Parameter(ValueFromRemainingArguments)]
        $SelfClean = $false
    )

    begin {
        $minLength = 0x4F8
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    }

    process {
        if ((-not $DigitalProductId4 -or $DigitalProductId4.Length -lt $minLength) -and $pid4 -eq [IntPtr]::Zero) {
            Write-Verbose "Loading DigitalProductId4 from registry"

            $reg = Get-ItemProperty -Path $regPath -ErrorAction Stop
            if (-not $reg.DigitalProductId4) {
                throw "DigitalProductId4 not found in registry."
            }

            $DigitalProductId4 = [byte[]]::new($reg.DigitalProductId4.Length)
            [Array]::Copy($reg.DigitalProductId4, $DigitalProductId4, $reg.DigitalProductId4.Length)
        }

        [int32]$PolicyCheck = 0
        if ($pid4 -eq [IntPtr]::Zero) {
            $SelfClean = $true
            $pid4 = New-IntPtr -Data $DigitalProductId4
        }

        try {
            $returnCode = $Global:slc::SLpCheckProductKey(
                $pid4, [ref]$PolicyCheck)
        }
        finally {
            if ($SelfClean) {
              Free-IntPtr $pid4
            }
        }

        [pscustomobject]@{
            IsCheckSuccessful = ($returnCode -eq 0x00)
            PolicyCheck       = ($PolicyCheck -eq 0x01)
        }
    }
}

<#
IsWindowsGenuine Function.

[C] Checking license status
https://forums.mydigitallife.net/threads/c-checking-license-status.39426/

A simple tool to read the activation and subscription status of Windows.
https://github.com/asdcorp/clic

SL_GENUINE_STATE enumeration (slpublic.h)
https://learn.microsoft.com/en-us/windows/win32/api/slpublic/ne-slpublic-sl_genuine_state

Example.

Write-Host "* Check Product Key Blob"
SL-CheckProductKey | Format-List

$PIDPtr   = [IntPtr]::Zero
$DPIDPtr  = [IntPtr]::Zero
$DPID4Ptr = New-IntPtr -Size 0x500 -InitialValue 0x4F8

$key = 'DBN7V-4R3HT-7P6Y3-TBJDT-GMPM3'
$configPath = 'C:\windows\System32\spp\tokens\pkeyconfig\pkeyconfig.xrm-ms'

try {
    try {
        # Call the function with appropriate parameters
        $result = $Global:PIDGENX::PidGenX2(
            # Most important Roles
            $key, $configPath,
            # Default value for MSPID, 03612 ?? 00000 ?
            # PIDGENX2 -> v26 = L"00000" // SPPCOMAPI, GetWindowsPKeyInfo -> L"03612"
            "00000",
            # Unknown1 / [Unknown2, Added in PidGenX2!]
            0,0,
            # Structs
            $PIDPtr, $DPIDPtr, $DPID4Ptr
        )

    } catch {

        $innerException = $_.Exception.InnerException
        $HResult   = $innerException.HResult
        $ErrorCode = $innerException.ErrorCode
        $ErrorText = switch ($HResult) {
            -2147024809 { "The parameter is incorrect." }                   # PGX_MALFORMEDKEY
            -1979645695 { "Specified key is not valid." }                   # PGX_INVALIDKEY
            -1979645951 { "Specified key is valid but can't be verified." } # (Add appropriate message if needed)
            -2147024894 { "Can't find specified pkeyconfig file." }         # PGX_PKEYMISSING
            -2147024893 { "Specified pkeyconfig path does not exist." }     # (Already exists)
            -2147483633 { "Specified key is BlackListed." }                 # PGX_BLACKLISTEDKEY
                default { "Unhandled HResult" }                             # any other error
        }

        $HResultHex = "0x{0:X8}" -f $HResult
        throw "HRESULT: $ErrorText ($HResultHex)"
    }

    # some work here
    SL-CheckProductKey -pid4 $DPID4Ptr | Format-List
    #Dump-MemoryAddress -Pointer $DPID4Ptr -Length 1272

    finally {
        [Marshal]::FreeHGlobal($PIDPtr)
        [Marshal]::FreeHGlobal($DPIDPtr)
        [Marshal]::FreeHGlobal($DPID4Ptr)
    }}
catch {}
#>
function SL-IsWindowsGenuineLocal {
    $Status = 0  
    $GenuineStates = @(
        "GENUINE", "INVALID LICENSE",
        "TAMPERED", "OFFLINE", "LAST"
    )
    $hResult = $Global:slc::SLIsWindowsGenuineLocal(
        [ref]$Status )

    if ($hResult -ne 0) {
        return $false
    }

    return [PsObject]@{
      IsGenuine = $Status -eq 0x00
      Status    = if ($Status -lt $GenuineStates.Count) { $GenuineStates[$Status] } else { "UNKNOWN ($Status)" }
    }
}

<#
Check if a specific Sku is token based edition
#>
Function IsTokenBasedEdition {
    param (
        [Parameter(Mandatory=$false)]
        [GUID]$SkuId,

        [Parameter(Mandatory=$false)]
        [GUID]$LicenseFileId,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
    }

    try {
        if ((-not $LicenseFileId -and -not $SkuId) -or (
            $LicenseFileId -and $SkuId)) {
                throw "Not a valid choice."
        }

        [Guid]$LicenseFile = [guid]::Empty

        if ($SkuId) {
            $LicenseFile = Retrieve-SKUInfo -SkuId $SkuId -eReturnIdType SL_ID_LICENSE_FILE
        }
        else {
            $LicenseFile = $LicenseFileId
        }

        [IntPtr]$TokenActivationGrants = [IntPtr]::Zero
        if ($LicenseFile -ne ([guid]::empty)) {
            $hrsults = $Global:slc::SLGetTokenActivationGrants(
                $hSLC, [ref]$LicenseFile, [ref]$TokenActivationGrants
            )
                    
            if ($hrsults -ne 0) {
                $errorMessege = Parse-ErrorMessage -MessageId $hrsults -Flags ([ErrorMessageType]::ACTIVATION -bor [ErrorMessageType]::HRESULT)
                Write-Warning "$($hrsults): $($errorMessege)"
                $result = $false
            }
            else {
                $null = $Global:slc::SLFreeTokenActivationGrants(
                    $TokenActivationGrants)
                $result = $true
            }

            return $result
        }
        throw "cant parse GUID"
    }
    finally {
        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}

<#
.SYNOPSIS

$fileId = '?'
$LicenseId = '?'
$OfficeAppId  = '0ff1ce15-a989-479d-af46-f275c6370663'
$windowsAppID  = '55c92734-d682-4d71-983e-d6ec3f16059f'
$enterprisesn = '7103a333-b8c8-49cc-93ce-d37c09687f92'

# should return $OfficeAppId & $windowsAppID
Write-Warning 'Get all installed application IDs.'
Get-SLIDList -eQueryIdType SL_ID_APPLICATION -eReturnIdType SL_ID_APPLICATION
Read-Host

# should return All Office & windows installed SKU
Write-Warning 'Get all installed product SKU IDs.'
Get-SLIDList -eQueryIdType SL_ID_PRODUCT_SKU -eReturnIdType SL_ID_PRODUCT_SKU
Read-Host

# should return $SKU per group <Office -or windows>
Write-Warning 'Get SKU IDs according to the input application ID.'
Get-SLIDList -eQueryIdType SL_ID_APPLICATION -eReturnIdType SL_ID_PRODUCT_SKU -pQueryId $OfficeAppId
Get-SLIDList -eQueryIdType SL_ID_APPLICATION -eReturnIdType SL_ID_PRODUCT_SKU -pQueryId $windowsAppID
Read-Host

# should return $windowsAppID or $OfficeAppId
Write-Warning 'Get application IDs according to the input SKU ID.'
Get-SLIDList -eQueryIdType SL_ID_PRODUCT_SKU -eReturnIdType SL_ID_APPLICATION -pQueryId $enterprisesn
Read-Host

# Same As SLGetInstalledProductKeyIds >> SL_ID_PKEY >> SLGetPKeyInformation >> BLOB
Write-Warning 'Get license PKey IDs according to the input SKU ID.'
Get-SLIDList -eQueryIdType SL_ID_PRODUCT_SKU -eReturnIdType SL_ID_PKEY -pQueryId $enterprisesn 
Read-Host

Write-Warning 'Get license file Ids according to the input SKU ID.'
Get-SLIDList -eQueryIdType SL_ID_PRODUCT_SKU -eReturnIdType SL_ID_LICENSE_FILE -pQueryId $enterprisesn 
Read-Host

Write-Warning 'Get license IDs according to the input license file ID.'
Get-SLIDList -eQueryIdType SL_ID_LICENSE_FILE -eReturnIdType SL_ID_LICENSE -pQueryId $fileId 
Read-Host

Write-Warning 'Get license file ID according to the input license ID.'
Get-SLIDList -eQueryIdType SL_ID_LICENSE -pQueryId $LicenseId -eReturnIdType SL_ID_LICENSE_FILE
Read-Host

Write-Warning 'Get License File Id according to the input License Id'
Get-SLIDList -eQueryIdType SL_ID_LICENSE -pQueryId $LicenseId -eReturnIdType SL_ID_LICENSE_FILE
Read-Host

write-warning "Get union of all application IDs or SKU IDs from all grants of a token activation license."
write-warning "Returns SL_E_NOT_SUPPORTED if the license ID is valid but doesn't refer to a token activation license."
Get-SLIDList -eQueryIdType SL_ID_LICENSE -pQueryId $LicenseId -eReturnIdType SL_ID_APPLICATION

write-warning "Get union of all application IDs or SKU IDs from all grants of a token activation license."
write-warning "Returns SL_E_NOT_SUPPORTED if the license ID is valid but doesn't refer to a token activation license."
Get-SLIDList -eQueryIdType SL_ID_LICENSE -pQueryId $LicenseId -eReturnIdType SL_ID_PRODUCT_SKU

# SLUninstallLicense >> [in] const SLID *pLicenseFileId
Write-Warning 'Get License File IDs associated with a specific Application ID:'
Get-SLIDList -eQueryIdType SL_ID_APPLICATION -pQueryId $OfficeAppId -eReturnIdType SL_ID_ALL_LICENSE_FILES
Read-Host

Write-Warning 'Get License File IDs associated with a specific Application ID:'
Get-SLIDList -eQueryIdType SL_ID_APPLICATION -pQueryId $OfficeAppId -eReturnIdType SL_ID_ALL_LICENSES
Read-Host

$LicensingProducts = (
    Get-SLIDList -eQueryIdType SL_ID_APPLICATION -eReturnIdType SL_ID_PRODUCT_SKU -pQueryId $windowsAppID | ? { Retrieve-SKUInfo -SkuId $_ -eReturnIdType SL_ID_PKEY }
    ) | % {
    [PSCustomObject]@{
        ID            = $_
        Description   = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Description'
        Name          = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'productName'
        LicenseFamily = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Family'
    }
}
#>
enum eQueryIdType {
    SL_ID_APPLICATION = 0
    SL_ID_PRODUCT_SKU = 1
    SL_ID_LICENSE_FILE = 2
    SL_ID_LICENSE = 3
}
enum eReturnIdType {
    SL_ID_APPLICATION = 0
    SL_ID_PRODUCT_SKU = 1
    SL_ID_LICENSE_FILE = 2
    SL_ID_LICENSE = 3
    SL_ID_PKEY = 4
    SL_ID_ALL_LICENSES = 5
    SL_ID_ALL_LICENSE_FILES = 6
}
function Get-SLIDList {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("SL_ID_APPLICATION", "SL_ID_PRODUCT_SKU", "SL_ID_LICENSE_FILE", "SL_ID_LICENSE")]
        [string]$eQueryIdType,

        [Parameter(Mandatory=$true)]
        [ValidateSet("SL_ID_APPLICATION", "SL_ID_PRODUCT_SKU", "SL_ID_LICENSE", "SL_ID_PKEY", "SL_ID_ALL_LICENSES", "SL_ID_ALL_LICENSE_FILES", "SL_ID_LICENSE_FILE")]
        [string]$eReturnIdType,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$pQueryId = $null,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )
    
    $dummyGuid = [Guid]::Empty
    $QueryIdValidation = ($eQueryIdType -ne $eReturnIdType) -and [string]::IsNullOrWhiteSpace($pQueryId)
    $GuidValidation = (-not [string]::IsNullOrWhiteSpace($pQueryId)) -and (
        -not [Guid]::TryParse($pQueryId, [ref]$dummyGuid) -or
        ($dummyGuid -eq [Guid]::Empty)
    )
    $AppIDValidation = ($eQueryIdType -ne [eQueryIdType]::SL_ID_APPLICATION) -and ($eReturnIdType.ToString() -match '_ALL_')
    $AppGUIDValidation = ($eQueryIdType -eq [eQueryIdType]::SL_ID_APPLICATION) -and ($eReturnIdType -ne $eQueryIdType) -and
                        (-not ($knownAppGuids -contains $pQueryId))

    if ($AppIDValidation -or $QueryIdValidation -or $GuidValidation -or $AppGUIDValidation) {
        Write-Warning "Invalid parameters:"

        if ($AppIDValidation) {
            "  - _ALL_ types are allowed only with SL_ID_APPLICATION"
            return  }

        if ($QueryIdValidation -and $GuidValidation) {
            "  - A valid, non-empty pQueryId is required when source and target types differ"
            return }

        if ($QueryIdValidation -and $AppGUIDValidation) {
            if ($eQueryIdType -eq [eQueryIdType]::SL_ID_APPLICATION) {
                try {
                    $output = foreach ($appId in $Global:knownAppGuids) {
                        Get-SLIDList -eQueryIdType $eQueryIdType -eReturnIdType $eReturnIdType -pQueryId $appId
                    }
                }
                catch {
                    Write-Warning "An error occurred while attempting to retrieve results with known GUIDs: $_"
                }

                if ($output) {
                    return $output.Guid
                } else {
                    Write-Warning "No valid results returned for the known Application GUIDs."
                    return
                }
            }

            Write-Warning "  - pQueryId must be a known Application GUID when source is SL_ID_APPLICATION and target differs"
            return
        }

        if ($QueryIdValidation) {
            "  - A valid pQueryId is required when source and target types differ"
            return }

        if ($GuidValidation) {
            "  - pQueryId must be a non-empty valid GUID"
            return }

        if ($AppGUIDValidation) {
            "  - pQueryId must match a known Application GUID when source is SL_ID_APPLICATION and target differs"
            return }
    }


    $eQueryIdTypeInt = [eQueryIdType]::$eQueryIdType
    $eReturnIdTypeInt = [eReturnIdType]::$eReturnIdType

    $queryIdPtr = [IntPtr]::Zero 
    $gch = $null                 

    $pnReturnIds = 0
    $ppReturnIds = [IntPtr]::Zero
    
    $needToCloseLocalHandle = $true
    $currentHSLC = if ($hSLC -and $hSLC -ne [IntPtr]::Zero -and $hSLC -ne 0) {
        $hSLC
    } elseif ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
        $global:hSLC_
    } else {
        Manage-SLHandle
    }

    try {
        if (-not $currentHSLC -or $currentHSLC -eq [IntPtr]::Zero -or $currentHSLC -eq 0) {
            $hresult = $Global:SLC::SLOpen([ref]$currentHSLC)
            
            if ($hresult -ne 0) {
                $uint32Value = $hresult -band 0xFFFFFFFF
                $hexString = "0x{0:X8}" -f $uint32Value
                throw "Failed to open SLC handle. HRESULT: $hexString"
            }
        } else {
            $needToCloseLocalHandle = $false
        }
        
        if ($pQueryId) {
            if ($pQueryId -match '^[{]?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}[}]?$') {
                $queryGuid = [Guid]$pQueryId
                $bytes = $queryGuid.ToByteArray()
                $gch = [GCHandle]::Alloc($bytes, [GCHandleType]::Pinned)
                $queryIdPtr = $gch.AddrOfPinnedObject()
            } else {
                $queryIdPtr = [Marshal]::StringToHGlobalUni($pQueryId)
            }
        } else {
            $queryIdPtr = [IntPtr]::Zero
        }

        $result = $Global:SLC::SLGetSLIDList($currentHSLC, $eQueryIdTypeInt, $queryIdPtr, $eReturnIdTypeInt, [ref]$pnReturnIds, [ref]$ppReturnIds)
        if ($result -eq 0 -and $pnReturnIds -gt 0 -and $ppReturnIds -ne [IntPtr]::Zero) {
            $guidList = @()

            #foreach ($i in 0..($pnReturnIds - 1)) {
            #    $currentPtr = [IntPtr]([Int64]$ppReturnIds + [Int64]16 * $i)
            #    $guidBytes = New-Object byte[] 16
            #    [Marshal]::Copy($currentPtr, $guidBytes, 0, 16)
            #    $guidList += (New-Object Guid (,$guidBytes))
            #}

            $currentPtr = [IntPtr]$ppReturnIds
            while (--$pnReturnIds -ge 0x0) {
                $guidList += [Marshal]::PtrToStructure($currentPtr, [Type]'Guid')
                $currentPtr = [IntPtr]::Add($currentPtr, 0x10)
            }

            return $guidList

        } else {
            $uint32Value = $result -band 0xFFFFFFFF
            $hexString = "0x{0:X8}" -f $uint32Value
            if ($result -eq 0xC004F012) {
                return @()
            } else {
                throw "Failed to retrieve ID list. HRESULT: $hexString"
            }
        }
    } catch {
        Write-Warning "Error in Get-SLIDList (QueryIdType: $($eQueryIdType), ReturnIdType: $($eReturnIdType), pQueryId: $($pQueryId)): $($_.Exception.Message)"
        throw $_
    } finally {

        if ($ppReturnIds -ne [IntPtr]::Zero) {
            $null = $Global:kernel32::LocalFree($ppReturnIds)
            $ppReturnIds = [IntPtr]::Zero
        }
        if ($queryIdPtr -ne [IntPtr]::Zero -and $gch -eq $null) {
            [Marshal]::FreeHGlobal($queryIdPtr)
            $queryIdPtr = [IntPtr]::Zero
        }
        if ($gch -ne $null -and $gch.IsAllocated) {
            $gch.Free()
            $gch = $null
        }

        if ($needToCloseLocalHandle -and $currentHSLC -ne [IntPtr]::Zero) {
            Free-IntPtr -handle $currentHSLC -Method License
            $currentHSLC = [IntPtr]::Zero
        }
    }
}

<#
.SYNOPSIS
Function Retrieve-SKUInfo retrieves related licensing IDs for a given SKU GUID.
Also, Support for SL_ID_ALL_LICENSES & SL_ID_ALL_LICENSE_FILES, Only for Application-ID

Specific SKUs require particular IDs:
- The SKU for SLUninstallLicense requires the ID_LICENSE_FILE GUID.
- The SKU for SLUninstallProofOfPurchase requires the ID_PKEY GUID.

Optional Pointer: Handle to the Software Licensing Service (SLC).
Optional eReturnIdType: Type of ID to return (e.g., SL_ID_APPLICATION, SL_ID_PKEY, etc.).

Retrieve-TokenSKUInfo, use Tsforge Lib instead.
#>
function Retrieve-SKUInfo {
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[{]?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}[}]?$')]
        [string]$SkuId,

        [Parameter(Mandatory = $false)]
        [ValidateSet("SL_ID_APPLICATION", "SL_ID_PRODUCT_SKU", "SL_ID_LICENSE", "SL_ID_PKEY", "SL_ID_ALL_LICENSES", "SL_ID_ALL_LICENSE_FILES", "SL_ID_LICENSE_FILE")]
        [string]$eReturnIdType,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    # Define once at the top
    $Is__ALL = $eReturnIdType -match '_ALL_'
    $IsAppID = $Global:knownAppGuids -contains $SkuId

    # XOR Case, Check if Both Valid, if one valid, exit
    if ($Is__ALL -xor $IsAppID) {
        Write-Warning "ApplicationID Work with SL_ID_ALL_LICENSES -or SL_ID_ALL_LICENSE_FILES Only!"
        return $null
    }

    function Get-IDs {
        param (
            [string]$returnType,
            [Intptr]$hSLC
        )
        try {
            if ($IsAppID) {
                return Get-SLIDList -eQueryIdType SL_ID_APPLICATION -eReturnIdType $returnType -pQueryId $SkuId -hSLC $hSLC
            } else {
                return Get-SLIDList -eQueryIdType SL_ID_PRODUCT_SKU -eReturnIdType $returnType -pQueryId $SkuId -hSLC $hSLC
            }
        } catch {
            Write-Warning "Get-SLIDList call failed for $returnType and $SkuId"
            return $null
        }
    }

    $product = [Guid]$SkuId

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }

    try {
        # [SL_ID_LICENSE_FILE] Case
        [Guid]$fileId = try {
            [Guid]::Parse((Get-ProductSkuInformation -ActConfigId $product -pwszValueName fileId -hSLC $hSLC).Trim().Substring(0,36))
        }
        catch {
            [GUID]::Empty
        }

        # [SL_ID_LICENSE] Case **Alternative**
        [Guid]$licenseId = try {
            [Guid]::Parse((Get-ProductSkuInformation -ActConfigId $product -pwszValueName licenseId -hSLC $hSLC).Trim().Substring(0,36))
        } catch {
            [Guid]::Empty
        }

        [Guid]$privateCertificateId = try {
            [Guid]::Parse((Get-ProductSkuInformation -ActConfigId $product -pwszValueName privateCertificateId -hSLC $hSLC).Trim().Substring(0,36))
        } catch {
            [Guid]::Empty
        }

        # [SL_ID_APPLICATION] Case **Alternative**
        [Guid]$applicationId = try {
            [Guid]::Parse((Get-ProductSkuInformation -ActConfigId $product -pwszValueName applicationId -hSLC $hSLC).Trim().Substring(0,36))
        } catch {
            [Guid]::Empty
        }

        # [SL_ID_PKEY] Case **Alternative**
        [Guid]$pkId = try {
            [Guid]::Parse((Get-ProductSkuInformation -ActConfigId $product -pwszValueName pkeyIdList -hSLC $hSLC).Trim().Substring(0,36)) # Instead `pkeyId`
        } catch {
            [Guid]::Empty
        }

        [uint32]$countRef = 0
        [IntPtr]$ppKeyIds = [intPtr]::Zero
        [GUID]$pKeyId = [GUID]::Empty
        [uint32]$hresults = $Global:SLC::SLGetInstalledProductKeyIds(
            $hSLC, [ref]$product, [ref]$countRef, [ref]$ppKeyIds)
        if ($hresults -eq 0) {
            if ($countRef -gt 0 -and (
                $ppKeyIds -ne [IntPtr]::Zero)) {
                    if ($ppKeyIds.ToInt64() -gt 0) {
                        try {
                            $buffer = New-Object byte[] 16
                            [Marshal]::Copy($ppKeyIds, $buffer, 0, 16)
                            $pKeyId = [Guid]::new($buffer)
                        }
                        catch {
                            $pKeyId = $null
                        }
        }}}

        # -------------------------------------------------

        if (-not $eReturnIdType) {
            $SKU_DATA = [pscustomobject]@{
                ID_SKU          = $SkuId
                ID_APPLICATION  = if ($applicationId -and $applicationId -ne [Guid]::Empty) { $applicationId } else { try { Get-IDs SL_ID_APPLICATION -hSLC $hSLC } catch { [Guid]::Empty } }
                ID_PKEY         = if ($pkId -and $pkId -ne [Guid]::Empty) { $pkId } elseif ($Product_SKU_ID -and $Product_SKU_ID -ne [Guid]::Empty) { $Product_SKU_ID } else { try { Get-IDs SL_ID_PKEY -hSLC $hSLC } catch { [Guid]::Empty } }
                ID_LICENSE      = if (($licenseId -and $privateCertificateId) -and ($licenseId -ne [Guid]::Empty -and $privateCertificateId -ne [Guid]::Empty)) { @($licenseId, $privateCertificateId) } else { try { Get-IDs SL_ID_LICENSE -hSLC $hSLC } catch { [Guid]::Empty } }
                ID_LICENSE_FILE = if ($fileId -and $fileId -ne [Guid]::Empty) { $fileId } else { try { Get-IDs SL_ID_LICENSE_FILE -hSLC $hSLC } catch { [Guid]::Empty } }
            }
            return $SKU_DATA
        }

        switch ($eReturnIdType) {
            "SL_ID_APPLICATION" {
                if ($applicationId -and $applicationId -ne [Guid]::Empty) {
                    return $applicationId
                }
                try { return Get-IDs SL_ID_APPLICATION -hSLC $hSLC } catch {}
                return [Guid]::Empty
            }

            "SL_ID_PRODUCT_SKU" {
                return $SkuId
            }

            "SL_ID_LICENSE" {
                if ($licenseId -and $privateCertificateId -and $licenseId -ne [Guid]::Empty -and $privateCertificateId -ne [Guid]::Empty) {
                    return @($licenseId, $privateCertificateId)
                }
                try { return Get-IDs SL_ID_LICENSE -hSLC $hSLC } catch {}
                return [Guid]::Empty
            }

            "SL_ID_PKEY" {
                if ($pkId -and $pkId -ne [Guid]::Empty) {
                    return $pkId
                }
                if ($pKeyId -and $pKeyId -ne [Guid]::Empty) {
                    return $pKeyId
                }
                try { return Get-IDs SL_ID_PKEY -hSLC $hSLC } catch {}
                return [Guid]::Empty
            }

            "SL_ID_ALL_LICENSES" {
                try { return Get-IDs SL_ID_ALL_LICENSES -hSLC $hSLC } catch {}
                return [Guid]::Empty
            }

            "SL_ID_ALL_LICENSE_FILES" {
                try { return Get-IDs SL_ID_ALL_LICENSE_FILES -hSLC $hSLC } catch {}
                return [Guid]::Empty
            }

            "SL_ID_LICENSE_FILE" {
                if ($fileId -and $fileId -ne [Guid]::Empty) {
                    return $fileId
                }

                # it possible using Get-SLIDList to convert SKU > ID_LICENSE > ID_LICENSE_FILE, but not directly.!
                try { return Get-SLIDList -eQueryIdType SL_ID_LICENSE -eReturnIdType SL_ID_LICENSE_FILE -pQueryId $licenseId } catch {}
                try { return Get-SLIDList -eQueryIdType SL_ID_LICENSE -eReturnIdType SL_ID_LICENSE_FILE -pQueryId $privateCertificateId } catch {}
                return [Guid]::Empty
            }
            default {
                return [Guid]::Empty
            }
        }
    }
    finally {

        if ($null -ne $ppKeyIds -and (
            $ppKeyIds -ne [IntPtr]::Zero) -and (
                $ppKeyIds -ne 0)) {
                    $null = $Global:kernel32::LocalFree($ppKeyIds)
        }

        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}
function Retrieve-TokenSKUInfo {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [Guid]$SkuId,

        [Parameter(Mandatory=$false)]
        [ValidateSet("Table", "MetaData")]
        [string]$Mode = "Table",

        [LibTSforge.TokenStore.TokenStoreModern]$Store,
        [switch]$KeepAlive
    )

    $SPP = @{
        Pub = "msft:sl/EUL/GENERIC/PUBLIC"; Priv = "msft:sl/EUL/GENERIC/PRIVATE"
        Met = "_--_met"; App = "applicationId"; Pk = "pkeyId"; Fil = "fileId"
    }

    $tsPath = [LibTSforge.SPP.SPPUtils]::GetTokensPath(
        [LibTSforge.Utils]::DetectVersion())
    $tsTmp  = [IO.Path]::GetTempFileName()
    
    try {
        if (-not $Store) {
            [File]::Copy($tsPath, $tsTmp, $true)
            $Store = [LibTSforge.TokenStore.TokenStoreModern]::new($tsTmp)
        }
        if (-not $Store) { throw "Store Init Failed" }

        $GetMeta = { param($id) if($id){ try {[LibTSforge.TokenStore.TokenMeta]::new($Store.GetEntry("$($id)$($SPP.Met)", 'xml').Data).Data} catch {} } }

        $SkuData = &$GetMeta $SkuId
        $Pub     = &$GetMeta $(if($SkuData){ $SkuData[$SPP.Pub] })
        $Priv    = &$GetMeta $(if($SkuData){ $SkuData[$SPP.Priv] })

        if ($Mode -eq "Table") {

            # Mode 1: Conversion Table (Friendly Name -> Value)
            return [PSCustomObject]@{
                ID_SKU          = $SkuId.ToString()
                ID_APPLICATION  = $Pub[$SPP.App]
                ID_PKEY         = $SkuData[$SPP.Pk]
                ID_LICENSE      = @($SkuData[$SPP.Pub], $SkuData[$SPP.Priv])
                ID_LICENSE_FILE = $Pub[$SPP.Fil]
            }
        } 
        elseif ($Mode -eq "MetaData") {

            # Mode 2: Extended Info (Internal Metadata)
            return [PSCustomObject]@{

                # --- Product Identification ---
                productName                = $Pub["productName"]
                Family                     = $Pub["Family"]
                productDescription         = $Pub["productDescription"]
                productAuthor              = $Pub["productAuthor"]
                UXDifferentiator           = $Pub["UXDifferentiator"]
                'win:branding'             = $Priv["win:branding"]

                # --- Licensing Configuration & Logic ---
                licenseVersion             = $Pub["licenseVersion"]
                metaInfoType               = $Pub["metaInfoType"]
                ActivationSequence         = $Pub["ActivationSequence"]
                EnableActivationValidation = $Pub["EnableActivationValidation"]
                EnableNotificationMode     = $Pub["EnableNotificationMode"]
                GraceTimerUniqueness       = $Pub["GraceTimerUniqueness"]
                ValidityTimerUniqueness    = $Pub["ValidityTimerUniqueness"]
                ProductKeyGroupUniqueness  = $Pub["ProductKeyGroupUniqueness"]

                # --- Identity & Global IDs ---
                applicationId              = $Pub["applicationId"]
                productSkuId               = $Pub["productSkuId"]
                fileId                     = $Pub["fileId"]
                pkeyConfigLicenseId        = $Pub["pkeyConfigLicenseId"]
                ValidationTemplateId       = $Pub["ValidationTemplateId"]

                # --- Certificates & Security ---
                issuanceCertificateId      = $Pub["issuanceCertificateId"]
                publicCertificateId        = $Priv["publicCertificateId"]
                privateCertificateId       = $Pub["privateCertificateId"]

                # --- Network Endpoints ---
                licensorUrl                = $Pub["licensorUrl"]
                ValidationURL              = $Pub["ValUrl"]
                UseLicenseURL              = $Pub["PAUrl"]
            }
        }
    }
    catch { Write-Error $_ }
    finally {
        if (!($KeepAlive.IsPresent) -and $Store) { $Store.Dispose() }
        if (Test-Path $tsTmp) { Remove-Item $tsTmp -Force }
    }
}

<#
.SYNOPSIS
Function Receive license data as Config or License file
#>
function Get-LicenseData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [Guid]$SkuID,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero,

        [ValidateNotNullOrEmpty()]
        [ValidateSet("License", "Config")]
        [string]$Mode
    )

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }
	
    try {
        $fileGuid = [guid]::Empty
        if ([string]::IsNullOrEmpty($Mode)) {
            throw "Missing Mode Choice"
        }
        if ($Mode -eq 'License') {
            $fileId    = Get-ProductSkuInformation -ActConfigId $SkuID -pwszValueName fileId
        }
        if ($Mode -eq 'Config') {
            $LicenseId = Get-ProductSkuInformation -ActConfigId $SkuID -pwszValueName pkeyConfigLicenseId
            $fileId    = Get-ProductSkuInformation -ActConfigId $LicenseId -pwszValueName fileId
        }
        if (-not $fileId -or (
	        [guid]$fileId -eq [GUID]::Empty)) {
		        return $null
        }

        $count = 0
        $ppbLicenseFile = [IntPtr]::Zero
        $res = $global:SLC::SLGetLicense($hSLC, [ref]$fileId, [ref]$count, [ref]$ppbLicenseFile)
        if ($res -ne 0) { throw "SLGetLicense failed (code $res)" }
        $blob = New-Object byte[] $count
        [Marshal]::Copy($ppbLicenseFile, $blob, 0, $count)
        $content = [Text.Encoding]::UTF8.GetString($blob)
        return $content

    }
    finally {
        Free-IntPtr -handle $ppbLicenseFile -Method Local
        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}

<#
.SYNOPSIS
Function Retrieve-SKUInfo retrieves related licensing IDs for a given SKU GUID.
Convert option, CD-KEY->Ref/ID, Ref->SKU, SKU->Ref
#>
function Retrieve-ProductKeyInfo {
    param (
        [ValidateScript({ $_ -ne $null -and $_ -ne [guid]::Empty })]
        [guid]$SkuId,

        [ValidateScript({ $_ -ne $null -and $_ -gt 0 })]
        [int]$RefGroupId,

        [ValidateScript({ $_ -match '^(?i)[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$' })]
        [string]$CdKey
    )

    # Validate only one parameter
    $paramsProvided = @($SkuId, $RefGroupId, $CdKey) | Where-Object { $_ }
    if ($paramsProvided.Count -ne 1) {
        Write-Warning "Please specify exactly one of -SkuId, -RefGroupId, or -CdKey"
        return $null
    }

    # SkuId to RefGroupId
    if ($SkuId) {
        $entry = $Global:PKeyDatabase | Where-Object { $_.ActConfigId -eq "{$SkuId}" } | Select-Object -First 1
        if ($entry) {
            return $entry.RefGroupId
        } else {
            Write-Warning "RefGroupId not found for SkuId: $SkuId"
            return $null
        }
    }

    # RefGroupId to SkuId
    elseif ($RefGroupId) {
        $entry = $Global:PKeyDatabase | Where-Object { $_.RefGroupId -eq $RefGroupId } | Select-Object -First 1
        if ($entry) {
            return [guid]($entry.ActConfigId -replace '[{}]', '')
        } else {
            Write-Warning "ActConfigId not found for RefGroupId: $RefGroupId"
            return $null
        }
    }

    # CdKey to RefGroupId to SkuId
    elseif ($CdKey) {
        try {
            $decoded = KeyDecode -key0 $CdKey.Substring(0,29)
            $refGroupFromKey = [int]$decoded[2].Value

            $entry = $Global:PKeyDatabase | Where-Object { $_.RefGroupId -eq $refGroupFromKey } | Select-Object -First 1
            if ($entry) {
                return [PSCustomObject]@{
                    RefGroupId = $refGroupFromKey
                    SkuId      = [guid]($entry.ActConfigId -replace '[{}]', '')
                }
            } else {
                Write-Warning "SKU not found for RefGroupId $refGroupFromKey extracted from CD Key"
                return $null
            }
        } catch {
            Write-Warning "Failed to decode CD Key: $_"
            return $null
        }
    }
}

<#
.SYNOPSIS
    Fires a licensing state change event after installing or removing a license/key.
#>
function Fire-LicensingStateChangeEvent {
    param (
        [Parameter(Mandatory=$true)]
        [IntPtr]$hSLC
    )
    
    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }

    try {
        $SlEvent = "msft:rm/event/licensingstatechanged"
        $WindowsSlid = New-Object Guid($Global:windowsAppID)
        $OfficeSlid  = New-Object Guid($Global:OfficeAppId)
        ($WindowsSlid, $OfficeSlid) | % {
            $hrEvent = $Global:SLC::SLFireEvent(
                $hSLC,  # Using the IntPtr (acting like a pointer)
                $SlEvent, 
                [ref]$_
            )

            # Check if the event firing was successful (HRESULT 0 means success)
            if ($hrEvent -eq 0) {
                Write-Host "Licensing state change event fired successfully."
            } else {
                Write-Host "Failed to fire licensing state change event. HRESULT: $hrEvent"
            }
        }
    }
    finally {
        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}

<#
.SYNOPSIS
    Re-Arm Specific ID <> SKU.
#>
Function SL-ReArm {
    param (
        [Parameter(Mandatory=$false)]
        [ValidateSet(
            '0ff1ce15-a989-479d-af46-f275c6370663',
            '55c92734-d682-4d71-983e-d6ec3f16059f'
        )]
        [GUID]$AppID,

        [Parameter(Mandatory=$false)]
        [GUID]$skuID,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
    }

    try {
        if (-not $AppID -or -not $skuID) {
            $hrsults = $Global:slc::SLReArmWindows()
        }
        elseif ($AppID -and $skuID) {
            $AppID_ = [GUID]::new($AppID)
            $skuID_ = [GUID]::new($skuID)
            $hrsults = $Global:slc::SLReArm(
                $hSLC, [ref]$AppID_, [REF]$skuID_, 0)
        }        
        if ($hrsults -ne 0) {
            $errorMessege = Parse-ErrorMessage -MessageId $hrsults -Flags ([ErrorMessageType]::ACTIVATION -bor [ErrorMessageType]::HRESULT)
            Write-Warning "$($hrsults): $($errorMessege)"
        }
        return $hrsults
    }
    finally {
        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}

<#
.SYNOPSIS
    Activate Specific SKU.
#>
Function SL-Activate {
    param (
        [Parameter(Mandatory=$true)]
        [GUID]$skuID,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
    }

    try {
        $skuID_ = [GUID]::new($skuID)
        $hrsults = $Global:slc::SLActivateProduct(
            $hSLC, [REF]$skuID_, 0,[IntPtr]::Zero,[IntPtr]::Zero,$null,0)

        if ($hrsults -ne 0) {
            $errorMessege = Parse-ErrorMessage -MessageId $hrsults -Flags ([ErrorMessageType]::ACTIVATION -bor [ErrorMessageType]::HRESULT)
            Write-Warning "$errorMessege, $hresult"
        }
        return $hrsults
    }
    finally {
        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}

<#
  sppcomapi.dll
  int64 fastcall CTokenActivation::SilentTokenActivate
  int64 fastcall CTokenActivation::SilentTokenActivateBySkuId(CTokenActivation *this, const struct _GUID *a2)
#>
Function SL-ActivateTokenBasedSku {
    param (
        [Guid]$ProductID = [Guid]::Empty
    )

    if (-not $sppcExt) {
        $global:sppcExt = Register-NativeMethods `
            -FunctionList @(
        @{
            Name       = 'SLGetTokenActivationGrants'
            Dll        = 'sppcext.dll'
            ReturnType = [Int32] # HRESULT
            Parameters = @(
                [IntPtr],                # hSLC (HSLC)
                [Guid].MakeByRefType(),  # pProductID (const GUID*)
                [IntPtr].MakeByRefType() # phGrants (HLOCAL*)
            )
        },
        @{
            Name       = 'SLGetTokenActivationCertificates'
            Dll        = 'sppcext.dll'
            ReturnType = [Int32] # HRESULT
            Parameters = @(
                [IntPtr],                # hGrants (HLOCAL)
                [UInt32],                # dwCertType (UINT)
                [IntPtr].MakeByRefType() # phCerts (HLOCAL*)
            )
        },
        @{
            Name       = 'SLGenerateTokenActivationChallenge'
            Dll        = 'sppcext.dll'
            ReturnType = [Int32] # HRESULT
            Parameters = @(
                [IntPtr],                # hSLC (HSLC)
                [Guid].MakeByRefType(),  # pProductID (const GUID*)
                [UInt32].MakeByRefType(),# pcbChallenge (UINT*)
                [IntPtr].MakeByRefType() # phChallenge (HLOCAL*)
            )
        },
        @{
            Name       = 'SLSignTokenActivationChallenge'
            Dll        = 'sppcext.dll'
            ReturnType = [Int32] # HRESULT
            Parameters = @(
                [IntPtr],                # hCert (HLOCAL)
                [UInt32],                # cbChallenge (UINT)
                [IntPtr],                # pbChallenge (HLOCAL/PBYTE)
                [IntPtr],                # pReserved (Always NULL)
                [UInt32],                # dwFlags
                [UInt32].MakeByRefType(),# pcbSignature (UINT*)
                [IntPtr].MakeByRefType(),# ppbSignature (PBYTE*)
                [IntPtr].MakeByRefType(),# ppbResponseValue (PBYTE*)
                [IntPtr].MakeByRefType() # phResponseMem (HLOCAL*)
            )
        },
        @{
            Name       = 'SLDepositTokenActivationResponse'
            Dll        = 'sppcext.dll'
            ReturnType = [Int32] # HRESULT
            Parameters = @(
                [IntPtr],                # hSLC
                [Guid].MakeByRefType(),  # pProductID
                [UInt32],                # cbChallenge
                [IntPtr],                # pbChallenge
                [UInt32],                # cbSignature
                [IntPtr],                # pbSignature
                [IntPtr],                # pbResponseValue
                [IntPtr]                 # hResponseMem
            )
        },
        @{
            Name       = 'SLFreeTokenActivationCertificates'
            Dll        = 'sppcext.dll'
            ReturnType = [Int32] # HRESULT
            Parameters = @( [IntPtr] )   # hCerts
        },
        @{
            Name       = 'SLFreeTokenActivationGrants'
            Dll        = 'sppcext.dll'
            ReturnType = [Int32] # HRESULT
            Parameters = @( [IntPtr] )   # hGrants
        })
    }

    if ($ProductID -eq [Guid]::Empty) {
        $ProductID = (Get-ActiveLicenseInfo).ActivationID
    }
    [IntPtr]$hSLC = Manage-SLHandle
    [IntPtr]$hGrants = [IntPtr]::Zero
    [IntPtr]$hChallenge = [IntPtr]::Zero
    [UInt32]$cbChallenge = 0x0
    $pProductID = [Ref]$ProductID

    try {
        $hr = $sppcExt::SLGetTokenActivationGrants($hSLC, $pProductID, [ref]$hGrants)
        if ($hr -ne 0) { throw "Failed to get grants: $hr" }

        $certTypes = @(2,1)
        foreach ($currentType in $certTypes) {
            
            [IntPtr]$pCerts = [IntPtr]::Zero
            $hr = $sppcExt::SLGetTokenActivationCertificates($hGrants, $currentType, [ref]$pCerts)
            if ($hr -eq -1073417467 -or $hr -lt 0 -or $pCerts -eq [IntPtr]::Zero) { continue }

            if ($hChallenge -eq [IntPtr]::Zero) {
                $hr = $sppcExt::SLGenerateTokenActivationChallenge($hSLC, $pProductID, [ref]$cbChallenge, [ref]$hChallenge)
                if ($hr -ne 0) { continue }
            }

            $certCount = [Marshal]::ReadInt32($pCerts)
            for ($j = 0; $j -lt $certCount; $j++) {

                [UInt32]$cbSignature = 0x0
                [IntPtr]$pSignature = 0L
                [IntPtr]$pResponseValue = 0L
                [IntPtr]$hResponseMem = 0L

                $offset = [IntPtr]::Size + ($j * [IntPtr]::Size)
                $currentCertHandle = [Marshal]::ReadIntPtr($pCerts, $offset)

                $hr = $sppcExt::SLSignTokenActivationChallenge(
                    $currentCertHandle, $cbChallenge, $hChallenge, 
                    [IntPtr]::Zero, 0x1, 
                    [ref]$cbSignature, [ref]$pSignature, 
                    [ref]$pResponseValue, [ref]$hResponseMem
                )

                if ($hr -eq -1073417467) { break }
                if ($hr -eq 0) {
                    $hr = $sppcExt::SLDepositTokenActivationResponse(
                        $hSLC, $pProductID, $cbChallenge, $hChallenge,
                        $cbSignature, $pSignature, $pResponseValue, $hResponseMem
                    )
                    if ($hResponseMem -ne [IntPtr]::Zero) {
                        [void]$global:kernel32::LocalFree($hResponseMem)
                    }
                    if ($hGrants -ne [IntPtr]::Zero) {
                        [void]$sppcExt::SLFreeTokenActivationGrants($hGrants)
                        $hGrants = [IntPtr]::Zero
                    }
                    if ($hChallenge -ne [IntPtr]::Zero) {
                        [void]$global:kernel32::LocalFree($hChallenge)
                        $hChallenge = [IntPtr]::Zero
                    }
                    if ($hr -eq 0) { return $true }
                }
            }
            $sppcExt::SLFreeTokenActivationCertificates($pCerts)
        }
    }
    catch {
        Write-Error "Token Activation Error: $_"
    }
    finally {
        if ($hGrants -ne [IntPtr]::Zero) { [void]$sppcExt::SLFreeTokenActivationGrants($hGrants) }
        if ($hChallenge -ne [IntPtr]::Zero) { [void]$global:kernel32::LocalFree($hChallenge) }
    }
    return $false
}

<#
.SYNOPSIS
    Activates Windows/Office offline by generating an Installation ID, 
    fetching a Confirmation ID via web service, and depositing it into the system.
#>
Function Invoke-OfflineActivation {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Office", "Windows")]
        [string]$SkuType
    )

    try {
        $Module = [AppDomain]::CurrentDomain.GetAssemblies()| ? { $_.ManifestModule.ScopeName -eq "OFFLINE" } | select -Last 1
        $Global:OFFLINE = $Module.GetTypes()[0]
    }
    catch {
        $Module = [AppDomain]::CurrentDomain.DefineDynamicAssembly("null", 1).DefineDynamicModule("OFFLINE", $False).DefineType("null")
        @(
            @('null', 'null', [int], @()), # place holder
            @('SLGenerateOfflineInstallationIdEx', 'sppc.dll', [Int32], @([IntPtr], [Guid].MakeByRefType(), [Int32], [IntPtr].MakeByRefType())),
            @('SLDepositOfflineConfirmationId',    'sppc.dll', [Int32], @([IntPtr], [Guid].MakeByRefType(), [IntPtr], [IntPtr]))

        ) | % {
            $Module.DefinePInvokeMethod(($_[0]), ($_[1]), 22, 1, [Type]($_[2]), [Type[]]($_[3]), 1, 3).SetImplementationFlags(128) # Def` 128, fail-safe 0
        }
        $Global:OFFLINE = $Module.CreateType()
    }

    $sppData = Get-SppStoreLicense -SkuType $SkuType -IgnoreEsu
    if (-not $sppData) {
        Write-Error "Could not found SPP Store data"
        return
    }
    foreach ($obj in $sppData) {
        
        $hr   = 0x0
        $hSLC = Manage-SLHandle
        $InstallationId = ''
        $pwszInstallationId = 0L

        $rawString     = $obj.DigitalProductId4
        $AdvancedPID   = ($rawString -split ",")[0].Replace("DPID v4.0: ", "").Trim()
        $pProductSkuId = [Guid]($obj.SkuId)

        try {
            $hr = $Global:OFFLINE::SLGenerateOfflineInstallationIdEx(
                $hSLC, [ref]$pProductSkuId, 0, [ref]$pwszInstallationId)
            if ($hr -eq 0x0) {
                $InstallationId = [marshal]::PtrToStringUni($pwszInstallationId)
            }
            if ($hr -ne 0) { 
                Write-Warning "GenerateOfflineInstallationIdEx Fail {$pProductSkuId}"
                continue
            }
            $pwszConfirmationId = Call-WebService `
                -requestType 1 `
                -installationId $InstallationId `
                -extendedProductId $AdvancedPID
            if ($pwszConfirmationId.Length -ne 48) {
                Write-Warning "Call-WebService Fail {$pProductSkuId}"
                continue
            }
            $hr = $Global:OFFLINE::SLDepositOfflineConfirmationId(
                $hSLC, [ref]$pProductSkuId, $pwszInstallationId, $pwszConfirmationId)
            Write-warning "SkuID: $pProductSkuId, Deposit Results : $hr"
        }
        finally {
            [marshal]::FreeHGlobal($pwszInstallationId)
            $pwszInstallationId = 0L
        }
    }
}

<#
.SYNOPSIS
   WMI -> RefreshLicenseStatus
#>
Function SL-RefreshLicenseStatus {
    param (
        [Parameter(Mandatory=$false)]
        [ValidateSet(
            '0ff1ce15-a989-479d-af46-f275c6370663',
            '55c92734-d682-4d71-983e-d6ec3f16059f'
        )]
        [GUID]$AppID,

        [Parameter(Mandatory=$false)]
        [GUID]$skuID,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
    }

    try {
        if (-not $AppID -and -not $skuID) {
            $hrsults = $Global:slc::SLConsumeWindowsRight($hSLC)
        }
        elseif ($AppID) {
            $AppID_ = [GUID]::new($AppID)
            if (-not $skuID) {
                $hrsults = $Global:slc::SLConsumeRight(
                    $hSLC, [ref]$AppID_, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero)
            }
            else {
                $skuID_ = [GUID]::new($skuID)
                $skuIDPtr = New-IntPtr -Size 16
                try {
                    [Marshal]::StructureToPtr($skuID_, $skuIDPtr, $false)
                    $hrsults = $Global:slc::SLConsumeRight(
                        $hSLC, [ref]$AppID_, $skuIDPtr, [IntPtr]::Zero, [IntPtr]::Zero)
                }
                finally {
                    New-IntPtr -hHandle $skuIDPtr -Release
                }
            }
        }
        elseif ($skuID) {
            $skuID_ = [GUID]::new($skuID)
            $AppID_ = Retrieve-SKUInfo -SkuId $skuID -eReturnIdType SL_ID_APPLICATION
            if (-not $AppID_) {
                throw "Couldn't retrieve AppId for SKU: $skuID"
            }
            $skuIDPtr = New-IntPtr -Size 16
            try {
                [Marshal]::StructureToPtr($skuID_, $skuIDPtr, $false)
                $hrsults = $Global:slc::SLConsumeRight(
                    $hSLC, [ref]$AppID_, $skuIDPtr, [IntPtr]::Zero, [IntPtr]::Zero)
            }
            finally {
                New-IntPtr -hHandle $skuIDPtr -Release
            }
        }

        if ($hrsults -ne 0) {
            $errorMessege = Parse-ErrorMessage -MessageId $hrsults -Flags ([ErrorMessageType]::ACTIVATION -bor [ErrorMessageType]::HRESULT)
            Write-Warning "$($hrsults): $($errorMessege)"
        }
        return $hrsults
    }
    finally {
        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}

<#
.SYNOPSIS

Usage: KEY
SL-InstallProductKey -Keys "3HYJN-9KG99-F8VG9-V3DT8-JFMHV"
SL-InstallProductKey -Keys ("BW9HJ-N9HF7-7M9PW-3PBJR-37DCT","NJ8QJ-PYYXJ-F6HVQ-RYPFK-BKQ86","K8BH4-6TN3G-YXVMY-HBMMF-KBXPT","GMN9H-QCX29-F3JWJ-RYPKC-DDD86","TN6YY-MWHCT-T6PK2-886FF-6RBJ6")
#>
function SL-InstallProductKey {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Keys,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }

    [guid[]]$PKeyIdLst = @()

    try {
        if (-not $Keys) {
            Write-Warning "No product keys provided. Please provide at least one key."
            return $null
        }

        $invalidKeys = $Keys | Where-Object { [string]::IsNullOrWhiteSpace($_) }
        if ($invalidKeys.Count -gt 0) {
            Write-Warning "The following keys are invalid (empty or whitespace): $($invalidKeys -join ', ')"
            return $null
        }

        foreach ($key in $Keys) {
            $KeyBlob = [System.Text.Encoding]::UTF8.GetBytes($key)
            $KeyTypes = @(
                "msft:rm/algorithm/pkey/detect",
                "msft:rm/algorithm/pkey/2009",
                "msft:rm/algorithm/pkey/2007",
                "msft:rm/algorithm/pkey/2005"
            )

            $PKeyIdOut = [Guid]::NewGuid()
            $installationSuccess = $false

            foreach ($KeyType in $KeyTypes) {
                $hrInstall = $Global:SLC::SLInstallProofOfPurchase(
                    $hSLC,
                    $KeyType,
                    $key,            # Directly using the key string
                    0,               # PKeyDataSize is 0 (no additional data)
                    [IntPtr]::Zero,  # No additional data (zero pointer)
                    [ref]$PKeyIdOut
                )

                if ($hrInstall -eq 0) {
                    Write-Host "Proof of purchase installed successfully with KeyType: $KeyType. PKeyId: $PKeyIdOut"
                    $PKeyIdLst += $PKeyIdOut  # Add the successful GUID to the list
                    $installationSuccess = $true  # Mark success for this key
                    break
                }
            }

            if (-not $installationSuccess) {
                $errorMessege = Parse-ErrorMessage -MessageId $hrInstall -Flags ([ErrorMessageType]::ACTIVATION -bor [ErrorMessageType]::HRESULT)
                Write-Warning "Failed to install the proof of purchase for key $key. HRESULT: $hrInstall"
                Write-Warning "$($hrInstall): $($errorMessege)"
            }
        }
    }
    finally {

        Fire-LicensingStateChangeEvent -hSLC $hSLC     
        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }

    # Return list of successfully installed PKeyIds
    # return $PKeyIdLst
}

<#
.SYNOPSIS
Usage: KEY -OR SKU -OR PKEY
Usage: Remove Current Windows KEY

Example.
SL-UninstallProductKey -ClearKey $true
SL-UninstallProductKey -KeyLst ("3HYJN-9KG99-F8VG9-V3DT8-JFMHV", "JFMHV") -skuList @("dabaa1f2-109b-496d-bf49-1536cc862900") -pkeyList @("e953e4ac-7ce5-0401-e56c-70c13b8e5a82")
#>
function SL-UninstallProductKey {
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$KeyLst,  # List of partial product keys (optional)

        [Parameter(Mandatory = $false)]
        [GUID[]]$skuList,  # List of GUIDs (optional)

        [Parameter(Mandatory = $false)]
        [GUID[]]$pkeyList,  # List of GUIDs (optional),

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero,

        [Parameter(Mandatory=$false)]
        [switch]$ClearKey
    )

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }

    try {
        # Initialize the list to hold GUIDs
        $guidList = @()

        if (-not ($skuList -or $KeyLst -or $pkeyList) -and !$ClearKey) {
            Write-Warning "No provided SKU or Key"
            return
        }
        
        $validSkuList = @()
        $validCdKeys  = @()
        $validPkeyList = @()
        if ($KeyLst) {
            foreach ($key in $KeyLst) {
                if ($key.Length -eq 5 -or $key -match '^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$') {
                    $validCdKeys += $key
                }}}
        if ($skuList) {
            foreach ($sku in $skuList) {
                if ($sku -match '^[{]?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}[}]?$') {
                    $validSkuList += [guid]$sku  }}}
        if ($pkeyList) {
            foreach ($pkey in $pkeyList) {
                if ($pkey -match '^[{]?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}[}]?$') {
                    $validPkeyList += [guid]$pkey }}}

        $results = @()
        foreach ($guid in (
            Get-SLIDList -eQueryIdType SL_ID_PRODUCT_SKU -eReturnIdType SL_ID_PRODUCT_SKU)) {
                $ID_PKEY = Retrieve-SKUInfo -SkuId $guid -eReturnIdType SL_ID_PKEY
                if ($ID_PKEY) {
                    $results += [PSCustomObject]@{
                        SL_ID_PRODUCT_SKU = $guid
                        SL_ID_PKEY = $ID_PKEY
                        PartialProductKey = Get-SLCPKeyInfo -PKEY $ID_PKEY -pwszValueName PartialProductKey
                    }}}

        if ($KeyLst) {
            foreach ($key in $KeyLst) {
                if ($key.Length -eq 29) {
                    $pPKeyId = [GUID]::Empty
                    $AlgoTypes = @(
                        "msft:rm/algorithm/pkey/detect",
                        "msft:rm/algorithm/pkey/2009",
                        "msft:rm/algorithm/pkey/2007",
                        "msft:rm/algorithm/pkey/2005"
                    )
                    foreach ($type in $AlgoTypes) {
                        $hresults = $Global:SLC::SLGetPKeyId(
                            $hSLC,$type,$key,[Intptr]::Zero,[Intptr]::Zero,[ref]$pPKeyId)
                        if ($hresults -eq 0) {
                            break;
                        }
                    }
                    if ($hresults -eq 0 -and (
                        $pPKeyId -ne [GUID]::Empty)) {
                            $results += [PSCustomObject]@{
                                SL_ID_PRODUCT_SKU = $null
                                SL_ID_PKEY = $pPKeyId
                                PartialProductKey = $key
                            }
                    }
                }
            }
        }

        # Initialize filtered results array
        $filteredResults = @()
        foreach ($item in $results) {          
            $isValidPkey = $validPkeyList -contains $item.SL_ID_PKEY
            $isValidKey  = $validCdKeys -contains $item.PartialProductKey
            $isValidSKU  = $validSkuList -contains $item.SL_ID_PRODUCT_SKU
            if ($isValidKey){
                write-warning "Valid key found, $($item.PartialProductKey)"
            }
            if ($isValidSKU){
                write-warning "Valid SKU found, $($item.SL_ID_PRODUCT_SKU)"
            }
            if ($isValidPkey){
                write-warning "Valid PKEY found, $($item.SL_ID_PKEY)"
            }
            if ($isValidKey -or $isValidSKU -or $isValidPkey) {
                $filteredResults += $item
            }
        }

        # Step 3: Retrieve unique SL_ID_PKEY values from the filtered results
        $SL_ID_PKEY_list = $filteredResults | Select-Object -ExpandProperty SL_ID_PKEY | Sort-Object | Select-Object -Unique

        if ($ClearKey) {
            $pPKeyId = [GUID]::Empty
            $AlgoTypes = @(
                "msft:rm/algorithm/pkey/detect",
                "msft:rm/algorithm/pkey/2009",
                "msft:rm/algorithm/pkey/2007",
                "msft:rm/algorithm/pkey/2005"
            )
            $DigitalKey  = $(Parse-DigitalProductId).DigitalKey
            if (-not $DigitalKey) {
                $DigitalKey = $(Parse-DigitalProductId4).DigitalKey
            }
            if ($DigitalKey) {
                foreach ($type in $AlgoTypes) {
                    $hresults = $Global:SLC::SLGetPKeyId(
                        $hSLC,$type,$DigitalKey,[Intptr]::Zero,[Intptr]::Zero,[ref]$pPKeyId)
                    if ($hresults -eq 0) {
                        break;
                    }
                }
                if ($hresults -eq 0 -and (
                    $pPKeyId -ne [GUID]::Empty)) {
                        $SL_ID_PKEY_list = @($pPKeyId)
                }
            }
        }

        # Proceed to uninstall each product key using its GUID
        foreach ($guid in $SL_ID_PKEY_list) {
            if ($guid) {
                Write-Host "Attempting to uninstall product key with GUID: $guid"
                $hrUninstall = $Global:SLC::SLUninstallProofOfPurchase($hSLC, $guid)

                if ($hrUninstall -eq 0) {
                    Write-Host "Product key uninstalled successfully: $guid"
                } else {
                    $uint32Value = $hrUninstall -band 0xFFFFFFFF
                    $hexString = "0x{0:X8}" -f $uint32Value
                    Write-Warning "Failed to uninstall product key with HRESULT: $hexString for GUID: $guid"
                }
            } else {
                Write-Warning "Skipping invalid GUID: $guid"
            }
        }
    }
    catch {
        Write-Warning "An unexpected error occurred: $_"
    }
    finally {
        
        # Launch event of license status change after license/key install/remove
        Fire-LicensingStateChangeEvent -hSLC $hSLC

        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}

<#
.SYNOPSIS

# Path to license file
$licensePath = 'C:\Program Files\Microsoft Office\root\Licenses16\client-issuance-bridge-office.xrm-ms'

if (-not (Test-Path $licensePath)) {
    Write-Warning "License file not found: $licensePath"
    return
}

# 1. Install license from file path (string)
Write-Host "`n--- Installing from file path ---"
$result1 = SL-InstallLicense -LicenseInput $licensePath
Write-Host "Result (file path): $result1`n"

# 2. Install license from byte array
Write-Host "--- Installing from byte array ---"
$bytes = [System.IO.File]::ReadAllBytes($licensePath)
$result2 = SL-InstallLicense -LicenseInput $bytes
Write-Host "Result (byte array): $result2`n"

# 3. Install license from text string
Write-Host "--- Installing from text string ---"
$licenseText = Get-Content $licensePath -Raw
$result3 = SL-InstallLicense -LicenseInput $licenseText
Write-Host "Result (text): $result3`n"
#>
function SL-InstallLicense {
    param (
        # Can be string (file path or raw text) or byte[]
        [Parameter(Mandatory = $true)]
        [object[]]$LicenseInput,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )
    
    # Prepare to install license
    $LicenseFileIdOut = [Guid]::NewGuid()
    # Store the file IDs for all successfully installed licenses
    $LicenseFileIds = @()

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }

    try {
        # Initialize an array to store blobs
        $LicenseBlobs = @()

        # Loop through each license input
        foreach ($input in $LicenseInput) {
            # Determine the type of input and process accordingly
            if ($input -is [byte[]]) {
                # If input is already a byte array, use it directly
                $LicenseBlob = $input
            }
            elseif ($input -is [string]) {
                if (Test-Path $input) {
                    # If it's a file path, read the file and get its byte array
                    $LicenseBlob = [System.IO.File]::ReadAllBytes($input)
                }
                else {
                    # If it's plain text, convert the text to a byte array
                    $LicenseBlob = [Encoding]::UTF8.GetBytes($input)
                }
            }
            else {
                Write-Warning "Invalid input type. Provide a file path, byte array, or text string."
                continue
            }

            if ($LicenseBlob) {
                # Pin the current blob in memory // use helper instead
                $blobPtr = New-IntPtr -Data $LicenseBlob
                $hrInstall = $Global:SLC::SLInstallLicense($hSLC, $LicenseBlob.Length, $blobPtr, [ref]$LicenseFileIdOut)
                Free-IntPtr -handle $blobPtr -Method Auto

                # Check if the installation was successful (HRESULT 0 means success)
                if ($hrInstall -ne 0) {
                    $errorMessege = Parse-ErrorMessage -MessageId $hrInstall -Flags ([ErrorMessageType]::ACTIVATION -bor [ErrorMessageType]::HRESULT)
                    if ($errorMessege) {
                        Write-Warning "$($hrInstall): $($errorMessege)"
                    } else {
                        Write-Warning "Unknown error HRESULT $hexString"
                    }
                    Write-Warning "Failed to install the proof of purchase for key $key. HRESULT: $hrInstall"
                    continue  # Skip to the next blob if the current installation fails
                }

                # If successful, add the LicenseFileIdOut to the array
                $LicenseFileIds += $LicenseFileIdOut
                Write-Host "Successfully installed license with FileId: $LicenseFileIdOut"
            }

        }
    }
    finally {
        # Launch event of license status change after license/key install/remove
        Fire-LicensingStateChangeEvent -hSLC $hSLC

        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }

    # Return all the File IDs that were successfully installed
    #return $LicenseFileIds
}

<#
.SYNOPSIS
Uninstalls the license specified by the license file ID and target user option.

By --> SL_ID_ALL_LICENSE_FILES
$OfficeAppId  = '0ff1ce15-a989-479d-af46-f275c6370663'
$SL_ID_List = Get-SLIDList -eQueryIdType SL_ID_APPLICATION -pQueryId $OfficeAppId -eReturnIdType SL_ID_ALL_LICENSE_FILES
SL-UninstallLicense -LicenseFileIds $SL_ID_List

By --> SL_ID_PRODUCT_SKU -->
$OfficeAppId  = '0ff1ce15-a989-479d-af46-f275c6370663'
$WMI_QUERY = Get-SLIDList -eQueryIdType SL_ID_APPLICATION -eReturnIdType SL_ID_PRODUCT_SKU -pQueryId $OfficeAppId
SL-UninstallLicense -ProductSKUs $WMI_QUERY

>>> Results >> 

ActConfigId                            ProductDescription                  
-----------                            ------------------                  
{DABAA1F2-109B-496D-BF49-1536CC862900} Office16_O365AppsBasicR_Subscription

>>> Command >>
SL-UninstallLicense -ProductSKUs ('DABAA1F2-109B-496D-BF49-1536CC862900' -as [GUID])
#>
function SL-UninstallLicense {
    param (
        [Parameter(Mandatory=$false)]
        [Guid[]]$ProductSKUs,

        [Parameter(Mandatory=$false)]
        [Guid[]]$LicenseFileIds,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    if (-not $ProductSKUs -and -not $LicenseFileIds) {
        throw "You must provide at least one of -ProductSKUs or -LicenseFileIds."
    }

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }

    try {
        
        $LicenseFileIdsLst = @()

        # Add valid LicenseFileIds directly
        if ($LicenseFileIds) {
            foreach ($lfid in $LicenseFileIds) {
                if ($lfid -is [Guid]) {
                    $LicenseFileIdsLst += $lfid }}}

        # Convert each ProductSKU to LicenseFileId and add it
        if ($ProductSKUs) {
            foreach ($sku in $ProductSKUs) {
                if ($sku -isnot [Guid]) { continue }
                $fileGuid = Retrieve-SKUInfo -SkuId $sku -eReturnIdType SL_ID_LICENSE_FILE -hSLC $hSLC
                if ($fileGuid -and ($fileGuid -is [Guid]) -and ($fileGuid -ne [Guid]::Empty)) {
                    $LicenseFileIdsLst += $fileGuid }}}

        foreach ($LicenseFileId in ($LicenseFileIdsLst | Sort-Object -Unique)) {
            $hresult = $Global:SLC::SLUninstallLicense($hSLC, [ref]$LicenseFileId)
            if ($hresult -ne 0) {
                $errorMessege = Parse-ErrorMessage -MessageId $hresult -Flags ([ErrorMessageType]::ACTIVATION -bor [ErrorMessageType]::HRESULT)
                Write-Warning "$errorMessege, $hresult"
            } 
            else {
                Write-Warning "License File ID: $LicenseFileId was removed."
            }
        }
        
    }
    catch {
        # Convert to unsigned 32-bit int (number)
        $hresult = $_.Exception.HResult
        if ($hresult -ne 0) {
            $errorMessege = Parse-ErrorMessage -MessageId $hresult -Flags ([ErrorMessageType]::ACTIVATION -bor [ErrorMessageType]::HRESULT)
            Write-Warning "$errorMessege, $hresult"
        }
    }
    finally {
        
        # Launch event of license status change after license/key install/remove
        Fire-LicensingStateChangeEvent -hSLC $hSLC

        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}

<#
.SYNOPSIS
Retrieves Software Licensing Client status for application and product SkuID.

Example <1>

Clear-Host
Write-Host

#Default Guid For Windows & Office
$windowsAppID = '55c92734-d682-4d71-983e-d6ec3f16059f'
$OfficeAppId  = '0ff1ce15-a989-479d-af46-f275c6370663'

# Get All Sku Per Application Id
#Get-SLLicensingStatus # default $windowsAppID
#Get-SLLicensingStatus $windowsAppID
#Get-SLLicensingStatus $OfficeAppId

# Get SkuiId info Of 'ed655016-a9e8-4434-95d9-4345352c2552'
#Get-SLLicensingStatus $null ed655016-a9e8-4434-95d9-4345352c2552
#Get-SLLicensingStatus $windowsAppID ed655016-a9e8-4434-95d9-4345352c2552

# Extra Option's
#Get-SLLicensingStatus
#Get-SLLicensingStatus -Expend
#Get-SLLicensingStatus -SkuID ed655016-a9e8-4434-95d9-4345352c2552
#Get-SLLicensingStatus -Expend | ? LicenseStatus -ne Unlicensed 

Example <2>

$LicensingProducts = (
    Get-SLIDList -eQueryIdType SL_ID_APPLICATION -eReturnIdType SL_ID_PRODUCT_SKU -pQueryId $windowsAppID | ? { Retrieve-SKUInfo -SkuId $_ -eReturnIdType SL_ID_PKEY }
    ) | % {
    [PSCustomObject]@{
        ID            = $_
        PKEY          = Retrieve-SKUInfo -SkuId $_ -eReturnIdType SL_ID_PKEY
        Description   = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Description'
        Name          = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'productName'
        LicenseFamily = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Family'
    }
}

Clear-Host
$LicensingProducts | % { 
    Write-Host
    Write-Warning "Get-SLCPKeyInfo Function"
    Get-SLCPKeyInfo -PKEY ($_).PKEY -loopAllValues

    Write-Host
    Write-Warning "Get-SLLicensingStatus"
    Get-SLLicensingStatus -ApplicationID 55c92734-d682-4d71-983e-d6ec3f16059f -SkuID ($_).ID

    Write-Host
    Write-Warning "Get-GenuineInformation"
    Write-Host
    Get-GenuineInformation -QueryId ($_).ID -loopAllValues

    Write-Host
    Write-Warning "Get-ApplicationInformation"
    Write-Host
    Get-ApplicationInformation -ApplicationId ($_).ID -loopAllValues
}
#>
enum LicenseStatusEnum {
    Unlicensed        = 0
    Licensed          = 1
    OOBGrace          = 2
    OOTGrace          = 3
    NonGenuineGrace   = 4
    Notification      = 5
    ExtendedGrace     = 6
}
enum LicenseCategory {
    KMS38        # Valid until 2038
    KMS4K        # Beyond 2038
    ShortTermVL  # Volume expiring within 6 months
    Unknown
    NonKMS
}
function Get-SLLicensingStatus {
    [CmdletBinding()]
    param(
        [Nullable[Guid]]$ApplicationID = $null,
        [Nullable[Guid]]$SkuID = $null,
        [switch]$Expend,
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    function Test-Guid {
        [CmdletBinding()]
        param (
            [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
            [object] $Value
        )
        process {
            if (-not $Value) { return $false }
            try {
                $guid = [Guid]::Parse($Value.ToString())
                return ($guid -ne [Guid]::Empty)
            } catch { return $false }
        }
    }

    # Or both null, Or both same,
    # but If one exist, we can handle things
    # $ApplicationID & [Optional: $skuId]
    # But even with just $skuId, we can get -> $ApplicationID
    # And still continue

    if ([Guid]::Equals($SkuID, $ApplicationID)) {
        $ApplicationID = [Guid]'55c92734-d682-4d71-983e-d6ec3f16059f'
    }
    if (!(Test-Guid $ApplicationID)) {
        try {
            $ApplicationID = Retrieve-SKUInfo -SkuId $SkuID -eReturnIdType SL_ID_APPLICATION
        } catch { }
        if (!(Test-Guid $ApplicationID)) {
            return $null
        }
    }

    # region --- Handle management ---
    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }
    # endregion

    # region --- Define struct if not already loaded ---
    if (-not ([PSTypeName]'SL_LICENSING_STATUS').Type) {
        New-Struct `
            -Module (New-InMemoryModule -ModuleName SL_LICENSING_STATUS) `
            -FullName SL_LICENSING_STATUS `
            -StructFields @{
                SkuId                = New-field 0 Guid
                eStatus              = New-field 1 Int32
                dwGraceTime          = New-field 2 UInt32
                dwTotalGraceDays     = New-field 3 UInt32
                hrReason             = New-field 4 Int32
                qwValidityExpiration = New-field 5 UInt64
            } | Out-Null
    }
    # endregion

    try {
        # region --- Call SL API ---
        $pAppID = [Guid]$ApplicationID
        $pSkuId = if (!$SkuID -or $SkuID -eq [Guid]::Empty) { [IntPtr]::Zero } else { Guid-Handler $SkuID $null Pointer }
        $pnCount = [uint32]0
        $ppStatus = [IntPtr]::Zero

        $result = $global:slc::SLGetLicensingStatusInformation(
            $hSLC,
            [ref]$pAppID,
            $pSkuId,
            [IntPtr]::Zero,
            [ref]$pnCount,
            [ref]$ppStatus
        )

        Free-IntPtr $pSkuId
        # endregion

        if ($result -ne 0 -or $pnCount -le 0 -or $ppStatus -eq [IntPtr]::Zero) {
            Write-Warning ("SLGetLicensingStatusInformation returned 0x{0:X8}" -f $result)
            return $null
        }

        # region --- Build results ---
        $blockSize = [Marshal]::SizeOf([Type][SL_LICENSING_STATUS])
        $LicensingStatusArr = New-Object SL_LICENSING_STATUS[] $pnCount

        0..($pnCount - 1) | % {
            $LicensingStatusArr[$_] = [SL_LICENSING_STATUS]([IntPtr]::Add($ppStatus, $_ * $blockSize))
        }

        if (Test-Guid $SkuID) {
            $ItemsToProcess = $LicensingStatusArr | Where-Object { $_.SkuId -eq $SkuID } | Select-Object -First 1
        } else {
            if ($expend.IsPresent) {
                $ItemsToProcess = $LicensingStatusArr
            } else {
                return $LicensingStatusArr
            }
        }

        $Results = @()
        foreach ($Status in $ItemsToProcess) {
            # --- Logic starts once here ---
            $expirationDateTime = $null
            if ($Status.qwValidityExpiration -gt 0) {
                try { $expirationDateTime = [DateTime]::FromFileTimeUtc($Status.qwValidityExpiration) } catch { }
            }

            $now = Get-Date
            $graceExpiration = $now.AddMinutes($Status.dwGraceTime)
            $daysLeft = ($graceExpiration - $now).Days

            $licenseCategory = $Global:PKeyDatabase | 
                Where-Object ActConfigId -eq "{$($Status.SkuID)}" | 
                Select-Object -First 1 -ExpandProperty ProductKeyType

            switch -Regex ($licenseCategory) {
                'Volume:GVLK' {
                    if ($graceExpiration.Year -gt 2038) { $typeKMS = [LicenseCategory]::KMS4K }
                    elseif ($graceExpiration.Year -in 2037, 2038) { $typeKMS = [LicenseCategory]::KMS38 }
                    elseif ($daysLeft -le 180 -and $daysLeft -ge 0) { $typeKMS = [LicenseCategory]::ShortTermVL }
                    else { $typeKMS = [LicenseCategory]::Unknown }
                }
                default { $typeKMS = [LicenseCategory]::NonKMS }
            }

            $errorMessage = Parse-ErrorMessage -MessageId $Status.hrReason -Flags ACTIVATION
            $hrHex = '0x{0:X8}' -f ($Status.hrReason -band 0xFFFFFFFF)

            $Results += [PSCustomObject]@{
                ID                   = $Status.SkuID
                LicenseStatus        = [Enum]::GetName([LicenseStatusEnum], $Status.eStatus)
                GracePeriodRemaining = $Status.dwGraceTime
                TotalGraceDays       = $Status.dwTotalGraceDays
                EvaluationEndDate    = $expirationDateTime
                LicenseStatusReason  = $hrHex
                LicenseChannel       = $licenseCategory
                LicenseTier          = $typeKMS
                ApiCallHResult       = ('0x{0:X8}' -f $result)
                ErrorMessage         = $errorMessage
            }
        }
        return $Results
        # endregion
    }
    catch {
        Write-Warning "Error while retrieving licensing info: $_"
        return $null
    }
    finally {
        Free-IntPtr -handle $ppStatus -Method Local
        if ($closeHandle) {
            Write-Warning "Releasing temporary SLC handle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}

<#
.SYNOPSIS
Gets the information of the specified product key.
work for all sku that are activated AKA [SL_ID_PKEY],
else, no results.

~~~~~~~~~~~~~~~~~~~~~~

sppobjs.dll
__int64 __fastcall sub_180111DFC(__int64 a1, const wchar_t *a2)
  if ( wcscmp(a2, L"SppBindingPkeyId") )
  {
    if ( !wcscmp(a2, L"DigitalPID2")
      || !wcscmp(a2, L"DigitalPID")
      || !wcscmp(a2, L"Pid2")
      || !wcscmp(a2, L"ProductSkuId")
      || !wcscmp(a2, L"Channel")
      || !wcscmp(a2, L"ProductKeySerial") )

~~~~~~~~~~~~~~~~~~~~~~

how to receive them --> demo code -->
Get-SLIDList -eQueryIdType SL_ID_PRODUCT_SKU -eReturnIdType SL_ID_PRODUCT_SKU | ? {Retrieve-SKUInfo -SkuId $_ -eReturnIdType SL_ID_PKEY}
Get-SLIDList -eQueryIdType SL_ID_PRODUCT_SKU -eReturnIdType SL_ID_PRODUCT_SKU | ? {Retrieve-SKUInfo -SkuId $_ -eReturnIdType SL_ID_PKEY} | % { Get-SLCPKeyInfo $_ -loopAllValues }

Example:
$LicensingProducts = (
    Get-SLIDList -eQueryIdType SL_ID_APPLICATION -eReturnIdType SL_ID_PRODUCT_SKU -pQueryId $windowsAppID | ? { Retrieve-SKUInfo -SkuId $_ -eReturnIdType SL_ID_PKEY }
    ) | % {
    [PSCustomObject]@{
        ID            = $_
        PKEY          = Retrieve-SKUInfo -SkuId $_ -eReturnIdType SL_ID_PKEY
        Description   = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Description'
        Name          = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'productName'
        LicenseFamily = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Family'
    }
}

Clear-Host
$LicensingProducts | % { 
    Write-Host
    Write-Warning "Get-SLCPKeyInfo Function"
    Get-SLCPKeyInfo -PKEY ($_).PKEY -loopAllValues

    Write-Host
    Write-Warning "Get-SLLicensingStatus"
    Get-SLLicensingStatus -ApplicationID 55c92734-d682-4d71-983e-d6ec3f16059f -SkuID ($_).ID

    Write-Host
    Write-Warning "Get-GenuineInformation"
    Write-Host
    Get-GenuineInformation -QueryId ($_).ID -loopAllValues

    Write-Host
    Write-Warning "Get-ApplicationInformation"
    Write-Host
    Get-ApplicationInformation -ApplicationId ($_).ID -loopAllValues
}
#>
function Get-SLCPKeyInfo {
    param(
        [Parameter(Mandatory = $false)]
        [Guid] $SKU,

        [Parameter(Mandatory = $false)]
        [Guid] $PKEY,

        [Parameter(Mandatory = $false)]
        [ValidateSet(
            "Pid2",                           # Format: 03612-04365...
            "DigitalPID",                     # Often mirrors Pid2 in modern Windows
            "DigitalPID2",                    # Binary Win 7/8 legacy blob
            "PKHash",                         # SHA-256 fingerprint
            "PartialProductKey",              # Last 5: YY74H
            "Channel",                        # OEM:NONSLP
            "ProductSkuId",                   # The GUID: ed655016...
            "ProductKeySerial"                # The 5-3-6-1 calculated serial  
        )]
        [string] $pwszValueName,

        [Parameter(Mandatory = $false)]
        [switch]$loopAllValues,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    # Oppsite XOR Case, Validate it Not both
    if (!($pwszValueName -xor $loopAllValues)) {
        Write-Warning "Choice 1 option only, can't use both / none"
        return
    }

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }

    try {
        
        # If loopAllValues is true, loop through all values in the ValidateSet and fetch the details for each
        $allValues = @{}
        $allValueNames = @(
            "Pid2",                           # Format: 03612-04365...
            "DigitalPID",                     # Often mirrors Pid2 in modern Windows
            "DigitalPID2",                    # Binary Win 7/8 legacy blob
            "PKHash",                         # SHA-256 fingerprint
            "PartialProductKey",              # Last 5: YY74H
            "Channel",                        # OEM:NONSLP
            "ProductSkuId",                   # The GUID: ed655016...
            "ProductKeySerial"                # The 5-3-6-1 calculated serial
        )
        foreach ($valueName in $allValueNames) {
            $allValues[$valueName] = $null
        }

        if ($PKEY -and $PKEY -ne [GUID]::Empty) {
            $PKeyId = $PKEY
        }
        elseif ($SKU -and $SKU -ne [GUID]::Empty) {
            $PKeyId = Retrieve-SKUInfo -SkuId $SKU -eReturnIdType SL_ID_PKEY -hSLC $hSLC
        }        
        if (-not $PKeyId) {
            return ([GUID]::Empty)
        }

        if ($loopAllValues) {
            foreach ($valueName in $allValueNames) {
                $dataType = 0
                $bufferSize = 0
                $bufferPtr = [IntPtr]::Zero

                $hr = $Global:SLC::SLGetPKeyInformation(
                    $hSLC, [ref]$PKeyId, $valueName, [ref]$dataType, [ref]$bufferSize, [ref]$bufferPtr )

                if ($hr -ne 0) {
                    continue;
                }
                $allValues[$valueName] = Parse-RegistryData -dataType $dataType -ptr $bufferPtr -valueSize $bufferSize -valueName $valueName
            }
            return $allValues #.GetEnumerator() | Where-Object { $null -ne $_.Value }
        }

        $dataType = 0
        $bufferSize = 0
        $bufferPtr = [IntPtr]::Zero

        $hr = $Global:SLC::SLGetPKeyInformation(
            $hSLC, [ref]$PKeyId, $pwszValueName, [ref]$dataType, [ref]$bufferSize, [ref]$bufferPtr )

        if ($hr -ne 0) {
            throw "SLGetPKeyInformation failed: HRESULT 0x{0:X8}" -f $hr
        }
        return Parse-RegistryData -dataType $dataType -ptr $bufferPtr -valueSize $bufferSize -valueName $pwszValueName
    }
    catch { }
    finally {
        if ($null -ne $bufferPtr -and (
            $bufferPtr -ne [IntPtr]::Zero)) {
                $null = $Global:kernel32::LocalFree($bufferPtr)
        }
        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}

<#
.SYNOPSIS
Gets information about the genuine state of a Windows computer.

~~~~~~~~~~~~~~~~~~~~~~

sppsvc.exe
__int64 __fastcall sub_1400C0498(
        __int64 (__fastcall **a1)(int, int, int, int, __int64),
        wchar_t *a2,
        __int64 (__fastcall ****a3)(int, int, int, int, __int64))
{
if ( !wcscmp(a2, L"SL_BRT_DATA") )
else if ( !wcscmp(a2, L"SL_BRT_COMMIT") )
else if ( !wcscmp(a2, L"SL_GENUINE_RESULT") )
else if ( !wcscmp(a2, L"SL_NONGENUINE_GRACE_FLAG") )
else if ( !wcscmp(a2, L"SL_LAST_ACT_ATTEMPT_HRESULT") )
else if ( !wcscmp(a2, L"SL_LAST_ACT_ATTEMPT_SERVER_FLAGS") )
else if ( !wcscmp(a2, L"SL_LAST_ACT_ATTEMPT_TIME") )
else if ( !wcscmp(a2, L"SL_ACTIVATION_VALIDATION_IN_PROGRESS") )
else if ( !wcscmp(a2, L"SL_GET_GENUINE_SERVER_AUTHZ") )
if ( wcsncmp(a2, L"SL_GET_GENUINE_AUTHZ", 0x14ui64) )

~~~~~~~~~~~~~~~~~~~~~~

[in] pQueryId
A pointer to an SLID structure that specifies the *application* to check.

pQueryId
pQueryId can be one of the following.  

ApplicationId in case of querying following property values.
    SL_PROP_BRT_DATA
    SL_PROP_BRT_COMMIT

SKUId in case of querying following property values.
    SL_PROP_LAST_ACT_ATTEMPT_HRESULT
    SL_PROP_LAST_ACT_ATTEMPT_TIME
    SL_PROP_LAST_ACT_ATTEMPT_SERVER_FLAGS
    SL_PROP_ACTIVATION_VALIDATION_IN_PROGRESS

Example:
$LicensingProducts = (
    Get-SLIDList -eQueryIdType SL_ID_APPLICATION -eReturnIdType SL_ID_PRODUCT_SKU -pQueryId $windowsAppID | ? { Retrieve-SKUInfo -SkuId $_ -eReturnIdType SL_ID_PKEY }
    ) | % {
    [PSCustomObject]@{
        ID            = $_
        PKEY          = Retrieve-SKUInfo -SkuId $_ -eReturnIdType SL_ID_PKEY
        Description   = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Description'
        Name          = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'productName'
        LicenseFamily = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Family'
    }
}

Clear-Host
$LicensingProducts | % { 
    Write-Host
    Write-Warning "Get-SLCPKeyInfo Function"
    Get-SLCPKeyInfo -PKEY ($_).PKEY -loopAllValues

    Write-Host
    Write-Warning "Get-SLLicensingStatus"
    Get-SLLicensingStatus -ApplicationID 55c92734-d682-4d71-983e-d6ec3f16059f -SkuID ($_).ID

    Write-Host
    Write-Warning "Get-GenuineInformation"
    Write-Host
    Get-GenuineInformation -QueryId ($_).ID -loopAllValues

    Write-Host
    Write-Warning "Get-ApplicationInformation"
    Write-Host
    Get-ApplicationInformation -ApplicationId ($_).ID -loopAllValues
}
 #>
function Get-GenuineInformation {
    param (
        [Parameter(Mandatory)]
        [string]$QueryId,

        [Parameter(Mandatory=$false)]
        [ValidateSet(
            'SL_BRT_DATA',
            'SL_BRT_COMMIT',
            'SL_GENUINE_RESULT',
            'SL_GET_GENUINE_AUTHZ',
            'SL_GET_GENUINE_SERVER_AUTHZ',
            'SL_NONGENUINE_GRACE_FLAG',
            'SL_LAST_ACT_ATTEMPT_TIME',
            'SL_LAST_ACT_ATTEMPT_HRESULT',
            'SL_LAST_ACT_ATTEMPT_SERVER_FLAGS',
            'SL_ACTIVATION_VALIDATION_IN_PROGRESS'
        )]
        [string]$ValueName,

        [Parameter(Mandatory = $false)]
        [switch]$loopAllValues,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    # Oppsite XOR Case, Validate it Not both
    if (!($ValueName -xor $loopAllValues)) {
        Write-Warning "Choice 1 option only, can't use both / none"
        return
    }

    # Cast ApplicationId to Guid
    $appGuid = [Guid]::Parse($QueryId)
    $IsAppID = $Global:knownAppGuids -contains $appGuid

    if ($IsAppID -and (-not $loopAllValues) -and ($ValueName -notmatch "_BRT_|GENUINE")) {
        Write-Warning "The selected property '$ValueName' is not valid for an ApplicationId."
        return
    }
    elseif ((-not $IsAppID) -and (-not $loopAllValues) -and ($ValueName -match '_BRT_')) {
        Write-Warning "The selected property '$ValueName' is not valid for a SKUId."
        return
    }

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }

    # Prepare variables for out params
    $dataType = 0
    $valueSize = 0
    $ptrValue = [IntPtr]::Zero

    if ($loopAllValues) {
          
        # Combine all arrays and remove duplicates
        $allValues = @{}
        $allValueNames = if ($IsAppID) {
            @(
                'SL_BRT_DATA',
                'SL_BRT_COMMIT'
                'SL_GENUINE_RESULT',
                'SL_GET_GENUINE_AUTHZ',
                'SL_GET_GENUINE_SERVER_AUTHZ',
                'SL_NONGENUINE_GRACE_FLAG'
            )
        } else {
            @(
                'SL_LAST_ACT_ATTEMPT_HRESULT',
                'SL_LAST_ACT_ATTEMPT_TIME',
                'SL_LAST_ACT_ATTEMPT_SERVER_FLAGS',
                'SL_ACTIVATION_VALIDATION_IN_PROGRESS'
            )
        }

        foreach ($Name in $allValueNames) {
            
            # Clear value
            $allValues[$Name] = $null

            $dataType = 0
            $valueSize = 0

            $hresult = $global:SLC::SLGetGenuineInformation(
                [ref] $appGuid,
                $Name,
                [ref] $dataType,
                [ref] $valueSize,
                [ref] $ptrValue
            )

            if ($hresult -ne 0) {
                continue
            }
            if ($valueSize -eq 0 -or $ptrValue -eq [IntPtr]::Zero) {
                continue
            }

            $allValues[$Name] = Parse-RegistryData -dataType $dataType -ptr $ptrValue -valueSize $valueSize -valueName $Name
            Free-IntPtr -handle $ptrValue -Method Local
            
            if ($allValues[$Name] -and (
                $Name -eq 'SL_LAST_ACT_ATTEMPT_HRESULT')) {
                $hrReason = $allValues[$Name]
                $errorMessage = Parse-ErrorMessage -MessageId $hrReason -Flags ACTIVATION
                $hrHex = '0x{0:X8}' -f ($hrReason -band 0xFFFFFFFF)
                $allValues[$Name] = $hrHex
            }
            
        }
        if ($errorMessage) {
            $allValues.Add("SL_LAST_ACT_ATTEMPT_MESSEGE",$errorMessage)
        }
        return $allValues
    }

    try {
        # Call SLGetGenuineInformation - pass [ref] for out params
        $hresult = $global:SLC::SLGetGenuineInformation(
            [ref] $appGuid,
            $ValueName,
            [ref] $dataType,
            [ref] $valueSize,
            [ref] $ptrValue
        )

        if ($hresult -ne 0) {
            $errorMessege = Parse-ErrorMessage -MessageId $hresult -Flags ([ErrorMessageType]::ACTIVATION -bor [ErrorMessageType]::HRESULT)
            Write-Warning "$errorMessege, $hresult"
            throw "SLGetGenuineInformation failed with HRESULT: $hresult"
        }

        if ($valueSize -eq 0 -or $ptrValue -eq [IntPtr]::Zero) {
            return $null
        }

        try {
            return Parse-RegistryData -dataType $dataType -ptr $ptrValue -valueSize $valueSize -valueName $ValueName
        }
        finally {
            Free-IntPtr -handle $ptrValue -Method Local
        }
    }
    finally {
        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}

<#
Check Status of SkuId, return results,
typedef enum _SL_GENUINE_STATE {
  SL_GEN_STATE_IS_GENUINE = 0,
  SL_GEN_STATE_INVALID_LICENSE,
  SL_GEN_STATE_TAMPERED,
  SL_GEN_STATE_OFFLINE,
  SL_GEN_STATE_LAST
} SL_GENUINE_STATE;

Example.
Get-SLIDList -eQueryIdType SL_ID_APPLICATION -eReturnIdType SL_ID_PRODUCT_SKU -pQueryId $windowsAppID | % {
  Write-Host "Check Sku $_"
  Get-GenuineStatus -pAppId $windowsAppID -pSkuId $_
  Write-Host
}
#>
Function Get-GenuineStatus {
    [CmdletBinding()]
    param (
        [GUID]$pAppId = '55c92734-d682-4d71-983e-d6ec3f16059f',
        [GUID]$pSkuId = [Guid]::Empty
    )

    if ($pAppId -eq [Guid]::Empty) {
        Write-Warning "pAppId cannot be an empty GUID."
        return
    }

    $pGenuineState = [int]0 
    [IntPtr]$pSkuIdPtr = if ($pSkuId -eq [Guid]::Empty) {
        [IntPtr]::Zero
    } else {
        New-IntPtr -Data (
            $pSkuId.ToByteArray())
    }

    try {
        $ret = $global:SLC::SLIsGenuineLocalEx(
            [ref]$pAppId, 
            $pSkuIdPtr,
            [ref]$pGenuineState
        )
    } catch {
        Write-Error "Failed to call sppc.dll."
        return
    } finally {
        Free-IntPtr $pSkuIdPtr
    }

    if ($ret -eq 0x0) {
        switch ($pGenuineState) {
            0x00 { return "Success: The installation is genuine." }
            0x01 { return "Error: The application does not have a valid license."}
            0x02 { return "Error: The Tampered flag is set."}
            0x03 { return "Error: The Offline flag is set."}
            0x04 { return "Status: State unchanged since last check."}
            Default { return "Unknown state detected: $pGenuineState"}
        }
    } else {
        $err = Parse-ErrorMessage $ret -Flags ([ErrorMessageType]::ACTIVATION -bor [ErrorMessageType]::HRESULT)
        return ("DLL Call failed. HRESULT: 0x{0:X}`n$err" -f $ret)
    }
}

<#
.SYNOPSIS
Gets information about the specified application.

Example:
$LicensingProducts = (
    Get-SLIDList -eQueryIdType SL_ID_APPLICATION -eReturnIdType SL_ID_PRODUCT_SKU -pQueryId $windowsAppID | ? { Retrieve-SKUInfo -SkuId $_ -eReturnIdType SL_ID_PKEY }
    ) | % {
    [PSCustomObject]@{
        ID            = $_
        PKEY          = Retrieve-SKUInfo -SkuId $_ -eReturnIdType SL_ID_PKEY
        Description   = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Description'
        Name          = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'productName'
        LicenseFamily = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Family'
    }
}

Clear-Host
$LicensingProducts | % { 
    Write-Host
    Write-Warning "Get-SLCPKeyInfo Function"
    Get-SLCPKeyInfo -PKEY ($_).PKEY -loopAllValues

    Write-Host
    Write-Warning "Get-SLLicensingStatus"
    Get-SLLicensingStatus -ApplicationID 55c92734-d682-4d71-983e-d6ec3f16059f -SkuID ($_).ID

    Write-Host
    Write-Warning "Get-GenuineInformation"
    Write-Host
    Get-GenuineInformation -QueryId ($_).ID -loopAllValues

    Write-Host
    Write-Warning "Get-ApplicationInformation"
    Write-Host
    Get-ApplicationInformation -ApplicationId ($_).ID -loopAllValues
}
#>
function Get-ApplicationInformation {
    param (
        [Parameter(Mandatory)]
        [string]$ApplicationId,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet(
            "TrustedTime",
            "IsKeyManagementService",
            "KeyManagementServiceCurrentCount",
            "KeyManagementServiceRequiredClientCount",
            "KeyManagementServiceUnlicensedRequests",
            "KeyManagementServiceLicensedRequests",
            "KeyManagementServiceOOBGraceRequests",
            "KeyManagementServiceOOTGraceRequests",
            "KeyManagementServiceNonGenuineGraceRequests",
            "KeyManagementServiceNotificationRequests",
            "KeyManagementServiceTotalRequests",
            "KeyManagementServiceFailedRequests"
        )]
        [string]$PropertyName,

        [Parameter(Mandatory = $false)]
        [switch]$loopAllValues,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    # Oppsite XOR Case, Validate it Not both
    if (!($PropertyName -xor $loopAllValues)) {
        Write-Warning "Choice 1 option only, can't use both / none"
        return
    }

    # Cast ApplicationId to Guid
    $appGuid = [Guid]$ApplicationId

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }

    if ($loopAllValues) {
          
        # Combine all arrays and remove duplicates
        $allValues = @{}
        $allValueNames = (
            "TrustedTime",
            "IsKeyManagementService",
            "KeyManagementServiceCurrentCount",
            "KeyManagementServiceRequiredClientCount",
            "KeyManagementServiceUnlicensedRequests",
            "KeyManagementServiceLicensedRequests",
            "KeyManagementServiceOOBGraceRequests",
            "KeyManagementServiceOOTGraceRequests",
            "KeyManagementServiceNonGenuineGraceRequests",
            "KeyManagementServiceNotificationRequests",
            "KeyManagementServiceTotalRequests",
            "KeyManagementServiceFailedRequests"
        )

        $dataTypePtr = [Marshal]::AllocHGlobal(4)
        $valueSizePtr = [Marshal]::AllocHGlobal(4)
        $ptrPtr = [Marshal]::AllocHGlobal([IntPtr]::Size)

        foreach ($valueName in $allValueNames) {
            # Clear value
            $allValues[$valueName] = $null

            # Initialize the out params to zero/null
            [Marshal]::WriteInt32($dataTypePtr, 0)
            [Marshal]::WriteInt32($valueSizePtr, 0)
            [Marshal]::WriteIntPtr($ptrPtr, [IntPtr]::Zero)

            $res = $global:SLC::SLGetApplicationInformation(
                $hSLC,
                [ref]$appGuid,
                $valueName,
                $dataTypePtr,
                $valueSizePtr,
                $ptrPtr
            )

            if ($res -ne 0) {
                continue
            }

            # Read the outputs from the unmanaged memory pointers
            $dataType = [Marshal]::ReadInt32($dataTypePtr)
            $valueSize = [Marshal]::ReadInt32($valueSizePtr)
        
            # Dereference the pointer-to-pointer to get actual buffer pointer
            $ptr = [Marshal]::ReadIntPtr($ptrPtr)

            if ($ptr -eq [IntPtr]::Zero) {
                continue
            }

            if ($valueSize -eq 0) {
                continue
            }

            $allValues[$valueName] = Parse-RegistryData -dataType $dataType -ptr $ptr -valueSize $valueSize -valueName $valueName
            Free-IntPtr -handle $ptr -Method Local
        }
        return $allValues
    }


    # Allocate memory for dataType (optional out parameter)
    $dataTypePtr = [Marshal]::AllocHGlobal(4)
    # Allocate memory for valueSize (UINT* out param)
    $valueSizePtr = [Marshal]::AllocHGlobal(4)
    # Allocate memory for pointer to byte buffer (PBYTE* out param)
    $ptrPtr = [Marshal]::AllocHGlobal([IntPtr]::Size)

    try {
        # Initialize the out params to zero/null
        [Marshal]::WriteInt32($dataTypePtr, 0)
        [Marshal]::WriteInt32($valueSizePtr, 0)
        [Marshal]::WriteIntPtr($ptrPtr, [IntPtr]::Zero)

        $hresult = $global:SLC::SLGetApplicationInformation(
            $hSLC,
            [ref]$appGuid,
            $PropertyName,
            $dataTypePtr,
            $valueSizePtr,
            $ptrPtr
        )

        if ($hresult -ne 0) {
            $errorMessege = Parse-ErrorMessage -MessageId $hresult -Flags ([ErrorMessageType]::ACTIVATION -bor [ErrorMessageType]::HRESULT)
            Write-Warning "$errorMessege, $hresult"
            throw "SLGetApplicationInformation failed (code $hresult)"
        }

        # Read the outputs from the unmanaged memory pointers
        $dataType = [Marshal]::ReadInt32($dataTypePtr)
        $valueSize = [Marshal]::ReadInt32($valueSizePtr)
        
        # Dereference the pointer-to-pointer to get actual buffer pointer
        $ptr = [Marshal]::ReadIntPtr($ptrPtr)

        if ($ptr -eq [IntPtr]::Zero) {
            throw "Pointer to data buffer is null"
        }

        if ($valueSize -eq 0) {
            throw "Returned value size is zero"
        }

        try {
            return Parse-RegistryData -dataType $dataType -ptr $ptr -valueSize $valueSize -valueName $PropertyName
        }
        finally {
            Free-IntPtr -handle $ptr -Method Local
        }
    }
    finally {
        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
        if ($dataTypePtr -and $dataTypePtr -ne [IntPtr]::Zero) {
            [Marshal]::FreeHGlobal($dataTypePtr)
        }
        if ($valueSizePtr -and $valueSizePtr -ne [IntPtr]::Zero) {
            [Marshal]::FreeHGlobal($valueSizePtr)
        }
        if ($ptrPtr -and $ptrPtr -ne [IntPtr]::Zero) {
            [Marshal]::FreeHGlobal($ptrPtr)
        }
    }
}

<#
.SYNOPSIS
Gets information about the specified product SKU.

Example.

Clear-Host
Write-Host
$skuID = Get-SLIDList -eQueryIdType SL_ID_APPLICATION -eReturnIdType SL_ID_PRODUCT_SKU -pQueryId $windowsAppID | ? { Retrieve-SKUInfo -SkuId $_ -eReturnIdType SL_ID_PKEY } | select -First 1

Write-Host
Write-host "Get-LicenseInformation" -ForegroundColor Green
Write-Host
$licenseInfo = Get-LicenseInformation -ActConfigId $skuID -loopAllValues
$licenseInfo.GetEnumerator() | Where-Object { ![string]::IsNullOrWhiteSpace($_.Value) }

Write-Host
Write-host "Get-ProductSkuInformation" -ForegroundColor Green
Write-Host
$skuInfo = Get-ProductSkuInformation -ActConfigId $skuID -loopAllValues
$skuInfo.GetEnumerator() | Where-Object { ![string]::IsNullOrWhiteSpace($_.Value) }

Extra Info.

"Description", "Name", "Author", 
Taken from Microsoft Offical Documentation.

# ----------------------------------------------

fileId                # SL_ID_LICENSE_FILE
pkeyId                # SL_ID_PKEY
productSkuId          # SL_ID_PRODUCT_SKU
applicationId         # SL_ID_APPLICATION
licenseId             # SL_ID_LICENSE 
privateCertificateId  # SL_ID_LICENSE 

# ------>>>> More info ------>>>

https://github.com/LBBNetwork/openredpill/blob/master/slpublic.h
https://learn.microsoft.com/en-us/windows/win32/api/slpublic/nf-slpublic-slgetslidlist

SL_ID_APPLICATION,  appId        X
SL_ID_PRODUCT_SKU,  skuId        ?
SL_ID_LICENSE_FILE, fileId       V
SL_ID_LICENSE,      LicenseId    V

# ----------------------------------------------

"msft:sl/EUL/GENERIC/PUBLIC",    "msft:sl/EUL/GENERIC/PRIVATE",
"msft:sl/EUL/PHONE/PUBLIC",      "msft:sl/EUL/PHONE/PRIVATE",
"msft:sl/EUL/STORE/PUBLIC",      "msft:sl/EUL/STORE/PRIVATE",
"msft:sl/EUL/ACTIVATED/PRIVATE", "msft:sl/EUL/ACTIVATED/PUBLIC",

# ----------------------------------------------

Also, 
if you read String's from sppwmi.dll [hint by abbody1406]
you will find more data.

!Jackpot!
inside sppsvc.exe, lot of data, we can search,
include fileId & more info.

# ----------------------------------------------

Also, some properties from *SoftwareLicensingProduct* WMI Class
can be enum too, some with diffrent name.

class SoftwareLicensingProduct
{
  string   ID;                                            --> Function * SLGetProductSkuInformation  --> productSkuId
  string   Name;                                          --> Function * SLGetProductSkuInformation 
  string   Description;                                   --> Function * SLGetProductSkuInformation 
  string   ApplicationID;                                 --> Function * SLGetProductSkuInformation 
  string   ProcessorURL;                                  --> Function * SLGetProductSkuInformation 
  string   MachineURL;                                    --> Function * SLGetProductSkuInformation 
  string   ProductKeyURL;                                 --> Function * SLGetProductSkuInformation 
  
  sppcomapi.dll
  __int64 __fastcall SPPGetServerAddresses(HSLC hSLC, struct SActivationServerAddress **a2, unsigned int *a3)
  v58[0] = (__int64)L"SPCURL"; // GetProcessorURL
  v58[1] = (__int64)L"RACURL"; // GetMachineURL
  v51 = L"PAURL";              // GetUseLicenseURL
  v58[2] = (__int64)L"PKCURL"; // GetProductKeyURL
  v58[3] = (__int64)L"EULURL"; // GetUseLicenseURL

  string   UseLicenseURL;                                 --> Function * SLGetProductSkuInformation  --> PAUrl [-or EULURL, By abbody1406]

  uint32   LicenseStatus;                                 --> Function * SLGetLicensingStatusInformation
  uint32   LicenseStatusReason;                           --> Function * SLGetLicensingStatusInformation
  uint32   GracePeriodRemaining;                          --> Function * SLGetLicensingStatusInformation
  datetime EvaluationEndDate;                             --> Function * SLGetLicensingStatusInformation
  string   OfflineInstallationId;                         --> Function * SLGenerateOfflineInstallationId
  string   PartialProductKey;                             --> Function * SLGetPKeyInformation
  string   ProductKeyID;                                  --> Function * SLGetPKeyInformation
  string   ProductKeyID2;                                 --> Function * SLGetPKeyInformation
  string   ProductKeyURL                                  --> Function * SLGetProductSkuInformation  --> PKCURL
  string   ProductKeyChannel;                             --> Function * SLGetPKeyInformation
  string   LicenseFamily;                                 --> Function * SLGetProductSkuInformation  --> Family
  string   LicenseDependsOn;                              --> Function * SLGetProductSkuInformation  --> DependsOn
  string   ValidationURL;                                 --> Function * SLGetProductSkuInformation  --> ValUrl
  boolean  LicenseIsAddon;                                --> Function * SLGetProductSkuInformation  --> [BOOL](DependsOn) // From TSforge project
  uint32   VLActivationInterval;                          --> Function * SLGetProductSkuInformation
  uint32   VLRenewalInterval;                             --> Function * SLGetProductSkuInformation
  string   KeyManagementServiceProductKeyID;              --> Function * SLGetProductSkuInformation  --> CustomerPID
  string   KeyManagementServiceMachine;                   --> Function * SLGetProductSkuInformation  --> KeyManagementServiceName
  uint32   KeyManagementServicePort;                      --> Function * SLGetProductSkuInformation  --> KeyManagementServicePort
  string   DiscoveredKeyManagementServiceMachineName;     --> Function * SLGetProductSkuInformation  --> DiscoveredKeyManagementServiceName
  uint32   DiscoveredKeyManagementServiceMachinePort;     --> Function * SLGetProductSkuInformation  --> DiscoveredKeyManagementServicePort
  BOOL     IsKeyManagementServiceMachine;                 --> Function * SLGetApplicationInformation --> Key: "IsKeyManagementService"                      (SL_INFO_KEY_IS_KMS)
  uint32   KeyManagementServiceCurrentCount;              --> Function * SLGetApplicationInformation --> Key: "KeyManagementServiceCurrentCount"            (SL_INFO_KEY_KMS_CURRENT_COUNT)
  uint32   RequiredClientCount;                           --> Function * SLGetApplicationInformation --> Key: "KeyManagementServiceRequiredClientCount"     (SL_INFO_KEY_KMS_REQUIRED_CLIENT_COUNT)
  uint32   KeyManagementServiceUnlicensedRequests;        --> Function * SLGetApplicationInformation --> Key: "KeyManagementServiceUnlicensedRequests"      (SL_INFO_KEY_KMS_UNLICENSED_REQUESTS)
  uint32   KeyManagementServiceLicensedRequests;          --> Function * SLGetApplicationInformation --> Key: "KeyManagementServiceLicensedRequests"        (SL_INFO_KEY_KMS_LICENSED_REQUESTS)
  uint32   KeyManagementServiceOOBGraceRequests;          --> Function * SLGetApplicationInformation --> Key: "KeyManagementServiceOOBGraceRequests"        (SL_INFO_KEY_KMS_OOB_GRACE_REQUESTS)
  uint32   KeyManagementServiceOOTGraceRequests;          --> Function * SLGetApplicationInformation --> Key: "KeyManagementServiceOOTGraceRequests"        (SL_INFO_KEY_KMS_OOT_GRACE_REQUESTS)
  uint32   KeyManagementServiceNonGenuineGraceRequests;   --> Function * SLGetApplicationInformation --> Key: "KeyManagementServiceNonGenuineGraceRequests" (SL_INFO_KEY_KMS_NON_GENUINE_GRACE_REQUESTS)
  uint32   KeyManagementServiceTotalRequests;             --> Function * SLGetApplicationInformation --> Key: "KeyManagementServiceTotalRequests"           (SL_INFO_KEY_KMS_TOTAL_REQUESTS)
  uint32   KeyManagementServiceFailedRequests;            --> Function * SLGetApplicationInformation --> Key: "KeyManagementServiceFailedRequests"          (SL_INFO_KEY_KMS_FAILED_REQUESTS)
  uint32   KeyManagementServiceNotificationRequests;      --> Function * SLGetApplicationInformation --> Key: "KeyManagementServiceNotificationRequests"    (SL_INFO_KEY_KMS_NOTIFICATION_REQUESTS)
  uint32   GenuineStatus;                                 --> Function * SLIsGenuineLocalEx
  uint32   ExtendedGrace;                                 --> Function * SLGetProductSkuInformation  --> TimeBasedExtendedGrace
  string   TokenActivationILID;                           --> Function * SLGetProductSkuInformation
  uint32   TokenActivationILVID;                          --> Function * SLGetProductSkuInformation
  uint32   TokenActivationGrantNumber;                    --> Function * SLGetProductSkuInformation 
  string   TokenActivationCertificateThumbprint;          --> Function * SLGetProductSkuInformation
  string   TokenActivationAdditionalInfo;                 --> Function * SLGetProductSkuInformation
  datetime TrustedTime;                                   --> Function * SLGetProductSkuInformation [Licensing System Date]
};

# ----------------------------------------------

Now found that it read --> r:otherInfo Section
So it support for Any <tm:infoStr name=

<r:otherInfo xmlns:r="urn:mpeg:mpeg21:2003:01-REL-R-NS">
	<tm:infoTables xmlns:tm="http://www.microsoft.com/DRM/XrML2/TM/v2">
		<tm:infoList tag="#global">
		<tm:infoStr name="licenseType">msft:sl/PL/GENERIC/PUBLIC</tm:infoStr>
		<tm:infoStr name="licenseVersion">2.0</tm:infoStr>
		<tm:infoStr name="licensorUrl">http://licensing.microsoft.com</tm:infoStr>
		<tm:infoStr name="licenseCategory">msft:sl/PL/GENERIC/PUBLIC</tm:infoStr>
		<tm:infoStr name="productSkuId">{2c060131-0e43-4e01-adc1-cf5ad1100da8}</tm:infoStr>
		<tm:infoStr name="privateCertificateId">{274ff0e9-dfec-43e7-b675-67e61645b6a9}</tm:infoStr>
		<tm:infoStr name="applicationId">{55c92734-d682-4d71-983e-d6ec3f16059f}</tm:infoStr>
		<tm:infoStr name="productName">Windows(R), EnterpriseSN edition</tm:infoStr>
		<tm:infoStr name="Family">EnterpriseSN</tm:infoStr>
		<tm:infoStr name="productAuthor">Microsoft Corporation</tm:infoStr>
		<tm:infoStr name="productDescription">Windows(R) Operating System</tm:infoStr>
		<tm:infoStr name="clientIssuanceCertificateId">{4961cc30-d690-43be-910c-8e2db01fc5ad}</tm:infoStr>
		<tm:infoStr name="hwid:ootGrace">0</tm:infoStr>
		</tm:infoList>
	</tm:infoTables>
</r:otherInfo>
<r:otherInfo xmlns:r="urn:mpeg:mpeg21:2003:01-REL-R-NS">
	<tm:infoTables xmlns:tm="http://www.microsoft.com/DRM/XrML2/TM/v2">
		<tm:infoList tag="#global">
		<tm:infoStr name="licenseType">msft:sl/PL/GENERIC/PRIVATE</tm:infoStr>
		<tm:infoStr name="licenseVersion">2.0</tm:infoStr>
		<tm:infoStr name="licensorUrl">http://licensing.microsoft.com</tm:infoStr>
		<tm:infoStr name="licenseCategory">msft:sl/PL/GENERIC/PRIVATE</tm:infoStr>
		<tm:infoStr name="publicCertificateId">{0f6421d2-b7ea-45e0-b87d-773975685c35}</tm:infoStr>
		<tm:infoStr name="clientIssuanceCertificateId">{4961cc30-d690-43be-910c-8e2db01fc5ad}</tm:infoStr>
		<tm:infoStr name="hwid:ootGrace">0</tm:infoStr>
		<tm:infoStr name="win:branding">126</tm:infoStr>
		</tm:infoList>
	</tm:infoTables>
</r:otherInfo>
#>
function Get-ProductSkuInformation {
    param (
        [Parameter(Mandatory)]
        [Guid]$ActConfigId,

        [Parameter(Mandatory = $false)]
        [ValidateSet(
        "fileId", "pkeyId", "productSkuId", "applicationId",
        "licenseId", "privateCertificateId", "pkeyIdList",

        "msft:sl/EUL/GENERIC/PUBLIC",    "msft:sl/EUL/GENERIC/PRIVATE",
        "msft:sl/EUL/PHONE/PUBLIC",      "msft:sl/EUL/PHONE/PRIVATE",
        "msft:sl/EUL/STORE/PUBLIC",      "msft:sl/EUL/STORE/PRIVATE",
        "msft:sl/EUL/ACTIVATED/PRIVATE", "msft:sl/EUL/ACTIVATED/PUBLIC",
        "msft:sl/PL/GENERIC/PUBLIC",     "msft:sl/PL/GENERIC/PRIVATE",

        "Description", "Name", "Author",
		
        "TokenActivationILID", "TokenActivationILVID","TokenActivationGrantNumber",
        "TokenActivationCertificateThumbprint", "TokenActivationAdditionalInfo",
        "pkeyConfigLicenseId", "licenseType", "licenseVersion", "licensorUrl", "licenseNamespace",
        "productName", "Family", "productAuthor", "productDescription", "licenseCategory",
        "hwid:ootGrace", "issuanceCertificateId", "ValUrl", "PAUrl", "ActivationSequence", 
        "UXDifferentiator", "ProductKeyGroupUniqueness", "EnableNotificationMode", "EULURL", 
        "GraceTimerUniqueness", "ValidityTimerUniqueness", "EnableActivationValidation", "PKCURL",
        "DependsOn", "phone:policy", "licensorKeyIndex", "BuildVersion", "ValidationTemplateId",
        "ProductUniquenessGroupId", "ApplicationBitmap", "migratable",
        "ProductKeyID", "VLActivationInterval", "VLRenewalInterval", "KeyManagementServiceProductKeyID", 
        "KeyManagementServicePort", "TrustedTime", "CustomerPID", "KeyManagementServiceName", 
        "KeyManagementServicePort", "DiscoveredKeyManagementServiceName", 
        "DiscoveredKeyManagementServicePort", "TimeBasedExtendedGrace",
        "ADActivationObjectDN", "ADActivationObjectName", "DiscoveredKeyManagementServiceIpAddress",
        "KeyManagementServiceLookupDomain", "RemainingRearmCount", "VLActivationType",
        "TokenActivationCertThumbprint", "RearmCount", "ADActivationCsvlkPID", "ADActivationCsvlkSkuID",
        "fileIndex", "licenseDescription", "metaInfoType", "DigitalEncryptedPID",
        "InheritedActivationId", "InheritedActivationHostMachineName", "InheritedActivationHostDigitalPid2",
        "InheritedActivationActivationTime"
        )]
        [String]$pwszValueName,

        [Parameter(Mandatory = $false)]
        [switch]$loopAllValues,

        [Parameter(Mandatory = $false)]
        [switch]$ReturnRawData,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    # 3 CASES OF XOR
    if (@([BOOL]$pwszValueName + [BOOL]$loopAllValues + [BOOL]$ReturnRawData) -ne 1) {
        Write-Warning "Exactly one of -pwszValueName, -loopAllValues, or -ReturnRawData must be specified."
        return
    }

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }

    try {
        if ($loopAllValues) {
            $allValues = @{}
            $SL_ID = @(
                "fileId",               # SL_ID_LICENSE_FILE
                "pkeyId",               # SL_ID_PKEY
                "pkeyIdList"            # SL_ID_PKEY [Same]
                "productSkuId",         # SL_ID_PRODUCT_SKU
                "applicationId"         # SL_ID_APPLICATION
                "licenseId",            # SL_ID_LICENSE
                "privateCertificateId"  # SL_ID_LICENSE
            )

            # un offical, intersting pattern
            # first saw in MAS AIO file, TSforge project}
            $MSFT = @(
                "msft:sl/EUL/GENERIC/PUBLIC",    "msft:sl/EUL/GENERIC/PRIVATE",    # un-offical
                "msft:sl/EUL/PHONE/PUBLIC",      "msft:sl/EUL/PHONE/PRIVATE",      # un-offical
                "msft:sl/EUL/STORE/PUBLIC",      "msft:sl/EUL/STORE/PRIVATE",      # un-offical
                "msft:sl/EUL/ACTIVATED/PRIVATE", "msft:sl/EUL/ACTIVATED/PUBLIC",   # extract from SPP* dll/exe files
                "msft:sl/PL/GENERIC/PUBLIC",     "msft:sl/PL/GENERIC/PRIVATE"      # extract from SPP* dll/exe files
            )
            
            # Offical from MS
            $OfficalPattern = @("Description", "Name", "Author")

            # the rest, from XML Blobs --> <infoStr>
            $xml = @("pkeyConfigLicenseId", "privateCertificateId", "licenseType", 
                "licensorUrl",  "licenseCategory", "productName", "Family","licenseVersion",
                "productAuthor", "productDescription",  "hwid:ootGrace", "issuanceCertificateId", "PAUrl",
                "ActivationSequence", "ValidationTemplateId", "ValUrl", "UXDifferentiator",
				"ProductKeyGroupUniqueness", "EnableNotificationMode", "GraceTimerUniqueness",
                "ValidityTimerUniqueness", "EnableActivationValidation",
                "DependsOn", "phone:policy", "licensorKeyIndex", "BuildVersion",
                "ProductUniquenessGroupId", "ApplicationBitmap", "migratable")
            
            # SoftwareLicensingProduct class (WMI)
            $SoftwareLicensingProduct = @(
                "Name",  "Description", "ApplicationID", "VLActivationInterval", "VLRenewalInterval",
                "ProductKeyID",  "KeyManagementServiceProductKeyID", "KeyManagementServicePort", 
                "RequiredClientCount", "TrustedTime", "TokenActivationILID", "TokenActivationILVID",
                "TokenActivationGrantNumber", "TokenActivationCertificateThumbprint", "CustomerPID",
                "KeyManagementServiceName", "KeyManagementServicePort","TimeBasedExtendedGrace", 
                "DiscoveredKeyManagementServiceName", "DiscoveredKeyManagementServicePort",
                "PKCURL", "EULURL"
            )

            # SPP* DLL/EXE file's
            $sppwmi = @(
                "ADActivationObjectDN", "ADActivationObjectName", "DiscoveredKeyManagementServiceIpAddress",
                "KeyManagementServiceLookupDomain", "RemainingRearmCount", "TokenActivationAdditionalInfo",
                "TokenActivationCertThumbprint", "VLActivationType", "RearmCount", "ADActivationCsvlkPID", 
                "fileIndex", "licenseDescription", "metaInfoType", "DigitalEncryptedPID", "ADActivationCsvlkSkuID",
				"InheritedActivationId", "InheritedActivationHostMachineName", "InheritedActivationHostDigitalPid2",
				"InheritedActivationActivationTime", "licenseNamespace"
            )

            # Combine all arrays and remove duplicates
            $allValueNames = ($SL_ID + $MSFT + $OfficalPattern + $xml + $SoftwareLicensingProduct + $sppwmi) | Sort-Object -Unique

            foreach ($valueName in $allValueNames) {
                $dataType = 0
                $valueSize = 0
                $ptr = [IntPtr]::Zero
                $res = $global:SLC::SLGetProductSkuInformation(
                    $hSLC,
                    [ref]$ActConfigId,
                    $valueName,
                    [ref]$dataType,
                    [ref]$valueSize,
                    [ref]$ptr
                )

                if ($res -ne 0) {
                    #Write-Warning "fail to process Name: $valueName"
                    $allValues[$valueName] = $null
                    continue;
                }
 
                $allValues[$valueName] = Parse-RegistryData -dataType $dataType -ptr $ptr -valueSize $valueSize -valueName $valueName
                Free-IntPtr -handle $ptr -Method Local
            }

            return $allValues
        }

        if ($pwszValueName) {
            $dataType = 0
            $valueSize = 0
            $ptr = [IntPtr]::Zero
            $res = $global:SLC::SLGetProductSkuInformation(
                $hSLC,
                [ref]$ActConfigId,
                $pwszValueName,
                [ref]$dataType,
                [ref]$valueSize,
                [ref]$ptr
            )

            if ($res -ne 0) {
                #$messege = $(Parse-ErrorMessage -MessageId $res)
                #Write-Warning "ERROR $res, $messege, Value: $pwszValueName"
                throw
            }

            try {
                return Parse-RegistryData -dataType $dataType -ptr $ptr -valueSize $valueSize -valueName $pwszValueName
            }
            finally {
                Free-IntPtr -handle $ptr -Method Local
            }
        }

        try {
            $content = Get-LicenseData -SkuID $ActConfigId -Mode License
            $xmlContent = $content.Substring($content.IndexOf('<r'))
            $xml = [xml]$xmlContent
        }
        catch {
        }

        if ($ReturnRawData) {
            return $xml
        }

        # Transform into detailed custom objects
        $licenseObjects = @()

        foreach ($license in $xml.licenseGroup.license) {
            $policyList = @()
            foreach ($policy in $license.grant.allConditions.allConditions.productPolicies.policyStr) {
                $policyList += [PSCustomObject]@{
                    Name  = $policy.name
                    Value = $policy.InnerText
                }
            }

            if (-not $policyList) {
                continue;
            }

            $licenseObjects += [PSCustomObject]@{
                LicenseId  = $license.licenseId
                GrantName  = $license.grant.name
                Policies   = $policyList
            }
        }

        return $licenseObjects
    }
    catch { }
    finally {
        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}
function Get-LicenseInformation {
    param (
        [Parameter(Mandatory)]
        [Guid]$ActConfigId,

        [Parameter(Mandatory = $false)]
        [ValidateSet(
        "fileId", "pkeyId", "productSkuId", "applicationId",
        "licenseId", "privateCertificateId", "pkeyIdList",

        "msft:sl/EUL/GENERIC/PUBLIC",    "msft:sl/EUL/GENERIC/PRIVATE",
        "msft:sl/EUL/PHONE/PUBLIC",      "msft:sl/EUL/PHONE/PRIVATE",
        "msft:sl/EUL/STORE/PUBLIC",      "msft:sl/EUL/STORE/PRIVATE",
        "msft:sl/EUL/ACTIVATED/PRIVATE", "msft:sl/EUL/ACTIVATED/PUBLIC",
        "msft:sl/PL/GENERIC/PUBLIC",     "msft:sl/PL/GENERIC/PRIVATE",

        "Description", "Name", "Author",
		"stilName", "stilVersion", "stilAuthZStatus", "stilExpiration", "stilComment", "stilComment2",
        "TokenActivationILID", "TokenActivationILVID","TokenActivationGrantNumber",
        "TokenActivationCertificateThumbprint", "TokenActivationAdditionalInfo",
        "pkeyConfigLicenseId", "licenseType", "licenseVersion", "licensorUrl", "licenseNamespace",
        "productName", "Family", "productAuthor", "productDescription", "licenseCategory",
        "hwid:ootGrace", "issuanceCertificateId", "ValUrl", "PAUrl", "ActivationSequence", 
        "UXDifferentiator", "ProductKeyGroupUniqueness", "EnableNotificationMode", "EULURL", 
        "GraceTimerUniqueness", "ValidityTimerUniqueness", "EnableActivationValidation", "PKCURL",
        "DependsOn", "phone:policy", "licensorKeyIndex", "BuildVersion", "ValidationTemplateId",
        "ProductUniquenessGroupId", "ApplicationBitmap", "migratable",
        "ProductKeyID", "VLActivationInterval", "VLRenewalInterval", "KeyManagementServiceProductKeyID", 
        "KeyManagementServicePort", "TrustedTime", "CustomerPID", "KeyManagementServiceName", 
        "KeyManagementServicePort", "DiscoveredKeyManagementServiceName", 
        "DiscoveredKeyManagementServicePort", "TimeBasedExtendedGrace",
        "ADActivationObjectDN", "ADActivationObjectName", "DiscoveredKeyManagementServiceIpAddress",
        "KeyManagementServiceLookupDomain", "RemainingRearmCount", "VLActivationType",
        "TokenActivationCertThumbprint", "RearmCount", "ADActivationCsvlkPID", "ADActivationCsvlkSkuID",
        "fileIndex", "licenseDescription", "metaInfoType", "DigitalEncryptedPID",
        "InheritedActivationId", "InheritedActivationHostMachineName", "InheritedActivationHostDigitalPid2",
        "InheritedActivationActivationTime"
        )]
        [String]$pwszValueName,

        [Parameter(Mandatory = $false)]
        [switch]$loopAllValues,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    # 3 CASES OF XOR
    if (@([BOOL]$pwszValueName + [BOOL]$loopAllValues) -ne 1) {
        Write-Warning "Exactly one of -pwszValueName, -loopAllValues, or -ReturnRawData must be specified."
        return
    }

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }

    $pSLLicenseId = Retrieve-SKUInfo -SkuId $ActConfigId -eReturnIdType SL_ID_LICENSE
    #$pSLLicenseId = Get-SLIDList -eQueryIdType SL_ID_PRODUCT_SKU -eReturnIdType SL_ID_LICENSE -pQueryId $ActConfigId
    if (!$pSLLicenseId) {
        return $null
    }

    try {
        [Guid]$pSLLicenseIdGuid = $pSLLicenseId
    } catch {
        [Guid]$pSLLicenseIdGuid = $pSLLicenseId[0]
    }

    try {
        if ($loopAllValues) {
            $allValues = @{}
            $SL_ID = @(
                "fileId",               # SL_ID_LICENSE_FILE
                "pkeyId",               # SL_ID_PKEY
                "pkeyIdList"            # SL_ID_PKEY [Same]
                "productSkuId",         # SL_ID_PRODUCT_SKU
                "applicationId"         # SL_ID_APPLICATION
                "licenseId",            # SL_ID_LICENSE
                "privateCertificateId"  # SL_ID_LICENSE
            )

            # un offical, intersting pattern
            # first saw in MAS AIO file, TSforge project}
            $MSFT = @(
                "msft:sl/EUL/GENERIC/PUBLIC",    "msft:sl/EUL/GENERIC/PRIVATE",    # un-offical
                "msft:sl/EUL/PHONE/PUBLIC",      "msft:sl/EUL/PHONE/PRIVATE",      # un-offical
                "msft:sl/EUL/STORE/PUBLIC",      "msft:sl/EUL/STORE/PRIVATE",      # un-offical
                "msft:sl/EUL/ACTIVATED/PRIVATE", "msft:sl/EUL/ACTIVATED/PUBLIC",   # extract from SPP* dll/exe files
                "msft:sl/PL/GENERIC/PUBLIC",     "msft:sl/PL/GENERIC/PRIVATE"      # extract from SPP* dll/exe files
            )
            
            # Offical from MS
            $OfficalPattern = @("Description", "Name", "Author")

            # the rest, from XML Blobs --> <infoStr>
            $xml = @("pkeyConfigLicenseId", "privateCertificateId", "licenseType", 
                "licensorUrl",  "licenseCategory", "productName", "Family","licenseVersion",
                "productAuthor", "productDescription",  "hwid:ootGrace", "issuanceCertificateId", "PAUrl",
                "ActivationSequence", "ValidationTemplateId", "ValUrl", "UXDifferentiator",
				"ProductKeyGroupUniqueness", "EnableNotificationMode", "GraceTimerUniqueness",
                "ValidityTimerUniqueness", "EnableActivationValidation",
                "DependsOn", "phone:policy", "licensorKeyIndex", "BuildVersion",
                "ProductUniquenessGroupId", "ApplicationBitmap", "migratable")
            
            # SoftwareLicensingProduct class (WMI)
            $SoftwareLicensingProduct = @(
                "Name",  "Description", "ApplicationID", "VLActivationInterval", "VLRenewalInterval",
                "ProductKeyID",  "KeyManagementServiceProductKeyID", "KeyManagementServicePort", 
                "RequiredClientCount", "TrustedTime", "TokenActivationILID", "TokenActivationILVID",
                "TokenActivationGrantNumber", "TokenActivationCertificateThumbprint", "CustomerPID",
                "KeyManagementServiceName", "KeyManagementServicePort","TimeBasedExtendedGrace", 
                "DiscoveredKeyManagementServiceName", "DiscoveredKeyManagementServicePort",
                "PKCURL", "EULURL", "stilName", "stilVersion", "stilAuthZStatus", "stilExpiration", "stilComment", "stilComment2"
            )

            # SPP* DLL/EXE file's
            $sppwmi = @(
                "ADActivationObjectDN", "ADActivationObjectName", "DiscoveredKeyManagementServiceIpAddress",
                "KeyManagementServiceLookupDomain", "RemainingRearmCount", "TokenActivationAdditionalInfo",
                "TokenActivationCertThumbprint", "VLActivationType", "RearmCount", "ADActivationCsvlkPID", 
                "fileIndex", "licenseDescription", "metaInfoType", "DigitalEncryptedPID", "ADActivationCsvlkSkuID",
				"InheritedActivationId", "InheritedActivationHostMachineName", "InheritedActivationHostDigitalPid2",
				"InheritedActivationActivationTime", "licenseNamespace"
            )

            # Combine all arrays and remove duplicates
            $allValueNames = ($SL_ID + $MSFT + $OfficalPattern + $xml + $SoftwareLicensingProduct + $sppwmi) | Sort-Object -Unique

            foreach ($valueName in $allValueNames) {
                $dataType = 0
                $valueSize = 0
                $ptr = [IntPtr]::Zero

                $res = $global:SLC::SLGetLicenseInformation(
                    $hSLC,
                    [ref]$pSLLicenseIdGuid,
                    $valueName,
                    [ref]$dataType,
                    [ref]$valueSize,
                    [ref]$ptr
                )

                if ($res -ne 0) {
                    #Write-Warning "fail to process Name: $valueName"
                    $allValues[$valueName] = $null
                    continue;
                }
 
                $allValues[$valueName] = Parse-RegistryData -dataType $dataType -ptr $ptr -valueSize $valueSize -valueName $valueName
                Free-IntPtr -handle $ptr -Method Local
            }

            return $allValues
        }

        if ($pwszValueName) {
            $dataType = 0
            $valueSize = 0
            $ptr = [IntPtr]::Zero

            $res = $global:SLC::SLGetLicenseInformation(
                $hSLC,
                [ref]$pSLLicenseIdGuid,
                $valueName,
                [ref]$dataType,
                [ref]$valueSize,
                [ref]$ptr
            )

            if ($res -ne 0) {
                #$messege = $(Parse-ErrorMessage -MessageId $res)
                #Write-Warning "ERROR $res, $messege, Value: $pwszValueName"
                throw
            }

            try {
                return Parse-RegistryData -dataType $dataType -ptr $ptr -valueSize $valueSize -valueName $pwszValueName
            }
            finally {
                Free-IntPtr -handle $ptr -Method Local
            }
        }

        Write-Error "Bad Option"
    }
    catch { }
    finally {
        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}

<#
.SYNOPSIS
    Retrieves various system and service information,
    based on the specified value name or fetches all available information if requested.

.Source
   sppwmi.dll.! 
   *GetServiceInformation*

.Usage

Example Code:
~~~~~~~~~~~~

Get-ServiceInfo -loopAllValues
Get-ServiceInfo -pwszValueName SecureStoreId

~~~~~~~~~~~~~~~~~~~~~~~~~

Clear-Host

Write-Host
Write-Host "Get-OA3xOriginalProductKey" -ForegroundColor Green
Get-OA3xOriginalProductKey

Write-Host
Write-Host "Get-ServiceInfo" -ForegroundColor Green
Get-ServiceInfo -loopAllValues | Format-Table -AutoSize

Write-Host
Write-Host "Get-ActiveLicenseInfo" -ForegroundColor Green
Get-ActiveLicenseInfo | Format-List
#>
function Get-ServiceInfo {
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet(
            "ActivePlugins", "CustomerPID", "SystemState", "Version",
            "BiosOA2MinorVersion", "BiosProductKey", "BiosSlicState",
            "BiosProductKeyDescription", "BiosProductKeyPkPn",
            "ClientMachineID", "SecureStoreId", "SessionMachineId",
            "DiscoveredKeyManagementPort",
            "DiscoveredKeyManagementServicePort",
            "DiscoveredKeyManagementServiceIpAddress",
            "DiscoveredKeyManagementServiceName",
            "IsKeyManagementService",
            "KeyManagementServiceCurrentCount",
            "KeyManagementServiceFailedRequests",
            "KeyManagementServiceLicensedRequests",
            "KeyManagementServiceNonGenuineGraceRequests",
            "KeyManagementServiceNotificationRequests",
            "KeyManagementServiceOOBGraceRequests",
            "KeyManagementServiceOOTGraceRequests",
            "KeyManagementServiceRequiredClientCount",
            "KeyManagementServiceTotalRequests",
            "KeyManagementServiceUnlicensedRequests",
            "TokenActivationAdditionalInfo",
            "TokenActivationCertThumbprint",
            "TokenActivationGrantNumber",
            "TokenActivationILID",
            "TokenActivationILVID"
        )]
        [String]$pwszValueName,

        [Parameter(Mandatory = $false)]
        [switch]$loopAllValues,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )

    # !Xor Case
    if (!($pwszValueName -xor [BOOL]$loopAllValues)) {
        Write-Warning "Exactly one of -pwszValueName, -loopAllValues, must be specified."
        return
    }

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }

    try {
        $allValues = @{}
        if ($loopAllValues) {
            $allValueNames = @(
                "ActivePlugins", "CustomerPID", "SystemState", "Version",
                "BiosOA2MinorVersion", "BiosProductKey", "BiosSlicState",
                "BiosProductKeyDescription", "BiosProductKeyPkPn",
                "ClientMachineID", "SecureStoreId", "SessionMachineId",
                "DiscoveredKeyManagementPort",
                "DiscoveredKeyManagementServicePort",
                "DiscoveredKeyManagementServiceIpAddress",
                "DiscoveredKeyManagementServiceName",
                "IsKeyManagementService",
                "KeyManagementServiceCurrentCount",
                "KeyManagementServiceFailedRequests",
                "KeyManagementServiceLicensedRequests",
                "KeyManagementServiceNonGenuineGraceRequests",
                "KeyManagementServiceNotificationRequests",
                "KeyManagementServiceOOBGraceRequests",
                "KeyManagementServiceOOTGraceRequests",
                "KeyManagementServiceRequiredClientCount",
                "KeyManagementServiceTotalRequests",
                "KeyManagementServiceUnlicensedRequests",
                "TokenActivationAdditionalInfo",
                "TokenActivationCertThumbprint",
                "TokenActivationGrantNumber",
                "TokenActivationILID",
                "TokenActivationILVID"
            )

            foreach ($valueName in $allValueNames) {
                $dataType = 0
                $valueSize = 0
                $ptr = [IntPtr]::Zero
                $res = $global:SLC::SLGetServiceInformation(
                    $hSLC,
                    $valueName,
                    [ref]$dataType,
                    [ref]$valueSize,
                    [ref]$ptr
                )

                if ($res -ne 0) {
                    #Write-Warning "fail to process Name: $valueName"
                    $allValues[$valueName] = $null
                    continue;
                }
 
                $allValues[$valueName] = Parse-RegistryData -dataType $dataType -ptr $ptr -valueSize $valueSize -valueName $valueName
                Free-IntPtr -handle $ptr -Method Local
            }

            return $allValues
        }

        if ($pwszValueName) {
            $dataType = 0
            $valueSize = 0
            $ptr = [IntPtr]::Zero
            $res = $global:SLC::SLGetServiceInformation(
                $hSLC,
                $pwszValueName,
                [ref]$dataType,
                [ref]$valueSize,
                [ref]$ptr
            )

            if ($res -ne 0) {
                #$messege = $(Parse-ErrorMessage -MessageId $res)
                #Write-Warning "ERROR $res, $messege, Value: $pwszValueName"
                throw
            }

            # Parse value based on data type
            try {
                return Parse-RegistryData -dataType $dataType -ptr $ptr -valueSize $valueSize -valueName $pwszValueName
            }
            finally {
                Free-IntPtr -handle $ptr -Method Local
            }
        }
    }
    catch { }
    finally {
        if ($closeHandle) {
            Write-Warning "Consider Open handle Using Manage-SLHandle"
            Free-IntPtr -handle $hSLC -Method License
        }
    }
}

<#
.SYNOPSIS
Get active information using SLGetActiveLicenseInfo API
return value is struct DigitalProductId4

Also, Parse-DigitalProductId4 function, read same results just from registry
"HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -> DigitalProductId4 [Propertie]

*** not always, in case of ==> Get-OA3xOriginalProductKey == TRUE
Get-ActiveLicenseInfo ==> IS EQAL too ==>
$GroupID = Decode-Key -Key (Get-OA3xOriginalProductKey) | Select-Object -ExpandProperty Group
$Global:PKeyDatabase | ? RefGroupId -eq $GroupID | Select-Object -First 1

it also mask the key, like it was mak key [it's bios key !]
and, not even active, so, why mark it as active ?

.Usage

Example Code:
~~~~~~~~~~~~

Clear-Host

Write-Host
Write-Host "Get-OA3xOriginalProductKey" -ForegroundColor Green
Get-OA3xOriginalProductKey

Write-Host
Write-Host "Get-ServiceInfo" -ForegroundColor Green
Get-ServiceInfo -loopAllValues | Format-Table -AutoSize

Write-Host
Write-Host "Get-ActiveLicenseInfo" -ForegroundColor Green
Get-ActiveLicenseInfo | Format-List
#>
function Get-ActiveLicenseInfo {
    param (
        [Guid]$SkuID = [Guid]::Empty
    )

    # Initialize all pointers to zero
    $hSLC = $ptr = $contextPtr = [IntPtr]::Zero
    $size = 0

    try {
        # If GUID is provided, allocate and copy
        if ($SkuID -ne [Guid]::Empty) {
            $guidBytes = $SkuID.ToByteArray()
            $contextPtr = New-IntPtr -Size 16
            [Marshal]::Copy($guidBytes, 0, $contextPtr, 16)
        }

        Manage-SLHandle -Release | Out-Null
        $hSLC = Manage-SLHandle

        if ($hSLC -eq [IntPtr]::Zero) {
            throw "Fail to get handle from SLOPEN API"
        }

        $res = $Global:SLC::SLGetActiveLicenseInfo($hSLC, $contextPtr, [ref]$size, [ref]$ptr)
        if ($res -ne 0 -or $ptr -eq [IntPtr]::Zero -or $size -le 0) {
            $ErrorMessage = Parse-ErrorMessage -MessageId $res
            throw "SLGetActiveLicenseInfo failed with HRESULT: $res, $ErrorMessage."
        }

        if ($size -lt 1280) {
            throw "Returned license buffer too small ($size bytes). Expected >= 1280 for DigitalProductId4."
        }
        
        Parse-DigitalProductId4 -Pointer $ptr -Length $size -FromIntPtr
    }
    catch {
        Write-Warning "Failed to get active license info: $_"
    }
    finally {
        if ($hSLC -ne [IntPtr]::Zero) {
            Manage-SLHandle -Release | Out-Null
        }
        if ($contextPtr -ne [IntPtr]::Zero) {
            New-IntPtr -hHandle $contextPtr -Release
        }
        if ($ptr -ne [IntPtr]::Zero) {
            $Global:kernel32::LocalFree($ptr) | Out-Null
        }
    }
}

<#
 Function Input  -> skuId -> [pkeyId]
 Function Output -> Extended PID, DigitalProductId v3 & v4

 very similer to 
 - Get-PidGenX             [PidgenX Api]
 - Get-ActiveLicenseInfo   [SLGetActiveLicenseInfo Api]
 - Parse-DigitalProductId4 [Manual parse Registry Pid4 Value]
 
 About parameter 4, Probably, MPC
 -----------------------------------------
 Default value for MSPID, 03612 ?? 00000 ?
 PIDGENX2 -> v26 = L"00000" // SPPCOMAPI, GetWindowsPKeyInfo -> L"03612"

 // Tsforge Source Code
 public string GetMPC()
 {
   if (mpc != null)
   {
       return mpc;
   }

   int build = Environment.OSVersion.Version.Build;
   mpc = build >= 10240 ? "03612" :
           build >= 9600 ? "06401" :
           build >= 9200 ? "05426" :
           "55041";

>> Example. >>

Clear-Host
Write-Host

Write-Host "Parse registry Results" -ForegroundColor Green
Write-Host
Parse-DigitalProductId4 -FromRegistry

Write-Host "SLGetActiveLicenseInfo Api Results" -ForegroundColor Green
Write-Host
Get-ActiveLicenseInfo

Write-Host "SLpGetMSPidInformation Api Results" -ForegroundColor Green
Write-Host
Get-pKeyInformation -SkuId ed655016-a9e8-4434-95d9-4345352c2552

Write-Host "PidGenX2 Api Results" -ForegroundColor Green
(Get-PidGenX `
    -key "QPM6N-7J2WJ-P88HH-P3YRH-YY74H" `
    -configPath "C:\Windows\System32\spp\tokens\pkeyconfig\pkeyconfig.xrm-ms" `
    -AsObject) | Format-Table
#>
function Get-pKeyInformation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Guid]$SkuId,

        [Parameter(Mandatory = $false)]
        [Int32]$MPC = 03612
    )

    # Params 1,   HSLC, NdrClientCall3((MIDL_STUBLESS_PROXY_INFO *)&pProxyInfo, 3u, 0i64, a1 ...
    # Params 2,   GUID, (*a1, a2, 16i64, a3); [PKEY] GUID
    # Params 3,   not used
    # Params 4,   Int32 value, MSPID value
    # Params 5,6  String, Extended ProductID
    # Params 7,8  DigitalProductId3 Struct
    # Params 9,+  DigitalProductId4 Struct

    $pkeyId = [Guid]::Empty
    $hSLC   = Manage-SLHandle
    try {
        $pkeyId = [Guid]::Parse(
            (Get-ProductSkuInformation -ActConfigId $skuId -pwszValueName pkeyId -hSLC $hSLC).Trim().Substring(0,36))
    } catch {}
    if ($pkeyId -eq $null -or $pkeyId -eq [Guid]::Empty) {
        Write-Error "Not a valid PkeyID GUID"
        return
    }

    $Epid = ''
    $Pid4 = $Pid3 = [IntPtr]::Zero
    $Length = $pid3_Size = $pid4_Size = 0x00

    $ret = $global:slc::SLpGetMSPidInformation(
            $hSLC, 
            [ref]$pkeyId, 
            0L, 
            $MPC,
            [ref]$Length,    [ref]$Epid,
            [ref]$pid3_Size, [ref]$Pid3,
            [ref]$pid4_Size, [ref]$Pid4
        )

    if ($ret -eq 0x0) {
        $pid4Obj = Parse-DigitalProductId4 -Pointer $Pid4 -Length $pid4_Size -FromIntPtr
        return [PSCustomObject]@{
            MajorVersion = $pid4Obj.MajorVersion
            MinorVersion = $pid4Obj.MinorVersion
            AdvancedPID  = $pid4Obj.AdvancedPID
            ActivationID = $pid4Obj.ActivationID
            EditionType  = $pid4Obj.EditionType
            EditionID    = $pid4Obj.EditionID
            KeyType      = $pid4Obj.KeyType
            EULA         = $pid4Obj.EULA
            DigitalKey   = $pid4Obj.DigitalKey
            Epid = $Epid
        }
    } else {
        Write-Error (Parse-ErrorMessage -MessageId $ret)
        return
    }
}

<#
.SYNOPSIS
Get Info per license, using Pkeyconfig [XML] & low level API

$WMI_QUERY = Get-SLIDList -eQueryIdType SL_ID_PRODUCT_SKU -eReturnIdType SL_ID_PRODUCT_SKU
$WMI_SQL = $WMI_QUERY | % { Get-LicenseInfo -ActConfigId $_ }
$WMIINFO = $WMI_SQL | Select-Object * -ExcludeProperty Policies | ? EditionID -NotMatch 'ESU'
Manage-SLHandle -Release | Out-null
#>
function Get-LicenseInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ActConfigId,

        [Parameter(Mandatory=$false)]
        [Intptr]$hSLC = [IntPtr]::Zero
    )
    function Get-BrandingValue {
        param (
            [Parameter(Mandatory=$true)]
            [guid]$sku
        )

        try {

            # Fetch license details for the SKU
            $xml = Get-ProductSkuInformation -ActConfigId $sku -ReturnRawData -hSLC $hSLC
            if (-not $xml) {
                return;  }

            $BrandingValue = $xml.licenseGroup.license[1].otherInfo.infoTables.infoList.infoStr | Where-Object Name -EQ 'win:branding'
            return $BrandingValue.'#text'

            #$match = $Global:productTypeTable | Where-Object {
            #    [Convert]::ToInt32($_.DWORD, 16) -eq $BrandingValue.'#text'
            #}
            #return $match.ProductID

        } catch {
            Write-Warning "An error occurred: $_"
            return $null
        }
    }
    Function Get-KeyManagementServiceInfo {
        param (
            [Parameter(Mandatory=$true)]
            [STRING]$SKU_ID
        )

        if ([STRING]::IsNullOrWhiteSpace($SKU_ID) -or (
        $SKU_ID -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')) {
            Return @();
        }

        $Base = "HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform"
        $Application_ID = Retrieve-SKUInfo -SkuId 7103a333-b8c8-49cc-93ce-d37c09687f92 -eReturnIdType SL_ID_APPLICATION | select -ExpandProperty Guid

        if ($Application_ID) {
            $KeyManagementServiceName = Get-ItemProperty -Path "$Base\$Application_ID\$SKU_ID" -Name "KeyManagementServiceName" -ea 0 | select -ExpandProperty KeyManagementServiceName
            $KeyManagementServicePort = Get-ItemProperty -Path "$Base\$Application_ID\$SKU_ID" -Name "KeyManagementServicePort" -ea 0 | select -ExpandProperty KeyManagementServicePort
        }
        if (-not $KeyManagementServiceName) {
            $KeyManagementServiceName = Get-ItemProperty -Path "$Base" -Name "KeyManagementServiceName" -ea 0 | select -ExpandProperty KeyManagementServiceName
        }
        if (-not $KeyManagementServicePort) {
            $KeyManagementServicePort = Get-ItemProperty -Path "$Base" -Name "KeyManagementServicePort" -ea 0 | select -ExpandProperty KeyManagementServicePort
        }
        return @{
            KeyManagementServiceName = $KeyManagementServiceName
            KeyManagementServicePort = $KeyManagementServicePort
        }
    }

    if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
        $hSLC = if ($global:hSLC_ -and $global:hSLC_ -ne [IntPtr]::Zero -and $global:hSLC_ -ne 0) {
            $global:hSLC_
        } else {
            Manage-SLHandle
        }
    }

    try {
        $closeHandle = $true
        if (-not $hSLC -or $hSLC -eq [IntPtr]::Zero -or $hSLC -eq 0) {
            $hr = $Global:SLC::SLOpen([ref]$hSLC)
            if ($hr -ne 0) {
                throw "SLOpen failed: HRESULT 0x{0:X8}" -f $hr
            }
        } else {
            $closeHandle = $false
        }
    }
    catch {
        return $null
    }
    
    # Normalize GUID (no braces for WMI)
    $guidNoBraces = $ActConfigId.Trim('{}')

    # Get WMI data filtered by ID
    #$wmiData = Get-WmiObject -Query "SELECT * FROM SoftwareLicensingProduct WHERE ID='$guidNoBraces'"

    $Policies = Get-ProductSkuInformation -ActConfigId $ActConfigId -hSLC $hSLC
    if ($Policies) {
        $policiesArray = foreach ($item in $Policies) {
            $LicenseId = $item.LicenseId
            foreach ($policy in $item.Policies) {
                if ($policy.Name -and $policy.Value) {
                    [PSCustomObject]@{
                        ID    = $LicenseId
                        Name  = $policy.Name
                        Value = $policy.Value
                    }
                }
            }
        }
    }

    # Gets the information of the specified product key.
    $SLCPKeyInfo = Get-SLCPKeyInfo -SKU $ActConfigId -loopAllValues -hSLC $hSLC

    # Define your ValidateSet values for license details
    $info = Get-ProductSkuInformation -ActConfigId $ActConfigId -loopAllValues -hSLC $hSLC

    if ($closeHandle) {
        Write-Warning "Consider Open handle Using Manage-SLHandle"
        Free-IntPtr -handle $hSLC -Method License
    }

    # Extract XML data filtered by ActConfigId
    $xmlData = $Global:PKeyDatabase | ? { $_.ActConfigId -eq $ActConfigId -or $_.ActConfigId -eq "{$guidNoBraces}" }
    $KeyManagementServiceInfo = Get-KeyManagementServiceInfo -SKU_ID $ActConfigId

    $ppwszInstallation = $null
    $ppwszInstallationIdPtr = [IntPtr]::Zero
    $pProductSkuId = [GUID]::new($ActConfigId)
    $null = $Global:SLC::SLGenerateOfflineInstallationIdEx(
        $hSLC, [ref]$pProductSkuId, 0, [ref]$ppwszInstallationIdPtr)
    if ($ppwszInstallationIdPtr -ne [IntPtr]::Zero) {
        $ppwszInstallation = [marshal]::PtrToStringAuto($ppwszInstallationIdPtr)
    }
    Free-IntPtr -handle $ppwszInstallationIdPtr -Method Local
    $ppwszInstallationIdPtr = 0

    $Branding = Get-BrandingValue -sku $ActConfigId

    return [PSCustomObject]@{
        # Policies
        Branding = $Branding
        Policies = $policiesArray

        # XML data properties, with safety checks
        ActConfigId        = if ($xmlData.ActConfigId) { $xmlData.ActConfigId } else { $null }
        RefGroupId         = if ($xmlData.RefGroupId) { $xmlData.RefGroupId } else { $null }
        EditionId          = if ($xmlData.EditionId) { $xmlData.EditionId } else { $null }
        #ProductDescription = if ($xmlData.ProductDescription) { $xmlData.ProductDescription } else { $null }
        ProductKeyType     = if ($xmlData.ProductKeyType) { $xmlData.ProductKeyType } else { $null }
        IsRandomized       = if ($xmlData.IsRandomized) { $xmlData.IsRandomized } else { $null }

        # License Details (from ValidateSet)
        Description          = $info["Description"]
        Name                 = $info["Name"]
        Author               = $info["Author"]
        licenseType         = $info["licenseType"]
        licenseVersion      = $info["licenseVersion"]
        licensorUrl         = $info["licensorUrl"]
        licenseCategory     = $info["licenseCategory"]
        ID                  = $info["productSkuId"]
        privateCertificateId = $info["privateCertificateId"]
        applicationId       = $info["applicationId"]
        productName         = $info["productName"]
        LicenseFamily       = $info["Family"]
        productAuthor       = $info["productAuthor"]
        productDescription  = $info["productDescription"]
        hwidootGrace        = $info["hwid:ootGrace"]
        TrustedTime         = $info["TrustedTime"]
        ProductUniquenessGroupId  = $info["ProductUniquenessGroupId"]
        issuanceCertificateId         = $info["issuanceCertificateId"]
        pkeyConfigLicenseId         = $info["pkeyConfigLicenseId"]
        ValidationURL         = $info["ValUrl"]
        BuildVersion         = $info["BuildVersion"]
        ActivationSequence         = $info["ActivationSequence"]
        EnableActivationValidation         = $info["EnableActivationValidation"]
        ValidityTimerUniqueness         = $info["ValidityTimerUniqueness"]
        ApplicationBitmap         = $info["ApplicationBitmap"]
        
        # Abbody1406 suggestion PAUrl -or EULURL
        UseLicenseURL         = if ($info["PAUrl"]) {$info["PAUrl"]} else {if ($info["EULURL"]) {$info["EULURL"]} else {$null}}
        ExtendedGrace         = $info["TimeBasedExtendedGrace"]
        phone_policy         = $info["phone:policy"]
        UXDifferentiator         = $info["UXDifferentiator"] # WindowsSkuCategory
        ProductKeyGroupUniqueness         = $info["ProductKeyGroupUniqueness"]
        migratable         = $info["migratable"]
        LicenseDependsOn         = $info["DependsOn"]
        LicenseIsAddon           = [BOOL]($info["DependsOn"])
        EnableNotificationMode         = $info["EnableNotificationMode"]
        GraceTimerUniqueness         = $info["GraceTimerUniqueness"]
        VLActivationInterval = $info["VLActivationInterval"]
        ValidationTemplateId = $info["ValidationTemplateId"]      
        licensorKeyIndex = $info["licensorKeyIndex"]
        TokenActivationILID = $info["TokenActivationILID"]
        TokenActivationILVID = $info["TokenActivationILVID"]
        TokenActivationGrantNumber = $info["TokenActivationGrantNumber"]
        TokenActivationCertificateThumbprint = $info["TokenActivationCertificateThumbprint"]
        OfflineInstallationId = $ppwszInstallation

        #KeyManagementServicePort = $info["KeyManagementServicePort"]
        #KeyManagementServiceName = if ($KeyManagementServiceInfo.KeyManagementServiceName) { $KeyManagementServiceInfo.KeyManagementServiceName } else { $null }
        #KeyManagementServicePort = if ($KeyManagementServiceInfo.KeyManagementServicePort) { $KeyManagementServiceInfo.KeyManagementServicePort } else { $null }

        # thank's abbody1406 for last 5 item's
        KeyManagementServiceProductKeyID = $info["CustomerPID"]
        KeyManagementServiceMachine = $info["KeyManagementServiceName"]
        KeyManagementServicePort = $info["KeyManagementServicePort"]
        DiscoveredKeyManagementServiceMachineName = $info["DiscoveredKeyManagementServiceName"]
        DiscoveredKeyManagementServiceMachinePort = $info["DiscoveredKeyManagementServicePort"]

        # another new list from sppwmi.dll
        ADActivationObjectDN = $info["ADActivationObjectDN"]
        ADActivationObjectName = $info["ADActivationObjectName"]
        ADActivationCsvlkPID = $info["ADActivationCsvlkPID"]
        ADActivationCsvlkSkuID = $info["ADActivationCsvlkSkuID"]
        DiscoveredKeyManagementServiceIpAddress = $info["DiscoveredKeyManagementServiceIpAddress"]
        KeyManagementServiceLookupDomain = $info["KeyManagementServiceLookupDomain"]
        TokenActivationAdditionalInfo = $info["TokenActivationAdditionalInfo"]
        TokenActivationCertThumbprint = $info["TokenActivationCertThumbprint"]
        VLActivationType = $info["VLActivationType"]
        RearmCount = $info["RearmCount"]
        RemainingRearmCount = $info["RemainingRearmCount"]

        # CPKey Info
        ProductKeyChannel    = $SLCPKeyInfo["Channel"]
        ProductKeyID        = $SLCPKeyInfo["DigitalPID"]
        ProductKeyID2       = $SLCPKeyInfo["DigitalPID2"]
        #ProductSkuId      = $SLCPKeyInfo["ProductSkuId"]
        PartialProductKey = $SLCPKeyInfo["PartialProductKey"]
    }
}

<#
Service & Active Lisence Info
~ Get-ServiceInfo >> SLGetServiceInformation
~ Get-ActiveLicenseInfo >> SLGetActiveLicenseInfo

mostly good for oem information
in case of oem license not exist,
SLGetActiveLicenseInfo will output current active license
#>
Function Query-ActiveLicenseInfo {
    $Info = @()
    $licInput, $serInput = @{}, @{}

    try {
        $ActiveLicenseInfo = Get-ActiveLicenseInfo
        @("ActivationID", "AdvancedPID", "DigitalKey",
            "EditionID", "EditionType", "EULA", "KeyType",
            "MajorVersion", "MinorVersion" ) | % { $licInput.Add($_,$ActiveLicenseInfo.$_)}

        $licInput.Keys | Sort | % {
            $Info += [PSCustomObject]@{
                Name = $_
                Value = $licInput[$_]
            }
        }

        $ServiceInfo = Get-ServiceInfo -loopAllValues
        $ServiceInfo.Keys | % { $serInput.Add($_,$ServiceInfo[$_])}

        $serInput.Keys | Sort | % {
            $Info += [PSCustomObject]@{
                Name = $_
                Value = $serInput[$_]
            }
        }
    }
    catch {
    }

    return $Info
}

<#
using namespace System
using namespace System.IO
using namespace System.Text
using namespace System.Text.RegularExpressions
using namespace System.Runtime.InteropServices

Clear-Host
Write-Host

[IntPtr]$ppbValue  = 0L
[Int32]$pcbValue   = 0x0
[Int32]$peDataType = 0x0
[string]$ValueName = 'Security-SPP-Action-StateData'

try {
    if ((Invoke-UnmanagedMethod `
        -Dll slc.dll `
        -Function SLGetWindowsInformation `
        -CharSet Unicode `
        -Values (
            $ValueName,
            [ref]$peDataType,
            [ref]$pcbValue,
            [ref]$ppbValue
        )) -eq 0x00) {

            Write-Host "Return Results from slc.dll::SLGetWindowsInformation`n" -ForegroundColor Magenta
            Parse-RegistryData $peDataType $ppbValue $pcbValue $ValueName
    }
}
finally {
    Free-IntPtr $ppbValue -Method Local
}

$pwszValueName = Init-NativeString -Value $ValueName -Encoding Unicode
$peDataType    = 0x0
$pcbValue      = 3000
$ppbValue      = New-IntPtr -Size 3000

try {
    if ((Invoke-UnmanagedMethod `
        -Dll ntdll.dll `
        -Function ZwQueryLicenseValue `
        -CharSet Unicode `
        -SysCall `
        -Values (
            $pwszValueName,
            [ref]$peDataType,
            $ppbValue,
            $pcbValue, ([ref]$pcbValue)
        )) -eq 0x00) {

            Write-Host "`nReturn Results from ntdll.dll::ZwQueryLicenseValue`n" -ForegroundColor Magenta
            Parse-RegistryData $peDataType $ppbValue $pcbValue $ValueName
    }
}
finally {
    Free-IntPtr $ppbValue -Method Auto
    Free-IntPtr $pwszValueName -Method UNICODE_STRING
}
#>
Function Get-WindowsInformation {
    param(
        [string]$pwszValueName
    )

    if ([string]::IsNullOrWhiteSpace($pwszValueName)) {
        Write-Warning "Use Default Value 'Security-SPP-Action-StateData'`n"
        $pwszValueName = 'Security-SPP-Action-StateData'
    }

    $peDataType, $pcbValue = 0x00, 0x00
    $ppbValue = New-IntPtr -Size ([Intptr]::Size)
    $ppbValuePtr = [IntPtr]::Zero

    try {
        $ret = $Global:slc::SLGetWindowsInformation(
            $pwszValueName,
            [ref]$peDataType,
            [ref]$pcbValue,
            $ppbValue
        )
        if ($ret -eq 0x00) {
            # Alternative use, Instead use Pointer By Ref .. Safe way
            $ppbValuePtr = [Marshal]::ReadIntPtr($ppbValue)
            return (
                Parse-RegistryData $peDataType $ppbValuePtr $pcbValue $pwszValueName
            )
        }

        return $null
    }
    finally {
        Free-IntPtr $ppbValue -Method Auto
        Free-IntPtr $ppbValuePtr -Method Local
    }
}

<#
Very similer to Get-WindowsInformation,
but some values results give different results
Security-SPP-LastWindowsActivationTime, Security-SPP-Action-StateData
very diffrenct results compare to Get-WindowsInformation

Example.

Clear-Host
Write-Host

$Value = 'Security-SPP-Action-StateData' # Security-SPP-LastWindowsActivationTime
Write-Host "`nGet-PolicyInformation" -ForegroundColor Green
Get-PolicyInformation -pwszValueName $Value -AppID 55c92734-d682-4d71-983e-d6ec3f16059f
Write-Host "`nGet-ApplicationPolicy" -ForegroundColor Green
Get-ApplicationPolicy -value $Value -AppID 55c92734-d682-4d71-983e-d6ec3f16059f
Write-Host "`nGet-WindowsInformation" -ForegroundColor Green
Get-WindowsInformation -pwszValueName $Value
Write-Host "`nGet-ProductPolicy" -ForegroundColor Green
(Get-ProductPolicy -Filter $Value -UseApi | select Value).Value

Write-Host "`nGet All available Names & Compare" -ForegroundColor Green
$ProductPolicyList     = (Get-ProductPolicy | select Name).Name
$ApplicationPolicyList = Get-ApplicationPolicy -AppID 55c92734-d682-4d71-983e-d6ec3f16059f -OutList
Compare-Object -ReferenceObject $ProductPolicyList -DifferenceObject $ApplicationPolicyList
write-host
#>
Function Get-PolicyInformation {
    param(
        [ValidateNotNullOrEmpty()]
        [String]$pwszValueName,

        [Parameter(Mandatory=$true)]
        [ValidateSet(
            '0ff1ce15-a989-479d-af46-f275c6370663',
            '55c92734-d682-4d71-983e-d6ec3f16059f'
        )]
        [GUID]$AppID,

        [Parameter(Mandatory=$false)]
        [GUID]$SkuID = [Guid]::empty
    )

    $hSLC              = Manage-SLHandle
    [Int32]$peDataType = 0x00 # Type
    [UInt32]$pcbValue  = 0x00 # Size
    [IntPtr]$ppbValue  = 0L   # Pointer

    if ([string]::IsNullOrWhiteSpace($pwszValueName)) {
        Write-Warning "Use Default Value 'Security-SPP-Action-StateData'`n"
        $pwszValueName = 'Security-SPP-Action-StateData'
    }
    
    # Gets the policy information after right has been consumed successfully.
    # Must call `SLConsumeRight`, before taking any further action
    if ($SkuID -ne [Guid]::empty) {
        SL-RefreshLicenseStatus -AppID $AppID -skuID $SkuID -hSLC $hSLC | Out-Null
    } else {    
        SL-RefreshLicenseStatus -AppID $AppID -hSLC $hSLC | Out-Null
    }

    $ret = $Global:slc::SLGetPolicyInformation(
            $hSLC,              # [In]  [IntPtr]
            $pwszValueName,     # [In]  [String]
            [ref]$peDataType,   # [Out] [Int32].MakeByRefType()
            [ref]$pcbValue,     # [Out] [UInt32].MakeByRefType()
            [ref]$ppbValue      # [Out] [IntPtr].MakeByRefType()
        )

    if ($ret -eq 0x00) {
        try {
            return (
                Parse-RegistryData `
                    -dataType $peDataType `
                    -ptr $ppbValue `
                    -valueSize $pcbValue `
                    -valueName $pwszValueName
            )
        }
        finally {
            Free-IntPtr `
                -handle $ppbValue `
                -Method Local
        }
    }
    switch ($ret) {
        0x80070057 {
            Write-Error "One or more arguments are not valid."
        }
        0xC004F012 {
            Write-Error "The value for the input key was not found."
        }
        0xC004F013 {
            Write-Error "The caller does not have permission to run the software."
        }
        default {
            Write-Error (Parse-ErrorMessage -MessageId $ret -Flags ACTIVATION)
        }
    }
}

<#
Very similer to Get-WindowsInformation,
but some values results give different results
Security-SPP-LastWindowsActivationTime, Security-SPP-Action-StateData
very diffrenct results compare to Get-WindowsInformation

Example.

Clear-Host
Write-Host

$Value = 'Security-SPP-Action-StateData' # Security-SPP-LastWindowsActivationTime
Write-Host "`nGet-PolicyInformation" -ForegroundColor Green
Get-PolicyInformation -pwszValueName $Value -AppID 55c92734-d682-4d71-983e-d6ec3f16059f
Write-Host "`nGet-ApplicationPolicy" -ForegroundColor Green
Get-ApplicationPolicy -value $Value -AppID 55c92734-d682-4d71-983e-d6ec3f16059f
Write-Host "`nGet-WindowsInformation" -ForegroundColor Green
Get-WindowsInformation -pwszValueName $Value
Write-Host "`nGet-ProductPolicy" -ForegroundColor Green
(Get-ProductPolicy -Filter $Value -UseApi | select Value).Value

Write-Host "`nGet All available Names & Compare" -ForegroundColor Green
$ProductPolicyList     = (Get-ProductPolicy | select Name).Name
$ApplicationPolicyList = Get-ApplicationPolicy -AppID 55c92734-d682-4d71-983e-d6ec3f16059f -OutList
Compare-Object -ReferenceObject $ProductPolicyList -DifferenceObject $ApplicationPolicyList
write-host

Example.

Get-ApplicationPolicy -AppID 55c92734-d682-4d71-983e-d6ec3f16059f -OutList | % {
    
    $value = $_
    $result1 = try {
        Get-PolicyInformation -pwszValueName $value -AppID 55c92734-d682-4d71-983e-d6ec3f16059f -ErrorAction Stop
    } catch { '' }
    $result2 = try {
        Get-WindowsInformation -pwszValueName $value -ErrorAction Stop
    } catch { '' }

    [PSCustomObject]@{
        Value   = $value
        Result1 = $result1
        Result2 = $result2
        Status  = if ($result1 -eq $result2) { "Match" } else { "Different" }
    }
} | Out-GridView -Title "Policy Results"
#>
Function Get-ApplicationPolicy {
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param (
        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByName')]
        [Alias('Name')]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [ValidateSet(
            '0ff1ce15-a989-479d-af46-f275c6370663', 
            '55c92734-d682-4d71-983e-d6ec3f16059f'
        )]
        [GUID]$AppID,

        [Parameter(Mandatory = $false)]
        [GUID]$SkuID = [Guid]::Empty,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByList')]
        [switch]$OutList
    )

    [UInt32]$pcbValue        = 0x0
    [Int32]$peDataType       = 0x0
    [IntPtr]$ppbValue        = 0L
    [IntPtr]$pProductSkuId   = 0L
    [IntPtr]$phPolicyContext = 0L
    [string]$pwszValueName   = if ($PSCmdlet.ParameterSetName -eq 'ByList') { "*" } else { $Value }
    
    $errorFlags = ([ErrorMessageType]::ACTIVATION -bor [ErrorMessageType]::HRESULT)

    try {
        # [in, optional] const SLID *pProductSkuId
        if ($SkuID -ne [Guid]::Empty) {
            $pProductSkuId = New-IntPtr -Data ($SkuID.ToByteArray())
        }

        # Stores the current consumed policies to disk for fast policy access.
        $HR = $Global:slc::SLPersistApplicationPolicies([ref]$AppID, $pProductSkuId, 0x00)
        if ($HR -ne 0) {
            switch ($HR) {
                0x80070057 { throw "One or more arguments are not valid." }
                Default    { throw (Parse-ErrorMessage -MessageId $HR -Flags $errorFlags) }
            }
        }

        # Loads the application policies set with the SLPersistApplicationPolicies function, for use by the SLGetApplicationPolicy function.
        $HR = $Global:slc::SLLoadApplicationPolicies([ref]$AppID, $pProductSkuId, 0x00, [ref]$phPolicyContext)
        if ($HR -ne 0) {
            switch ($HR) {
                0x80070057 { throw "One or more arguments are not valid." }
                0xC004F072 { throw "The license policies for fast query could not be found." }
                Default    { throw (Parse-ErrorMessage -MessageId $HR -Flags $errorFlags) }
            }
        }

        # Queries a policy from the set stored with the SLPersistApplicationPolicies function
        $HR = $Global:slc::SLGetApplicationPolicy($phPolicyContext, $pwszValueName, [ref]$peDataType, [ref]$pcbValue, [ref]$ppbValue)
        if ($HR -ne 0) {
            switch ($HR) {
                0x80070057 { throw "One or more arguments are not valid." }
                0xC004F073 { throw "The policy context was not found." }
                0xC004F012 { throw "The policy '$pwszValueName' is not found." }
                0xC004F013 { throw "The policy list is empty." }
                Default    { throw(Parse-ErrorMessage -MessageId $HR -Flags $errorFlags) }
            }
        }

        # Parse Result later
        Parse-RegistryData -dataType $peDataType -ptr $ppbValue -valueSize $pcbValue -valueName $pwszValueName
    }
    catch {
        Write-Error "Get-ApplicationPolicy Error: $($_.Exception.Message)"
    }
    finally {

        # Cleanup memory
        Free-IntPtr $ppbValue -Method Local
        Free-IntPtr $pProductSkuId -Method Auto

        # Releases the policy context handle returned by the SLLoadApplicationPolicies function.
        if ($phPolicyContext -ne [IntPtr]::Zero) {
            $Global:slc::SLUnloadApplicationPolicies($phPolicyContext, 0x00) | Out-Null
        }
    }
}
#endregion
#region "Keys"
function Get-Strings {
    param (
        [Parameter(Position = 1, Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [String[]]
        $Path,

        [ValidateSet('Default','Ascii','Unicode')]
        [String]
        $Encoding = 'Default',

        [UInt32]
        $MinimumLength = 3
    )

    $Results = @()

    foreach ($File in $Path) {
        if ($Encoding -eq 'Unicode' -or $Encoding -eq 'Default') {
            $UnicodeFileContents = Get-Content -Encoding 'Unicode' $File -EA 0
            if (![STRING]::IsNullOrWhiteSpace($UnicodeFileContents)) {
                $UnicodeRegex = [Regex] "[\u0020-\u007E]{$MinimumLength,}"
                $Results += $UnicodeRegex.Matches($UnicodeFileContents)
            }
        }
        
        if ($Encoding -eq 'Ascii' -or $Encoding -eq 'Default') {
            $AsciiFileContents = Get-Content -Encoding 'UTF7' $File
            $AsciiRegex = [Regex] "[\x20-\x7E]{$MinimumLength,}"
            $Results += $AsciiRegex.Matches($AsciiFileContents)
        }
    }

    return $Results | ForEach-Object { $_.Value }
}
function LookUp-Strings {
    [CmdletBinding(DefaultParameterSetName = "ByPattern")]
    param (
        [Parameter(Mandatory=$True, ParameterSetName="ByPattern")]
        [ValidateNotNullOrEmpty()]
        [string]$Pattern,

        [Parameter(Mandatory=$True, ParameterSetName="ByLength")]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MinLength,

        [ValidateNotNullOrEmpty()]
        [string]$Path = "C:\windows\system32"
    )

    Clear-Host
    Write-Host "Scanning: $Path" -ForegroundColor Cyan

    if (!(Test-Path $Path)) {
        Write-Error "Path not valid"
        return
    }

    $Files = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue | 
             Where-Object { $_.Extension -match '\.(exe|dll|sys)$' } | 
             Select-Object -ExpandProperty FullName

    foreach ($Name in $Files) {
        # Set 1: Pattern Search (Auto-calculates length based on pattern)
        if ($PSCmdlet.ParameterSetName -eq "ByPattern") {
            $Data = Get-Strings -Path $Name -MinimumLength ($Pattern.Length) 2>$null | 
                    Where-Object { $_ -match [regex]::Escape($Pattern) }
        } 
        # Set 2: Length Search (Grabs everything > 0)
        else {
            $Data = Get-Strings -Path $Name -MinimumLength $MinLength 2>$null
        }

        if ($Data) {
            Write-Host $Name -ForegroundColor Green
            $Data        
        }
    }
}
function Extract-CdKeys {
    param (
        [string[]]$strings
    )

    # Define a regex pattern to match the CD keys
    $pattern = '\b[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}\b'

    # Create a hash set to store unique CD keys
    $uniqueCdKeys = @{}

    # Extract the CD keys
    foreach ($line in $strings) {
        if ($line -match $pattern) {
            $matches = [regex]::Matches($line, $pattern)
            foreach ($match in $matches) {
                $uniqueCdKeys[$match.Value] = $true
            }
        }
    }

    return $uniqueCdKeys.Keys
}
function Add-Missing-Ref {
    param (
        [string[]]$cdKeys
    )

    # Define the output list for results
    $results = @()

    # Read reference data into a hash table
    $IgnoreCase = [Text.RegularExpressions.RegexOptions]::IgnoreCase
    $Rpattern = '^\s*(\d+)\s*=\s*"(.*)"\s*#?\s*(.*)?$'
    $refHashTable = @{}

    # Process each key from cdKeys
    foreach ($keyInfo in $cdKeys) {
        if ($keyInfo) {
            $keyId = $null
            try {
            $keyId = @(KeyDecode -key0 $keyInfo )[2].Value
            }
            catch {}

            # Use the captured KeyId in the results
            if ($keyId) {
                $results += "$keyId = `"$keyInfo`" # Add Ref."
            } else {
                continue
            }
        }
    }

    return $results
}
function Add-Missing-Label {
    param (
        [PSCustomObject[]]$referenceData  # Accepts reference data directly
    )

    # Create a list for results
    $results = [List[PSCustomObject]]::new()

    $IgnoreCase = [Text.RegularExpressions.RegexOptions]::IgnoreCase
    $pattern = '^\s*(\d+)\s*=\s*"(.*)"\s*#.*$'

    # Read all keys from the reference data
    foreach ($line in $referenceData) {
        $match = [Regex]::Matches($line, $pattern, $IgnoreCase)

        if ($match.Count -gt 0) {
            $keyKey = $match[0].Groups[1].Value.Trim()  # Key
            $keyValue = $match[0].Groups[2].Value.Trim()  # Value

            # Check for a corresponding reference
            $KeyText = $KeysText[[int]$keyKey]

            # Add the processed key to results
            $results.Add([PSCustomObject]@{ Key = $keyKey; Value = $keyValue; RefText = $KeyText })
        }
    }

    # Return the results
    return $results
}
#endregion
#region "App"
function Run-Tsforge {
Write-host
Write-host
$selected = $null
$ver   = [LibTSforge.Utils]::DetectVersion()
$prod  = [LibTSforge.SPP.SPPUtils]::DetectCurrentKey()

Manage-SLHandle -Release | Out-null
$LicensingProducts = Get-SLIDList -eQueryIdType SL_ID_APPLICATION -eReturnIdType SL_ID_PRODUCT_SKU -pQueryId $windowsAppID | % {
    [PSCustomObject]@{
        ID            = $_
        Description   = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Description'
        Name          = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'productName'
        LicenseFamily = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Family'
    }
}

$products = $LicensingProducts | Where-Object { $_.Description -notmatch 'DEMO|MSDN|PIN|FREE|TIMEBASED|GRACE|W10' } | Select ID,Description,Name
$selected = $products | Sort-Object @{Expression='Name';Descending=$false}, @{Expression='Description';Descending=$true} | Out-GridView -Title 'Select Products to activate' -OutputMode Multiple
if (-not $selected) {
    Write-Host
    Write-Host "ERROR: No matching product found" -ForegroundColor Red
    Write-Host
    return
}

if ($selected -and @($selected).Count -ge 1) {
	foreach ($item in $selected) {
		$tsactid = $item.ID
		Write-Host "ID:          $tsactid" -ForegroundColor DarkGreen
		Write-Host "Name:        $($item.Name)" -ForegroundColor DarkGreen
		Write-Host "Description: $($item.Description)" -ForegroundColor White

        $name = $($item.Name)
        $description = $($item.Description)
        $key = GetRandomKey -ProductID $tsactid
        Write-Warning "GetRandomKey, $key"

        if (-not $key) {
            if ($description -match "Windows") {
                $windowsPath = Join-Path $env:windir "System32\spp\tokens\pkeyconfig\pkeyconfig.xrm-ms"
                $xmlData = Extract-Base64Xml -FilePath $windowsPath | Where-Object ActConfigId -Match "{$tsactid}"
            }
            elseif ($description -match "office") {
                $registryPath = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun"
                $officeInstallRoot = (Get-ItemProperty -Path $registryPath -ea 0).InstallPath
                if ($officeInstallRoot) {
                    $pkeyconfig = Join-Path $officeInstallRoot "\root\Licenses16\pkeyconfig-office.xrm-ms"
                    if ($pkeyconfig -and [System.IO.File]::Exists($pkeyconfig)) {
                        $xmlData = Extract-Base64Xml -FilePath $pkeyconfig | Where-Object ActConfigId -Match "{$tsactid}"
                    }
                }
            }
            if ($xmlData -and $xmlData.RefGroupId) {
                $key = Encode-Key $xmlData.RefGroupId 0 0
                Write-Warning "Encode-Key, $key"
            }
        }

		# Check if the product is VIRTUAL_MACHINE_ACTIVATION
		if ($item.Description -match 'VIRTUAL_MACHINE_ACTIVATION') {
			Write-Host "REQUIRES: Windows Server Datacenter as HOST + hyper-V or QEMU to work," -ForegroundColor Yellow
            Write-Host "by design output indicate success but slmgr.vbs -dlv indicate real state" -ForegroundColor Yellow
		}
		Write-Host

		if ($key) {
			SL-InstallProductKey -Keys @($key)
			Write-Host "Install key: $key"
		} else {
			Write-Warning "No key generated for: $($item.Name)"
			continue
		}

		Activate-License -desc $item.Description -ver $ver -prod $prod -tsactid $tsactid
	}
}
}
function Run-oHook {

if ($AutoMode) {
    Install
    return
}

Write-Host
Write-Host "Welcome to the oHook DLL Installtion Script" -ForegroundColor Cyan
Write-Host "-------------------------------------------"
Write-Host

# Prompt the user for action (I for Install, R for Remove)
$action = Read-Host "Do you want to Install (I) or Remove (R)? (Enter 'I' or 'R')"

# Normalize the input to uppercase for better consistency
$action = $action.ToUpper()

Write-Host

# Run the appropriate function based on user input
switch ($action) {
    'I' {
        Install
        break
    }
    'R' {
        Remove
        break
    }
    default {
        Write-Host "Invalid choice. Please enter either 'I' for Install or 'R' for Remove." -ForegroundColor Red
        break
    }
}

Write-Host "--------------------------------------"
Write-Host "Script execution completed."
return
}
function Run-HWID {
    param (
        [bool]$ForceVolume = $false
    )

Write-Host
Write-Host "Notice:" -ForegroundColor Magenta
Write-Host
Write-Host "HWID activation isn't supported for Evaluation or Server versions." -ForegroundColor Yellow
Write-Host "If HWID activation isn't possible, KMS38 will be used." -ForegroundColor Yellow
Write-Host "For Evaluation and Server, the script uses alternative methods:" -ForegroundColor Yellow
Write-Host
Write-Host "* KMS38   for {Server}`n* TSForge for {Evaluation}" -ForegroundColor Green
Write-Host

$sandbox = "Null" | Get-Service -ea 0
if (-not $sandbox) {
    Write-Host "'Null' service found! Possible sandbox environment." -ForegroundColor Red
    return
}

# remvoe KMS38 lock --> From MAS PROJECT, KMS38_Activation.cmd
$SID = New-Object SecurityIdentifier('S-1-5-32-544')
$Admin = ($SID.Translate([NTAccount])).Value
$ruleArgs = @("$Admin", "FullControl", "Allow")
$path = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform\55c92734-d682-4d71-983e-d6ec3f16059f'
$regkey = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64').OpenSubKey($path, 'ReadWriteSubTree', 'ChangePermissions')
if ($regkey) {
    $acl = $regkey.GetAccessControl()
    $rule = [RegistryAccessRule]::new.Invoke($ruleArgs)
    $acl.ResetAccessRule($rule)
    $regkey.SetAccessControl($acl)
}

$ClipUp = Get-Command ClipUp -ea 0
if (-not $ClipUp) {
  Write-Host
  Write-Host "ClipUp.exe is missing.!" -ForegroundColor Yellow
  Write-Host "Attemp to download ClipUp.exe from remote server" -ForegroundColor Yellow
  iwr "https://github.com/BlueOnBLack/Misc/raw/refs/heads/main/ClipUp.exe" -OutFile "$env:windir\ClipUp.exe" -ea 0
  if ([IO.FILE]::Exists("$env:windir\ClipUp.exe")) {
    if (@(Get-AuthenticodeSignature "$env:windir\ClipUp.exe" -ea 0).Status -eq 'Valid') {
      Write-Host "File was download & verified, at location: $env:windir\ClipUp.exe" -ForegroundColor Yellow
    }
    else {
      ri "$env:windir\ClipUp.exe" -Force -ea 0
    }
  }
}

$ClipUp = Get-Command ClipUp -ea 0
if (-not $ClipUp) {
  Write-Host "ClipUp.exe not found" -ForegroundColor Yellow
  return
}

$osInfo = Get-CimInstance Win32_OperatingSystem
$server = $osInfo.Caption -match "Server"
$evaluation = $osInfo.Caption -match "Evaluation"

if ($server) {
  Write-Host
  Write-Host "Server edition found" -ForegroundColor Yellow
  Write-Host "KMS38 will use instead" -ForegroundColor Yellow
}
elseif ($evaluation) {
  Write-Host
  Write-Host "evaluation edition found" -ForegroundColor Yellow
  Write-Host "use TSFORGE to Remove-Reset Evaluation Lock" -ForegroundColor Yellow
  Write-Host
  $version = [LibTSforge.Utils]::DetectVersion();
  $production = [LibTSforge.SPP.SPPUtils]::DetectCurrentKey();
  
  try {
    # Update from latest TSforge_Activation.cmd
    [LibTSforge.Modifiers.TamperedFlagsDelete]::DeleteTamperFlags($ver, $prod)
    [LibTSforge.SPP.SLApi]::RefreshLicenseStatus()
    [LibTSforge.Modifiers.RearmReset]::Reset($ver, $prod)
    [LibTSforge.Modifiers.GracePeriodReset]::Reset($version,$production)
    [LibTSforge.Modifiers.KeyChangeLockDelete]::Delete($version,$production)
  }
  catch {
  }

  Write-Host
  Write-Host "Done." -ForegroundColor Green
  return
}

# Check if the build is too old
if ($Global:osVersion.Build -lt 10240) {
    Write-Host "`n[!] Unsupported OS version detected: $buildNum" -ForegroundColor Red
    Write-Host "HWID Activation is only supported on Windows 10 or 11." -ForegroundColor DarkYellow
    Write-Host "Use the TSforge activation option from the main menu." -ForegroundColor Cyan
    return
}

("ClipSVC","wlidsvc","sppsvc","KeyIso","LicenseManager","Winmgmt") | % { Start-Service $_ -ea 0}
$EditionID = Get-ProductID
if (!$EditionID) {
  throw "EditionID Variable not found" }
$hashTable = @'
ID,KEY,SKU_ID,Key_part,value,Status,Type,Product
8b351c9c-f398-4515-9900-09df49427262,XGVPP-NMH47-7TTHJ-W3FW7-8HV2C,4,X19-99683,HGNKjkKcKQHO6n8srMUrDh/MElffBZarLqCMD9rWtgFKf3YzYOLDPEMGhuO/auNMKCeiU7ebFbQALS/MyZ7TvidMQ2dvzXeXXKzPBjfwQx549WJUU7qAQ9Txg9cR9SAT8b12Pry2iBk+nZWD9VtHK3kOnEYkvp5WTCTsrSi6Re4,0,OEM:NONSLP,Enterprise
c83cef07-6b72-4bbc-a28f-a00386872839,3V6Q6-NQXCX-V8YXR-9QCYV-QPFCT,27,X19-98746,NHn2n0N1UfVf00CfaI5LCDMDsKdVAWpD/HAfUrcTAKsw9d2Sks4h5MhyH/WUx+B6dFi8ol7D3AHorR8y9dqVS1Bd2FdZNJl/tTR1PGwYn6KL88NS19aHmFNdX8s4438vaa+Ty8Qk8EDcwm/wscC8lQmi3/RgUKYdyGFvpbGSVlk,0,Volume:MAK,EnterpriseN
4de7cb65-cdf1-4de9-8ae8-e3cce27b9f2c,VK7JG-NPHTM-C97JM-9MPGT-3V66T,48,X19-98841,Yl/jNfxJ1SnaIZCIZ4m6Pf3ySNoQXifNeqfltNaNctx+onwiivOx7qcSn8dFtURzgMzSOFnsRQzb5IrvuqHoxWWl1S3JIQn56FvKsvSx7aFXIX3+2Q98G1amPV/WEQ0uHA5d7Ya6An+g0Z0zRP7evGoomTs4YuweaWiZQjQzSpA,0,Retail,Professional
9fbaf5d6-4d83-4422-870d-fdda6e5858aa,2B87N-8KFHP-DKV6R-Y2C8J-PKCKT,49,X19-98859,Ge0mRQbW8ALk7T09V+1k1yg66qoS0lhkgPIROOIOgxKmWPAvsiLAYPKDqM4+neFCA/qf1dHFmdh0VUrwFBPYsK251UeWuElj4bZFVISL6gUt1eZwbGfv5eurQ0i+qZiFv+CcQOEFsd5DD4Up6xPLLQS3nAXODL5rSrn2sHRoCVY,0,Retail,ProfessionalN
f742e4ff-909d-4fe9-aacb-3231d24a0c58,4CPRK-NM3K3-X6XXQ-RXX86-WXCHW,98,X19-98877,vel4ytVtnE8FhvN87Cflz9sbh5QwHD1YGOeej9QP7hF3vlBR4EX2/S/09gRneeXVbQnjDOCd2KFMKRUWHLM7ZhFBk8AtlG+kvUawPZ+CIrwrD3mhi7NMv8UX/xkLK3HnBupMEuEwsMJgCUD8Pn6om1mEiQebHBAqu4cT7GN9Y0g,0,Retail,CoreN
1d1bac85-7365-4fea-949a-96978ec91ae0,N2434-X9D7W-8PF6X-8DV9T-8TYMD,99,X19-99652,Nv17eUTrr1TmUX6frlI7V69VR6yWb7alppCFJPcdjfI+xX4/Cf2np3zm7jmC+zxFb9nELUs477/ydw2KCCXFfM53bKpBQZKHE5+MdGJGxebOCcOtJ3hrkDJtwlVxTQmUgk5xnlmpk8PHg82M2uM5B7UsGLxGKK4d3hi0voSyKeI,0,Retail,CoreCountrySpecific
3ae2cc14-ab2d-41f4-972f-5e20142771dc,BT79Q-G7N6G-PGBYW-4YWX6-6F4BT,100,X19-99661,FV2Eao/R5v8sGrfQeOjQ4daokVlNOlqRCDZXuaC45bQd5PsNU3t1b4AwWeYM8TAwbHauzr4tPG0UlsUqUikCZHy0poROx35bBBMBym6Zbm9wDBVyi7nCzBtwS86eOonQ3cU6WfZxhZRze0POdR33G3QTNPrnVIM2gf6nZJYqDOA,0,Retail,CoreSingleLanguage
2b1f36bb-c1cd-4306-bf5c-a0367c2d97d8,YTMG3-N6DKC-DKB77-7M9GH-8HVX7,101,X19-98868,GH/jwFxIcdQhNxJIlFka8c1H48PF0y7TgJwaryAUzqSKXynONLw7MVciDJFVXTkCjbXSdxLSWpPIC50/xyy1rAf8aC7WuN/9cRNAvtFPC1IVAJaMeq1vf4mCqRrrxJQP6ZEcuAeHFzLe/LLovGWCd8rrs6BbBwJXCvAqXImvycQ,0,Retail,Core
2a6137f3-75c0-4f26-8e3e-d83d802865a4,XKCNC-J26Q9-KFHD2-FKTHY-KD72Y,119,X19-99606,hci78IRWDLBtdbnAIKLDgV9whYgtHc1uYyp9y6FszE9wZBD5Nc8CUD2pI2s2RRd3M04C4O7M3tisB3Ov/XVjpAbxlX3MWfUR5w4MH0AphbuQX0p5MuHEDYyfqlRgBBRzOKePF06qfYvPQMuEfDpKCKFwNojQxBV8O0Arf5zmrIw,0,OEM:NONSLP,PPIPro
e558417a-5123-4f6f-91e7-385c1c7ca9d4,YNMGQ-8RYV3-4PGQ3-C8XTP-7CFBY,121,X19-98886,x9tPFDZmjZMf29zFeHV5SHbXj8Wd8YAcCn/0hbpLcId4D7OWqkQKXxXHIegRlwcWjtII0sZ6WYB0HQV2KH3LvYRnWKpJ5SxeOgdzBIJ6fhegYGGyiXsBv9sEb3/zidPU6ZK9LugVGAcRZ6HQOiXyOw+Yf5H35iM+2oDZXSpjvJw,0,Retail,Education
c5198a66-e435-4432-89cf-ec777c9d0352,84NGF-MHBT6-FXBX8-QWJK7-DRR8H,122,X19-98892,jkL4YZkmBCJtvL1fT30ZPBcjmzshBSxjwrE0Q00AZ1hYnhrH+npzo1MPCT6ZRHw19ZLTz7wzyBb0qqcBVbtEjZW0Xs2MYLxgriyoONkhnPE6KSUJBw7C0enFVLHEqnVu/nkaOFfockN3bc+Eouw6W2lmHjklPHc9c6Clo04jul0,0,Retail,EducationN
f6e29426-a256-4316-88bf-cc5b0f95ec0c,PJB47-8PN2T-MCGDY-JTY3D-CBCPV,125,X23-50331,OPGhsyx+Ctw7w/KLMRNrY+fNBmKPjUG0R9RqkWk4e8ez+ExSJxSLLex5WhO5QSNgXLmEra+cCsN6C638aLjIdH2/L7D+8z/C6EDgRvbHMmidHg1lX3/O8lv0JudHkGtHJYewjorn/xXGY++vOCTQdZNk6qzEgmYSvPehKfdg8js,1,Volume:MAK,EnterpriseS,Ge
cce9d2de-98ee-4ce2-8113-222620c64a27,KCNVH-YKWX8-GJJB9-H9FDT-6F7W2,125,X22-66075,GCqWmJOsTVun9z4QkE9n2XqBvt3ZWSPl9QmIh9Q2mXMG/QVt2IE7S+ES/NWlyTSNjLVySr1D2sGjxgEzy9kLwn7VENQVJ736h1iOdMj/3rdqLMSpTa813+nPSQgKpqJ3uMuvIvRP0FdB7Y4qt8qf9kNKK25A1QknioD/6YubL/4,1,Volume:MAK,EnterpriseS,VB
d06934ee-5448-4fd1-964a-cd077618aa06,43TBQ-NH92J-XKTM7-KT3KK-P39PB,125,X21-83233,EpB6qOCo8pRgO5kL4vxEHck2J1vxyd9OqvxUenDnYO9AkcGWat/D74ZcFg5SFlIya1U8l5zv+tsvZ4wAvQ1IaFW1PwOKJLOaGgejqZ41TIMdFGGw+G+s1RHsEnrWr3UOakTodby1aIMUMoqf3NdaM5aWFo8fOmqWC5/LnCoighs,0,OEM:NONSLP,EnterpriseS,RS5
706e0cfd-23f4-43bb-a9af-1a492b9f1302,NK96Y-D9CD8-W44CQ-R8YTK-DYJWX,125,X21-05035,ntcKmazIvLpZOryft28gWBHu1nHSbR+Gp143f/BiVe+BD2UjHBZfSR1q405xmQZsygz6VRK6+zm8FPR++71pkmArgCLhodCQJ5I4m7rAJNw/YX99pILphi1yCRcvHsOTGa825GUVXgf530tHT6hr0HQ1lGeGgG1hPekpqqBbTlg,0,OEM:NONSLP,EnterpriseS,RS1
faa57748-75c8-40a2-b851-71ce92aa8b45,FWN7H-PF93Q-4GGP8-M8RF3-MDWWW,125,X19-99617,Fe9CDClilrAmwwT7Yhfx67GafWRQEpwyj8R+a4eaTqbpPcAt7d1hv1rx8Sa9AzopEGxIrb7IhiPoDZs0XaT1HN0/olJJ/MnD73CfBP4sdQdLTsSJE3dKMWYTQHpnjqRaS/pNBYRr8l9Mv8yfcP8uS2MjIQ1cRTqRmC7WMpShyCg,0,OEM:NONSLP,EnterpriseS,TH
3d1022d8-969f-4222-b54b-327f5a5af4c9,2DBW3-N2PJG-MVHW3-G7TDK-9HKR4,126,X21-04921,zLPNvcl1iqOefy0VLg+WZgNtRNhuGpn8+BFKjMqjaNOSKiuDcR6GNDS5FF1Aqk6/e6shJ+ohKzuwrnmYq3iNQ3I2MBlYjM5kuNfKs8Vl9dCjSpQr//GBGps6HtF2xrG/2g/yhtYC7FbtGDIE16uOeNKFcVg+XMb0qHE/5Etyfd8,0,Volume:MAK,EnterpriseSN,RS1
60c243e1-f90b-4a1b-ba89-387294948fb6,NTX6B-BRYC2-K6786-F6MVQ-M7V2X,126,X19-98770,kbXfe0z9Vi1S0yfxMWzI5+UtWsJKzxs7wLGUDLjrckFDn1bDQb4MvvuCK1w+Qrq33lemiGpNDspa+ehXiYEeSPFcCvUBpoMlGBFfzurNCHWiv3o1k3jBoawJr/VoDoVZfxhkps0fVoubf9oy6C6AgrkZ7PjCaS58edMcaUWvYYg,0,Volume:MAK,EnterpriseSN,TH
01eb852c-424d-4060-94b8-c10d799d7364,3XP6D-CRND4-DRYM2-GM84D-4GG8Y,139,X23-37869,PVW0XnRJnsWYjTqxb6StCi2tge/uUwegjdiFaFUiZpwdJ620RK+MIAsSq5S+egXXzIWNntoy2fB6BO8F1wBFmxP/mm/3rn5C33jtF5QrbNqY7X9HMbqSiC7zhs4v4u2Xa4oZQx8JQkwr8Q2c/NgHrOJKKRASsSckhunxZ+WVEuM,1,Retail,ProfessionalCountrySpecific,Zn
eb6d346f-1c60-4643-b960-40ec31596c45,DXG7C-N36C4-C4HTG-X4T3X-2YV77,161,X21-43626,MaVqTkRrGnOqYizl15whCOKWzx01+BZTVAalvEuHXM+WV55jnIfhWmd/u1GqCd5OplqXdU959zmipK2Iwgu2nw/g91nW//sQiN/cUcvg1Lxo6pC3gAo1AjTpHmGIIf9XlZMYlD+Vl6gXsi/Auwh3yrSSFh5s7gOczZoDTqQwHXA,0,Retail,ProfessionalWorkstation
89e87510-ba92-45f6-8329-3afa905e3e83,WYPNQ-8C467-V2W6J-TX4WX-WT2RQ,162,X21-43644,JVGQowLiCcPtGY9ndbBDV+rTu/q5ljmQTwQWZgBIQsrAeQjLD8jLEk/qse7riZ7tMT6PKFVNXeWqF7PhLAmACbE8O3Lvp65XMd/Oml9Daynj5/4n7unsffFHIHH8TGyO5j7xb4dkFNqC5TX3P8/1gQEkTIdZEOTQQXFu0L2SP5c,0,Retail,ProfessionalWorkstationN
62f0c100-9c53-4e02-b886-a3528ddfe7f6,8PTT6-RNW4C-6V7J2-C2D3X-MHBPB,164,X21-04955,CEDgxI8f/fxMBiwmeXw5Of55DG32sbGALzHihXkdbYTDaE3pY37oAA4zwGHALzAFN/t254QImGPYR6hATgl+Cp804f7serJqiLeXY965Zy67I4CKIMBm49lzHLFJeDnVTjDB0wVyN29pvgO3+HLhZ22KYCpkRHFFMy2OKxS68Yc,0,Retail,ProfessionalEducation
13a38698-4a49-4b9e-8e83-98fe51110953,GJTYN-HDMQY-FRR76-HVGC7-QPF8P,165,X21-04956,r35zp9OfxKSBcTxKWon3zFtbOiCufAPo6xRGY5DJqCRFKdB0jgZalNQitvjmaZ/Rlez2vjRJnEart4LrvyW4d9rrukAjR3+c3UkeTKwoD3qBl9AdRJbXCa2BdsoXJs1WVS4w4LuVzpB/SZDuggZt0F2DlMB427F5aflook/n1pY,0,Retail,ProfessionalEducationN
df96023b-dcd9-4be2-afa0-c6c871159ebe,NJCF7-PW8QT-3324D-688JX-2YV66,175,X21-41295,rVpetYUmiRB48YJfCvJHiaZapJ0bO8gQDRoql+rq5IobiSRu//efV1VXqVpBkwILQRKgKIVONSTUF5y2TSxlDLbDSPKp7UHfbz17g6vRKLwOameYEz0ZcK3NTbApN/cMljHvvF/mBag1+sHjWu+eoFzk8H89k9nw8LMeVOPJRDc,0,Retail,ServerRdsh
d4ef7282-3d2c-4cf0-9976-8854e64a8d1e,V3WVW-N2PV2-CGWC3-34QGF-VMJ2C,178,X21-32983,Xzme9hDZR6H0Yx0deURVdE6LiTOkVqWng5W/OTbkxRc0rq+mSYpo/f/yqhtwYlrkBPWx16Yok5Bvcb34vbKHvEAtxfYp4te20uexLzVOtBcoeEozARv4W/6MhYfl+llZtR5efsktj4N4/G4sVbuGvZ9nzNfQO9TwV6NGgGEj2Ec,0,Retail,Cloud
af5c9381-9240-417d-8d35-eb40cd03e484,NH9J3-68WK7-6FB93-4K3DF-DJ4F6,179,X21-32987,QGRDZOU/VZhYLOSdp2xDnFs8HInNZctcQlWCIrORVnxTQr55IJwN4vK3PJHjkfRLQ/bgUrcEIhyFbANqZFUq8yD1YNubb2bjNORgI/m8u85O9V7nDGtxzO/viEBSWyEHnrzLKKWYqkRQKbbSW3ungaZR0Ti5O2mAUI4HzAFej50,0,Retail,CloudN
8ab9bdd1-1f67-4997-82d9-8878520837d9,XQQYW-NFFMW-XJPBH-K8732-CKFFD,188,X21-99378,djy0od0uuKd2rrIl+V1/2+MeRltNgW7FEeTNQsPMkVSL75NBphgoso4uS0JPv2D7Y1iEEvmVq6G842Kyt52QOwXgFWmP/IQ6Sq1dr+fHK/4Et7bEPrrGBEZoCfWqk0kdcZRPBij2KN6qCRWhrk1hX2g+U40smx/EYCLGh9HCi24,0,OEM:DM,IoTEnterprise
ed655016-a9e8-4434-95d9-4345352c2552,QPM6N-7J2WJ-P88HH-P3YRH-YY74H,191,X21-99682,qHs/PzfhYWdtSys2edzcz4h+Qs8aDqb8BIiQ/mJ/+0uyoJh1fitbRCIgiFh2WAGZXjdgB8hZeheNwHibd8ChXaXg4u+0XlOdFlaDTgTXblji8fjETzDBk9aGkeMCvyVXRuUYhTSdp83IqGHz7XuLwN2p/6AUArx9JZCoLGV8j3w,0,OEM:NONSLP,IoTEnterpriseS,VB
6c4de1b8-24bb-4c17-9a77-7b939414c298,CGK42-GYN6Y-VD22B-BX98W-J8JXD,191,X23-12617,J/fpIRynsVQXbp4qZNKp6RvOgZ/P2klILUKQguMlcwrBZybwNkHg/kM5LNOF/aDzEktbPnLnX40GEvKkYT6/qP4cMhn/SOY0/hYOkIdR34ilzNlVNq5xP7CMjCjaUYJe+6ydHPK6FpOuEoWOYYP5BZENKNGyBy4w4shkMAw19mA,0,OEM:NONSLP,IoTEnterpriseS,Ge
d4bdc678-0a4b-4a32-a5b3-aaa24c3b0f24,K9VKN-3BGWV-Y624W-MCRMQ-BHDCD,202,X22-53884,kyoNx2s93U6OUSklB1xn+GXcwCJO1QTEtACYnChi8aXSoxGQ6H2xHfUdHVCwUA1OR0UeNcRrMmOzZBOEUBtdoGWSYPg9AMjvxlxq9JOzYAH+G6lT0UbCWgMSGGrqdcIfmshyEak3aUmsZK6l+uIAFCCZZ/HbbCRkkHC5rWKstMI,0,Retail,CloudEditionN
92fb8726-92a8-4ffc-94ce-f82e07444653,KY7PN-VR6RX-83W6Y-6DDYQ-T6R4W,203,X22-53847,gD6HnT4jP4rcNu9u83gvDiQq1xs7QSujcDbo60Di5iSVa9/ihZ7nlhnA0eDEZfnoDXriRiPPqc09T6AhSnFxLYitAkOuPJqL5UMobIrab9dwTKlowqFolxoHhLOO4V92Hsvn/9JLy7rEzoiAWHhX/0cpMr3FCzVYPeUW1OyLT1A,0,Retail,CloudEdition
5a85300a-bfce-474f-ac07-a30983e3fb90,N979K-XWD77-YW3GB-HBGH6-D32MH,205,X23-15042,blZopkUuayCTgZKH4bOFiisH9GTAHG5/js6UX/qcMWWc3sWNxKSX1OLp1k3h8Xx1cFuvfG/fNAw/I83ssEtPY+A0Gx1JF4QpRqsGOqJ5ruQ2tGW56CJcCVHkB+i46nJAD759gYmy3pEYMQbmpWbhLx3MJ6kvwxKfU+0VCio8k50,0,OEM:DM,IoTEnterpriseSK
80083eae-7031-4394-9e88-4901973d56fe,P8Q7T-WNK7X-PMFXY-VXHBG-RRK69,206,X23-62084,habUJ0hhAG0P8iIKaRQ74/wZQHyAdFlwHmrejNjOSRG08JeqilJlTM6V8G9UERLJ92/uMDVHIVOPXfN8Zdh8JuYO8oflPnqymIRmff/pU+Gpb871jV2JDA4Cft5gmn+ictKoN4VoSfEZRR+R5hzF2FsoCExDNNw6gLdjtiX94uA,0,OEM:DM,IoTEnterpriseK
1bc2140b-285b-4351-b99c-26a126104b29,TMP2N-KGFHJ-PWM6F-68KCQ-3PJBP,210,X23-60513,AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA,0,Retail,WNC
'@
$customObjectArray = $hashTable | ConvertFrom-Csv

Manage-SLHandle -Release | Out-null
$LicensingProducts = Get-SLIDList -eQueryIdType SL_ID_PRODUCT_SKU -eReturnIdType SL_ID_PRODUCT_SKU | % {
    try {
        $Branding = $null
        [XML]$licenseData = Get-ProductSkuInformation $_ -ReturnRawData $true
        $Branding = ($licenseData.licenseGroup.license[1].otherInfo.infoTables.infoList.infoStr | ? Name -EQ win:branding).'#text'
    }
    catch {
        $Branding = $null
    }
    [PSCustomObject]@{
        ID            = $_
        Description   = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Description'
        Name          = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'productName'
        LicenseFamily = Get-ProductSkuInformation -ActConfigId $_ -pwszValueName 'Family'
        Branding      = $Branding
    }
}
$SupportedProducts = $LicensingProducts | 
    ? { $customObjectArray.ID -contains $_.ID } | ? {
        ($customObjectArray | ? ID -EQ $_.ID | select -ExpandProperty SKU_ID ) -match $_.Branding }

if ($ForceVolume -eq $true) {
   $SupportedProducts = $null
}

if ($server -or !$SupportedProducts) {

  Write-Host
  Write-Host "ERROR: No matching product found" -ForegroundColor Red
  Write-Host "Trying to use KMS38 instead." -ForegroundColor Red

  try {
    $product = $LicensingProducts | ? Description -Match 'VOLUME_KMSCLIENT' | ? LicenseFamily -EQ $EditionID
    if (-not $product) {
      $product = $LicensingProducts | ? Description -Match 'VOLUME_KMSCLIENT' | ? { $_.LicenseFamily } | Out-GridView -Title "Select prefered product's" -OutputMode Single
    }
    if ($product){
        $Vol_Key = GetRandomKey -ProductID $product.ID
        if (-not $Vol_Key) {
            $refSku = Retrieve-ProductKeyInfo -SkuId $product.ID
            $Vol_Key = Encode-Key $refSku 0 0
            Write-Warning "Encode-Key, $Vol_Key"
        }
    }
    else {
      Write-Host
      Write-Host "ERROR: No matching product found" -ForegroundColor Red
    }
  } catch {
    Write-Host "ERROR: fetch product - Key for VOLUME_KMSCLIENT version" -ForegroundColor Red
    return
  }
  if ([STRING]::IsNullOrWhiteSpace($Vol_Key) -or [STRING]::IsNullOrEmpty(($Vol_Key))) {
    return
  }
}
else {
  $filter = ($customObjectArray | ? Status -EQ 0 | select ID).ID
  $products =  $SupportedProducts | ? {$filter -contains $_.ID}

  $product = $null
  $product = $products | ? {$_.LicenseFamily -match $EditionID} | select -First 1
  if (-not $product) {
    $product = $products | Out-GridView -Title "Select prefered product's" -OutputMode Single
  }

  if (-not $product) {
    return  }
}

Function Encode-Blob {
    param (
        $SessionIdStr
    )
    function Sign {
        param (
            $Properties,
            $rsa
        )

        $sha256 = [Security.Cryptography.SHA256]::Create()
        $bytes = [Text.Encoding]::UTF8.GetBytes($Properties)
        $hash = $sha256.ComputeHash($bytes)

        $signature = $rsa.SignHash($hash, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
        return [Convert]::ToBase64String($signature)
    }
    [byte[]] $key = 0x07,0x02,0x00,0x00,0x00,0xA4,0x00,0x00,0x52,0x53,0x41,0x32,0x00,0x04,0x00,0x00,
                    0x01,0x00,0x01,0x00,0x29,0x87,0xBA,0x3F,0x52,0x90,0x57,0xD8,0x12,0x26,0x6B,0x38,
                    0xB2,0x3B,0xF9,0x67,0x08,0x4F,0xDD,0x8B,0xF5,0xE3,0x11,0xB8,0x61,0x3A,0x33,0x42,
                    0x51,0x65,0x05,0x86,0x1E,0x00,0x41,0xDE,0xC5,0xDD,0x44,0x60,0x56,0x3D,0x14,0x39,
                    0xB7,0x43,0x65,0xE9,0xF7,0x2B,0xA5,0xF0,0xA3,0x65,0x68,0xE9,0xE4,0x8B,0x5C,0x03,
                    0x2D,0x36,0xFE,0x28,0x4C,0xD1,0x3C,0x3D,0xC1,0x90,0x75,0xF9,0x6E,0x02,0xE0,0x58,
                    0x97,0x6A,0xCA,0x80,0x02,0x42,0x3F,0x6C,0x15,0x85,0x4D,0x83,0x23,0x6A,0x95,0x9E,
                    0x38,0x52,0x59,0x38,0x6A,0x99,0xF0,0xB5,0xCD,0x53,0x7E,0x08,0x7C,0xB5,0x51,0xD3,
                    0x8F,0xA3,0x0D,0xA0,0xFA,0x8D,0x87,0x3C,0xFC,0x59,0x21,0xD8,0x2E,0xD9,0x97,0x8B,
                    0x40,0x60,0xB1,0xD7,0x2B,0x0A,0x6E,0x60,0xB5,0x50,0xCC,0x3C,0xB1,0x57,0xE4,0xB7,
                    0xDC,0x5A,0x4D,0xE1,0x5C,0xE0,0x94,0x4C,0x5E,0x28,0xFF,0xFA,0x80,0x6A,0x13,0x53,
                    0x52,0xDB,0xF3,0x04,0x92,0x43,0x38,0xB9,0x1B,0xD9,0x85,0x54,0x7B,0x14,0xC7,0x89,
                    0x16,0x8A,0x4B,0x82,0xA1,0x08,0x02,0x99,0x23,0x48,0xDD,0x75,0x9C,0xC8,0xC1,0xCE,
                    0xB0,0xD7,0x1B,0xD8,0xFB,0x2D,0xA7,0x2E,0x47,0xA7,0x18,0x4B,0xF6,0x29,0x69,0x44,
                    0x30,0x33,0xBA,0xA7,0x1F,0xCE,0x96,0x9E,0x40,0xE1,0x43,0xF0,0xE0,0x0D,0x0A,0x32,
                    0xB4,0xEE,0xA1,0xC3,0x5E,0x9B,0xC7,0x7F,0xF5,0x9D,0xD8,0xF2,0x0F,0xD9,0x8F,0xAD,
                    0x75,0x0A,0x00,0xD5,0x25,0x43,0xF7,0xAE,0x51,0x7F,0xB7,0xDE,0xB7,0xAD,0xFB,0xCE,
                    0x83,0xE1,0x81,0xFF,0xDD,0xA2,0x77,0xFE,0xEB,0x27,0x1F,0x10,0xFA,0x82,0x37,0xF4,
                    0x7E,0xCC,0xE2,0xA1,0x58,0xC8,0xAF,0x1D,0x1A,0x81,0x31,0x6E,0xF4,0x8B,0x63,0x34,
                    0xF3,0x05,0x0F,0xE1,0xCC,0x15,0xDC,0xA4,0x28,0x7A,0x9E,0xEB,0x62,0xD8,0xD8,0x8C,
                    0x85,0xD7,0x07,0x87,0x90,0x2F,0xF7,0x1C,0x56,0x85,0x2F,0xEF,0x32,0x37,0x07,0xAB,
                    0xB0,0xE6,0xB5,0x02,0x19,0x35,0xAF,0xDB,0xD4,0xA2,0x9C,0x36,0x80,0xC6,0xDC,0x82,
                    0x08,0xE0,0xC0,0x5F,0x3C,0x59,0xAA,0x4E,0x26,0x03,0x29,0xB3,0x62,0x58,0x41,0x59,
                    0x3A,0x37,0x43,0x35,0xE3,0x9F,0x34,0xE2,0xA1,0x04,0x97,0x12,0x9D,0x8C,0xAD,0xF7,
                    0xFB,0x8C,0xA1,0xA2,0xE9,0xE4,0xEF,0xD9,0xC5,0xE5,0xDF,0x0E,0xBF,0x4A,0xE0,0x7A,
                    0x1E,0x10,0x50,0x58,0x63,0x51,0xE1,0xD4,0xFE,0x57,0xB0,0x9E,0xD7,0xDA,0x8C,0xED,
                    0x7D,0x82,0xAC,0x2F,0x25,0x58,0x0A,0x58,0xE6,0xA4,0xF4,0x57,0x4B,0xA4,0x1B,0x65,
                    0xB9,0x4A,0x87,0x46,0xEB,0x8C,0x0F,0x9A,0x48,0x90,0xF9,0x9F,0x76,0x69,0x03,0x72,
                    0x77,0xEC,0xC1,0x42,0x4C,0x87,0xDB,0x0B,0x3C,0xD4,0x74,0xEF,0xE5,0x34,0xE0,0x32,
                    0x45,0xB0,0xF8,0xAB,0xD5,0x26,0x21,0xD7,0xD2,0x98,0x54,0x8F,0x64,0x88,0x20,0x2B,
                    0x14,0xE3,0x82,0xD5,0x2A,0x4B,0x8F,0x4E,0x35,0x20,0x82,0x7E,0x1B,0xFE,0xFA,0x2C,
                    0x79,0x6C,0x6E,0x66,0x94,0xBB,0x0A,0xEB,0xBA,0xD9,0x70,0x61,0xE9,0x47,0xB5,0x82,
                    0xFC,0x18,0x3C,0x66,0x3A,0x09,0x2E,0x1F,0x61,0x74,0xCA,0xCB,0xF6,0x7A,0x52,0x37,
                    0x1D,0xAC,0x8D,0x63,0x69,0x84,0x8E,0xC7,0x70,0x59,0xDD,0x2D,0x91,0x1E,0xF7,0xB1,
                    0x56,0xED,0x7A,0x06,0x9D,0x5B,0x33,0x15,0xDD,0x31,0xD0,0xE6,0x16,0x07,0x9B,0xA5,
                    0x94,0x06,0x7D,0xC1,0xE9,0xD6,0xC8,0xAF,0xB4,0x1E,0x2D,0x88,0x06,0xA7,0x63,0xB8,
                    0xCF,0xC8,0xA2,0x6E,0x84,0xB3,0x8D,0xE5,0x47,0xE6,0x13,0x63,0x8E,0xD1,0x7F,0xD4,
                    0x81,0x44,0x38,0xBF

    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
    $rsa.ImportCspBlob($key)
    $SessionId = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($SessionIdStr + [char]0))
    $PropertiesStr = "OA3xOriginalProductId=;OA3xOriginalProductKey=;SessionId=$SessionId;TimeStampClient=2022-10-11T12:00:00Z"
    $SignatureStr = Sign $PropertiesStr $rsa
    return @"
<?xml version="1.0" encoding="utf-8"?><genuineAuthorization xmlns="http://www.microsoft.com/DRM/SL/GenuineAuthorization/1.0"><version>1.0</version><genuineProperties origin="sppclient"><properties>$PropertiesStr</properties><signatures><signature name="clientLockboxKey" method="rsa-sha256">$SignatureStr</signature></signatures></genuineProperties></genuineAuthorization>
"@
}

$outputPath = Join-Path "C:\ProgramData\Microsoft\Windows\ClipSVC\GenuineTicket" "GenuineTicket.xml"
if ($Vol_Key) {
    $SessionID = 'OSMajorVersion=5;OSMinorVersion=1;OSPlatformId=2;PP=0;GVLKExp=2038-01-19T03:14:07Z;DownlevelGenuineState=1;'
    $signature = Encode-Blob -SessionIdStr $SessionID
    #$signature = '<?xml version="1.0" encoding="utf-8"?><genuineAuthorization xmlns="http://www.microsoft.com/DRM/SL/GenuineAuthorization/1.0"><version>1.0</version><genuineProperties origin="sppclient"><properties>OA3xOriginalProductId=;OA3xOriginalProductKey=;SessionId=TwBTAE0AYQBqAG8AcgBWAGUAcgBzAGkAbwBuAD0ANQA7AE8AUwBNAGkAbgBvAHIAVgBlAHIAcwBpAG8AbgA9ADEAOwBPAFMAUABsAGEAdABmAG8AcgBtAEkAZAA9ADIAOwBQAFAAPQAwADsARwBWAEwASwBFAHgAcAA9ADIAMAAzADgALQAwADEALQAxADkAVAAwADMAOgAxADQAOgAwADcAWgA7AEQAbwB3AG4AbABlAHYAZQBsAEcAZQBuAHUAaQBuAGUAUwB0AGEAdABlAD0AMQA7AAAA;TimeStampClient=2022-10-11T12:00:00Z</properties><signatures><signature name="clientLockboxKey" method="rsa-sha256">C52iGEoH+1VqzI6kEAqOhUyrWuEObnivzaVjyef8WqItVYd/xGDTZZ3bkxAI9hTpobPFNJyJx6a3uriXq3HVd7mlXfSUK9ydeoUdG4eqMeLwkxeb6jQWJzLOz41rFVSMtBL0e+ycCATebTaXS4uvFYaDHDdPw2lKY8ADj3MLgsA=</signature></signatures></genuineProperties></genuineAuthorization>'
}

$cProduct = $customObjectArray | ? ID -EQ $product.ID
if (-not $Vol_Key) {
    $SessionID = 'OSMajorVersion=5;OSMinorVersion=1;OSPlatformId=2;PP=0;Pfn=Microsoft.Windows.'+$($cProduct.SKU_ID)+'.'+$($cProduct.Key_part)+
        '_8wekyb3d8bbwe;PKeyIID=465145217131314304264339481117862266242033457260311819664735280;'
    $signature = Encode-Blob -SessionIdStr $SessionID

    <#
    $SessionID += [char]0
    $encoded = [convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($SessionID))

    if ($encoded -notmatch 'AAAA$') {
       Write-Warning "Base64 string doesn't contain 'AAAA'"
    }

    $signature = '<?xml version="1.0" encoding="utf-8"?><genuineAuthorization xmlns="http://www.microsoft.com/DRM/SL/GenuineAuthorization/1.0">'+
      '<version>1.0</version><genuineProperties origin="sppclient"><properties>OA3xOriginalProductId=;OA3xOriginalProductKey=;SessionId=' +
      $encoded + ';TimeStampClient=2022-10-11T12:00:00Z</properties><signatures><signature name="clientLockboxKey" method="rsa-sha256">' +
      $cProduct.value + '=</signature></signatures></genuineProperties></genuineAuthorization>'
    #>

    $geoName = (Get-ItemProperty -Path "HKCU:\Control Panel\International\Geo").Name
    $geoNation = (Get-ItemProperty -Path "HKCU:\Control Panel\International\Geo").Nation
}

$tdir = "$env:ProgramData\Microsoft\Windows\ClipSVC\GenuineTicket"

# Create directory if it doesn't exist
if (-not (Test-Path -Path $tdir)) {
    New-Item -ItemType Directory -Path $tdir | Out-Null
}

# Delete files starting with "Genuine" in $tdir
Get-ChildItem -Path $tdir -Filter "Genuine*" -File -ea 0 | Remove-Item -Force -ea 0

# Delete .xml files in $tdir
Get-ChildItem -Path $tdir -Filter "*.xml" -File -ea 0 | Remove-Item -Force -ea 0

# Delete all files in the Migration folder
$migrationPath = "$env:ProgramData\Microsoft\Windows\ClipSVC\Install\Migration"
if (Test-Path -Path $migrationPath) {
    Get-ChildItem -Path $migrationPath -File -ea 0 | Remove-Item -Force -ea 0
}

if ($Vol_Key) {
    # Remove registry keys
    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform\55c92734-d682-4d71-983e-d6ec3f16059f" -Force -Recurse -ea 0
    Remove-Item -Path "HKU:\S-1-5-20\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform\55c92734-d682-4d71-983e-d6ec3f16059f" -Force -Recurse -ea 0

    # Registry path for new entries
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform\55c92734-d682-4d71-983e-d6ec3f16059f\$($product.ID)"

    # Create new registry values
    New-Item -Path $regPath -Force -ea 0 | Out-Null
    New-ItemProperty -Path $regPath -Name "KeyManagementServiceName" -PropertyType String -Value "127.0.0.2" -Force -ea 0
    New-ItemProperty -Path $regPath -Name "KeyManagementServicePort" -PropertyType String -Value "1688" -Force -ea 0
}

try {
    if ($geoName -and $geoNation -and ($geoName -ne 'US')){
      Set-WinHomeLocation -GeoId 244 -ea 0 }
    if ($Vol_Key) {
        $tsactid = $product.ID
        Manage-SLHandle -Release | Out-null
        Write-Warning "SL-InstallProductKey -Keys $Vol_Key"
        SL-InstallProductKey -Keys @($Vol_Key)
    }
    else {
        $tsactid = $cProduct.ID

        Manage-SLHandle -Release | Out-null
        $HWID_KEY = $cProduct.Key
        Write-Warning "SL-InstallProductKey -Keys $HWID_KEY"
        SL-InstallProductKey -Keys @($HWID_KEY)
    }
    
    $ID_PKEY = Retrieve-SKUInfo -SkuId $tsactid -eReturnIdType SL_ID_PKEY
    if ($ID_PKEY -eq $null) {
        $RefGroupId = $Global:PKeyDatabase | ? ActConfigId -Match "{$tsactid}" | select -ExpandProperty RefGroupId
        if (-not $RefGroupId) {
           Write-Warning "Fail to receive RefGroupId for $tsactid"
		   if ($HWID_KEY) {
			   Clear-host
			   Write-host
			   Run-HWID -ForceVolume $true
			   return
		   }
        }
        if ($RefGroupId) {
            $key = Encode-Key $RefGroupId
            if ($key) {
                $null = SL-InstallProductKey -Keys $key
                $ID_PKEY = Retrieve-SKUInfo -SkuId $tsactid -eReturnIdType SL_ID_PKEY
                if ($ID_PKEY -eq $null) {
                    Write-Warning "Fail to install key for $tsactid"
                    return
                }}}}

    [System.IO.File]::WriteAllText($outputPath, $signature, [Encoding]::UTF8)
    Write-Host
    clipup -v -o
    [System.IO.File]::WriteAllText($outputPath, $signature, [Encoding]::UTF8)
    Write-Host
    if ($Vol_Key) {
      Stop-Service sppsvc -force -ea 0
    }
    Restart-Service ClipSVC
    Write-Host

    if ($Vol_Key) {
        Manage-SLHandle -Release | Out-null
        $null = SL-ReArm -AppID 55c92734-d682-4d71-983e-d6ec3f16059f -skuID $product.ID
    }
    else {
        Manage-SLHandle -Release | Out-null
        $null = SL-Activate -skuID $product.ID
    }
   
    Manage-SLHandle -Release | Out-null
    $null = SL-RefreshLicenseStatus -AppID 55c92734-d682-4d71-983e-d6ec3f16059f -skuID $product.ID
}
catch {
    Write-Host "ERROR: Failed to activate. Operation aborted." -ForegroundColor Red
    Write-Host
    Write-Host $_.Exception.Message
    Write-Host
    return
}
Finally {
  if ($geoNation) {
    Set-WinHomeLocation -GeoId $geoNation -ea 0 }
}

Manage-SLHandle -Release | Out-null
$StatusInfo = Get-SLLicensingStatus -ApplicationID 55c92734-d682-4d71-983e-d6ec3f16059f -SkuID $product.ID

if (-not $StatusInfo) {
    Write-Warning "Fail to fetch status data"
    return
}
if ($Vol_Key -and (
    $StatusInfo.LicenseTier -ne [LicenseCategory]::KMS38)) {
        Write-Host
        Write-Host "KMS38 Activation Failed." -ForegroundColor Red
        Write-Host "Try re-apply Activation again later" -ForegroundColor Red
        Write-Host
        Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform\55c92734-d682-4d71-983e-d6ec3f16059f" -Force -Recurse -ea 0
        Remove-Item -Path "HKU:\S-1-5-20\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform\55c92734-d682-4d71-983e-d6ec3f16059f" -Force -Recurse -ea 0
}
elseif (-not $Vol_Key -and (
    $StatusInfo.LicenseStatus -ne [LicenseStatusEnum]::Licensed)) {
    Write-Host
    Write-Host "HWID Activation Failed." -ForegroundColor Red
    Write-Host "Try re-apply Activation again later" -ForegroundColor Red
    Write-Host
}
else {
    Write-Host
    Write-Host "everything is Well Done" -ForegroundColor Yellow
    Write-Host "Go Home & Rest. !" -ForegroundColor Yellow
    Write-Host

    if ($Vol_Key) {

        # enable KMS38 lock --> From MAS PROJECT, KMS38_Activation.cmd
        $SID = New-Object SecurityIdentifier('S-1-5-32-544')
        $Admin = ($SID.Translate([NTAccount])).Value
        $ruleArgs = @("$Admin", "Delete, SetValue", "ContainerInherit", "None", "Deny")
        $path = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform\55c92734-d682-4d71-983e-d6ec3f16059f'
        $key = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64').OpenSubKey($path, 'ReadWriteSubTree', 'ChangePermissions')
        if ($key) {
            $acl = $key.GetAccessControl()
            $rule = [RegistryAccessRule]::new.Invoke($ruleArgs)
            $acl.ResetAccessRule($rule)
            $key.SetAccessControl($acl)
        }
    }
}

}
function Run-KMS {
    Set-DefinedEntities
    Clean-RegistryKeys
    Service-Check

    # Windows_Addict Not genuine fix
    $regPaths = @($Global:XSPP_USER, $Global:XSPP_HKLM_X32, $Global:XSPP_HKLM_X64)
    foreach ($path in $regPaths) {
        try {
            New-Item -Path $path -Force -ea 0 | Out-Null
            if (Test-Path $path) {
                Set-ItemProperty -Path $path -Name 'KeyManagementServiceName' -Value $Global:IP_ADDRESS -Type String -Force -ea 0
            }
        } catch {
            #Write-Host "Failed to write to $path" -ForegroundColor Red
        }
    }

    write-host
    write-host "Convert & Activate Smart Solution For Office / Windows Products"
    write-host "Support Activation for 			 :: Office 2010 --> late Office 2021"
    write-host "Support Convert    For 			 :: Office 2016 [MSI], 2016 --> 2021 [C2R]"
    write-host "Support Convert / Activation for :: Windows Vista --> Late Windows 11"
    write-host
    write-host "** Keep Origional Activated OEM / Retail / Mak Licences"
    write-host "** Clean Duplicated Licences Of same Products, different year"
    write-host "** Clean Unused Product Licences like :: 365, Home, Professional, Private"
    write-host
    LetsActivate
    Clean-RegistryKeys

    # Windows_Addict Not genuine fix
    $regPaths = @($Global:XSPP_USER, $Global:XSPP_HKLM_X32, $Global:XSPP_HKLM_X64)
    foreach ($path in $regPaths) {
        try {
            New-Item -Path $path -Force -ea 0 | Out-Null
            if (Test-Path $path) {
                Set-ItemProperty -Path $path -Name 'KeyManagementServiceName' -Value $Global:IP_ADDRESS -Type String -Force -ea 0
            }
        } catch {
            #Write-Host "Failed to write to $path" -ForegroundColor Red
        }
    }
}
function Run-Troubleshoot {
param (
    [bool]$AutoMode = $false,
    [bool]$RunUpgrade = $false,
    [bool]$RunWmiRepair = $false,
    [bool]$RecoverKeys  = $false,
    [bool]$RunTokenStoreReset = $false,
    [bool]$RunUninstallLicenses = $false,
    [bool]$RunScrubOfficeC2R = $false,
    [bool]$RunOfficeLicenseInstaller = $false,
    [bool]$RunOfficeOnlineInstallation = $false
)
# --> Start
$dicKeepSku = @{}
$Start_Time = $(Get-Date -Format hh:mm:ss)
$IgnoreCase = [Text.RegularExpressions.RegexOptions]::IgnoreCase

Set-Location "HKLM:\"
$sPackageGuid = $null

@("SOFTWARE\Microsoft\Office\15.0\ClickToRun",
  "SOFTWARE\Microsoft\Office\16.0\ClickToRun",
  "SOFTWARE\Microsoft\Office\ClickToRun" ) | % {
    try {
      $sPackageGuid = gpv $_ PackageGUID -ea 0
    } catch{}}
Function Convert-To-System {
   param (
     [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Mandatory)]
     [string] $NAME
   )
  
  switch ($NAME){
   "ARM"      {return "ARM"}
   "CHPE"     {return "CHPE"}
   "Win7"     {return "7.0"}
   "Win8"     {return "8.0"}
   "Win8.0"   {return "8.0"}
   "Win8.1"   {return "8.1"}
   "Default"  {return "10.0"}
   "RDX Test" {return "RDX"}
  }
  return "Null"
}
Function Convert-To-Channel {
   param (
     [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Mandatory)]
     [string] $FFN
   )
  
  switch ($FFN){
   "492350f6-3a01-4f97-b9c0-c7c6ddf67d60" {return "Current"}
   "64256afe-f5d9-4f86-8936-8840a6a4f5be" {return "CurrentPreview"}
   "5440fd1f-7ecb-4221-8110-145efaa6372f" {return "BetaChannel"}
   "55336b82-a18d-4dd6-b5f6-9e5095c314a6" {return "MonthlyEnterprise"}
   "7ffbc6bf-bc32-4f92-8982-f9dd17fd3114" {return "SemiAnnual"}
   "b8f9b850-328d-4355-9145-c59439a0c4cf" {return "SemiAnnualPreview"}
   "f2e724c1-748f-4b47-8fb8-8e0d210e9208" {return "PerpetualVL2019"}
   "5030841d-c919-4594-8d2d-84ae4f96e58e" {return "PerpetualVL2021"}
   "7983BAC0-E531-40CF-BE00-FD24FE66619C" {return "PerpetualVL2024"}
   "ea4a4090-de26-49d7-93c1-91bff9e53fc3" {return "DogfoodDevMain"}
   "f3260cf1-a92c-4c75-b02e-d64c0a86a968" {return "DogfoodCC"}
   "c4a7726f-06ea-48e2-a13a-9d78849eb706" {return "DogfoodDCEXT"}
   "834504cc-dc55-4c6d-9e71-e024d0253f6d" {return "DogfoodFRDC"}
   "5462eee5-1e97-495b-9370-853cd873bb07" {return "MicrosoftCC"}
   "f4f024c8-d611-4748-a7e0-02b6e754c0fe" {return "MicrosoftDC"}
   "b61285dd-d9f7-41f2-9757-8f61cba4e9c8" {return "MicrosoftDevMain"}
   "9a3b7ff2-58ed-40fd-add5-1e5158059d1c" {return "MicrosoftFRDC"}
   "1d2d2ea6-1680-4c56-ac58-a441c8c24ff9" {return "MicrosoftLTSC"}
   "86752282-5841-4120-ac80-db03ae6b5fdb" {return "MicrosoftLTSC2021"}
   "C02D8FE6-5242-4DA8-972F-82EE55E00671" {return "MicrosoftLTSC2024"}
   "2e148de9-61c8-4051-b103-4af54baffbb4" {return "InsidersLTSC"}
   "12f4f6ad-fdea-4d2a-a90f-17496cc19a48" {return "InsidersLTSC2021"}
   "20481F5C-C268-4624-936C-52EB39DDBD97" {return "InsidersLTSC2024"}
   "0002c1ba-b76b-4af9-b1ee-ae2ad587371f" {return "InsidersMEC"}
  }
  return "Null"
}
Function Get-Office-Apps {
   param (
     [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
     [string] $FFN
   )
  
  $ProgressPreference = 'SilentlyContinue'    # Subsequent calls do not display UI.
  $URI = 'https://clients.config.office.net/releases/v1.0/OfficeReleases'
  $URI = 'https://mrodevicemgr.officeapps.live.com/mrodevicemgrsvc/api/v2/C2RReleaseData'
  $REQ = IWR $URI -ea 0

  if (-not $REQ) {
    return $null
  }

  $Json = $REQ.Content | ConvertFrom-Json
  $Json|Sort-Object FFN|select @{Name='Channel'; Expr={$_.FFN|Convert-To-Channel}},FFN,@{Name='Build'; Expr={$_.AvailableBuild}},@{Name='System'; Expr={$_.Name|Convert-To-System}}
}
Function IsC2R {
   param (
     [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Mandatory)]
     [string] $Value,
	 
	 [parameter(Mandatory=$false)]
     [bool] $FastSearch
   )

  $OREF          = "^(.*)(\\ROOT\\OFFICE1)(.*)$"
  $MSOFFICE      = "^(.*)(\\Microsoft Office)(.*)$"
  $OREFROOT      = "^(.*)(Microsoft Office\\root\\)(.*)$"
  $OCOMMON	     = "^(.*)(\\microsoft shared\\ClickToRun)(.*)$"

  
  if (($FastSearch -ne $null) -and ($FastSearch -eq $true)) {
	if ([REGEX]::IsMatch(
      $Value,$MSOFFICE,$IgnoreCase)) {
        return $true }
	return $false
  }
  
  if ([REGEX]::IsMatch(
    $Value,$OREF,$IgnoreCase)) {
      return $true }
  if ([REGEX]::IsMatch(
    $Value,$MSOFFICE,$IgnoreCase)) {
      return $true }
  if ([REGEX]::IsMatch(
    $Value,$OREFROOT,$IgnoreCase)) {
      return $true }
  if ([REGEX]::IsMatch(
    $Value,$OCOMMON,$IgnoreCase)) {
      return $true }
             
  return $false
}
Function GetExpandedGuid {
   param (
     [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Mandatory)]
     [ValidatePattern('^[0-9a-fA-F]{32}$')]
     [ValidateScript( { [Guid]::Parse($_) -is [Guid] })]
     [string] $sGuid
   )

if (($sGuid.Length -ne 32) -or (
  $sGuid -notmatch '00F01FEC')) {
    return $null }

$output = ""
([ordered]@{
1=$sGuid.ToCharArray(0,8)
2=$sGuid.ToCharArray(8,4)
3=$sGuid.ToCharArray(12,4)}).GetEnumerator() | % {
  [ARRAY]::Reverse($_.Value)
  $output += (-join $_.Value) }
$sArr = $sGuid.ToCharArray()
([ordered]@{
17=20
21=32 }).GetEnumerator() | % {
$_.Key..$_.Value | % {
  if ($_ % 2) {
    $output += $sArr[$_]
} else {
    $output += $sArr[$_-2] }} }
return [Guid]::Parse(
  -join $output).ToString().ToUpper()
}
Function CheckDelete {
   param (
     [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Mandatory)]
     [string] $sProductCode
   )

   # FOR GUID FORMAT
   # {90160000-008C-0000-1000-0000000FF1CE}

   # ensure valid GUID length
   if ($sProductCode.Length -ne 38) {
     return $false }	

    # only care if it's in the expected ProductCode pattern
	if (-not(
	  InScope $sProductCode)) {
        return $false }
	
    # check if it's a known product that should be kept
    if ($dicKeepSku.ContainsKey($sProductCode)) {
      return $false }
	
  return $True
}
Function InScope {
   param (
     [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Mandatory)]
     [string] $sProductCode
   )
   
   $PRODLEN = 13
   $OFFICEID = "0000000FF1CE}"
   if ($sProductCode.Length -ne 38) {
     return $false }

   $sProd = $sProductCode.ToUpper()
   if ($sProd.Substring($sProd.Length-13,$PRODLEN) -ne $OFFICEID ) {
     if ($sPackageGuid -and ($sProd -eq $sPackageGuid.ToUpper())) {
       return $True }
     switch ($sProductCode)
     {
       "{6C1ADE97-24E1-4AE4-AEDD-86D3A209CE60}" {return $True}
       "{9520DDEB-237A-41DB-AA20-F2EF2360DCEB}" {return $True}
       "{9AC08E99-230B-47e8-9721-4577B7F124EA}" {return $True}
     }
     return $false }
   
   if ([INT]$sProd.Substring(3,2) -gt 14) {
     switch ($sProd.Substring(10,4))
     {
       "007E" {return $True}
       "008F" {return $True}
       "008C" {return $True}
       "24E1" {return $True}
       "237A" {return $True}
       "00DD" {return $True}
       Default {return $false}
     }
   }

    return $false
}
function Get-Shortcut {
<#
.SYNOPSIS
    Get information about a Shortcut (.lnk file)
.DESCRIPTION
    Get information about a Shortcut (.lnk file)
.PARAMETER Path
    File
.EXAMPLE
    Get-Shortcut -Path 'C:\Portable\Test.lnk'
 
    Link : Test.lnk
    TargetPath : C:\Portable\PortableApps\Notepad++Portable\Notepad++Portable.exe
    WindowStyle : 1
    IconLocation : ,0
    Hotkey :
    Target : Notepad++Portable.exe
    Arguments :
    LinkPath : C:\Portable\Test.lnk
#>

    [CmdletBinding(ConfirmImpact='None')]
    param(
        [string] $path
    )

    begin {
        Write-Verbose -Message "Starting [$($MyInvocation.Mycommand)]"
        $obj = New-Object -ComObject WScript.Shell
    }

    process {
        if (Test-Path -Path $Path) {
            $ResolveFile = Resolve-Path -Path $Path
            if ($ResolveFile.count -gt 1) {
                Write-Warning -Message "ERROR: File specification [$File] resolves to more than 1 file."
            } else {
                Write-Verbose -Message "Using file [$ResolveFile] in section [$Section], getting comments"
                $ResolveFile = Get-Item -Path $ResolveFile
                if ($ResolveFile.Extension -eq '.lnk') {
                    $link = $obj.CreateShortcut($ResolveFile.FullName)

                    $info = @{}
                    $info.Hotkey = $link.Hotkey
                    $info.TargetPath = $link.TargetPath
                    $info.LinkPath = $link.FullName
                    $info.Arguments = $link.Arguments
                    $info.Target = try {Split-Path -Path $info.TargetPath -Leaf } catch { 'n/a'}
                    $info.Link = try { Split-Path -Path $info.LinkPath -Leaf } catch { 'n/a'}
                    $info.WindowStyle = $link.WindowStyle
                    $info.IconLocation = $link.IconLocation

                    New-Object -TypeName PSObject -Property $info
                } else {
                    Write-Warning -Message 'Extension is not .lnk'
                }
            }
        } else {
            Write-Warning -Message "ERROR: File [$Path] does not exist"
        }
    }

    end {
        Write-Verbose -Message "Ending [$($MyInvocation.Mycommand)]"
    }
}
Function CleanShortcuts {
   param (
     [parameter(Mandatory=$True)]
     [string] $sFolder
   )

 Set-Location "c:\"

 if (-not (
   Test-Path $sFolder )) {
     return; }

 dir $sFolder -Filter *.lnk -Recurse -ea 0 | % {
    $Shortcut = Get-Shortcut(
      $_.FullName) -ea 0
    if ($Shortcut -and $Shortcut.TargetPath -and (
      $Shortcut.TargetPath|IsC2R)) {
          RI $_.FullName -Force -ea 0  }}
}
function UninstallOfficeC2R {
$URL = 
  "http://officecdn.microsoft.com/pr/wsus/setup.exe"

$Path = 
  "$env:WINDIR\temp\setup.exe"

$XML = 
  "$env:WINDIR\temp\RemoveAll.xml"


$CODE = @"
<Configuration> 
  <Remove All="TRUE"> 
</Remove> 
  <Display Level="None" AcceptEULA="TRUE" />   
</Configuration>
"@

try {
  "*** -- build the remove.xml"
  $CODE | Out-File $XML
  "*** -- ODT not available. Try to download"
  (New-Object WebClient).DownloadFile($URL, $Path)
}
catch { }

Set-Location "$env:SystemDrive\"
Push-Location "$env:WINDIR\temp\"
if ([IO.FILE]::Exists(
  $Path)) {
    $Proc = start $Path -arg "/configure RemoveAll.xml" -Wait -WindowStyle Hidden -PassThru -ea 0
    "*** -- ODT uninstall for OfficeC2R returned with value:$($Proc.ExitCode)" }

if ($Proc -and $Proc.ExitCode -eq 0) {
  "*** -- Use unified ARP uninstall command [No-Need]"
  return }

"*** -- Use unified ARP uninstall command"

try {
  $HashList = GetUninstall }
catch {
  $HashList = $null }

$arrayList = @{}
$OfficeClickToRun = $null

if ($HashList) {
  foreach ($key in $HashList.keys) {
    $value = $HashList[$key]
    if (($value -notlike "*OfficeClickToRun.exe*") -and (
      $false -eq ($value|CheckDelete) )) {
      continue }
    $data  = $value.Split( )
    if ($data) {
      0..$data.Count | % {
        if ($data[$_] -match 'productstoremove=') {
          $data[$_] = "productstoremove=AllProducts" }}
    
    $value   = $data -join (' ')
    $value  += ' displaylevel=false'
    $prefix  = $value.Split('"')
    try {
      $OfficeClickToRun = $prefix[1]
      $arrayList.Add($key,$prefix[2]) }
    catch {}
}}}

foreach ($key in $arrayList.Keys) {
  if ([IO.FILE]::Exists($OfficeClickToRun)) {
    $value = $arrayList[$key]
    $Proc = start $OfficeClickToRun -Arg $value -Wait -WindowStyle Hidden -PassThru -ea 0
    "*** -- uninstall command: $arg, exit code value: $($Proc.ExitCode)"
}}

return
}
Function CloseOfficeApps {
$dicApps = @{}
$dicApps.Add("appvshnotify.exe","appvshnotify.exe")
$dicApps.Add("integratedoffice.exe","integratedoffice.exe")
$dicApps.Add("integrator.exe","integrator.exe")
$dicApps.Add("firstrun.exe","firstrun.exe")
$dicApps.Add("communicator.exe","communicator.exe")
$dicApps.Add("msosync.exe","msosync.exe")
$dicApps.Add("OneNoteM.exe","OneNoteM.exe")
$dicApps.Add("iexplore.exe","iexplore.exe")
$dicApps.Add("mavinject32.exe","mavinject32.exe")
$dicApps.Add("werfault.exe","werfault.exe")
$dicApps.Add("perfboost.exe","perfboost.exe")
$dicApps.Add("roamingoffice.exe","roamingoffice.exe")
$dicApps.Add("officeclicktorun.exe","officeclicktorun.exe")
$dicApps.Add("officeondemand.exe","officeondemand.exe")
$dicApps.Add("OfficeC2RClient.exe","OfficeC2RClient.exe")
$dicApps.Add("explorer.exe","explorer.exe")
$dicApps.Add("msiexec.exe","msiexec.exe")
$dicApps.Add("ose.exe","ose.exe")
$dicList = $dicApps.Values -join "|"

$Process = gwmi -Query "Select * From Win32_Process"
$Process | ? {
  [REGEX]::IsMatch($_.Name,$dicList, $IgnoreCase)} | % {
    try {($_).Terminate()|Out-Null} catch {} }

$Process = gwmi -Query "Select * From Win32_Process"
$Process | % {
  $ExecuePath = ($_).Properties | ? Name -EQ ExecutablePath | select Value
  if ($ExecuePath -and $ExecuePath.Value) {
    if ($ExecuePath.Value|IsC2R) {
        try {
          ($_).Terminate()|Out-Null}
        catch {} }}}
}
Function DelSchtasks {
SCHTASKS /Delete /F /TN "C2RAppVLoggingStart" *>$null
SCHTASKS /Delete /F /TN "FF_INTEGRATEDstreamSchedule" *>$null
SCHTASKS /Delete /F /TN "Microsoft Office 15 Sync Maintenance for {d068b555-9700-40b8-992c-f866287b06c1}" *>$null
SCHTASKS /Delete /F /TN "Microsoft\Office\Office Automatic Updates 2.0" *>$null
SCHTASKS /Delete /F /TN "Microsoft\Office\Office Automatic Updates" *>$null
SCHTASKS /Delete /F /TN "Microsoft\Office\Office ClickToRun Service Monitor" *>$null
SCHTASKS /Delete /F /TN "Microsoft\Office\Office Feature Updates Logon" *>$null
SCHTASKS /Delete /F /TN "Microsoft\Office\Office Feature Updates" *>$null
SCHTASKS /Delete /F /TN "Microsoft\Office\Office Performance Monitor" *>$null
SCHTASKS /Delete /F /TN "Microsoft\Office\OfficeInventoryAgentFallBack" *>$null
SCHTASKS /Delete /F /TN "Microsoft\Office\OfficeInventoryAgentLogOn" *>$null
SCHTASKS /Delete /F /TN "Microsoft\Office\OfficeTelemetryAgentFallBack" *>$null
SCHTASKS /Delete /F /TN "Microsoft\Office\OfficeTelemetryAgentLogOn" *>$null
SCHTASKS /Delete /F /TN "Office 15 Subscription Heartbeat" *>$null
SCHTASKS /Delete /F /TN "Office Background Streaming" *>$null
SCHTASKS /Delete /F /TN "Office Subscription Maintenance" *>$null
}
Function ClearShellIntegrationReg {
Set-Location "HKLM:\"
RI "HKLM:SOFTWARE\Classes\Protocols\Handler\osf" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Classes\CLSID\{573FFD05-2805-47C2-BCE0-5F19512BEB8D}" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Classes\CLSID\{8BA85C75-763B-4103-94EB-9470F12FE0F7}" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Classes\CLSID\{CD55129A-B1A1-438E-A425-CEBC7DC684EE}" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Classes\CLSID\{D0498E0A-45B7-42AE-A9AA-ABA463DBD3BF}" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Classes\CLSID\{E768CD3B-BDDC-436D-9C13-E1B39CA257B1}" -Force -ea 0 -Recurse

RI "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers\Microsoft SPFS Icon Overlay 1 (ErrorConflict)" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers\Microsoft SPFS Icon Overlay 2 (SyncInProgress)" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers\Microsoft SPFS Icon Overlay 3 (InSync)" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers\Microsoft SPFS Icon Overlay 1 (ErrorConflict)" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers\Microsoft SPFS Icon Overlay 2 (SyncInProgress)" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers\Microsoft SPFS Icon Overlay 3 (InSync)" -Force -ea 0 -Recurse
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved\" "{B28AA736-876B-46DA-B3A8-84C5E30BA492}" -Force -ea 0
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved\" "{8B02D659-EBBB-43D7-9BBA-52CF22C5B025}" -Force -ea 0
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved\" "{0875DCB6-C686-4243-9432-ADCCF0B9F2D7}" -Force -ea 0
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved\" "{42042206-2D85-11D3-8CFF-005004838597}" -Force -ea 0
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved\" "{993BE281-6695-4BA5-8A2A-7AACBFAAB69E}" -Force -ea 0
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved\" "{C41662BB-1FA0-4CE0-8DC5-9B7F8279FF97}" -Force -ea 0
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved\" "{506F4668-F13E-4AA1-BB04-B43203AB3CC0}" -Force -ea 0
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved\" "{D66DC78C-4F61-447F-942B-3FB6980118CF}" -Force -ea 0
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved\" "{46137B78-0EC3-426D-8B89-FF7C3A458B5E}" -Force -ea 0
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved\" "{8BA85C75-763B-4103-94EB-9470F12FE0F7}" -Force -ea 0
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved\" "{CD55129A-B1A1-438E-A425-CEBC7DC684EE}" -Force -ea 0
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved\" "{D0498E0A-45B7-42AE-A9AA-ABA463DBD3BF}" -Force -ea 0
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved\" "{E768CD3B-BDDC-436D-9C13-E1B39CA257B1}" -Force -ea 0
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved\" "{E768CD3B-BDDC-436D-9C13-E1B39CA257B1}" -Force -ea 0
RI "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects\{31D09BA0-12F5-4CCE-BE8A-2923E76605DA}" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects\{B4F3A835-0E21-4959-BA22-42B3008E02FF}" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects\{D0498E0A-45B7-42AE-A9AA-ABA463DBD3BF}" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects\{31D09BA0-12F5-4CCE-BE8A-2923E76605DA}" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects\{B4F3A835-0E21-4959-BA22-42B3008E02FF}" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects\{D0498E0A-45B7-42AE-A9AA-ABA463DBD3BF}" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\{0875DCB6-C686-4243-9432-ADCCF0B9F2D7}" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\Namespace\{B28AA736-876B-46DA-B3A8-84C5E30BA492}" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\NetworkNeighborhood\Namespace\{46137B78-0EC3-426D-8B89-FF7C3A458B5E}" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Microsoft Office Temp Files" -Force -ea 0 -Recurse
}
function Get-MsiProducts {
  
  # PowerShell: Get-MsiProducts / Get Windows Installer Products
  # https://gist.github.com/MyITGuy/153fc0f553d840631269720a56be5136#file-file01-ps1

    function Get-MsiUpgradeCode {
        [CmdletBinding()]
        param (
            [Guid]$ProductCode,
            [Guid]$UpgradeCode
        )
        function ConvertFrom-CompressedGuid {
            <#
	        .SYNOPSIS
		        Converts a compressed globally unique identifier (GUID) string into a GUID string.
	        .DESCRIPTION
            Takes a compressed GUID string and breaks it into 6 parts. It then loops through the first five parts and reversing the order. It loops through the sixth part and reversing the order of every 2 characters. It then joins the parts back together and returns a GUID.
	        .EXAMPLE
		        ConvertFrom-CompressedGuid -CompressedGuid '2820F6C7DCD308A459CABB92E828C144'
	
		        The output of this example would be: {7C6F0282-3DCD-4A80-95AC-BB298E821C44}
	        .PARAMETER CompressedGuid
		        A compressed globally unique identifier (GUID) string.
	        #>
            [CmdletBinding()]
            [OutputType([String])]
            param (
                [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Mandatory)]
                [ValidatePattern('^[0-9a-fA-F]{32}$')]
                [ValidateScript( { [Guid]::Parse($_) -is [Guid] })]
                [String]$CompressedGuid
            )
            process {
                Write-Verbose "CompressedGuid: $($CompressedGuid)"
                $GuidString = ([Guid]$CompressedGuid).ToString('N')
                Write-Verbose "GuidString: $($GuidString)"
                $Indexes = [ordered]@{
                    0  = 8
                    8  = 4
                    12 = 4
                    16 = 2
                    18 = 2
                    20 = 12
                }
                $Guid = ''
                foreach ($key in $Indexes.Keys) {
                    $value = $Indexes[$key]
                    $Substring = $GuidString.Substring($key, $value)
                    Write-Verbose "Substring: $($Substring)"
                    switch ($key) {
                        20 {
                            $parts = $Substring -split '(.{2})' | Where-Object { $_ }
                            foreach ($part In $parts) {
                                $part = $part -split '(.{1})'
                                Write-Verbose "Part: $($part)"
                                [Array]::Reverse($part)
                                Write-Verbose "Reversed: $($part)"
                                $Guid += $part -join ''
                            }
                        }
                        default {
                            $part = $Substring.ToCharArray()
                            Write-Verbose "Part: $($part)"
                            [Array]::Reverse($part)
                            Write-Verbose "Reversed: $($part)"
                            $Guid += $part -join ''
                        }
                    }
                }
                [Guid]::Parse($Guid).ToString('B').ToUpper()
            }
        }

        function ConvertTo-CompressedGuid {
            <#
	        .SYNOPSIS
		        Converts a GUID string into a compressed globally unique identifier (GUID) string.
	        .DESCRIPTION
		        Takes a GUID string and breaks it into 6 parts. It then loops through the first five parts and reversing the order. It loops through the sixth part and reversing the order of every 2 characters. It then joins the parts back together and returns a compressed GUID string.
	        .EXAMPLE
		        ConvertTo-CompressedGuid -Guid '{7C6F0282-3DCD-4A80-95AC-BB298E821C44}'
	
            The output of this example would be: 2820F6C7DCD308A459CABB92E828C144
	        .PARAMETER Guid
            A globally unique identifier (GUID).
	        #>
            [CmdletBinding()]
            [OutputType([String])]
            param (
                [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Mandatory)]
                [ValidateScript( { [Guid]::Parse($_) -is [Guid] })]
                [Guid]$Guid
            )
            process {
                Write-Verbose "Guid: $($Guid)"
                $GuidString = $Guid.ToString('N')
                Write-Verbose "GuidString: $($GuidString)"
                $Indexes = [ordered]@{
                    0  = 8
                    8  = 4
                    12 = 4
                    16 = 2
                    18 = 2
                    20 = 12
                }
                $CompressedGuid = ''
                foreach ($key in $Indexes.keys) {
                    $value = $Indexes[$key]
                    $Substring = $GuidString.Substring($key, $value)
                    Write-Verbose "Substring: $($Substring)"
                    switch ($key) {
                        20 {
                            $parts = $Substring -split '(.{2})' | Where-Object { $_ }
                            foreach ($part In $parts) {
                                $part = $part -split '(.{1})'
                                Write-Verbose "Part: $($part)"
                                [Array]::Reverse($part)
                                Write-Verbose "Reversed: $($part)"
                                $CompressedGuid += $part -join ''
                            }
                        }
                        default {
                            $part = $Substring.ToCharArray()
                            Write-Verbose "Part: $($part)"
                            [Array]::Reverse($part)
                            Write-Verbose "Reversed: $($part)"
                            $CompressedGuid += $part -join ''
                        }
                    }
                }
                [Guid]::Parse($CompressedGuid).ToString('N').ToUpper()
            }
        }

        filter ByProductCode {
            $Object = $_
            Write-Verbose "ProductCode: $($ProductCode)"
            if ($ProductCode) {
                $Object | Where-Object { [Guid]($_.ProductCode) -eq [Guid]($ProductCode) }
                break
            }
            $Object
        }

        $Path = "Registry::HKEY_CLASSES_ROOT\Installer\UpgradeCodes\*"
        if ($UpgradeCode) {
            $CompressedUpgradeCode = ConvertTo-CompressedGuid -Guid $UpgradeCode -Verbose:$false
            Write-Verbose "CompressedUpgradeCode: $($CompressedUpgradeCode)"
            $Path = "Registry::HKEY_CLASSES_ROOT\Installer\UpgradeCodes\$($CompressedUpgradeCode)"
        }

        Get-Item -Path $Path -ErrorAction SilentlyContinue | ForEach-Object {
            $UpgradeCodeFromCompressedGuid = ConvertFrom-CompressedGuid -CompressedGuid $_.PSChildName -Verbose:$false
            foreach ($ProductCodeCompressedGuid in ($_.GetValueNames())) {
                $Properties = [ordered]@{
                    ProductCode = ConvertFrom-CompressedGuid -CompressedGuid $ProductCodeCompressedGuid -Verbose:$false
                    UpgradeCode = [Guid]::Parse($UpgradeCodeFromCompressedGuid).ToString('B').ToUpper()
                }
                [PSCustomObject]$Properties | ByProductCode
            }
        }
    }

    $MsiUpgradeCodes = Get-MsiUpgradeCode

    $Installer = New-Object -ComObject WindowsInstaller.Installer
	$Type = $Installer.GetType()
	$Products = $Type.InvokeMember('Products', [BindingFlags]::GetProperty, $null, $Installer, $null)
	foreach ($Product In $Products) {
		$hash = @{}
		$hash.ProductCode = $Product
		$Attributes = @('Language', 'ProductName', 'PackageCode', 'Transforms', 'AssignmentType', 'PackageName', 'InstalledProductName', 'VersionString', 'RegCompany', 'RegOwner', 'ProductID', 'ProductIcon', 'InstallLocation', 'InstallSource', 'InstallDate', 'Publisher', 'LocalPackage', 'HelpLink', 'HelpTelephone', 'URLInfoAbout', 'URLUpdateInfo')		
		foreach ($Attribute In $Attributes) {
			$hash."$($Attribute)" = $null
		}
		foreach ($Attribute In $Attributes) {
			try {
				$hash."$($Attribute)" = $Type.InvokeMember('ProductInfo', [BindingFlags]::GetProperty, $null, $Installer, @($Product, $Attribute))
			} catch [Exception] {
				#$error[0]|format-list -force
			}
		}
        
        # UpgradeCode
        $hash.UpgradeCode = $MsiUpgradeCodes | Where-Object ProductCode -eq ($hash.ProductCode) | Select-Object -ExpandProperty UpgradeCode

		New-Object -TypeName PSObject -Property $hash
	}
}
function UninstallLicenses($DllPath) {
  
  # https://github.com/ave9858
  # https://gist.github.com/ave9858/9fff6af726ba3ddc646285d1bbf37e71

    $DynAssembly = New-Object AssemblyName('Win32Lib')
    $AssemblyBuilder = [AppDomain]::CurrentDomain.DefineDynamicAssembly($DynAssembly, [AssemblyBuilderAccess]::Run)
    $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('Win32Lib', $False)
    $TypeBuilder = $ModuleBuilder.DefineType('sppc', 'Public, Class')
    $DllImportConstructor = [DllImportAttribute].GetConstructor(@([String]))
    $FieldArray = [Reflection.FieldInfo[]] @([DllImportAttribute].GetField('EntryPoint'))

    $Open = $TypeBuilder.DefineMethod('SLOpen', [Reflection.MethodAttributes] 'Public, Static', [int], @([IntPtr].MakeByRefType()))
    $Open.SetCustomAttribute((New-Object CustomAttributeBuilder(
                $DllImportConstructor,
                @($DllPath),
                $FieldArray,
                @('SLOpen'))))

    $GetSLIDList = $TypeBuilder.DefineMethod('SLGetSLIDList', [Reflection.MethodAttributes] 'Public, Static', [int], @([IntPtr], [int], [guid].MakeByRefType(), [int], [int].MakeByRefType(), [IntPtr].MakeByRefType()))
    $GetSLIDList.SetCustomAttribute((New-Object CustomAttributeBuilder(
                $DllImportConstructor,
                @($DllPath),
                $FieldArray,
                @('SLGetSLIDList'))))

    $UninstallLicense = $TypeBuilder.DefineMethod('SLUninstallLicense', [Reflection.MethodAttributes] 'Public, Static', [int], @([IntPtr], [IntPtr]))
    $UninstallLicense.SetCustomAttribute((New-Object CustomAttributeBuilder(
                $DllImportConstructor,
                @($DllPath),
                $FieldArray,
                @('SLUninstallLicense'))))

    $SPPC = $TypeBuilder.CreateType()
    $Handle = [IntPtr]::Zero
    $SPPC::SLOpen([ref]$handle) | Out-Null
    $pnReturnIds = 0
    $ppReturnIds = [IntPtr]::Zero

    if (!$SPPC::SLGetSLIDList($handle, 0, [ref][guid]"0ff1ce15-a989-479d-af46-f275c6370663", 6, [ref]$pnReturnIds, [ref]$ppReturnIds)) {
        foreach ($i in 0..($pnReturnIds - 1)) {
            $SPPC::SLUninstallLicense($handle, [Int64]$ppReturnIds + [Int64]16 * $i) | Out-Null
        }    
    }
}
function GetUninstall {
$UninstallArr  = @{}
$UninstallKeys = @{}
$UninstallKeys.Add(1,"HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")
$UninstallKeys.Add(2,"HKLM:SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")

foreach ($sKey in $UninstallKeys.Values) {
  Set-Location "HKLM:\"
  Push-Location $sKey -ea 0

  if (@(Get-Location).Path -NE 'HKLM:\') {
    $children = gci .
    $children | % {
      $sName = $_.Name.Replace('HKEY_LOCAL_MACHINE','HKLM:')
      $sGuid = $sName.Split('\')|select -Last 1
      Set-Location "HKLM:\"; Push-Location "$sName" -ea 0
      if (@(Get-Location).Path -NE 'HKLM:\') {
        try {
          $UninstallString = $null
          $UninstallString = gpv . -Name 'UninstallString' -ea 0 }
        catch {}
        if ($UninstallString -and (
          $UninstallString|IsC2R)) {

            try {
              $UninstallArr.Add(
                $sGuid, $UninstallString)}
            catch {}}}}}
}

return $UninstallArr
}
function CleanUninstall {

$UninstallKeys = @{}
$UninstallKeys.Add(1,"HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")
$UninstallKeys.Add(2,"HKLM:SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")

foreach ($sKey in $UninstallKeys.Values) {
Set-Location "HKLM:\"
Push-Location $sKey -ea 0

if (@(Get-Location).Path -NE 'HKLM:\') {
  $children = gci .
  $children | % {
    $sName = $_.Name.Replace('HKEY_LOCAL_MACHINE','HKLM:')
    $sGuid = $sName.Split('\')|select -Last 1
    
    Set-Location "HKLM:\"
    Push-Location "$sName" -ea 0
    if (@(Get-Location).Path -NE 'HKLM:\') {
      try {
        $InstallLocation = $null
        $InstallLocation = gpv . -Name 'InstallLocation' -ea 0 }
      catch {}

      if (($sGuid -and ($sGuid|CheckDelete)) -or (
        $InstallLocation -and ($InstallLocation|IsC2R))) {
          Set-Location "HKLM:\"
          RI $sName -Recurse -Force }
    }}}}
}
Function RegWipe {

CloseOfficeApps

"*** -- C2R specifics"
"*** -- Virtual InstallRoot"
"*** -- Mapi Search reg"
"*** -- Office key in HKLM"

Set-Location "HKLM:\"
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Run" Lync15 -Force -ea 0
RP "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\Run" Lync16 -Force -ea 0
RI "HKLM:SOFTWARE\Microsoft\Office\15.0\Common\InstallRoot\Virtual" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Office\16.0\Common\InstallRoot\Virtual" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Office\Common\InstallRoot\Virtual" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Classes\CLSID\{2027FC3B-CF9D-4ec7-A823-38BA308625CC}" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Office\15.0\ClickToRun" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Office\15.0\ClickToRunStore" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Office\16.0\ClickToRun" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Office\16.0\ClickToRunStore" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Office\ClickToRun" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Office\ClickToRunStore" -Force -ea 0 -Recurse
RI "HKLM:Software\Microsoft\Office\15.0" -Force -ea 0 -Recurse
RI "HKLM:Software\Microsoft\Office\16.0" -Force -ea 0 -Recurse

"*** -- HKCU Registration"
Set-Location "HKCU:\"
RI "HKCU:Software\Microsoft\Office\15.0\Registration" -Force -ea 0 -Recurse
RI "HKCU:Software\Microsoft\Office\16.0\Registration" -Force -ea 0 -Recurse
RI "HKCU:Software\Microsoft\Office\Registration" -Force -ea 0 -Recurse
RI "HKCU:SOFTWARE\Microsoft\Office\15.0\ClickToRun" -Force -ea 0 -Recurse
RI "HKCU:SOFTWARE\Microsoft\Office\16.0\ClickToRun" -Force -ea 0 -Recurse
RI "HKCU:SOFTWARE\Microsoft\Office\ClickToRun" -Force -ea 0 -Recurse
RI "HKCU:Software\Microsoft\Office\15.0" -Force -ea 0 -Recurse
RI "HKCU:Software\Microsoft\Office\16.0" -Force -ea 0 -Recurse

"*** -- App Paths"
$Keys = reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths" 2>$null
$keys | % {
$value = reg query "$_" /ve /t REG_SZ 2>$null
if ($value -match "\\Microsoft Office") {
  reg delete $_ /f | Out-Null }}

"*** -- Run key"
$hDefKey = "HKLM"
$sSubKeyName = "SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
Set-Location "$($hDefKey):\"
Push-Location "$($hDefKey):$($sSubKeyName)" -ea 0

if (@(Get-Location).Path -ne "$($hDefKey):\") {
  $arrNames = gi .
  if ($arrNames)  {
    $arrNames.Property | % { 
      $name = GPV . $_
      if ($name -and (
        $Name|IsC2R)) {
          RP . $_ -Force
}}}}

"*** -- Un-install Keys"
CleanUninstall

"*** -- UpgradeCodes, WI config, WI global config"
"*** -- msiexec based uninstall [Fail-Safe]"

# First here ... 
# HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products

$hash     = $null;
$HashList = $null;
$sKey     = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products"

Set-Location 'HKLM:\'
$sProducts = 
  GCI $sKey -ea 0
$HashList = $sProducts | % {
  ($_).PSPath.Split('\') | select -Last 1 | % {
    [PSCustomObject]@{
    cGuid = $_
    sGuid = ($_|GetExpandedGuid) }}}
$GuidList = 
  $HashList | ? sGuid

if ($GuidList) {
  $GuidList | ? sGuid | % {
    $Proc = $null
    $ProductCode = $_.sGuid
    $sMsiProp = "REBOOT=ReallySuppress NOREMOVESPAWN=True"
    $sUninstallCmd = "/x {$($ProductCode)} $($sMsiProp) /q"

    if ($ProductCode) {
      $Proc = start msiexec.exe -Args $sUninstallCmd -Wait -WindowStyle Hidden -ea 0 -PassThru
      "*** -- Msiexec $($sUninstallCmd) ,End with value: $($proc.ExitCode)" }

    Set-Location 'HKLM:\'
    RI "$sKey\$($_.sGuid)" -Force -Recurse -ea 0 | Out-Null
    Set-Location 'HKCR:\'
    RI "HKCR:\Installer\Products\$($_.sGuid)" -Force -Recurse -ea 0 | Out-Null }}

# Second here ... 
# HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UpgradeCodes

$hash     = $null;
$HashList = $null;
$sKey     = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UpgradeCodes"

Set-Location 'HKLM:\'
$sUpgradeCodes = 
  GCI $sKey -ea 0
$HashList = $sUpgradeCodes | % {
  ($_).PSPath.Split('\') | select -Last 1 | % {
    [PSCustomObject]@{
    cGuid = $_
    sGuid = ($_|GetExpandedGuid) }}}
$GuidList = 
  $HashList | ? sGuid

if ($GuidList) {
  $GuidList | % {
    Set-Location 'HKLM:\'
    RI "$sKey\$($_.sGuid)" -Force -Recurse -ea 0 | Out-Null
    Set-Location 'HKCR:\'
    RI "HKCR:\Installer\UpgradeCodes\$($_.sGuid)" -Force -Recurse -ea 0 | Out-Null }}

# make sure we clean everything
$sKeyToRe = @{}
$sKeyList = (
  "SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UpgradeCodes",
  "SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products" )

foreach ($sKey in $sKeyList)
{
  Set-Location "HKLM:\"
  $sKey = "HKLM:" + $sKey

  Set-Location "HKLM:\"
  Push-Location $sKey -ea 0

  if (@(Get-Location).Path -NE 'HKLM:\') {
    $children = gci .
    $children | % {
      $sName = $_.Name.Replace('HKEY_LOCAL_MACHINE','HKLM:')
      $sGuid = $sName.Split('\')|select -Last 1

      Set-Location "HKLM:\"
      Push-Location $sName -ea 0
      if (@(Get-Location).Path -NE 'HKLM:\') {

      $InstallSource   = $null
      $UninstallString = $null
    
      try {
        $InstallSource   = GPV "InstallProperties" -Name InstallSource   -ea 0
        $UninstallString = GPV "InstallProperties" -Name UninstallString -ea 0 }
      catch { }
    
      $CheckOfficeApp = $null
      $CheckOfficeApp = ($sGuid -and ($sGuid|CheckDelete)) -or (
        $InstallSource -and $UninstallString -and ($InstallSource|ISC2R) -and (
        [REGEX]::Match($UninstallString, "^.*{(.*)}.*$",$IgnoreCase)))

      if ($CheckOfficeApp -eq $true) {
        $Matches = [REGEX]::Matches($UninstallString,"^.*{(.*)}.*$",
          $IgnoreCase)
        try {
          $ProductCode = $null
          $ProductCode = $Matches[0].Groups[1].Value }
        catch {}

        $proc = $null
        $sMsiProp = "REBOOT=ReallySuppress NOREMOVESPAWN=True"
        $sUninstallCmd = "/x {$($ProductCode)} $($sMsiProp) /q"

        if ($ProductCode) {
          $proc = start msiexec.exe -Args $sUninstallCmd -Wait -WindowStyle Hidden -ea 0 -PassThru
          "*** -- mSiexec $($sUninstallCmd) ,End with value: $($proc.ExitCode)"
		  $sKeyToRe.Add($sName,$sName) }
}}}}}

Set-Location "HKLM:\"
$sKeyToRe.Keys | % {
  RI $_ -Force -Recurse -ea 0 | Out-Null }

Set-Location "HKCR:\"
$sKeyToRe.Keys | % {
  $GUID = ($_).Split('\') | Select-Object -Last 1
  if ($GUID) {
    RI "HKCR:\Installer\Products\$GUID" -Force -Recurse -ea 0 | Out-Null }}

"*** -- Known Typelib Registration"
RegWipeTypeLib

"*** -- Published Components [JAWOT]"

"*** -- ActiveX/COM Components [JAWOT]"
$COM = (
"{00020800-0000-0000-C000-000000000046}","{00020803-0000-0000-C000-000000000046}",
"{00020812-0000-0000-C000-000000000046}","{00020820-0000-0000-C000-000000000046}",
"{00020821-0000-0000-C000-000000000046}","{00020827-0000-0000-C000-000000000046}",
"{00020830-0000-0000-C000-000000000046}","{00020832-0000-0000-C000-000000000046}",
"{00020833-0000-0000-C000-000000000046}","{00020906-0000-0000-C000-000000000046}",
"{00020907-0000-0000-C000-000000000046}","{000209F0-0000-0000-C000-000000000046}",
"{000209F4-0000-0000-C000-000000000046}","{000209F5-0000-0000-C000-000000000046}",
"{000209FE-0000-0000-C000-000000000046}","{000209FF-0000-0000-C000-000000000046}",
"{00024500-0000-0000-C000-000000000046}","{00024502-0000-0000-C000-000000000046}",
"{00024505-0016-0000-C000-000000000046}","{048EB43E-2059-422F-95E0-557DA96038AF}",
"{18A06B6B-2F3F-4E2B-A611-52BE631B2D22}","{1B261B22-AC6A-4E68-A870-AB5080E8687B}",
"{1CDC7D25-5AA3-4DC4-8E0C-91524280F806}","{3C18EAE4-BC25-4134-B7DF-1ECA1337DDDC}",
"{64818D10-4F9B-11CF-86EA-00AA00B929E8}","{64818D11-4F9B-11CF-86EA-00AA00B929E8}",
"{65235197-874B-4A07-BDC5-E65EA825B718}","{73720013-33A0-11E4-9B9A-00155D152105}",
"{75D01070-1234-44E9-82F6-DB5B39A47C13}","{767A19A0-3CC7-415B-9D08-D48DD7B8557D}",
"{84F66100-FF7C-4fb4-B0C0-02CD7FB668FE}","{8A624388-AA27-43E0-89F8-2A12BFF7BCCD}",
"{912ABC52-36E2-4714-8E62-A8B73CA5E390}","{91493441-5A91-11CF-8700-00AA0060263B}",
"{AA14F9C9-62B5-4637-8AC4-8F25BF29D5A7}","{C282417B-2662-44B8-8A94-3BFF61C50900}",
"{CF4F55F4-8F87-4D47-80BB-5808164BB3F8}","{DC020317-E6E2-4A62-B9FA-B3EFE16626F4}",
"{EABCECDB-CC1C-4A6F-B4E3-7F888A5ADFC8}","{F4754C9B-64F5-4B40-8AF4-679732AC0607}")

#Set-Location "HKCR:\"
$COM | % {
  # will not work .. why ? don't know
  # ri "HKCR:CLSID\$_" -Recurse -Force -ea 0 
}

"*** -- TypeLib Interface [JAWOT]"
$interface = @(
"{000672AC-0000-0000-C000-000000000046}","{000C0300-0000-0000-C000-000000000046}"
"{000C0301-0000-0000-C000-000000000046}","{000C0302-0000-0000-C000-000000000046}"
"{000C0304-0000-0000-C000-000000000046}","{000C0306-0000-0000-C000-000000000046}"
"{000C0308-0000-0000-C000-000000000046}","{000C030A-0000-0000-C000-000000000046}"
"{000C030C-0000-0000-C000-000000000046}","{000C030D-0000-0000-C000-000000000046}"
"{000C030E-0000-0000-C000-000000000046}","{000C0310-0000-0000-C000-000000000046}"
"{000C0311-0000-0000-C000-000000000046}","{000C0312-0000-0000-C000-000000000046}"
"{000C0313-0000-0000-C000-000000000046}","{000C0314-0000-0000-C000-000000000046}"
"{000C0315-0000-0000-C000-000000000046}","{000C0316-0000-0000-C000-000000000046}"
"{000C0317-0000-0000-C000-000000000046}","{000C0318-0000-0000-C000-000000000046}"
"{000C0319-0000-0000-C000-000000000046}","{000C031A-0000-0000-C000-000000000046}"
"{000C031B-0000-0000-C000-000000000046}","{000C031C-0000-0000-C000-000000000046}"
"{000C031D-0000-0000-C000-000000000046}","{000C031E-0000-0000-C000-000000000046}"
"{000C031F-0000-0000-C000-000000000046}","{000C0320-0000-0000-C000-000000000046}"
"{000C0321-0000-0000-C000-000000000046}","{000C0322-0000-0000-C000-000000000046}"
"{000C0324-0000-0000-C000-000000000046}","{000C0326-0000-0000-C000-000000000046}"
"{000C0328-0000-0000-C000-000000000046}","{000C032E-0000-0000-C000-000000000046}"
"{000C0330-0000-0000-C000-000000000046}","{000C0331-0000-0000-C000-000000000046}"
"{000C0332-0000-0000-C000-000000000046}","{000C0333-0000-0000-C000-000000000046}"
"{000C0334-0000-0000-C000-000000000046}","{000C0337-0000-0000-C000-000000000046}"
"{000C0338-0000-0000-C000-000000000046}","{000C0339-0000-0000-C000-000000000046}"
"{000C033A-0000-0000-C000-000000000046}","{000C033B-0000-0000-C000-000000000046}"
"{000C033D-0000-0000-C000-000000000046}","{000C033E-0000-0000-C000-000000000046}"
"{000C0340-0000-0000-C000-000000000046}","{000C0341-0000-0000-C000-000000000046}"
"{000C0353-0000-0000-C000-000000000046}","{000C0356-0000-0000-C000-000000000046}"
"{000C0357-0000-0000-C000-000000000046}","{000C0358-0000-0000-C000-000000000046}"
"{000C0359-0000-0000-C000-000000000046}","{000C035A-0000-0000-C000-000000000046}"
"{000C0360-0000-0000-C000-000000000046}","{000C0361-0000-0000-C000-000000000046}"
"{000C0362-0000-0000-C000-000000000046}","{000C0363-0000-0000-C000-000000000046}"
"{000C0364-0000-0000-C000-000000000046}","{000C0365-0000-0000-C000-000000000046}"
"{000C0366-0000-0000-C000-000000000046}","{000C0367-0000-0000-C000-000000000046}"
"{000C0368-0000-0000-C000-000000000046}","{000C0369-0000-0000-C000-000000000046}"
"{000C036A-0000-0000-C000-000000000046}","{000C036C-0000-0000-C000-000000000046}"
"{000C036D-0000-0000-C000-000000000046}","{000C036E-0000-0000-C000-000000000046}"
"{000C036F-0000-0000-C000-000000000046}","{000C0370-0000-0000-C000-000000000046}"
"{000C0371-0000-0000-C000-000000000046}","{000C0372-0000-0000-C000-000000000046}"
"{000C0373-0000-0000-C000-000000000046}","{000C0375-0000-0000-C000-000000000046}"
"{000C0376-0000-0000-C000-000000000046}","{000C0377-0000-0000-C000-000000000046}"
"{000C0379-0000-0000-C000-000000000046}","{000C037A-0000-0000-C000-000000000046}"
"{000C037B-0000-0000-C000-000000000046}","{000C037C-0000-0000-C000-000000000046}"
"{000C037D-0000-0000-C000-000000000046}","{000C037E-0000-0000-C000-000000000046}"
"{000C037F-0000-0000-C000-000000000046}","{000C0380-0000-0000-C000-000000000046}"
"{000C0381-0000-0000-C000-000000000046}","{000C0382-0000-0000-C000-000000000046}"
"{000C0385-0000-0000-C000-000000000046}","{000C0386-0000-0000-C000-000000000046}"
"{000C0387-0000-0000-C000-000000000046}","{000C0388-0000-0000-C000-000000000046}"
"{000C0389-0000-0000-C000-000000000046}","{000C038A-0000-0000-C000-000000000046}"
"{000C038B-0000-0000-C000-000000000046}","{000C038C-0000-0000-C000-000000000046}"
"{000C038E-0000-0000-C000-000000000046}","{000C038F-0000-0000-C000-000000000046}"
"{000C0390-0000-0000-C000-000000000046}","{000C0391-0000-0000-C000-000000000046}"
"{000C0392-0000-0000-C000-000000000046}","{000C0393-0000-0000-C000-000000000046}"
"{000C0395-0000-0000-C000-000000000046}","{000C0396-0000-0000-C000-000000000046}"
"{000C0397-0000-0000-C000-000000000046}","{000C0398-0000-0000-C000-000000000046}"
"{000C0399-0000-0000-C000-000000000046}","{000C039A-0000-0000-C000-000000000046}"
"{000C03A0-0000-0000-C000-000000000046}","{000C03A1-0000-0000-C000-000000000046}"
"{000C03A2-0000-0000-C000-000000000046}","{000C03A3-0000-0000-C000-000000000046}"
"{000C03A4-0000-0000-C000-000000000046}","{000C03A5-0000-0000-C000-000000000046}"
"{000C03A6-0000-0000-C000-000000000046}","{000C03A7-0000-0000-C000-000000000046}"
"{000C03B2-0000-0000-C000-000000000046}","{000C03B9-0000-0000-C000-000000000046}"
"{000C03BA-0000-0000-C000-000000000046}","{000C03BB-0000-0000-C000-000000000046}"
"{000C03BC-0000-0000-C000-000000000046}","{000C03BD-0000-0000-C000-000000000046}"
"{000C03BE-0000-0000-C000-000000000046}","{000C03BF-0000-0000-C000-000000000046}"
"{000C03C0-0000-0000-C000-000000000046}","{000C03C1-0000-0000-C000-000000000046}"
"{000C03C2-0000-0000-C000-000000000046}","{000C03C3-0000-0000-C000-000000000046}"
"{000C03C4-0000-0000-C000-000000000046}","{000C03C5-0000-0000-C000-000000000046}"
"{000C03C6-0000-0000-C000-000000000046}","{000C03C7-0000-0000-C000-000000000046}"
"{000C03C8-0000-0000-C000-000000000046}","{000C03C9-0000-0000-C000-000000000046}"
"{000C03CA-0000-0000-C000-000000000046}","{000C03CB-0000-0000-C000-000000000046}"
"{000C03CC-0000-0000-C000-000000000046}","{000C03CD-0000-0000-C000-000000000046}"
"{000C03CE-0000-0000-C000-000000000046}","{000C03CF-0000-0000-C000-000000000046}"
"{000C03D0-0000-0000-C000-000000000046}","{000C03D1-0000-0000-C000-000000000046}"
"{000C03D2-0000-0000-C000-000000000046}","{000C03D3-0000-0000-C000-000000000046}"
"{000C03D4-0000-0000-C000-000000000046}","{000C03D5-0000-0000-C000-000000000046}"
"{000C03D6-0000-0000-C000-000000000046}","{000C03D7-0000-0000-C000-000000000046}"
"{000C03E0-0000-0000-C000-000000000046}","{000C03E1-0000-0000-C000-000000000046}"
"{000C03E2-0000-0000-C000-000000000046}","{000C03E3-0000-0000-C000-000000000046}"
"{000C03E4-0000-0000-C000-000000000046}","{000C03E5-0000-0000-C000-000000000046}"
"{000C03E6-0000-0000-C000-000000000046}","{000C03F0-0000-0000-C000-000000000046}"
"{000C03F1-0000-0000-C000-000000000046}","{000C0410-0000-0000-C000-000000000046}"
"{000C0411-0000-0000-C000-000000000046}","{000C0913-0000-0000-C000-000000000046}"
"{000C0914-0000-0000-C000-000000000046}","{000C0936-0000-0000-C000-000000000046}"
"{000C1530-0000-0000-C000-000000000046}","{000C1531-0000-0000-C000-000000000046}"
"{000C1532-0000-0000-C000-000000000046}","{000C1533-0000-0000-C000-000000000046}"
"{000C1534-0000-0000-C000-000000000046}","{000C1709-0000-0000-C000-000000000046}"
"{000C170B-0000-0000-C000-000000000046}","{000C170F-0000-0000-C000-000000000046}"
"{000C1710-0000-0000-C000-000000000046}","{000C1711-0000-0000-C000-000000000046}"
"{000C1712-0000-0000-C000-000000000046}","{000C1713-0000-0000-C000-000000000046}"
"{000C1714-0000-0000-C000-000000000046}","{000C1715-0000-0000-C000-000000000046}"
"{000C1716-0000-0000-C000-000000000046}","{000C1717-0000-0000-C000-000000000046}"
"{000C1718-0000-0000-C000-000000000046}","{000C171B-0000-0000-C000-000000000046}"
"{000C171C-0000-0000-C000-000000000046}","{000C1723-0000-0000-C000-000000000046}"
"{000C1724-0000-0000-C000-000000000046}","{000C1725-0000-0000-C000-000000000046}"
"{000C1726-0000-0000-C000-000000000046}","{000C1727-0000-0000-C000-000000000046}"
"{000C1728-0000-0000-C000-000000000046}","{000C1729-0000-0000-C000-000000000046}"
"{000C172A-0000-0000-C000-000000000046}","{000C172B-0000-0000-C000-000000000046}"
"{000C172C-0000-0000-C000-000000000046}","{000C172D-0000-0000-C000-000000000046}"
"{000C172E-0000-0000-C000-000000000046}","{000C172F-0000-0000-C000-000000000046}"
"{000C1730-0000-0000-C000-000000000046}","{000C1731-0000-0000-C000-000000000046}"
"{000CD100-0000-0000-C000-000000000046}","{000CD101-0000-0000-C000-000000000046}"
"{000CD102-0000-0000-C000-000000000046}","{000CD6A1-0000-0000-C000-000000000046}"
"{000CD6A2-0000-0000-C000-000000000046}","{000CD6A3-0000-0000-C000-000000000046}"
"{000CD706-0000-0000-C000-000000000046}","{000CD809-0000-0000-C000-000000000046}"
"{000CD900-0000-0000-C000-000000000046}","{000CD901-0000-0000-C000-000000000046}"
"{000CD902-0000-0000-C000-000000000046}","{000CD903-0000-0000-C000-000000000046}"
"{000CDB00-0000-0000-C000-000000000046}","{000CDB01-0000-0000-C000-000000000046}"
"{000CDB02-0000-0000-C000-000000000046}","{000CDB03-0000-0000-C000-000000000046}"
"{000CDB04-0000-0000-C000-000000000046}","{000CDB05-0000-0000-C000-000000000046}"
"{000CDB06-0000-0000-C000-000000000046}","{000CDB09-0000-0000-C000-000000000046}"
"{000CDB0A-0000-0000-C000-000000000046}","{000CDB0E-0000-0000-C000-000000000046}"
"{000CDB0F-0000-0000-C000-000000000046}","{000CDB10-0000-0000-C000-000000000046}"
"{00194002-D9C3-11D3-8D59-0050048384E3}","{4291224C-DEFE-485B-8E69-6CF8AA85CB76}"
"{4B0F95AC-5769-40E9-98DF-80CDD086612E}","{4CAC6328-B9B0-11D3-8D59-0050048384E3}"
"{55F88890-7708-11D1-ACEB-006008961DA5}","{55F88892-7708-11D1-ACEB-006008961DA5}"
"{55F88896-7708-11D1-ACEB-006008961DA5}","{6EA00553-9439-4D5A-B1E6-DC15A54DA8B2}"
"{88FF5F69-FACF-4667-8DC8-A85B8225DF15}","{8A64A872-FC6B-4D4A-926E-3A3689562C1C}"
"{919AA22C-B9AD-11D3-8D59-0050048384E3}","{A98639A1-CB0C-4A5C-A511-96547F752ACD}"
"{ABFA087C-F703-4D53-946E-37FF82B2C994}","{D996597A-0E80-4753-81FC-DCF16BDF4947}"
"{DE9CD4FF-754A-49DD-A0DC-B787DA2DB0A1}","{DFD3BED7-93EC-4BCE-866C-6BAB41D28621}"
)

#Set-Location "HKCR:\"
$interface | % {
  # will not work .. why ? don't know
  # RI "HKCR\Interface\$_" -Recurse -Force -ea 0
}

"*** -- Components in Global [ & Could take 2-3 minutes & ]"
$Keys = reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components" 2>$null
$keys | % {
 $data = reg query $_ /t REG_SZ 2>$null
 if (($data -ne $null) -and (
   $data -match "\\Microsoft Office")) {
     reg delete $_ /f | Out-Null }}

"*** -- Components in CLSID [ & Could take 2-3 minutes & ]"
$Keys = reg query "HKLM\SOFTWARE\Classes\CLSID" 2>$null
$keys | % {
  $LocalServer32 = reg query "$_\LocalServer32" /ve /t REG_SZ 2>$null
  if (($LocalServer32 -ne $null) -and (
    $LocalServer32[2] -match "\\Microsoft Office")) {
      reg delete $_ /f | Out-Null }
  if ($LocalServer32 -eq $null) {
    $InprocServer32 = reg query "$_\InprocServer32" /ve /t REG_SZ 2>$null
    if (($InprocServer32 -ne $null) -and (
      $InprocServer32[2] -match "\\Microsoft Office")) {
        reg delete $_ /f | Out-Null }}}

<#
-- reg query "HKEY_CLASSES_ROOT\CLSID\
-- "HKEY_CLASSES_ROOT\CLSID\{C282417B-2662-44B8-8A94-3BFF61C50900}"

-- reg query "HKEY_CLASSES_ROOT\CLSID\{C282417B-2662-44B8-8A94-3BFF61C50900}\LocalServer32"
-- ERROR: The system was unable to find the specified registry key or value. [ACCESS DENIED ERROR]

$Keys = reg query "HKCR\CLSID" 2>$null
$keys | % {
  $LocalServer32 = reg query "$_\LocalServer32" /ve /t REG_SZ 2>$null
  if (($LocalServer32 -ne $null) -and (
    $LocalServer32[2] -match "\\Microsoft Office")) {
      reg delete $_ /f | Out-Null }
  if ($LocalServer32 -eq $null) {
    $InprocServer32 = reg query "$_\InprocServer32" /ve /t REG_SZ 2>$null
    if (($InprocServer32 -ne $null) -and (
      $InprocServer32[2] -match "\\Microsoft Office")) {
        reg delete $_ /f | Out-Null }}}
#>
}
Function FileWipe {

"*** -- remove the OfficeSvc service"
$service = $null
$service = Get-WmiObject Win32_Service -Filter "Name='OfficeSvc'" -ea 0
if ($service) { 
  try {
    $service.delete()|out-null}
  catch {} }

"*** -- remove the ClickToRunSvc service"
$service = $null
$service = Get-WmiObject Win32_Service -Filter "Name='ClickToRunSvc'" -ea 0
if ($service) { 
  try {
    $service.delete()|out-null}
  catch {} }

"*** -- delete C2R package files"
Set-Location "$($env:SystemDrive)\"

RI @(Join-Path $env:ProgramFiles "Microsoft Office\Office16") -Recurse -force -ea 0
RI @(Join-Path $env:ProgramData "Microsoft\office\FFPackageLocker") -Recurse -force -ea 0 
RI @(Join-Path $env:ProgramData "Microsoft\office\FFStatePBLocker") -Recurse -force -ea 0 
RI @(Join-Path $env:ProgramFiles "Microsoft Office\AppXManifest.xml") -force -ea 0 
RI @(Join-Path $env:ProgramFiles "Microsoft Office\FileSystemMetadata.xml") -force -ea 0 

RI @(Join-Path $env:ProgramData "Microsoft\ClickToRun") -Recurse -force -ea 0 
RI @(Join-Path $env:ProgramData "Microsoft\office\Heartbeat") -Recurse -force -ea 0 
RI @(Join-Path $env:ProgramData "Microsoft\office\FFPackageLocker") -Recurse -force -ea 0 
RI @(Join-Path $env:ProgramData "Microsoft\office\ClickToRunPackageLocker") -Recurse -force -ea 0 
RI @(Join-Path $env:ProgramFiles "Microsoft Office 15") -Recurse -force -ea 0 
RI @(Join-Path $env:ProgramFiles "Microsoft Office 16") -Recurse -force -ea 0 
RI @(Join-Path $env:ProgramFiles "Microsoft Office\root") -Recurse -force -ea 0 
RI @(Join-Path $env:ProgramFiles "Microsoft Office\Office16") -Recurse -force -ea 0 
RI @(Join-Path $env:ProgramFiles "Microsoft Office\Office15") -Recurse -force -ea 0 
RI @(Join-Path $env:ProgramFiles "Microsoft Office\PackageManifests") -Recurse -force -ea 0 
RI @(Join-Path $env:ProgramFiles "Microsoft Office\PackageSunrisePolicies") -Recurse -force -ea 0 
RI @(Join-Path $env:CommonProgramFiles "microsoft shared\ClickToRun") -Recurse -force -ea 0 

if ($env:ProgramFilesX86) {
  RI @(Join-Path $env:ProgramFilesX86 "Microsoft Office\AppXManifest.xml") -force -ea 0 
  RI @(Join-Path $env:ProgramFilesX86 "Microsoft Office\FileSystemMetadata.xml") -force -ea 0 
  RI @(Join-Path $env:ProgramFilesX86 "Microsoft Office\root") -Recurse -force -ea 0 
  RI @(Join-Path $env:ProgramFilesX86 "Microsoft Office\Office16") -Recurse -force -ea 0 
  RI @(Join-Path $env:ProgramFilesX86 "Microsoft Office\Office15") -Recurse -force -ea 0 
  RI @(Join-Path $env:ProgramFilesX86 "Microsoft Office\PackageManifests") -Recurse -force -ea 0 
  RI @(Join-Path $env:ProgramFilesX86 "Microsoft Office\PackageSunrisePolicies") -Recurse -force -ea 0 
}

RI @(Join-Path $env:userprofile "Microsoft Office") -Recurse -force -ea 0 
RI @(Join-Path $env:userprofile "Microsoft Office 15") -Recurse -force -ea 0 
RI @(Join-Path $env:userprofile "Microsoft Office 16") -Recurse -force -ea 0
}
Function RestoreExplorer {
$wmiInfo = gwmi -Query "Select * From Win32_Process Where Name='explorer.exe'"
if (-not $wmiInfo) {
  start "explorer"}
}
Function Uninstall {

"*** -- remove the published component registration for C2R packages"
$Location = (
  "SOFTWARE\Microsoft\Office\ClickToRun",
  "SOFTWARE\Microsoft\Office\16.0\ClickToRun",
  "SOFTWARE\Microsoft\Office\15.0\ClickToRun" )

Foreach ($Loc in $Location) {
  Set-Location "HKLM:\"
  Set-Location $Loc -ea 0
  if (@(Get-Location).Path -ne 'HKLM:\') {
    try {
      $sPkgFld  = $null; $sPkgGuid = $null;
      $sPkgFld  = GPV . -Name PackageFolder
      $sPkgGuid = GPV . -Name PackageGUID
      HandlePakage $sPkgFld $sPkgGuid
    }
    catch {
      $sPkgFld  = $null
      $sPkgGuid = $null
    }
}}

"*** -- delete potential blocking registry keys for msiexec based tasks"
Set-Location "HKLM:\"
RI "HKLM:SOFTWARE\Microsoft\Office\15.0\ClickToRun" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Office\16.0\ClickToRun" -Force -ea 0 -Recurse
RI "HKLM:SOFTWARE\Microsoft\Office\ClickToRun" -Force -ea 0 -Recurse

Set-Location "HKCU:\"
RI "HKCU:SOFTWARE\Microsoft\Office\15.0\ClickToRun" -Force -ea 0 -Recurse
RI "HKCU:SOFTWARE\Microsoft\Office\16.0\ClickToRun" -Force -ea 0 -Recurse
RI "HKCU:SOFTWARE\Microsoft\Office\ClickToRun" -Force -ea 0 -Recurse

"*** -- AppV keys"
$hDefKey_List = @(
  "HKCU", "HKLM" )
$sSubKeyName_List = @(
  "SOFTWARE\Microsoft\AppV\ISV",
  "SOFTWARE\Microsoft\AppVISV" )

foreach ($hDefKey in $hDefKey_List) {
  foreach ($sSubKeyName in $sSubKeyName_List) {
    Set-Location "$($hDefKey):\"
    Push-Location "$($hDefKey):$($sSubKeyName)" -ea 0
    if (@(Get-Location).Path -ne "$($hDefKey):\") {
      $arrNames = gi .
      if ($arrNames)  {
        $arrNames.Property | % { 
          $name = GPV . $_
          if ($name -and (
            $Name|IsC2R)) {
              RP . $_ -Force }}}}}}	
	
"*** -- msiexec based uninstall"
try {
  $omsi = Get-MsiProducts }
catch { 
 return }

 if (!($omsi)) { # ! same as -not
   return }
 
$sUninstallCmd = $null
$sMsiProp = "REBOOT=ReallySuppress NOREMOVESPAWN=True"

 $omsi | % {
  $ProductCode   = $_.ProductCode
  $InstallSource = $_.InstallSource

  if (($ProductCode -and ($ProductCode|CheckDelete)) -or (
    $InstallSource -and ($InstallSource|IsC2R))) {
        $sUninstallCmd = "/x $($ProductCode) $($sMsiProp) /q"
	    $proc = start msiexec.exe -Args $sUninstallCmd -Wait -WindowStyle Hidden -ea 0 -PassThru
        "*** -- msIexec $($sUninstallCmd) ,End with value: $($proc.ExitCode)"

 }}
 net stop msiserver *>$null
}
Function RegWipeTypeLib {
$sTLKey = 
"Software\Classes\TypeLib\"

$RegLibs = @(
"\0\Win32\","\0\Win64\","\9\Win32\","\9\Win64\")

$arrTypeLibs = @(
"{000204EF-0000-0000-C000-000000000046}","{000204EF-0000-0000-C000-000000000046}",
"{00020802-0000-0000-C000-000000000046}","{00020813-0000-0000-C000-000000000046}",
"{00020905-0000-0000-C000-000000000046}","{0002123C-0000-0000-C000-000000000046}",
"{00024517-0000-0000-C000-000000000046}","{0002E157-0000-0000-C000-000000000046}",
"{00062FFF-0000-0000-C000-000000000046}","{0006F062-0000-0000-C000-000000000046}",
"{0006F080-0000-0000-C000-000000000046}","{012F24C1-35B0-11D0-BF2D-0000E8D0D146}",
"{06CA6721-CB57-449E-8097-E65B9F543A1A}","{07B06096-5687-4D13-9E32-12B4259C9813}",
"{0A2F2FC4-26E1-457B-83EC-671B8FC4C86D}","{0AF7F3BE-8EA9-4816-889E-3ED22871FE05}",
"{0D452EE1-E08F-101A-852E-02608C4D0BB4}","{0EA692EE-BB50-4E3C-AEF0-356D91732725}",
"{1F8E79BA-9268-4889-ADF3-6D2AABB3C32C}","{2374F0B1-3220-4c71-B702-AF799F31ABB4}",
"{238AA1AC-786F-4C17-BAAB-253670B449B9}","{28DD2950-2D4A-42B5-ABBF-500AA42E7EC1}",
"{2A59CA0A-4F1B-44DF-A216-CB2C831E5870}","{2DF8D04C-5BFA-101B-BDE5-00AA0044DE52}",
"{2DF8D04C-5BFA-101B-BDE5-00AA0044DE52}","{2F7FC181-292B-11D2-A795-DFAA798E9148}",
"{3120BA9F-4FC8-4A4F-AE1E-02114F421D0A}","{31411197-A502-11D2-BBCA-00C04F8EC294}",
"{3B514091-5A69-4650-87A3-607C4004C8F2}","{47730B06-C23C-4FCA-8E86-42A6A1BC74F4}",
"{49C40DDF-1B04-4868-B3B5-E49F120E4BFA}","{4AC9E1DA-5BAD-4AC7-86E3-24F4CDCECA28}",
"{4AFFC9A0-5F99-101B-AF4E-00AA003F0F07}","{4D95030A-A3A9-4C38-ACA8-D323A2267698}",
"{55A108B0-73BB-43db-8C03-1BEF4E3D2FE4}","{56D04F5D-964F-4DBF-8D23-B97989E53418}",
"{5B87B6F0-17C8-11D0-AD41-00A0C90DC8D9}","{66CDD37F-D313-4E81-8C31-4198F3E42C3C}",
"{6911FD67-B842-4E78-80C3-2D48597C2ED0}","{698BB59C-38F1-4CEF-92F9-7E3986E708D3}",
"{6DDCE504-C0DC-4398-8BDB-11545AAA33EF}","{6EFF1177-6974-4ED1-99AB-82905F931B87}",
"{73720002-33A0-11E4-9B9A-00155D152105}","{759EF423-2E8F-4200-ADF0-5B6177224BEE}",
"{76F6F3F5-9937-11D2-93BB-00105A994D2C}","{773F1B9A-35B9-4E95-83A0-A210F2DE3B37}",
"{7D868ACD-1A5D-4A47-A247-F39741353012}","{7E36E7CB-14FB-4F9E-B597-693CE6305ADC}",
"{831FDD16-0C5C-11D2-A9FC-0000F8754DA1}","{8404DD0E-7A27-4399-B1D9-6492B7DD7F7F}",
"{8405D0DF-9FDD-4829-AEAD-8E2B0A18FEA4}","{859D8CF5-7ADE-4DAB-8F7D-AF171643B934}",
"{8E47F3A2-81A4-468E-A401-E1DEBBAE2D8D}","{91493440-5A91-11CF-8700-00AA0060263B}",
"{9A8120F2-2782-47DF-9B62-54F672075EA1}","{9B7C3E2E-25D5-4898-9D85-71CEA8B2B6DD}",
"{9B92EB61-CBC1-11D3-8C2D-00A0CC37B591}","{9D58B963-654A-4625-86AC-345062F53232}",
"{9DCE1FC0-58D3-471B-B069-653CE02DCE88}","{A4D51C5D-F8BF-46CC-92CC-2B34D2D89716}",
"{A717753E-C3A6-4650-9F60-472EB56A7061}","{AA53E405-C36D-478A-BBFF-F359DF962E6D}",
"{AAB9C2AA-6036-4AE1-A41C-A40AB7F39520}","{AB54A09E-1604-4438-9AC7-04BE3E6B0320}",
"{AC0714F2-3D04-11D1-AE7D-00A0C90F26F4}","{AC2DE821-36A2-11CF-8053-00AA006009FA}",
"{B30CDC65-4456-4FAA-93E3-F8A79E21891C}","{B8812619-BDB3-11D0-B19E-00A0C91E29D8}",
"{B9164592-D558-4EE7-8B41-F1C9F66D683A}","{B9AA1F11-F480-4054-A84E-B5D9277E40A8}",
"{BA35B84E-A623-471B-8B09-6D72DD072F25}","{BDEADE33-C265-11D0-BCED-00A0C90AB50F}",
"{BDEADEF0-C265-11D0-BCED-00A0C90AB50F}","{BDEADEF0-C265-11D0-BCED-00A0C90AB50F}",
"{C04E4E5E-89E6-43C0-92BD-D3F2C7FBA5C4}","{C3D19104-7A67-4EB0-B459-D5B2E734D430}",
"{C78F486B-F679-4af5-9166-4E4D7EA1CEFC}","{CA973FCA-E9C3-4B24-B864-7218FC1DA7BA}",
"{CBA4EBC4-0C04-468d-9F69-EF3FEED03236}","{CBBC4772-C9A4-4FE8-B34B-5EFBD68F8E27}",
"{CD2194AA-11BE-4EFD-97A6-74C39C6508FF}","{E0B12BAE-FC67-446C-AAE8-4FA1F00153A7}",
"{E985809A-84A6-4F35-86D6-9B52119AB9D7}","{ECD5307E-4419-43CF-8BDA-C9946AC375CF}",
"{EDCD5812-6A06-43C3-AFAC-46EF5D14E22C}","{EDCD5812-6A06-43C3-AFAC-46EF5D14E22C}",
"{EDCD5812-6A06-43C3-AFAC-46EF5D14E22C}","{EDDCFF16-3AEE-4883-BD91-0F3978640DFB}",
"{EE9CFA8C-F997-4221-BE2F-85A5F603218F}","{F2A7EE29-8BF6-4a6d-83F1-098E366C709C}",
"{F3685D71-1FC6-4CBD-B244-E60D8C89990B}")

    foreach ($tl in $arrTypeLibs) {
  
      Set-Location "HKLM:\"
      $sKey = "HKLM:" + $sTLKey + $tl

      Set-Location "HKLM:\"
      Push-Location $sKey -ea 0
      if (@(Get-Location).Path -eq 'HKLM:\') {
        continue
      }

      $children   = GCI .
      $fCanDelete = $false

      if (-not $children) {
        Set-Location "HKLM:\"
        Push-Location "HKLM:$($sTLKey)" -ea 0
        if (@(Get-Location).Path -ne 'HKLM:\') {
          RI $tl -Recurse -Force }
        continue
      }
  
      foreach ($K in $children) {
    
        $sTLVerKey = $sKey + "\" + $K.PSChildName
        $PSChildName = GCI $K.PSChildName -ea 0
        if ($PSChildName) {
          $fCanDelete = $true }
    
        Set-Location "HKLM:\"
        Push-Location $sKey -ea 0
        if (@(Get-Location).Path -eq 'HKLM:\') {
          continue }
    
        $RegLibs | % {
          Set-Location "HKLM:\"
          Push-Location "$($sTLVerKey)$($_)" -ea 0
          if (@(Get-Location).Path -ne 'HKLM:\') {
            try {
              $Default = gpv . -Name '(Default)' -ea 0 }
            catch {}
            if ($Default -and (
              [IO.FILE]::Exists($Default))) {
                $fCanDelete = $false }}}

        if ($fCanDelete) {
          Set-Location "HKLM:\"
          Push-Location $sKey -ea 0
          if (@(Get-Location).Path -ne 'HKLM:\') {
	      RI $K.PSChildName -Recurse -Force }}
      }
    }
}
Function CleanOSPP {
    $OfficeAppId  = '0ff1ce15-a989-479d-af46-f275c6370663'
    $SL_ID_PRODUCT_SKU = Get-SLIDList -eQueryIdType SL_ID_APPLICATION -pQueryId $OfficeAppId -eReturnIdType SL_ID_PRODUCT_SKU
    $SL_ID_ALL_LICENSE_FILES = Get-SLIDList -eQueryIdType SL_ID_APPLICATION -pQueryId $OfficeAppId -eReturnIdType SL_ID_ALL_LICENSE_FILES
    if ($SL_ID_PRODUCT_SKU) {
       SL-UninstallProductKey -skuList $SL_ID_PRODUCT_SKU
    }
    if ($SL_ID_ALL_LICENSE_FILES) {
       SL-UninstallLicense -LicenseFileIds $SL_ID_ALL_LICENSE_FILES
    }
}
Function ClearVNextLicCache {

$Licenses = Join-Path $ENV:localappdata "Microsoft\Office\Licenses"
    if (Test-Path $Licenses) {
      Set-Location "$($env:SystemDrive)\"
      RI $Licenses -Recurse -Force -ea 0 }
}
Function HandlePakage {
  param (
   [parameter(Mandatory=$True)]
   [string]$sPkgFldr,

   [parameter(Mandatory=$True)]
   [string]$sPkgGuid
  )

  $RootPath =
    Join-Path $sPkgFldr "\root"
  $IntegrationPath =
    Join-Path $sPkgFldr "\root\Integration"
  $Integrator =
    Join-Path $sPkgFldr "\root\Integration\Integrator.exe"
  $Integrator_ =
    "$env:ProgramData\Microsoft\ClickToRun\{$sPkgGuid}\integrator.exe"

  if (-not (
      Test-Path ($IntegrationPath ))) {
        return }
  
  Set-Location 'c:\'
  Push-Location $RootPath

  #Remove `Root`->`Integration\C2RManifest*.xml`
  if (@(Get-Location).Path -ne 'c:\') {
    RI .\Integration\ -Filter "C2RManifest*.xml" -Recurse -Force -ea 0
  }
  
  if ([IO.FILE]::Exists(
    $Integrator)) {
      $Args = "/U /Extension PackageRoot=""$($RootPath)"" PackageGUID=""$($sPkgGuid)"""
      $Proc = start $Integrator -arg $Args -Wait -WindowStyle Hidden -PassThru -ea 0
	  "*** -- Uninstall ID: $sPkgGuid with Full Args, returned with value:$($Proc.ExitCode)"
      $Args = "/U"
      $Proc = start $Integrator -arg $Args -Wait -WindowStyle Hidden -PassThru  -ea 0
	  "*** -- Uninstall ID: $sPkgGuid with Minimum Args, returned with value:$($Proc.ExitCode)" }

  if ([IO.FILE]::Exists(
    $Integrator_)) {
      $Args = "/U /Extension PackageRoot=""$($RootPath)"" PackageGUID=""$($sPkgGuid)"""
      $Proc = start $Integrator_ -arg $Args -Wait -WindowStyle Hidden -PassThru -ea 0
	  "*** -- Uninstall ID: $sPkgGuid with Full Args, returned with value:$($Proc.ExitCode)"
      $Args = "/U"
      $Proc = start $Integrator_ -arg $Args -Wait -WindowStyle Hidden -PassThru  -ea 0
	  "*** -- Uninstall ID: $sPkgGuid with Minimum Args, returned with value:$($Proc.ExitCode)" }
}
Function Office_Online_Install (
  [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
  [String] $Channel) {
Function Get-Lang {
  $oLang = @{}
  $oLang.Add(1033,"English")
  $oLang.Add(1078,"Afrikaans")
  $oLang.Add(1052,"Albanian")
  $oLang.Add(1118,"Amharic")
  $oLang.Add(1025,"Arabic")
  $oLang.Add(1067,"Armenian")
  $oLang.Add(1101,"Assamese")
  $oLang.Add(1068,"Azerbaijani Latin")
  $oLang.Add(2117,"Bangla Bangladesh")
  $oLang.Add(1093,"Bangla Bengali India")
  $oLang.Add(1069,"Basque Basque")
  $oLang.Add(1059,"Belarusian")
  $oLang.Add(5146,"Bosnian")
  $oLang.Add(1026,"Bulgarian")
  $oLang.Add(2051,"Catalan Valencia")
  $oLang.Add(1027,"Catalan")
  $oLang.Add(2052,"Chinese Simplified")
  $oLang.Add(1028,"Chinese Traditional")
  $oLang.Add(1050,"Croatian")
  $oLang.Add(1029,"Czech")
  $oLang.Add(1030,"Danish")
  $oLang.Add(1164,"Dari")
  $oLang.Add(1043,"Dutch")
  $oLang.Add(2057,"English UK")
  $oLang.Add(1061,"Estonian")
  $oLang.Add(1124,"Filipino")
  $oLang.Add(1035,"Finnish")
  $oLang.Add(3084,"French Canada")
  $oLang.Add(1036,"French")
  $oLang.Add(1110,"Galician")
  $oLang.Add(1079,"Georgian")
  $oLang.Add(1031,"German")
  $oLang.Add(1032,"Greek")
  $oLang.Add(1095,"Gujarati")
  $oLang.Add(1128,"Hausa Nigeria")
  $oLang.Add(1037,"Hebrew")
  $oLang.Add(1081,"Hindi")
  $oLang.Add(1038,"Hungarian")
  $oLang.Add(1039,"Icelandic")
  $oLang.Add(1136,"Igbo")
  $oLang.Add(1057,"Indonesian")
  $oLang.Add(2108,"Irish")
  $oLang.Add(1040,"Italian")
  $oLang.Add(1041,"Japanese")
  $oLang.Add(1099,"Kannada")
  $oLang.Add(1087,"Kazakh")
  $oLang.Add(1107,"Khmer")
  $oLang.Add(1089,"KiSwahili")
  $oLang.Add(1159,"Kinyarwanda")
  $oLang.Add(1111,"Konkani")
  $oLang.Add(1042,"Korean")
  $oLang.Add(1088,"Kyrgyz")
  $oLang.Add(1062,"Latvian")
  $oLang.Add(1063,"Lithuanian")
  $oLang.Add(1134,"Luxembourgish")
  $oLang.Add(1071,"Macedonian")
  $oLang.Add(1086,"Malay Latin")
  $oLang.Add(1100,"Malayalam")
  $oLang.Add(1082,"Maltese")
  $oLang.Add(1153,"Maori")
  $oLang.Add(1102,"Marathi")
  $oLang.Add(1104,"Mongolian")
  $oLang.Add(1121,"Nepali")
  $oLang.Add(2068,"Norwedian Nynorsk")
  $oLang.Add(1044,"Norwegian Bokmal")
  $oLang.Add(1096,"Odia")
  $oLang.Add(1123,"Pashto")
  $oLang.Add(1065,"Persian")
  $oLang.Add(1045,"Polish")
  $oLang.Add(1046,"Portuguese Brazilian")
  $oLang.Add(2070,"Portuguese Portugal")
  $oLang.Add(1094,"Punjabi Gurmukhi")
  $oLang.Add(3179,"Quechua")
  $oLang.Add(1048,"Romanian")
  $oLang.Add(1047,"Romansh")
  $oLang.Add(1049,"Russian")
  $oLang.Add(1074,"Setswana")
  $oLang.Add(1169,"Scottish Gaelic")
  $oLang.Add(7194,"Serbian Bosnia")
  $oLang.Add(10266,"Serbian Serbia")
  $oLang.Add(9242,"Serbian")
  $oLang.Add(1132,"Sesotho sa Leboa")
  $oLang.Add(2137,"Sindhi Arabic")
  $oLang.Add(1115,"Sinhala")
  $oLang.Add(1051,"Slovak")
  $oLang.Add(1060,"Slovenian")
  $oLang.Add(3082,"Spanish")
  $oLang.Add(2058,"Spanish Mexico")
  $oLang.Add(1053,"Swedish")
  $oLang.Add(1097,"Tamil")
  $oLang.Add(1092,"Tatar Cyrillic")
  $oLang.Add(1098,"Telugu")
  $oLang.Add(1054,"Thai")
  $oLang.Add(1055,"Turkish")
  $oLang.Add(1090,"Turkmen")
  $oLang.Add(1058,"Ukrainian")
  $oLang.Add(1056,"Urdu")
  $oLang.Add(1152,"Uyghur")
  $oLang.Add(1091,"Uzbek")
  $oLang.Add(1066,"Vietnamese")
  $oLang.Add(1106,"Welsh")
  $oLang.Add(1160,"Wolof")
  $oLang.Add(1130,"Yoruba")
  $oLang.Add(1076,"isiXhosa")
  $oLang.Add(1077,"isiZulu")
  return $oLang
}
Function Get-Culture {
  $oLang = @{}
  $oLang.Add(1033,"en-us")
  $oLang.Add(1078,"af-za")
  $oLang.Add(1052,"sq-al")
  $oLang.Add(1118,"am-et")
  $oLang.Add(1025,"ar-sa")
  $oLang.Add(1067,"hy-am")
  $oLang.Add(1101,"as-in")
  $oLang.Add(1068,"az-latn-az")
  $oLang.Add(2117,"bn-bd")
  $oLang.Add(1093,"bn-in")
  $oLang.Add(1069,"eu-es")
  $oLang.Add(1059,"be-by")
  $oLang.Add(5146,"bs-latn-ba")
  $oLang.Add(1026,"bg-bg")
  $oLang.Add(2051,"ca-es-valencia")
  $oLang.Add(1027,"ca-es")
  $oLang.Add(2052,"zh-cn")
  $oLang.Add(1028,"zh-tw")
  $oLang.Add(1050,"hr-hr")
  $oLang.Add(1029,"cs-cz")
  $oLang.Add(1030,"da-dk")
  $oLang.Add(1164,"prs-af")
  $oLang.Add(1043,"nl-nl")
  $oLang.Add(2057,"en-GB")
  $oLang.Add(1061,"et-ee")
  $oLang.Add(1124,"fil-ph")
  $oLang.Add(1035,"fi-fi")
  $oLang.Add(3084,"fr-CA")
  $oLang.Add(1036,"fr-fr")
  $oLang.Add(1110,"gl-es")
  $oLang.Add(1079,"ka-ge")
  $oLang.Add(1031,"de-de")
  $oLang.Add(1032,"el-gr")
  $oLang.Add(1095,"gu-in")
  $oLang.Add(1128,"ha-Latn-NG")
  $oLang.Add(1037,"he-il")
  $oLang.Add(1081,"hi-in")
  $oLang.Add(1038,"hu-hu")
  $oLang.Add(1039,"is-is")
  $oLang.Add(1136,"ig-NG")
  $oLang.Add(1057,"id-id")
  $oLang.Add(2108,"ga-ie")
  $oLang.Add(1040,"it-it")
  $oLang.Add(1041,"ja-jp")
  $oLang.Add(1099,"kn-in")
  $oLang.Add(1087,"kk-kz")
  $oLang.Add(1107,"km-kh")
  $oLang.Add(1089,"sw-ke")
  $oLang.Add(1159,"rw-RW")
  $oLang.Add(1111,"kok-in")
  $oLang.Add(1042,"ko-kr")
  $oLang.Add(1088,"ky-kg")
  $oLang.Add(1062,"lv-lv")
  $oLang.Add(1063,"lt-lt")
  $oLang.Add(1134,"lb-lu")
  $oLang.Add(1071,"mk-mk")
  $oLang.Add(1086,"ms-my")
  $oLang.Add(1100,"ml-in")
  $oLang.Add(1082,"mt-mt")
  $oLang.Add(1153,"mi-nz")
  $oLang.Add(1102,"mr-in")
  $oLang.Add(1104,"mn-mn")
  $oLang.Add(1121,"ne-np")
  $oLang.Add(2068,"nn-no")
  $oLang.Add(1044,"nb-no")
  $oLang.Add(1096,"or-in")
  $oLang.Add(1123,"ps-AF")
  $oLang.Add(1065,"fa-ir")
  $oLang.Add(1045,"pl-pl")
  $oLang.Add(1046,"pt-br")
  $oLang.Add(2070,"pt-pt")
  $oLang.Add(1094,"pa-in")
  $oLang.Add(3179,"quz-pe")
  $oLang.Add(1048,"ro-ro")
  $oLang.Add(1047,"rm-CH")
  $oLang.Add(1049,"ru-ru")
  $oLang.Add(1074,"tn-ZA")
  $oLang.Add(1169,"gd-gb")
  $oLang.Add(7194,"sr-cyrl-ba")
  $oLang.Add(10266,"sr-cyrl-rs")
  $oLang.Add(9242,"sr-latn-rs")
  $oLang.Add(1132,"nso-ZA")
  $oLang.Add(2137,"sd-arab-pk")
  $oLang.Add(1115,"si-lk")
  $oLang.Add(1051,"sk-sk")
  $oLang.Add(1060,"sl-si")
  $oLang.Add(3082,"es-es")
  $oLang.Add(2058,"es-MX")
  $oLang.Add(1053,"sv-se")
  $oLang.Add(1097,"ta-in")
  $oLang.Add(1092,"tt-ru")
  $oLang.Add(1098,"te-in")
  $oLang.Add(1054,"th-th")
  $oLang.Add(1055,"tr-tr")
  $oLang.Add(1090,"tk-tm")
  $oLang.Add(1058,"uk-ua")
  $oLang.Add(1056,"ur-pk")
  $oLang.Add(1152,"ug-cn")
  $oLang.Add(1091,"uz-latn-uz")
  $oLang.Add(1066,"vi-vn")
  $oLang.Add(1106,"cy-gb")
  $oLang.Add(1160,"wo-SN")
  $oLang.Add(1130,"yo-NG")
  $oLang.Add(1076,"xh-ZA")
  $oLang.Add(1077,"zu-ZA")
  return $oLang
}
Function Get-Channels {
  $oProd = @{}
  $oProd.Add("BetaChannel","5440fd1f-7ecb-4221-8110-145efaa6372f")
  $oProd.Add("Current","492350f6-3a01-4f97-b9c0-c7c6ddf67d60")
  $oProd.Add("CurrentPreview","64256afe-f5d9-4f86-8936-8840a6a4f5be")
  $oProd.Add("DogfoodCC","f3260cf1-a92c-4c75-b02e-d64c0a86a968")
  $oProd.Add("DogfoodDCEXT","c4a7726f-06ea-48e2-a13a-9d78849eb706")
  $oProd.Add("DogfoodDevMain","ea4a4090-de26-49d7-93c1-91bff9e53fc3")
  $oProd.Add("DogfoodFRDC","834504cc-dc55-4c6d-9e71-e024d0253f6d")
  $oProd.Add("InsidersLTSC","2e148de9-61c8-4051-b103-4af54baffbb4")
  $oProd.Add("InsidersLTSC2021","12f4f6ad-fdea-4d2a-a90f-17496cc19a48")
  $oProd.Add("InsidersLTSC2024","20481F5C-C268-4624-936C-52EB39DDBD97")
  $oProd.Add("InsidersMEC","0002c1ba-b76b-4af9-b1ee-ae2ad587371f")   
  $oProd.Add("MicrosoftCC","5462eee5-1e97-495b-9370-853cd873bb07")
  $oProd.Add("MicrosoftDC","f4f024c8-d611-4748-a7e0-02b6e754c0fe")
  $oProd.Add("MicrosoftDevMain","b61285dd-d9f7-41f2-9757-8f61cba4e9c8")
  $oProd.Add("MicrosoftFRDC","9a3b7ff2-58ed-40fd-add5-1e5158059d1c")
  $oProd.Add("MicrosoftLTSC","1d2d2ea6-1680-4c56-ac58-a441c8c24ff9")
  $oProd.Add("MicrosoftLTSC2021","86752282-5841-4120-ac80-db03ae6b5fdb")
  $oProd.Add("MicrosoftLTSC2024","C02D8FE6-5242-4DA8-972F-82EE55E00671")
  $oProd.Add("MonthlyEnterprise","55336b82-a18d-4dd6-b5f6-9e5095c314a6")
  $oProd.Add("PerpetualVL2019","f2e724c1-748f-4b47-8fb8-8e0d210e9208")
  $oProd.Add("PerpetualVL2021","5030841d-c919-4594-8d2d-84ae4f96e58e")
  $oProd.Add("PerpetualVL2024","7983BAC0-E531-40CF-BE00-FD24FE66619C")
  $oProd.Add("SemiAnnual","7ffbc6bf-bc32-4f92-8982-f9dd17fd3114")
  $oProd.Add("SemiAnnualPreview","b8f9b850-328d-4355-9145-c59439a0c4cf")
  return $oProd
}

  $IsX32=$Null
  $IsX64=$Null
  $file = $Null

  $IgnoreCase = [Text.RegularExpressions.RegexOptions]::IgnoreCase

  $oProductsId = Get-Channels
  if ($Channel -and ($oProductsId[$Channel] -eq $null)) {
    throw "ERROR: BAD CHANNEL"
  }

  if ($Channel) {
    $sChannel = $oProductsId.GetEnumerator()|? {$_.key -eq $Channel}
  }

  if (-not($sChannel)){
    $sChannel = $oProductsId | OGV -Title "Select Channel" -OutputMode Single
    if (-not ($sChannel)){
      return;
  }}

  # find FFNRoot value
  $FFNRoot = $sChannel.value
  $sUrl="http://officecdn.microsoft.com/pr/$FFNRoot"

  $oVer = Get-Office-Apps|?{($_.Channel -eq $sChannel.Key) -and ($_.System -eq '10.0')}|select -Last 1|select -ExpandProperty Build
  if ([string]::IsNullOrEmpty($oVer)) {
    throw "ERROR: FAIL TO GET BUILD VERSION"
  }

  ri @(Join-Path $env:TEMP VersionDescriptor.xml) -Force -ea 0
  try {
        Switch ([intptr]::Size) {
            4 { 
                $IsX32 = $true
                $IsX64 = $Null
                $file = "$ENV:TEMP\v32.cab"
                ri $file -Force -ea 0
            
                # Attempt to download the v32.cab file
                try {
                    Write-Warning "Cab File, $sUrl/Office/Data/v32.cab"
                    iwr -Uri "$sUrl/Office/Data/v32.cab" -OutFile $file -ErrorAction Stop
                } catch {
                    Write-Warning "ERROR: FAIL DOWNLOAD CAB FILE for v32.cab ($_)"
                    return
                }

                # Attempt to extract the CAB file
                try {
                    Expand $file -f:VersionDescriptor.xml $env:TEMP *>$Null
                } catch {
                    Write-Warning "ERROR: FAIL EXTRACT XML FILE for v32.cab ($_)"
                    return
                }
            }

            8 {
                $IsX32 = $Null
                $IsX64 = $true
                $file = "$ENV:TEMP\v64.cab"
                ri $file -Force -ea 0
            
                # Attempt to download the v64.cab file
                try {
                    Write-Warning "Cab File, $sUrl/Office/Data/v64.cab"
                    iwr -Uri "$sUrl/Office/Data/v64.cab" -OutFile $file -ErrorAction Stop
                } catch {
                    Write-Warning "ERROR: FAIL DOWNLOAD CAB FILE for v64.cab ($_)"
                    return
                }

                # Attempt to extract the CAB file
                try {
                    Expand $file -f:VersionDescriptor.xml $env:TEMP *>$Null
                } catch {
                    Write-Warning "ERROR: FAIL EXTRACT XML FILE for v64.cab ($_)"
                    return
                }
            }
        }
    }
    catch {
        Write-Warning "Script failed during processing. Exiting."
        return
    }

  if (!(Test-path(
    @(Join-Path $env:TEMP VersionDescriptor.xml)))) {
      throw "ERROR: FAIL EXTRACT XML FILE"
  }

  $oXml = Get-Content @(Join-Path $env:TEMP VersionDescriptor.xml) -ea 0
  if (!$oXml) {
    throw "ERROR: FAIL READ XML FILE"
  }

  $rPat = '^(.*)(ProductReleaseId Name=)(.*)>$'
  $oApps = $oXml|?{[REGEX]::IsMatch($_,$rPat,$IgnoreCase)}|%{$_.SubString(28,$_.Length-28-2)}|sort|OGV -title "Found Office Apps" -OutputMode Multiple
  if (-not $oApps) {
    return;
  }

  $LangList = Get-Lang
 
  $mLang = $LangList |  OGV -Title "Select the Main Language" -OutputMode Single
  if (-not $mLang) {
    return;
  }
  $aLang = $LangList |  OGV -Title "Select Additional Language[s]" -PassThru

  $culture = ''
  $oCul = Get-Culture
  
  $mLang | % {
    $culture += $oCul[[INT]$_.Key]
  }

  if ($aLang) {
    $aLang | % {
      $culture += '_' + $oCul[[INT]$_.Key]
  }}
  
  # Start set values
  $type = "CDN"
  $bUrl = $sUrl
  $misc = "flt.useoutlookshareaddon=unknown flt.useofficehelperaddon=unknown"

  $sCulture = $culture
  $mCulture = $oCul[[INT]$mLang[0].Name]

  $sAppList = ($oApps | ForEach-Object { "$_.16_${sCulture}_x-none" }) -join '|'
  
  $services = @("WSearch", "ClickToRunSvc")

  foreach ($svcName in $services) {
    try {
        $svc = Get-Service -Name $svcName -ErrorAction Stop
        if ($svc.Status -eq 'Running') {
            $svc.Stop() | Out-Null
        }
    } catch {
        # Silently continue; service may not exist or already be stopped
    }
  }
  
  if ($IsX32) {
	$vSys = "x86"
    $c2r = "$ENV:ProgramFiles(x86)\Common Files\Microsoft Shared\ClickToRun"
    MD $c2r -ea 0 | Out-Null
    $file = "$ENV:TEMP\i320.cab"
    ri $file -Force -ea 0
    iwr -Uri "$sUrl/Office/Data/$oVer/i320.cab" -OutFile $file -ea 0
    if (-not(Test-Path($file))){throw "ERROR: FAIL DOWNLOAD CAB FILE"}
    Expand $file -f:* $c2r *>$Null
    Push-Location $c2r
  }

  if ($IsX64) {
	$vSys = "x64"
    $c2r = "$ENV:ProgramFiles\Common Files\Microsoft Shared\ClickToRun"
    MD $c2r -ea 0 | Out-Null
    $file = "$ENV:TEMP\i640.cab"
    ri $file -Force -ea 0
    iwr -Uri "$sUrl/Office/Data/$oVer/i640.cab" -OutFile $file -ea 0
    if (-not(Test-Path($file))){throw "ERROR: FAIL DOWNLOAD CAB FILE"}
    Expand $file -f:* $c2r *>$Null
    Push-Location $c2r
  }
  
  $args = @(
    "platform=$vSys"
    "culture=$mCulture"
    "productstoadd=$sAppList"
    "cdnbaseurl.16=$sUrl"
    "baseurl.16=$bUrl"
    "version.16=$oVer"
    "mediatype.16=$type"
    "sourcetype.16=$type"
    "updatesenabled.16=True"
    "acceptalleulas.16=True"
    "displaylevel=True"
    "bitnessmigration=False"
    "deliverymechanism=$FFNRoot"
    "$misc"
  )
  $OfficeClickToRun = Join-Path $c2r OfficeClickToRun.exe
  if (-not (Test-Path -Path $OfficeClickToRun)) {
    Write-Warning "Missing file, $OfficeClickToRun"
    return
  }
  $process = Start-Process -FilePath $OfficeClickToRun -ArgumentList $args -NoNewWindow -PassThru
  $process.WaitForExit()
  if ($process.ExitCode -eq 0) {
     Write-Host "OfficeClickToRun.exe ran successfully."
  } else {
      Write-Host "There was an error. Exit code: $($process.ExitCode)"
  }
  return
}
function Uninstall-Licenses {
    
    Manage-SLHandle -Release | Out-null
    $WMI_QUERY = @()
    $WMI_QUERY = Get-SLIDList -eQueryIdType SL_ID_PRODUCT_SKU -eReturnIdType SL_ID_PRODUCT_SKU
    $WMI_SQL = foreach ($iid in $WMI_QUERY) {
        Get-LicenseInfo -ActConfigId $iid
    }

    # Filter the results to ensure only items with EditionId
    $filteredResults = $WMI_SQL | Where-Object { $_.EditionId } | Select-Object ActConfigId, EditionId, ProductDescription

    # Show the GridView where user can select multiple items, with all columns visible
    $selectedItems = $filteredResults | Out-GridView -Title "Select Prodouct SKU To Remove" -PassThru

    # If any items are selected
    if ($selectedItems) {
        # Extract only ActConfigId GUIDs from the selected items
        $GUID_ARRAY = $selectedItems | Select-Object -ExpandProperty ActConfigId

        # Uninstall the products using the GUID array
        #SL-UninstallProductKey $skuList $GUID_ARRAY
        SL-UninstallLicense -ProductSKUs $GUID_ARRAY
    } else {
        Write-Host "No items selected."
    }
    Manage-SLHandle -Release | Out-null
}
Function Reset-Store {
    Write-Host
    Write-Host "##### Running :: slmgr.vbs /rilc"
    Stop-Service -Name sppsvc -Force
    $networkServicePath = "$env:SystemDrive\Windows\ServiceProfiles\NetworkService\AppData\Roaming\Microsoft\SoftwareProtectionPlatform"
    if (Test-Path "$networkServicePath\tokens.bar") {
        Remove-Item "$networkServicePath\tokens.bar" -Force
    }
    if (Test-Path "$networkServicePath\tokens.dat") {
        Rename-Item "$networkServicePath\tokens.dat" -NewName "tokens.bar"
    }
    $storePath = "$env:SystemDrive\Windows\System32\spp\store"
    if (Test-Path "$storePath\tokens.bar") {
        Remove-Item "$storePath\tokens.bar" -Force
    }
    if (Test-Path "$storePath\tokens.dat") {
        Rename-Item "$storePath\tokens.dat" -NewName "tokens.bar"
    }
    $storePath2 = "$env:SystemDrive\Windows\System32\spp\store\2.0"
    if (Test-Path "$storePath2\tokens.bar") {
        Remove-Item "$storePath2\tokens.bar" -Force
    }
    if (Test-Path "$storePath2\tokens.dat") {
        Rename-Item "$storePath2\tokens.dat" -NewName "tokens.bar"
    }
    Start-Service -Name sppsvc
  
    $pathList = (
    (Join-Path $ENV:SystemRoot "system32\oem"),
    (Join-Path $ENV:SystemRoot "system32\spp\tokens"))

    $Selection = @(
        foreach ($loc in $pathList) {
            if (Test-Path $loc) {
                # Find all .xrm-ms files in the location and add them to $LicenseFiles
                Get-ChildItem -Path $loc -Filter *.xrm-ms -Recurse -Force | ForEach-Object {
                    $_.FullName } } })
    
    Manage-SLHandle -Release | Out-null
    SL-InstallLicense -LicenseInput $Selection
}
Function Office-License-Installer {
    Manage-SLHandle -Release | Out-null
    $targetPath = "$env:ProgramFiles\Microsoft Office\root\Licenses16"
    Set-Location $targetPath -ErrorAction SilentlyContinue
    if ($PWD.Path -ieq $targetPath) {
    } else {
        Write-Warning "Failed to change to the target folder."
        return
    }

    $LicensingService = gwmi SoftwareLicensingService -ErrorAction Stop
    if (-not $LicensingService) {
        return }

    $file_list = dir * -Name
    $loc = (Get-Location).Path
    if ($AutoMode -and $LicensePattern -and (-not [string]::IsNullOrWhiteSpace($LicensePattern))) {
        $Selection = dir "*$LicensePattern*" -Name
    } else {
        $Selection = $file_list | ogv -Title "License installer - Helper" -OutputMode Multiple
    }
    if ($Selection) {
    
        $AllLicenseFiles = @(
            $Selection + ($file_list | Where-Object { $_ -like "pkeyconfig*" -or $_ -like "Client*" })
        ) | ForEach-Object { Join-Path $loc $_ }

        #$AllLicenseFiles | ForEach-Object { Write-Host "Install License: $_" }
        SL-installLicense -LicenseInput $AllLicenseFiles
    }
     Manage-SLHandle -Release | Out-null
    return
}
Function OffScrubc2r {
# ---------------------- #
# Begin of main function #
# ---------------------- #

"*** $(Get-Date -Format hh:mm:ss): Load HKCR Hive"
if ($null -eq (Get-PSDrive HKCR -ea 0)) {
    New-PSDrive HKCR Registry HKEY_CLASSES_ROOT -ErrorAction Stop | Out-Null }

"*** $(Get-Date -Format hh:mm:ss): Clean OSPP"
CleanOSPP

"*** $(Get-Date -Format hh:mm:ss): Clean vNext Licenses"
ClearVNextLicCache

"*** $(Get-Date -Format hh:mm:ss): End running processes"
ClearShellIntegrationReg
CloseOfficeApps

"*** $(Get-Date -Format hh:mm:ss): Clean Scheduler tasks"
DelSchtasks

"*** $(Get-Date -Format hh:mm:ss): Clean Office shortcuts"
CleanShortcuts -sFolder "$env:AllusersProfile"
CleanShortcuts -sFolder "$env:SystemDrive\Users"

"*** $(Get-Date -Format hh:mm:ss): Remove Office C2R / O365"
Uninstall

"*** $(Get-Date -Format hh:mm:ss): call odt based uninstall"
UninstallOfficeC2R

"*** $(Get-Date -Format hh:mm:ss): CleanUp"
FileWipe
RegWipe

"*** $(Get-Date -Format hh:mm:ss): Ensure Explorer runs"
RestoreExplorer

"*** $(Get-Date -Format hh:mm:ss): Un-Load HKCR Hive"
Set-Location "HKLM:\"
Remove-PSDrive -Name HKCR -ea 0 | Out-Null

write-host "Begin: $($Start_Time), End: $(Get-Date -Format hh:mm:ss)"
Write-Host
timeout 3 *>$null
return
}
function Test-WMIHealth {
    Write-Host "`nTesting WMI health..." -ForegroundColor Cyan
    $WmiFailure = $false

    try {
        $null = Get-Disk -ErrorAction Stop
        $null = Get-Partition -ErrorAction Stop
        $arch = (Get-CimInstance Win32_Processor).AddressWidth
        if ($arch -match "64|32") {
            # Nothing here
        } else {
            $WmiFailure = $true
        }
    } catch {
        $WmiFailure = $true
    }

    if ($WmiFailure) {
        Write-Host "`n*** WMI STATUS = FAIL ***" -ForegroundColor Red
    } else {
        Write-Host "`n*** WMI STATUS = OK ***" -ForegroundColor Green
    }
}
function Invoke-WMIRepair {
    param (
        [ValidateSet("Soft", "Hard")]
        [string]$Mode = "Soft"
    )

    if ($Mode -eq "Soft") {
        Write-Host "`n[Soft Repair] Starting..." -ForegroundColor Yellow
        winmgmt /verifyrepository
        winmgmt /salvagerepository

        # Restart WMI service after soft repair
        Restart-Service -Name winmgmt -Force
    } else {
        Write-Host "`n[Hard Repair] Starting..." -ForegroundColor Red

        # Stop and disable winmgmt service before repair
        Stop-Service -Name winmgmt -Force -ea 0
        Set-Service -Name winmgmt -StartupType Disabled

        $basePaths = @(
            "$env:windir\System32",
            "$env:windir\SysWOW64"
        )

        foreach ($base in $basePaths) {
            $wbem = Join-Path $base "wbem"
            if (Test-Path $wbem) {
                Push-Location $wbem

                winmgmt /resetrepository
                winmgmt /resyncperf

                if (Test-Path "$wbem\Repos_bakup") {
                    Remove-Item "$wbem\Repos_bakup" -Recurse -Force
                }
                if (Test-Path "$wbem\Repository") {
                    Rename-Item "$wbem\Repository" "Repos_bakup"
                }

                # Re-register key DLLs
                $dlls = @("scecli.dll", "userenv.dll")
                foreach ($dll in $dlls) {
                    $dllPath = Join-Path $base $dll
                    if (Test-Path $dllPath) {
                        Start-Process regsvr32 -ArgumentList "/s", $dllPath -Wait -NoNewWindow
                    }
                }

                # Register all DLLs in wbem folder
                Get-ChildItem -Filter *.dll | ForEach-Object {
                    Start-Process regsvr32 -ArgumentList "/s", $_.FullName -Wait -NoNewWindow
                }

                # Recompile MOFs and MFLs in wbem root folder
                Get-ChildItem -Filter *.mof | ForEach-Object { mofcomp $_.FullName | Out-Null }
                Get-ChildItem -Filter *.mfl | ForEach-Object { mofcomp $_.FullName | Out-Null }

                # === NEW: Recompile MOFs recursively in all wbem subfolders ===
                Write-Host "[INFO] Recursively recompiling MOFs in wbem subfolders..." -ForegroundColor Cyan
                Get-ChildItem -Recurse -Filter *.mof -ea 0 | ForEach-Object {
                    try {
                        mofcomp $_.FullName | Out-Null
                        Write-Host "Compiled: $($_.FullName)"
                    } catch {
                        Write-Warning "Failed to compile: $($_.FullName)"
                    }
                }

                # === NEW: Explicit Storage MOFs and DLLs ===
                Write-Host "[INFO] Recompiling storage-related MOFs and registering DLLs..." -ForegroundColor Cyan

                $criticalMofs = @(
                    # Storage-related
                    "$env:windir\System32\wbem\storage.mof",
                    "$env:windir\System32\wbem\disk.mof",
                    "$env:windir\System32\wbem\volume.mof",

                    # Core system management
                    "$env:windir\System32\wbem\cimwin32.mof",
                    "$env:windir\System32\wbem\netevent.mof",
                    "$env:windir\System32\wbem\wmipicmp.mof",
                    "$env:windir\System32\wbem\msiprov.mof",
                    "$env:windir\System32\wbem\wmi.mof",
                    "$env:windir\System32\wbem\eventlog.mof",
                    "$env:windir\System32\wbem\perf.mof",
                    "$env:windir\System32\wbem\perfproc.mof",
                    "$env:windir\System32\wbem\perfdisk.mof",
                    "$env:windir\System32\wbem\perfnet.mof",

                    # Networking
                    "$env:windir\System32\wbem\netbios.mof",
                    "$env:windir\System32\wbem\network.mof",

                    # Other potentially important MOFs
                    "$env:windir\System32\wbem\swprv.mof",
                    "$env:windir\System32\wbem\vsprov.mof"
                )

                foreach ($mof in $criticalMofs) {
                    if (Test-Path $mof) {
                        mofcomp $mof | Out-Null
                        Write-Host "Compiled storage MOF: $mof"
                    } else {
                        Write-Warning "Storage MOF not found: $mof"
                    }
                }

                $storageDlls = @(
                    "$env:windir\System32\storprov.dll",
                    "$env:windir\System32\vmstorfl.dll"
                )

                foreach ($dll in $storageDlls) {
                    if (Test-Path $dll) {
                        Start-Process regsvr32 -ArgumentList "/s", $dll -Wait -NoNewWindow
                        Write-Host "Registered DLL: $dll"
                    } else {
                        Write-Warning "Storage DLL not found: $dll"
                    }
                }

                # Restart winmgmt service and set to Automatic
                Set-Service -Name winmgmt -StartupType Automatic
                Start-Service -Name winmgmt

                # Re-register wmiprvse.exe
                Start-Process "wmiprvse.exe" -ArgumentList "/regserver" -Wait -NoNewWindow

                Pop-Location
            }
        }
    }

    Write-Host "`n[$Mode Repair] Completed." -ForegroundColor Green
}
Function WMI_Reset_Main {

    Clear-Host
    Write-Host "* Make sure to run as administrator"
    Write-Host "* Please disable any antivirus temporarily`n"
    Pause

    Test-WMIHealth
    Write-Host
    Write-Host "`nChoose repair mode:"
    Write-Host "[1] Soft Repair (Safe, Recommended First)"
    Write-Host "[2] Hard Repair (Full Reset, use only if Soft Repair fails)"
    $modeInput = Read-Host "Enter 1 or 2"

    switch ($modeInput) {
        '1' { Invoke-WMIRepair -Mode Soft }
        '2' { Invoke-WMIRepair -Mode Hard }
        default { Write-Host "Invalid selection. Exiting." -ForegroundColor Red; Pause; return }
    }

    # Ask for reboot after repair
    Write-Host "`nA system restart is strongly recommended to complete the WMI repair." -ForegroundColor Cyan
    $reboot = Read-Host "Do you want to restart now? (Y/N)"

    if ($reboot -match '^[Yy]$') {
        Write-Host "`nRestarting system..." -ForegroundColor Yellow
        Restart-Computer -Force
    } else {
        Write-Host "`nPlease remember to restart the system manually later." -ForegroundColor Red
        return
    }
}

if ($AutoMode) {
    $actionMap = [ordered]@{
        "RecoverKeys"                 = $RecoverKeys;
        "RunWmiRepair"                = $RunWmiRepair;
        "RunTokenStoreReset"          = $RunTokenStoreReset;
        "RunUninstallLicenses"        = $RunUninstallLicenses;
        "RunScrubOfficeC2R"           = $RunScrubOfficeC2R;
        "RunOfficeLicenseInstaller"   = $RunOfficeLicenseInstaller;
        "RunOfficeOnlineInstallation" = $RunOfficeOnlineInstallation
    }

    foreach ($action in $actionMap.GetEnumerator()) {
        if ($action.Value) {
            switch ($action.Name) {
                "RunWmiRepair" {
                    try {
                        WMI_Reset_Main
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                    break
                }
                "RunTokenStoreReset" {
                    try {
                        Reset-Store
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                    break
                }
                "RunUninstallLicenses" {
                    try {
                        Uninstall-Licenses
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                    break
                }
                "RunScrubOfficeC2R" {
                    try {
                        OffScrubc2r
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                    break
                }
                "RunOfficeLicenseInstaller" {
                    try {
                        Office-License-Installer
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                    break
                }
                "RunOfficeOnlineInstallation" {
                    try {
                        Office_Online_Install
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                    break
                }
                default {
                }
            }
        }
    }

    return
}
  
Clear-host
Write-Host
Write-Host "Troubleshoot Menu" -ForegroundColor Green
Write-Host
Write-Host "1. Wmi Repair / Reset" -ForegroundColor Green
write-host "2. Token Store Reset" -ForegroundColor Green
Write-Host "3. Uninstall Licenses" -ForegroundColor Green
write-host "4. Scrub Office C2R" -ForegroundColor Green
write-host "5. Office License Installer" -ForegroundColor Green
write-host "6. Office Online Installation" -ForegroundColor Green
write-host "7. Upgrade Windows edition" -ForegroundColor Green
write-host "8. Recover Windows & Office License" -ForegroundColor Green
Write-Host
$choice = Read-Host "Please choose an option:"
Write-Host

switch ($choice) {
    "1" {
        WMI_Reset_Main
    }
    "2" {
        Reset-Store
    }
    "3" {
        Uninstall-Licenses
    }
    "4" {
        OffScrubc2r
    }
    "5" {
        Office-License-Installer
    }
    "6" {
        Office_Online_Install
    }
    "7" {
        Get-EditionTargetsFromMatrix -UpgradeFrom
    }
    "8" {
        Clear-Host
        Write-Host
        write-host "Recover Windows License" -ForegroundColor Green
        write-host
        Get-SppStoreLicense -SkuType Windows
        write-host "Recover Office License" -ForegroundColor Green
        write-host
        Get-SppStoreLicense -SkuType Office
    }    
}
# --> End
}
Function Check-Status {

    Clear-host
    Write-Host
    Write-Host "Start Check ..."
    Write-Host

    $ohook_found = $false
    $paths = @(
        "$env:ProgramFiles\Microsoft Office\Office15\sppc*.dll",
        "$env:ProgramFiles\Microsoft Office\Office16\sppc*.dll",
        "$env:ProgramW6432\Microsoft Office\Office15\sppc*.dll",
        "$env:ProgramW6432\Microsoft Office\Office16\sppc*.dll",
        "$env:ProgramFiles(x86)\Microsoft Office\Office15\sppc*.dll",
        "$env:ProgramFiles(x86)\Microsoft Office\Office16\sppc*.dll"
    )

    foreach ($path in $paths) {
        if (Get-ChildItem -Path $path -Filter 'sppc*.dll' -Attributes ReparsePoint -ea 0) {
            $ohook_found = $true
            break
        }
    }

    # Also check the root\vfs paths
    $vfsPaths = @(
        "$env:ProgramFiles\Microsoft Office 15\root\vfs\System\sppc*.dll",
        "$env:ProgramFiles\Microsoft Office 15\root\vfs\SystemX86\sppc*.dll",
        "$env:ProgramFiles\Microsoft Office\root\vfs\System\sppc*.dll",
        "$env:ProgramFiles\Microsoft Office\root\vfs\SystemX86\sppc*.dll",
        "$env:ProgramW6432\Microsoft Office 15\root\vfs\System\sppc*.dll",
        "$env:ProgramW6432\Microsoft Office 15\root\vfs\SystemX86\sppc*.dll",
        "$env:ProgramW6432\Microsoft Office\root\vfs\System\sppc*.dll",
        "$env:ProgramW6432\Microsoft Office\root\vfs\SystemX86\sppc*.dll",
        "$env:ProgramFiles(x86)\Microsoft Office 15\root\vfs\System\sppc*.dll",
        "$env:ProgramFiles(x86)\Microsoft Office 15\root\vfs\SystemX86\sppc*.dll",
        "$env:ProgramFiles(x86)\Microsoft Office\root\vfs\System\sppc*.dll",
        "$env:ProgramFiles(x86)\Microsoft Office\root\vfs\SystemX86\sppc*.dll"
    )

    foreach ($path in $vfsPaths) {
        if (Get-ChildItem -Path $path -Filter 'sppc*.dll' -Attributes ReparsePoint -ea 0) {
            $ohook_found = $true
            break
        }
    }

    if ($ohook_found) {
        Write-Host "=== Office Ohook Bypass found ==="
        Write-Host
    }

    Check-Activation Windows RETAIL
    Check-Activation Windows MAK
    Check-Activation Windows OEM
    Check-Activation Office RETAIL
    Check-Activation Office MAK

    $output = Search_VL_Products -ProductName windows
    if ($output -and ($output -isnot [string])) {
      foreach ($obj in $output) {

        Write-Host "=== Volume License Found: $($obj.Name) === "
        if ($obj.GracePeriodRemaining -gt 259200) {
            Write-Host "=== Windows is KMS38/KMS4K activated ==="
        }
        Write-Host
      }
    }

    $output = Search_VL_Products -ProductName office
    if ($output -and ($output -isnot [string])) {
      foreach ($obj in $output) {

        Write-Host "=== Volume License Found: $($obj.Name) === "
        if ($obj.GracePeriodRemaining -gt 259200) {
            Write-Host "=== Office is KMS4K activated ==="
        }
        Write-Host
      }
    }
    Write-Host "End Check ..."
    return
}
#endregion

if ($AutoMode) {
    $actionMap = [ordered]@{
        "RunWmiRepair"                = $RunWmiRepair;
        "RecoverKeys"                 = $RecoverKeys;
        "RunTokenStoreReset"          = $RunTokenStoreReset;
        "RunUninstallLicenses"        = $RunUninstallLicenses;
        "RunScrubOfficeC2R"           = $RunScrubOfficeC2R;
        "RunOfficeLicenseInstaller"   = $RunOfficeLicenseInstaller;
        "RunOfficeOnlineInstallation" = $RunOfficeOnlineInstallation
        "RunUpgrade"                  = $RunUpgrade
        "RunHWID"                     = $RunHWID;
        "RunoHook"                    = $RunoHook;
        "RunVolume"                   = $RunVolume;
        "RunTsforge"                  = $RunTsforge;       
        "RunCheckActivation"          = $RunCheckActivation;
    }

    foreach ($action in $actionMap.GetEnumerator()) {
        if ($action.Value) {
            switch ($action.Name) {
                "RunHWID" {
                    try {
                        Run-HWID
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                }
                "RunoHook" {
                    try {
                        Run-oHook
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                }
                "RunVolume" {
                    try {
                        Run-KMS
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                }
                "RunTsforge" {
                    try {
                        Run-Tsforge
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                }
                "RunCheckActivation" {
                    try {
                        Check-Status
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                }
                "RunWmiRepair" {
                    try {
                        Run-Troubleshoot -AutoMode $true -RunWmiRepair $true
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                }
                "RunTokenStoreReset" {
                    try {
                        Run-Troubleshoot -AutoMode $true -RunTokenStoreReset $true
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                }
                "RunUninstallLicenses" {
                    try {
                        Run-Troubleshoot -AutoMode $true -RunUninstallLicenses $true
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                }
                "RunScrubOfficeC2R" {
                    try {
                        Run-Troubleshoot -AutoMode $true -RunScrubOfficeC2R $true
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                }
                "RunOfficeLicenseInstaller" {
                    try {
                        Run-Troubleshoot -AutoMode $true -RunOfficeLicenseInstaller $true
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                }
                "RunOfficeOnlineInstallation" {
                    try {
                        Run-Troubleshoot -AutoMode $true -RunOfficeOnlineInstallation $true
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                }
                "RunUpgrade" {
                    try {
                        Get-EditionTargetsFromMatrix -UpgradeFrom
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                }
                "RecoverKeys" {
                    try {
                        write-host "Recover Windows License" -ForegroundColor Green
                        write-host
                        Get-SppStoreLicense -SkuType Windows
                        write-host "Recover Office License" -ForegroundColor Green
                        write-host
                        Get-SppStoreLicense -SkuType Office
                    }
                    catch {
                        Write-Warning "$($action.Name) Mode Fail"
                    }
                }
                default {
                }
            }
        }
    }
    Write-Host
    Manage-SLHandle -Release | Out-null
    Read-Host "Press any key to close"
    return
}

do {
    Clear-Host
    Write-Host
    Write-Host "Welcome to Darki Activation p``s`` services" -ForegroundColor Yellow
    Write-Host "Choose a tool to activate:" -ForegroundColor Yellow
    Write-Host
    Write-Host "[H] HWID \ KMS38     {for Windows products only}" -ForegroundColor Yellow
    Write-Host "[O] oHook            {bypass for Office products only}" -ForegroundColor Yellow
    Write-Host "[K] Volume           {For Office -and windows products}" -ForegroundColor Yellow
    Write-Host "[T] Tsforge          {For Office -and windows (+esu) products}" -ForegroundColor Yellow
    Write-Host "[S] Troubleshoot     {For Office -and windows Products}" -ForegroundColor Yellow
    Write-Host "[C] Check Activation {For Office -and windows Products}" -ForegroundColor Yellow
    Write-Host "[E] Exit             {Exit the program}" -ForegroundColor Yellow
    Write-Host
        
    $choice = Read-Host "Enter {H} or {O} or {K} or {T} or {S} or {C} or {E} to Exit"
    Write-Host
    switch ($choice.ToUpper()) {
        "T" {
            Run-Tsforge
        }
        "O" {
            Run-oHook
        }
        "H" {
            Run-HWID
        }
        "K" {
            Run-KMS
        }
        "S" {
            Run-Troubleshoot
        }
        "C" {
            Check-Status
        }
        "E" {
            Write-Host "Exiting the program..." -ForegroundColor Red
            Manage-SLHandle -Release | Out-null
            break
        }
        default {
            Write-Host "Invalid selection. Please enter a valid option."
        }
    }
        
    Read-Host "Press Enter to continue..."  

} until ($choice.ToUpper() -eq "E")