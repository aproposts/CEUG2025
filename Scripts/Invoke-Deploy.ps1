[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory)]
    [ValidateSet(
        'Development',
        'Test_A',
        'Test_B',
        'Pre-Production',
        'Production'
    )]
    [string]
    $Build,

    [Parameter(Mandatory)]
    [string]
    $ComputerName,

    [Parameter()]
    [pscredential]
    $Credential,

    [Parameter()]
    [timespan]
    $Timeout = (New-TimeSpan -Seconds 30),
    
    [Parameter()]
    [string]
    $LogPath,

    [Parameter()]
    [switch]
    $LogAppend
)

$buildDir = "$PSScriptRoot\builds\$Build"

$logFile = switch ($LogPath) {
    { -not $_ } {
        "$buildDir\deploy.log" | ForEach-Object {
            if (Test-Path $_) {
                Get-Item $_
            }
            else {
                New-Item $_
            }
        }
    }
    { $_ -and -not (Test-Path $_) } {
        New-Item $_ -ErrorAction Stop
    }
    default {
        Get-Item $_ -ErrorAction Stop
    }
}

$startTranscriptSplat = @{
    Path             = $logFile.FullName
    UseMinimalHeader = $true
}
if ($LogAppend) {
    $startTranscriptSplat.Append = $LogAppend
}

$cmdFile = Get-ChildItem $buildDir -Filter '*.deploy.cmd' -ErrorAction Stop
$paramFile = Get-ChildItem $buildDir -Filter '*.SetParameters.xml' -ErrorAction Stop
$deployFile = Get-ChildItem $buildDir -Filter '*.zip' -ErrorAction Stop

'Setting deploy ZIP to inherit permissions:' | Write-Host
& icacls.exe $deployFile.FullName /inheritance:e | Write-Host

$paramXml = [xml]::new()
$paramXml.Load($paramFile.FullName)
$iisAppPath = $paramXml.SelectSingleNode('//setParameter[@name="IIS Web Application Name"]').value
$iisSiteName = $iisAppPath.Split('/')[0]

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.UseShellExecute = $false
$startInfo.FileName = $cmdFile.FullName
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true

if ($Credential) {
    $startInfo.Domain = $Credential.GetNetworkCredential().Domain
    $startInfo.UserName = $Credential.GetNetworkCredential().UserName
    $startInfo.Password = $Credential.GetNetworkCredential().SecurePassword
}

$deployArgs = [ordered] @{
    ComputerName = "/M:$ComputerName"
}

if ($PSCmdlet.ShouldProcess($ComputerName, "Deploy build '$Build' to '$iisAppPath'")) {

    $deployArgs.Deploy = '/Y'

    Start-Transcript @startTranscriptSplat

    "Stopping running application pools for site '$iisSiteName' on $ComputerName..." |
    Write-Host

    $invokeCommandSplat = @{
        ComputerName = $ComputerName
        ErrorAction  = 'Stop'
    }
    if ($Credential) { $invokeCommandSplat.Credential = $Credential }

    $iisAppPools = Invoke-Command @invokeCommandSplat {
        $VerbosePreference = $using:VerbosePreference

        Get-IISSite $using:iisSiteName | ForEach-Object {
            $_.Applications.ApplicationPoolName | 
            Get-Unique | 
            Get-IISAppPool |
            Where-Object State -eq Started
        } | ForEach-Object {
            '{0}: {1}' -f $_.Name, $_.Stop() | 
            Write-Host

            $_
        }
    }
}
else {
    $deployArgs.Deploy = '/T'
}

$startInfo.Arguments = $deployArgs.Values -join ' '

try {
    $process = [System.Diagnostics.Process]::Start($startInfo)

    while (-not $process.StandardOutput.EndOfStream -or 
        -not $process.StandardError.EndOfStream -or 
        -not $process.HasExited
    ) {
        switch ($process) {
            { -not $_.StandardOutput.EndOfStream } {
                $_.StandardOutput.ReadToEnd() -split "`n"
            }
            { -not $_.StandardError.EndOfStream } {
                $_.StandardError.ReadToEnd() | 
                Write-Error -ErrorAction Stop
            }
        }
    }
}
catch {
    throw $_
}
finally {
    if (-not $process.HasExited -and -not $process.WaitForExit($Timeout)) {
        $process.Kill($true)
        $process.WaitForExit()
    }
    $process.Close()
}

if ($iisAppPools) {
    "Restarting application pools for site '$iisSiteName' on $ComputerName..." | 
    Write-Host

    Invoke-Command @invokeCommandSplat {
        $VerbosePreference = $using:VerbosePreference

        Get-IISSite $using:iisSiteName | ForEach-Object {
            $_.Applications.ApplicationPoolName | 
            Get-Unique | 
            Get-IISAppPool |
            Where-Object Name -in $using:iisAppPools.Name
        } | ForEach-Object {
            '{0}: {1}' -f $_.Name, $_.Start() | 
            Write-Host
        }
    }
}

Stop-Transcript