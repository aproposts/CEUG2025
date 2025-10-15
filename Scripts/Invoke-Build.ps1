[CmdletBinding()]
param (
    [Parameter(Mandatory,ValueFromPipeline)]
    [ValidateSet(
        'Development',
        'Test_A',
        'Test_B',
        'Pre-Production',
        'Production'
    )]
    [string]
    $PublishProfile,

    [Parameter()]
    [string]
    $LogPath,

    [Parameter()]
    [switch]
    $LogAppend,

    [Parameter()]
    [ValidateSet(
        'Quiet',
        'Minimal',
        'Normal',
        'Detailed',
        'Diagnostic'
    )]
    [string]
    $LogVerbosity = 'Normal'
)

begin {
    $projFile = "$PSScriptRoot\source\Ellucian.Web.Student\Ellucian.Web.Student\Ellucian.Web.Student.csproj" |
    Get-Item -ErrorAction Stop
}

process {
    $projFile | Split-Path | 
    Join-Path -ChildPath "Properties\PublishProfiles\$PublishProfile.pubxml" | 
    ForEach-Object {
        if (-not (Test-Path $_)) {
            'No file for PublishProfile "{0}" at location "{1}"' -f $PublishProfile, $_ |
            Write-Error -ErrorAction Stop
        }
    }
    
    $logFile = switch ($LogPath) {
        { -not $_ } {
            "$PSScriptRoot\builds\$PublishProfile\build.log" | ForEach-Object {
                if (Test-Path $_) {
                    Get-Item $_
                }
                else {
                    New-Item $_ -Force
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

    # https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/visual-studio-publish-profiles?view=aspnetcore-9.0
    
    $dotnetArgs = @(
        'publish'
        $projFile.FullName
        '-p:Configuration=Release'
        '-p:PublishProfile={0}' -f $PublishProfile
        '-verbosity:detailed'
        '-fileLoggerParameters:Verbosity={0};logfile={1};Append={2}' -f @(
            $LogVerbosity
            $logFile.FullName
            $LogAppend
        )
    )
    
    & dotnet @dotnetArgs
}

