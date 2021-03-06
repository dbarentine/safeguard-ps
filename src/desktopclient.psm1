<#
.SYNOPSIS
Download and install Safeguard desktop client from Safeguard appliance.

.DESCRIPTION
This will download a Safeguard client installer from the specified appliance
and install it.

.PARAMETER Appliance
IP address or hostname of a Safeguard appliance.

.PARAMETER Insecure
Ignore verification of Safeguard appliance SSL certificate--will be ignored for entire session.

.INPUTS
None.

.OUTPUTS
None.
#>
function Install-SafeguardDesktopClient
{
    Param(
        [Parameter(Mandatory=$false,Position=0)]
        [string]$Appliance,
        [Parameter(Mandatory=$false)]
        [switch]$Insecure
    )

    $ErrorActionPreference = "Stop"
    if (-not $PSBoundParameters.ContainsKey("Verbose")) { $VerbosePreference = $PSCmdlet.GetVariableValue("VerbosePreference") }
    Import-Module -Name "$PSScriptRoot\sslhandling.psm1" -Scope Local

    if ($SafeguardSession)
    {
        $Insecure = $SafeguardSession["Insecure"]
    }
    Edit-SslVersionSupport
    if ($Insecure)
    {
        Disable-SslVerification
    }

    if (-not $Appliance)
    {
        if ($SafeguardSession)
        {
            $Appliance = $SafeguardSession["Appliance"]
        }
        else
        {
            $Appliance = (Read-Host "Appliance")
        }
    }

    try
    {
        # Get Version Info from Appliance
    $UninstallKey = "HKLM\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    $Version = (Invoke-RestMethod "https://$Appliance/service/appliance/v2/Version" -EA SilentlyContinue)
    if (-not $Version)
    {
        $Version = (Invoke-RestMethod "https://$Appliance/service/appliance/v1/Version" -EA SilentlyContinue)
        if (-not $Version)
        {
            throw "You must specify a valid Safeguard Appliance"
        }
    }

    # Clear Safeguard Client Updates
    $Installers = @(Get-ChildItem -Path "$env:LOCALAPPDATA\Pangaea\Safeguard" -Filter "*.msi" -Recurse -EA SilentlyContinue) + `
                    @(Get-ChildItem -Path "$env:LOCALAPPDATA\Pangaea\Safeguard" -Filter "*.msi" -Recurse -EA SilentlyContinue)
    foreach ($installer in $Installers)
    {
        Write-Host "Removing: $($installer.FullName)"
        Remove-Item -Force $installer.FullName
    }

    Write-Host ("Downloading Safeguard Client for BUILD: {0}.{1}.{2}.{3}" -f $Version.Major,$Version.Minor,$Version.Revision,$Version.Build)
    $TempFile = "$env:TEMP\Safeguard.msi"
    Remove-Item -Force $TempFile -EA SilentlyContinue
    $WebClient = (New-Object System.Net.WebClient)
    try
    {
        $WebClient.DownloadFile("https://$Appliance/en-US/Safeguard.msi", $TempFile)
    }
    catch
    {
        $WebClient.DownloadFile("https://$Appliance/Safeguard.msi", $TempFile)
    }
    Write-Host "Uninstalling previous build..."
    try
    {
        $Key = ((& reg query $UninstallKey /s /v DisplayName | Select-String "Safeguard" -Context 1,0).ToString().Split("`n") | Select-String HKEY).ToString().Trim()
        $UninstallCmd = (& reg query $Key /v UninstallString | Select-String "UninstallString").ToString()
    }
    catch
    {}
    if ($UninstallCmd)
    {
        $CmdArray = $UninstallCmd.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
        Start-Process $CmdArray[2] -ArgumentList "$($CmdArray[3]) /quiet /passive" -Verb RunAs -Wait
    }
    else
    {
        Write-Host "Not currently installed."
    }

    Write-Host "Installing..."
    Start-Process msiexec.exe -ArgumentList "/i $TempFile /quiet /passive" -Verb RunAs -Wait
    }
    finally
    {
        if ($Insecure)
        {
            Enable-SslVerification
        }
    }
}
