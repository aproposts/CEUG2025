#Region 'PREFIX' -1

param (
    [Parameter()]
    [string]
    $importConfigPath
)
#EndRegion 'PREFIX'
#Region '.\Private\private.ps1' -1

function convertToHashtable {
    [OutputType([hashtable])]
    param(
        [Parameter(ValueFromPipeline)]    
        [psobject] $InputObject
    )

    process {
        $hashtable = @{}
    
        foreach ($property in $InputObject.psobject.Properties) {
            $hashtable.Add($property.Name, $property.Value) | Out-Null
        }
    
        return $hashtable
    }
}

function joinHashtables {
    [OutputType([hashtable])]
    param(
        [Parameter(ValueFromPipeline)]
        [hashtable[]] $Hashtable
    )

    begin {
        $joined = @{}
    }

    process {
        $Hashtable | ForEach-Object {
            foreach ($key in $_.Keys) {
                $joined[$key] = $_[$key]
            }
        }
    }

    end {
        return $joined
    }
}

function filterHashtable {
    [OutputType([hashtable])]
    param(
        [Parameter(ValueFromPipeline)]
        [hashtable] $Hashtable,
        [string[]] $IncludeKeys,
        [string[]] $ExcludeKeys
    )

    process {
        $filtered = @{}

        $Hashtable.GetEnumerator() |
        Where-Object Key -notin $ExcludeKeys |
        Where-Object {
            if ($IncludeKeys) { $_.Key -in $IncludeKeys }
        } |
        ForEach-Object {
            $filtered.Add($_.Key, $_.Value) | Out-Null
        }

        return $filtered
    }
}

function labelHandler {

    $colleagueSites = (Get-ColleagueSitesConfig).Sites |
    Where-Object Label -like $Label
    
    if (-not $colleagueSites) {
        'No Colleague site with Label like "{0}"' -f $Label |
        Write-Error

        return
    }

    $caller = (Get-PSCallStack)[1]
    $callerBoundParameters = $caller.InvocationInfo.BoundParameters

    $colleagueSites | ForEach-Object {
        $callerBoundParameters.Remove('Label') | Out-Null
        $siteLabel = $_.Label

        $compareObjectSplat = @{
            ReferenceObject  = (
                $_.psobject.Properties.Name
            )
            DifferenceObject = $(
                $caller.InvocationInfo.MyCommand.Parameters.Keys
            )
            IncludeEqual     = $true
            ExcludeDifferent = $true
        }

        $properties = Compare-Object @compareObjectSplat |
        Select-Object -ExpandProperty InputObject

        $recallSplat = @(
            ($_ | 
            Select-Object $properties -ExcludeProperty Label |
            convertToHashtable),
            $callerBoundParameters
        ) | joinHashtables

        if (
            $recallSplat.ContainsKey('Uri') -and 
            -not $recallSplat.ContainsKey('ComputerName') -and 
            ($uriHost = ([uri] $recallSplat.Uri).Host) -notmatch "^$env:COMPUTERNAME"
        ) {
            $recallSplat.ComputerName = $uriHost
        }

        & $caller.Command @recallSplat | 
        ForEach-Object {
            $_ | Add-Member -Force -PassThru @{ ColleagueSiteLabel = $siteLabel }
        }
    }
}

function invokeRemotely {
    [CmdletBinding()]
    param (
        # [Parameter(Mandatory)]
        # [hashtable]
        # $Parameters,
        # Parameter help description
        [Parameter()]
        [System.Management.Automation.CallStackFrame]
        $CallStackFrame = (Get-PSCallStack)[0],

        [Parameter()]
        [string]
        $ComputerName,

        [Parameter()]
        [pscredential]
        $Credential = (Get-ColleagueSitesCredential),

        [Parameter()]
        [switch]
        $AsJob,

        [Parameter()]
        [string]
        $JobName,

        [Parameter(ValueFromRemainingArguments)]
        [psobject[]]
        $Remaining
    )

    if (-not $PSBoundParameters.ContainsKey('Credential') -and $Credential) {
        $PSBoundParameters.Add('Credential', $Credential) | Out-Null
    }

    $invokeCommandSplat = @{}

    $PSBoundParameters.GetEnumerator() |
    Where-Object Key -in (Get-Command Invoke-Command).Parameters.Keys |
    Where-Object Key -notin [System.Management.Automation.PSCmdlet]::CommonParameters |
    Where-Object Key -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters |
    ForEach-Object {
        $invokeCommandSplat[$_.Key] = $_.Value
    }

    $commandParameters = @{}

    $CallStackFrame.InvocationInfo.BoundParameters.GetEnumerator() |
    Where-Object Key -notin $invokeCommandSplat.Keys |
    ForEach-Object {
        $commandParameters[$_.Key] = $_.Value
    }

    $command = $CallStackFrame.Command | Get-Command
    $module = $command.Module

    $preferenceVariables = @{}
    
    Get-Variable '*Preference' | 
    ForEach-Object {
        $preferenceVariables[$_.Name] = $_.Value
    }

    $invokeCommandSplat.ArgumentList = @(
        $commandParameters
        $command
        $module
        $preferenceVariables
    )

    Invoke-Command @invokeCommandSplat {
        [CmdletBinding()]
        param(
            $commandParameters,
            $command,
            $module,
            $preferenceVariables
        )

        $newModuleSplat = @{
            Name        = $module.Name
            ScriptBlock = [scriptblock]::Create($module.Definition)
        }

        New-Module @newModuleSplat |
        Import-Module

        $preferenceVariables.GetEnumerator() | ForEach-Object {
            Set-Variable -Name $_.Key -Value $_.Value
        }

        if ($commandParameters) {
            & $command @commandParameters
        }
        else {
            & $command
        }
    }
}
#EndRegion '.\Private\private.ps1' 223
#Region '.\Public\ColleagueSiteApplicationPool\Get-ColleagueSiteApplicationPool.ps1' -1

function Get-ColleagueSiteApplicationPool {
    <#
    .SYNOPSIS
    Gets IIS application pools for Colleague site applications.

    .DESCRIPTION
    Retrieves the IIS application pools associated with Colleague site applications. Can target specific applications by label, URI, site name, or application path to return their corresponding application pools.

    .PARAMETER Label
    The label of the Colleague site as defined in the configuration.

    .PARAMETER Uri
    The URI to match against site bindings and application paths.

    .PARAMETER SiteName
    The name of the IIS site containing the application.

    .PARAMETER ApplicationPath
    The path of the application within the site.

    .PARAMETER ComputerName
    The name of the remote computer to query.

    .PARAMETER Credential
    Credentials to use for remote operations.

    .INPUTS
    String
    Accepts site names, labels, and computer names from the pipeline.

    .OUTPUTS
    Microsoft.Web.Administration.ApplicationPool
    Returns IIS application pool objects.

    .EXAMPLE
    Get-ColleagueSiteApplicationPool -Label "Production"
    Gets the application pool for the "Production" site.

    .EXAMPLE
    Get-ColleagueSiteApplicationPool -SiteName "MyColleagueApp"
    Gets the application pool for the specified site.

    .EXAMPLE
    Get-ColleagueSiteApplicationPool -Uri "https://colleague.example.com/api"
    Gets the application pool for the application matching the URI.

    .EXAMPLE
    Get-ColleagueSiteApplicationPool | Where-Object State -eq 'Stopped'
    Gets all application pools and filters for stopped ones.

    .NOTES
    This function returns the actual application pool objects, which can be used with other IIS management cmdlets.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias('Get-CSAppPool')]
    param (
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [ValidateScript({
                (Get-ColleagueSitesConfig).Sites |
                Where-Object Label -like $_
            })]
        [Alias('ColleagueSiteLabel')]
        [string]
        $Label,

        [Parameter()]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [uri]
        $Uri,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $SiteName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Path')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $ApplicationPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('PSComputerName')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $ComputerName,

        [Parameter()]
        [pscredential]
        $Credential
    )

    process {
        if ($Label) { return labelHandler }
        if ($ComputerName) { return invokeRemotely @PSBoundParameters }

        $app = try {
            Get-ColleagueSiteApplication @PSBoundParameters -ErrorAction Stop
        }
        catch {
            $_ | Write-Error -ErrorAction Stop
        }

        $app.ApplicationPoolName | 
        Get-Unique | 
        ForEach-Object {
            Get-IISAppPool $_
        }
    }
}
#EndRegion '.\Public\ColleagueSiteApplicationPool\Get-ColleagueSiteApplicationPool.ps1' 113
#Region '.\Public\ColleagueSiteApplicationPool\Restart-ColleagueSiteApplicationPool.ps1' -1

function Restart-ColleagueSiteApplicationPool {
    <#
    .SYNOPSIS
    Restarts IIS application pools for Colleague site applications.

    .DESCRIPTION
    Restarts the IIS application pools associated with Colleague site applications. The function will stop the application pool, wait for it to fully stop, then start it again. Can target specific applications by label, URI, site name, or application path.

    .PARAMETER Label
    The label of the Colleague site as defined in the configuration.

    .PARAMETER Uri
    The URI to match against site bindings and application paths.

    .PARAMETER SiteName
    The name of the IIS site containing the application.

    .PARAMETER ApplicationPath
    The path of the application within the site.

    .PARAMETER ComputerName
    The name of the remote computer to operate on.

    .PARAMETER Credential
    Credentials to use for remote operations.

    .INPUTS
    String
    Accepts site names, labels, and computer names from the pipeline.

    .EXAMPLE
    Restart-ColleagueSiteApplicationPool -Label "Production"
    Restarts the application pool for the "Production" site.

    .EXAMPLE
    Restart-ColleagueSiteApplicationPool -SiteName "MyColleagueApp"
    Restarts the application pool for the specified site.

    .EXAMPLE
    Restart-CSAppPool -Uri "https://colleague.example.com/api"
    Restarts the application pool for the application matching the URI using the alias.

    .NOTES
    This function will display the status of the restart operation and wait for the application pool to fully stop before starting it again.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias('Restart-CSAppPool')]
    param (
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [ValidateScript({
                (Get-ColleagueSitesConfig).Sites |
                Where-Object Label -like $_
            })]
        [Alias('ColleagueSiteLabel')]
        [string]
        $Label,

        [Parameter()]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [uri]
        $Uri,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $SiteName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Path')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $ApplicationPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('PSComputerName')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $ComputerName,

        [Parameter()]
        [pscredential]
        $Credential
    )

    process {
        if ($Label) { return labelHandler }
        if ($ComputerName) { return invokeRemotely @PSBoundParameters }

        $PSBoundParameters | Out-String | Write-Debug

        $app = try {
            Get-ColleagueSiteApplication @PSBoundParameters -ErrorAction Stop
        }
        catch {
            $_ | Write-Error -ErrorAction Stop
        }

        $app | Out-String | Write-Debug

        $app.ApplicationPoolName | 
        Get-Unique | 
        ForEach-Object {
            $appPool = Get-IISAppPool $_

            'Stopping application pool "{0}".' -f $_ |
            Write-Host -NoNewline

            $appPool.Stop() | Out-Null

            while ($appPool.State -ne 'Stopped') {
                Start-Sleep -Seconds 1
                Write-Host -NoNewline '.'
            }

            ' {0}.' -f $appPool.State | Write-Host

            '{0} application pool "{1}".' -f $appPool.Start(), $_ |
            Write-Host
        }
    }
}
#EndRegion '.\Public\ColleagueSiteApplicationPool\Restart-ColleagueSiteApplicationPool.ps1' 124
#Region '.\Public\ColleagueSiteApplicationPool\Start-ColleagueSiteApplicationPool.ps1' -1

function Start-ColleagueSiteApplicationPool {
    <#
    .SYNOPSIS
    Starts IIS application pools for Colleague site applications.

    .DESCRIPTION
    Starts the IIS application pools associated with Colleague site applications. Can target specific applications by label, URI, site name, or application path.

    .PARAMETER Label
    The label of the Colleague site as defined in the configuration.

    .PARAMETER Uri
    The URI to match against site bindings and application paths.

    .PARAMETER SiteName
    The name of the IIS site containing the application.

    .PARAMETER ApplicationPath
    The path of the application within the site.

    .PARAMETER ComputerName
    The name of the remote computer to operate on.

    .PARAMETER Credential
    Credentials to use for remote operations.

    .INPUTS
    String
    Accepts site names, labels, and computer names from the pipeline.

    .EXAMPLE
    Start-ColleagueSiteApplicationPool -Label "Production"
    Starts the application pool for the "Production" site.

    .EXAMPLE
    Start-ColleagueSiteApplicationPool -SiteName "MyColleagueApp"
    Starts the application pool for the specified site.

    .EXAMPLE
    Start-CSAppPool -Uri "https://colleague.example.com/api"
    Starts the application pool for the application matching the URI using the alias.

    .NOTES
    This function will display the status of the start operation for each application pool.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias('Start-CSAppPool')]
    param (
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [ValidateScript({
                (Get-ColleagueSitesConfig).Sites |
                Where-Object Label -like $_
            })]
        [Alias('ColleagueSiteLabel')]
        [string]
        $Label,

        [Parameter()]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [uri]
        $Uri,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $SiteName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Path')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $ApplicationPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('PSComputerName')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $ComputerName,

        [Parameter()]
        [pscredential]
        $Credential
    )

    process {
        if ($Label) { return labelHandler }
        if ($ComputerName) { return invokeRemotely @PSBoundParameters }

        $app = try {
            Get-ColleagueSiteApplication @PSBoundParameters -ErrorAction Stop
        }
        catch {
            $_ | Write-Error -ErrorAction Stop
        }

        $app.ApplicationPoolName | 
        Get-Unique | 
        ForEach-Object {
            $appPool = Get-IISAppPool $_

            '{0} application pool "{1}".' -f $appPool.Start(), $_ |
            Write-Host
        }
    }
}
#EndRegion '.\Public\ColleagueSiteApplicationPool\Start-ColleagueSiteApplicationPool.ps1' 108
#Region '.\Public\ColleagueSiteApplicationPool\Stop-ColleagueSiteApplicationPool.ps1' -1

function Stop-ColleagueSiteApplicationPool {
    <#
    .SYNOPSIS
    Stops IIS application pools for Colleague site applications.

    .DESCRIPTION
    Stops the IIS application pools associated with Colleague site applications. Can target specific applications by label, URI, site name, or application path.

    .PARAMETER Label
    The label of the Colleague site as defined in the configuration.

    .PARAMETER Uri
    The URI to match against site bindings and application paths.

    .PARAMETER SiteName
    The name of the IIS site containing the application.

    .PARAMETER ApplicationPath
    The path of the application within the site.

    .PARAMETER ComputerName
    The name of the remote computer to operate on.

    .PARAMETER Credential
    Credentials to use for remote operations.

    .INPUTS
    String
    Accepts site names, labels, and computer names from the pipeline.

    .EXAMPLE
    Stop-ColleagueSiteApplicationPool -Label "Production"
    Stops the application pool for the "Production" site.

    .EXAMPLE
    Stop-ColleagueSiteApplicationPool -SiteName "MyColleagueApp"
    Stops the application pool for the specified site.

    .EXAMPLE
    Stop-CSAppPool -Uri "https://colleague.example.com/api"
    Stops the application pool for the application matching the URI using the alias.

    .NOTES
    This function will display the status of the stop operation for each application pool.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias('Stop-CSAppPool')]
    param (
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [ValidateScript({
                (Get-ColleagueSitesConfig).Sites |
                Where-Object Label -like $_
            })]
        [Alias('ColleagueSiteLabel')]
        [string]
        $Label,

        [Parameter()]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [uri]
        $Uri,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $SiteName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Path')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $ApplicationPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('PSComputerName')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $ComputerName,

        [Parameter()]
        [pscredential]
        $Credential
    )

    process {
        if ($Label) { return labelHandler }
        if ($ComputerName) { return invokeRemotely @PSBoundParameters }

        $app = try {
            Get-ColleagueSiteApplication @PSBoundParameters -ErrorAction Stop
        }
        catch {
            $_ | Write-Error -ErrorAction Stop
        }

        $app.ApplicationPoolName | 
        Get-Unique | 
        ForEach-Object {
            $appPool = Get-IISAppPool $_

            '{0} application pool "{1}".' -f $appPool.Stop(), $_ |
            Write-Host
        }
    }
}
#EndRegion '.\Public\ColleagueSiteApplicationPool\Stop-ColleagueSiteApplicationPool.ps1' 108
#Region '.\Public\ColleagueSitesArgumentCompleter.ps1' -1

function ColleagueSitesArgumentCompleter {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.CompletionResult])]
    param(
        [string] $CommandName,
        [string] $ParameterName,
        [string] $WordToComplete,
        [System.Management.Automation.Language.CommandAst] $CommandAst,
        [System.Collections.IDictionary] $FakeBoundParameters
    )
    
    $CompletionResults = [System.Collections.Generic.List[System.Management.Automation.CompletionResult]]::new()

    $otherSiteParameterKeys = [System.Collections.Generic.List[string]]::new()

    $sitePropertyNames = (Get-ColleagueSitesConfig Sites) | 
    ForEach-Object { $_.psobject.Properties.Name } | 
    Sort-Object -Unique

    $FakeBoundParameters.GetEnumerator() | 
    Where-Object {
        $_.Key -in $sitePropertyNames -and
        $_.Key -ne $ParameterName
    } | 
    ForEach-Object {
        $otherSiteParameterKeys.Add($_.Key) | Out-Null
    }
    
    Get-ColleagueSitesConfig Sites | 
    Where-Object {
        if ($otherSiteParameterKeys) {
            $otherSiteParameterKeys.TrueForAll({ 
                    param($key) $_.$key -like $FakeBoundParameters[$key] 
                })
        }
        else {
            $true
        }
    } |
    Where-Object $ParameterName -like "$WordToComplete*" | 
    Select-Object -ExpandProperty $ParameterName | 
    Sort-Object -Unique | 
    ForEach-Object {
        $CompletionResults.Add($_) | Out-Null
    }
        
    return $CompletionResults
}
#EndRegion '.\Public\ColleagueSitesArgumentCompleter.ps1' 49
#Region '.\Public\ColleagueSitesConfig\Export-ColleagueSitesConfig.ps1' -1

function Export-ColleagueSitesConfig {
    <#
    .SYNOPSIS
    Exports ColleagueSites configuration to a JSON file.

    .DESCRIPTION
    Exports the current configuration to a JSON file. Credentials are excluded from the export for security reasons.

    .PARAMETER Config
    Optional. The configuration object to export. If not specified, uses the current configuration.

    .PARAMETER Path
    Optional. The path where the configuration will be saved. If not specified, uses the default configuration path.

    .INPUTS
    PSCustomObject
    Accepts configuration objects from the pipeline.

    .EXAMPLE
    Export-ColleagueSitesConfig
    Exports the current configuration to the default path.

    .EXAMPLE
    Export-ColleagueSitesConfig -Path "C:\MyConfig\config.json"
    Exports the configuration to a specific file.

    .EXAMPLE
    $config | Export-ColleagueSitesConfig
    Exports a configuration object from the pipeline.
    #>
    [CmdletBinding()]
    [Alias('Export-CSConfig')]
    param (
        [Parameter(ValueFromPipeline)]
        [PSCustomObject]
        $Config = (Get-ColleagueSitesConfig),

        [Parameter()]
        [string]
        $Path = (Get-ColleagueSitesConfig).ConfigPath
    )

    begin {
        if (-not $PSBoundParameters.ContainsKey('Path') -and
            -not (Test-Path $Path)
        ) {
            New-Item $Path -Force | Out-Null
        }
    }

    process {
        $Config | 
        Select-Object -Property '*' -ExcludeProperty '*Credential' |
        ConvertTo-Json | 
        Set-Content $Path -ErrorAction Stop
    }
}
#EndRegion '.\Public\ColleagueSitesConfig\Export-ColleagueSitesConfig.ps1' 58
#Region '.\Public\ColleagueSitesConfig\Get-ColleagueSitesConfig.ps1' -1

function Get-ColleagueSitesConfig {
    <#
    .SYNOPSIS
    Gets the ColleagueSites configuration.

    .DESCRIPTION
    Retrieves the current ColleagueSites configuration. If no configuration is loaded, it will attempt to import from the default configuration paths.

    .PARAMETER Property
    Optional. Specifies a specific property to retrieve from the configuration. Valid values are:
    - Sites
    - ConfigPath
    - WarmUpScriptFileName
    - WarmUpCredentialPath
    - WarmUpCredential
    - Credential

    .OUTPUTS
    PSCustomObject
    Returns the complete configuration object, or the specified property value if Property parameter is used.

    .EXAMPLE
    Get-ColleagueSitesConfig
    Gets the complete configuration object.

    .EXAMPLE
    Get-ColleagueSitesConfig -Property Sites
    Gets only the Sites property from the configuration.

    .EXAMPLE
    Get-CSConfig
    Gets the configuration using the alias.
    #>
    [CmdletBinding()]
    [Alias('Get-CSConfig')]
    param(
        [Parameter()]
        [ValidateSet(
            'Sites',
            'ConfigPath',
            'WarmUpScriptFileName',
            'WarmUpCredentialPath',
            'WarmUpCredential',
            'Credential'
        )]
        [string]
        $Property
    )

    if (-not $Script:config) {
        Import-ColleagueSitesConfig $importConfigPath |
        Set-ColleagueSitesConfig
    }

    if ($Property) {
        $Script:config | 
        Select-Object -ExpandProperty $Property
    }
    else {
        $Script:config
    }
}
#EndRegion '.\Public\ColleagueSitesConfig\Get-ColleagueSitesConfig.ps1' 63
#Region '.\Public\ColleagueSitesConfig\Import-ColleagueSitesConfig.ps1' -1

function Import-ColleagueSitesConfig {
    <#
    .SYNOPSIS
    Imports ColleagueSites configuration from JSON files.

    .DESCRIPTION
    Imports configuration settings from JSON files. If no path is specified, searches for configuration files in default locations including the module directory, ProgramData, and user's local application data.

    .PARAMETER Path
    Optional. Specifies one or more paths to configuration files. If not specified, searches default locations.

    .INPUTS
    String[]
    Accepts file paths from the pipeline.

    .OUTPUTS
    PSCustomObject
    Returns configuration objects loaded from the specified files.

    .EXAMPLE
    Import-ColleagueSitesConfig
    Imports configuration from default locations.

    .EXAMPLE
    Import-ColleagueSitesConfig -Path "C:\MyConfig\config.json"
    Imports configuration from a specific file.

    .EXAMPLE
    "C:\Config1.json", "C:\Config2.json" | Import-ColleagueSitesConfig
    Imports configuration from multiple files via pipeline.
    #>
    [CmdletBinding()]
    [Alias('Import-CSConfig')]
    param (
        [Parameter(ValueFromPipeline)]
        [string[]]
        $Path
    )

    begin {
        $locations = @()
    }

    process {
        $locations += if ($Path) { 
            $Path | ForEach-Object {
                Resolve-Path $_ -ErrorAction Stop
            }
        }
        else {
            @(
                "$PSScriptRoot\config.json"
                @(
                    $env:ProgramData
                    $MyInvocation.MyCommand.ModuleName
                    'config.json'
                ) -join [System.IO.Path]::DirectorySeparatorChar
                @(
                    $env:LOCALAPPDATA
                    $MyInvocation.MyCommand.ModuleName
                    'config.json'
                ) -join [System.IO.Path]::DirectorySeparatorChar
            ) | 
            Where-Object {
                -not [string]::IsNullOrEmpty($_) -and 
                (Test-Path $_)
            } |
            ForEach-Object {
                Resolve-Path $_
            }
        }
    }

    end {
        $locations |
        Get-Item -PipelineVariable configFile | 
        ForEach-Object {
            Get-Content $_ |
            ConvertFrom-Json |
            Add-Member -Force -PassThru @{ ConfigPath = $configFile.FullName }
        }
    }
}
#EndRegion '.\Public\ColleagueSitesConfig\Import-ColleagueSitesConfig.ps1' 84
#Region '.\Public\ColleagueSitesConfig\New-ColleagueSitesConfig.ps1' -1

function New-ColleagueSitesConfig {
    <#
    .SYNOPSIS
    Creates a new ColleagueSites configuration object.

    .DESCRIPTION
    Creates a new ColleagueSites configuration object with default values. This object contains settings for sites, configuration paths, warm-up scripts, and credentials.

    .OUTPUTS
    PSCustomObject
    Returns a configuration object with the following properties:
    - Sites: Array of site objects with Label and Uri properties
    - ConfigPath: Path to the configuration file
    - WarmUpScriptFileName: Name of the warm-up script file
    - WarmUpCredentialPath: Path to the warm-up credential file
    - WarmUpCredential: PSCredential object for warm-up operations
    - Credential: PSCredential object for site operations

    .EXAMPLE
    $config = New-ColleagueSitesConfig
    Creates a new configuration object with default values.

    .EXAMPLE
    New-CSConfig
    Creates a new configuration object using the alias.
    #>
    [CmdletBinding()]
    [Alias('New-CSConfig')]
    param()

    [pscustomobject] @{
        Sites                = @(
            [pscustomobject] @{
                Label = ''
                Uri   = ''
            }
        )
        ConfigPath           = @()
        WarmUpScriptFileName = 'WarmUp.ps1'
        WarmUpCredentialPath = @(
            $env:LOCALAPPDATA
            $MyInvocation.MyCommand.ModuleName
            'WarmUpCredential.clixml'
        ) -join [System.IO.Path]::DirectorySeparatorChar
        WarmUpCredential     = $null
        Credential           = $null
    }
}
#EndRegion '.\Public\ColleagueSitesConfig\New-ColleagueSitesConfig.ps1' 49
#Region '.\Public\ColleagueSitesConfig\Set-ColleagueSitesConfig.ps1' -1

function Set-ColleagueSitesConfig {
    <#
    .SYNOPSIS
    Sets the ColleagueSites configuration.

    .DESCRIPTION
    Updates the module's configuration with values from the provided configuration object. Only properties that exist in the default configuration will be updated.

    .PARAMETER ColleagueSitesConfig
    Configuration object containing the settings to apply.

    .INPUTS
    PSCustomObject[]
    Accepts configuration objects from the pipeline.

    .EXAMPLE
    $config = New-ColleagueSitesConfig
    $config.Sites = @(@{Label='Dev'; Uri='https://dev.example.com'})
    Set-ColleagueSitesConfig $config
    Sets the configuration with a custom site definition.

    .EXAMPLE
    Get-ColleagueSitesConfig | Set-ColleagueSitesConfig
    Resets the configuration to current values.
    #>
    [CmdletBinding()]
    [Alias('Set-CSConfig')]
    param (
        [Parameter(ValueFromPipeline)]
        [PSCustomObject[]]
        $ColleagueSitesConfig
    )

    begin {
        $Script:config = New-ColleagueSitesConfig
    }

    process {
        $ColleagueSitesConfig | ForEach-Object {
            $_.psobject.Properties.Name | Where-Object {
                $_ -in $Script:config.psobject.Properties.Name
            } | ForEach-Object {
                if ($_ -in @('ConfigPath')) {
                    $Script:config.$_ += $ColleagueSitesConfig.$_
                }
                else {
                    $Script:config.$_ = $ColleagueSitesConfig.$_
                }
            }   
        }
    }
}
#EndRegion '.\Public\ColleagueSitesConfig\Set-ColleagueSitesConfig.ps1' 53
#Region '.\Public\ColleagueSitesCredential\Get-ColleagueSitesCredential.ps1' -1

function Get-ColleagueSitesCredential {
    <#
    .SYNOPSIS
    Gets the credential for ColleagueSites operations.

    .DESCRIPTION
    Retrieves the credential that will be used for ColleagueSites operations. If no credential is set in the configuration, attempts to find one from the call stack.

    .OUTPUTS
    PSCredential
    Returns the credential object for ColleagueSites operations.

    .EXAMPLE
    $cred = Get-ColleagueSitesCredential
    Gets the current credential for ColleagueSites operations.

    .EXAMPLE
    Get-CSCredential
    Gets the credential using the alias.
    #>
    [CmdletBinding()]
    [Alias('Get-CSCredential')]
    param()

    if ($credential = Get-ColleagueSitesConfig Credential) {
        return $credential
    }
    else {
        Get-PSCallStack |
        Where-Object {
            $_.InvocationInfo.BoundParameters.ContainsKey('Credential')
        } | 
        Select-Object -First 1 |
        ForEach-Object {
            $credential = $_.InvocationInfo.BoundParameters.Credential

            'Using call stack credential for {0}.' -f $credential.UserName | 
            Write-Verbose

            return $credential
        }
    }
}
#EndRegion '.\Public\ColleagueSitesCredential\Get-ColleagueSitesCredential.ps1' 44
#Region '.\Public\ColleagueSitesCredential\Set-ColleagueSitesCredential.ps1' -1

function Set-ColleagueSitesCredential {
    <#
    .SYNOPSIS
    Sets the credential for ColleagueSites operations.

    .DESCRIPTION
    Sets the credential that will be used for ColleagueSites operations. If no credential is provided, prompts the user for username and password.

    .PARAMETER Credential
    Optional. The PSCredential object to use for authentication. If not provided, prompts for credentials.

    .INPUTS
    PSCredential
    Accepts credential objects from the pipeline.

    .EXAMPLE
    Set-ColleagueSitesCredential
    Prompts for username and password and sets the credential.

    .EXAMPLE
    $cred = Get-Credential
    Set-ColleagueSitesCredential -Credential $cred
    Sets the credential using an existing PSCredential object.

    .EXAMPLE
    Get-Credential | Set-ColleagueSitesCredential
    Sets the credential from pipeline input.
    #>
    [CmdletBinding()]
    [Alias('Set-CSCredential')]
    param(
        [Parameter(ValueFromPipeline)]
        [pscredential]
        $Credential
    )

    process {
        if (-not $Credential) {
            try {
                # Use Read-Host to prevent Windows Powershell from trying to use the
                # GUI in certain types of remote sessions.
            
                $username = Read-Host -Prompt 'ColleagueSites Username'
                $password = Read-Host -Prompt 'ColleagueSites Password' -AsSecureString 
                $Credential = [pscredential]::new($username, $password)
            }
            catch {
                'Failed reading credential.' | 
                Write-Error -ErrorAction Stop
            }
        }

        $local:config = Get-ColleagueSitesConfig

        $local:config.Credential = $Credential

        Set-ColleagueSitesConfig $local:config
    }
}
#EndRegion '.\Public\ColleagueSitesCredential\Set-ColleagueSitesCredential.ps1' 60
#Region '.\Public\Get-ColleagueSite.ps1' -1

function Get-ColleagueSite {
    <#
    .SYNOPSIS
    Gets IIS sites configured for Colleague operations.

    .DESCRIPTION
    Retrieves IIS sites based on various criteria including label, URI, site name, or computer name. Can operate on local or remote machines.

    .PARAMETER Label
    The label of the Colleague site as defined in the configuration.

    .PARAMETER Uri
    The URI to match against site bindings.

    .PARAMETER SiteName
    The name of the IIS site to retrieve.

    .PARAMETER ComputerName
    The name of the remote computer to query.

    .PARAMETER Credential
    Credentials to use for remote operations.

    .INPUTS
    String
    Accepts site names, labels, and computer names from the pipeline.

    .OUTPUTS
    Microsoft.Web.Administration.Site
    Returns IIS site objects.

    .EXAMPLE
    Get-ColleagueSite
    Gets all IIS sites on the local machine.

    .EXAMPLE
    Get-ColleagueSite -Label "Production"
    Gets the site with the "Production" label from configuration.

    .EXAMPLE
    Get-ColleagueSite -SiteName "MyColleagueApp"
    Gets the IIS site named "MyColleagueApp".

    .EXAMPLE
    Get-ColleagueSite -Uri "https://colleague.example.com"
    Gets the site that matches the specified URI.

    .EXAMPLE
    Get-CS -ComputerName "WebServer01"
    Gets sites from a remote computer using the alias.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias('Get-CS')]
    param (
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [ValidateScript({
                (Get-ColleagueSitesConfig).Sites |
                Where-Object Label -like $_
            })]
        [Alias('ColleagueSiteLabel')]
        [string]
        $Label,

        [Parameter()]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [uri]
        $Uri,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $SiteName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('PSComputerName')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $ComputerName,

        [Parameter()]
        [pscredential]
        $Credential
    )

    process {
        if ($Label) { return labelHandler }
        if ($ComputerName) { return invokeRemotely @PSBoundParameters }
    
        if ($SiteName) {
            $site = Get-IISSite | 
            Where-Object Name -like $SiteName
    
            if ($site) {
                return $site
            }
            else {
                'No site with name like "{0}".' -f $SiteName | 
                Write-Error
            }
        }
        elseif ($Uri) {
            $site = Get-IISSite -PipelineVariable site | 
            Where-Object {
                foreach ($bindingInfo in $_.Bindings.BindingInformation) {
                    $bindingInfo -match '(?<ip>\S+?):(?<port>\d+):(?<host>\S*)' |
                    Where-Object {
                        $Matches.port -eq $Uri.Port -and $(
                            if ($Uri.HostNameType -eq 'Dns') {
                                $Uri.Host -match [regex]::Escape($Matches.host)
                            }
                            else {
                                $Uri.Host -like $Matches.ip
                            }
                        )
                    } | 
                    ForEach-Object {
                        'Binding information "{0}" for site "{1}" matches Uri "{2}' -f @(
                            $bindingInfo
                            $site.Name
                            $Uri
                        ) | Write-Verbose
                        return $true
                    }
                }
            }
    
            if ($site) {
                return $site
            }
            else {
                'No site binding for Uri "{0}"' -f $Uri | 
                Write-Error
            }
        }
        else {
            return Get-IISSite
        }
    }
}
#EndRegion '.\Public\Get-ColleagueSite.ps1' 142
#Region '.\Public\Get-ColleagueSiteApplication.ps1' -1

function Get-ColleagueSiteApplication {
    <#
    .SYNOPSIS
    Gets IIS applications within Colleague sites.

    .DESCRIPTION
    Retrieves IIS applications from sites based on various criteria including label, URI, site name, or application path. Can operate on local or remote machines.

    .PARAMETER Label
    The label of the Colleague site as defined in the configuration.

    .PARAMETER Uri
    The URI to match against site bindings and application paths.

    .PARAMETER SiteName
    The name of the IIS site containing the application.

    .PARAMETER ApplicationPath
    The path of the application within the site.

    .PARAMETER ComputerName
    The name of the remote computer to query.

    .PARAMETER Credential
    Credentials to use for remote operations.

    .INPUTS
    String
    Accepts site names, labels, and computer names from the pipeline.

    .OUTPUTS
    Microsoft.Web.Administration.Application
    Returns IIS application objects.

    .EXAMPLE
    Get-ColleagueSiteApplication
    Gets all applications from all sites.

    .EXAMPLE
    Get-ColleagueSiteApplication -Label "Production"
    Gets applications from the site with the "Production" label.

    .EXAMPLE
    Get-ColleagueSiteApplication -SiteName "MyColleagueApp" -ApplicationPath "/api"
    Gets the "/api" application from the specified site.

    .EXAMPLE
    Get-CSApp -Uri "https://colleague.example.com/api"
    Gets the application that matches the specified URI using the alias.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias('Get-CSApp')]
    param (
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [ValidateScript({
                (Get-ColleagueSitesConfig).Sites |
                Where-Object Label -like $_
            })]
        [Alias('ColleagueSiteLabel')]
        [string]
        $Label,

        [Parameter()]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [uri]
        $Uri,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $SiteName,

        [Parameter()]
        [Alias('Path')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $ApplicationPath,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('PSComputerName')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $ComputerName,

        [Parameter()]
        [pscredential]
        $Credential
    )
    
    begin {
        
    }
    
    process {
        if ($Label) { return labelHandler }
        if ($ComputerName) { return invokeRemotely @PSBoundParameters }

        $site = try {
            if ($SiteName) {
                Get-ColleagueSite -Name $SiteName -ErrorAction Stop
            }
            elseif ($Uri) {
                Get-ColleagueSite -Uri $Uri -ErrorAction Stop
            }
            else {
                Get-ColleagueSite -ErrorAction Stop
            }
        }
        catch { $_ | Write-Error -ErrorAction Stop }
        

        $app = $site.Applications | 
        Where-Object {
            if ($ApplicationPath) {
                $_.Path -like "$ApplicationPath"
            }
            elseif ($Uri) {
                $_.Path -eq $Uri.AbsolutePath
            }
            else {
                $true
            }
        }

        if (-not $app) {
            if ($ApplicationPath) {
                'No site application with path like "{0}".' -f $ApplicationPath |
                Write-Error
            }
            elseif ($Uri) {
                'No site application for Uri path "{0}"' -f $Uri.AbsolutePath |
                Write-Error
            }
            else {
                'No site application for specified parameters: {0}' -f ($PSBoundParameters.Keys -join ', ') |
                Write-Error
            }
        }
        else {
            return $app
        }
    }
    
    end {
        
    }
}
#EndRegion '.\Public\Get-ColleagueSiteApplication.ps1' 150
#Region '.\Public\Invoke-ColleagueApiWarmUp.ps1' -1

function Invoke-ColleagueApiWarmUp {
    <#
    .SYNOPSIS
    Invokes warm-up operations for Colleague API applications.

    .DESCRIPTION
    Executes warm-up scripts for Colleague API applications to initialize the application and improve first-request performance. Can optionally recycle application pools before warm-up and include Ethos API warm-up.

    .PARAMETER Label
    The label of the Colleague site as defined in the configuration.

    .PARAMETER Uri
    The URI of the Colleague API to warm up.

    .PARAMETER SiteName
    The name of the IIS site containing the application.

    .PARAMETER ApplicationPath
    The path of the application within the site.

    .PARAMETER WarmUpCredential
    Credentials to use for the warm-up operation. If not specified, uses the configured warm-up credential.

    .PARAMETER Recycle
    If specified, recycles the application pool before performing the warm-up.

    .PARAMETER Ethos
    If specified, includes Ethos API warm-up in the operation.

    .PARAMETER ComputerName
    The name of the remote computer to operate on.

    .PARAMETER Credential
    Credentials to use for remote operations.

    .PARAMETER AsJob
    If specified, runs the warm-up operation as a background job.

    .PARAMETER JobName
    The name to assign to the background job.

    .INPUTS
    String
    Accepts site names, labels, and computer names from the pipeline.

    .EXAMPLE
    Invoke-ColleagueApiWarmUp -Label "Production"
    Performs warm-up for the "Production" site.

    .EXAMPLE
    Invoke-ColleagueApiWarmUp -Uri "https://colleague.example.com/api" -Recycle
    Recycles the application pool and performs warm-up for the specified URI.

    .EXAMPLE
    Invoke-ColleagueApiWarmUp -SiteName "MyColleagueApp" -Ethos
    Performs warm-up including Ethos API for the specified site.

    .NOTES
    This function looks for a warm-up script file (WarmUp.ps1) in the application's physical directory and executes it with the appropriate parameters.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'Label', Mandatory, ValueFromPipelineByPropertyName)]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [ValidateScript({
                (Get-ColleagueSitesConfig).Sites |
                Where-Object Label -like $_
            })]
        [Alias('ColleagueSiteLabel')]
        [string]
        $Label,

        [Parameter(ParameterSetName = 'Uri', Mandatory)]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [uri]
        $Uri,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $SiteName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Path')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $ApplicationPath,

        [Parameter()]
        [pscredential]
        $WarmUpCredential,

        [Parameter()]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [switch]
        $Recycle,

        [Parameter()]
        [switch]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        $Ethos,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('PSComputerName')]
        [ArgumentCompleter({ ColleagueSitesArgumentCompleter @args })]
        [string]
        $ComputerName,

        [Parameter()]
        [pscredential]
        $Credential,

        [Parameter()]
        [switch]
        $AsJob,

        [Parameter()]
        [string]
        $JobName
    )

    begin {
        if (-not $WarmUpCredential) {
            $WarmUpCredential = Get-WarmUpCredential -ErrorAction Stop
            $PSBoundParameters['WarmUpCredential'] = $WarmUpCredential # Passes credentials to remote invocations.
        }
    }

    process {
        if ($Label) { return labelHandler }
        if ($ComputerName) { return invokeRemotely @PSBoundParameters }


        $getColleagueSiteApplicationSplat = @{}

        $PSBoundParameters.GetEnumerator() |
        Where-Object Key -in (Get-Command Get-ColleagueSiteApplication).Parameters.Keys |
        Where-Object Key -notin [System.Management.Automation.PSCmdlet]::CommonParameters |
        Where-Object Key -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters |
        ForEach-Object { 
            $getColleagueSiteApplicationSplat[$_.Key] = $_.Value 
        }

        try {
            $app = Get-ColleagueSiteApplication @getColleagueSiteApplicationSplat -ErrorAction Stop
        }
        catch {
            $_ | Write-Error
            return
        }

        if ($Recycle) {
            Restart-ColleagueSiteApplicationPool @getColleagueSiteApplicationSplat
        }

        $warmUpScriptFileName = Get-ColleagueSitesConfig WarmUpScriptFileName

        $warmUpScript = $app.VirtualDirectories.PhysicalPath | 
        Get-ChildItem -Recurse -File -Filter $warmUpScriptFileName | 
        Select-Object -First 1

        if (-not $warmUpScript) {
            'No file with name "{0}" in physical application path.' -f $warmUpScriptFileName | 
            Write-Error

            return
        }
    
        'Running script "{0}"' -f $warmUpScript.FullName |
        Write-Host
            
        $warmUpSplat = @{
            webApiBaseUrl = $Uri
            userId        = $WarmUpCredential.UserName
            password      = $WarmUpCredential.GetNetworkCredential().Password
            runEthosApi   = $Ethos
        }
        
        & $warmUpScript.FullName @warmUpSplat
    }
}
#EndRegion '.\Public\Invoke-ColleagueApiWarmUp.ps1' 184
#Region '.\Public\WarmUpCredential\Export-WarmUpCredential.ps1' -1

function Export-WarmUpCredential {
    <#
    .SYNOPSIS
    Exports warm-up credentials to a file.

    .DESCRIPTION
    Exports warm-up credentials to a CLIXML file for later use. The credentials are encrypted and can only be decrypted by the same user on the same machine.

    .PARAMETER Credential
    Optional. The credential to export. If not specified, uses the current warm-up credential.

    .PARAMETER Path
    Optional. The path where the credential will be saved. If not specified, uses the default warm-up credential path from configuration.

    .INPUTS
    PSCredential
    Accepts credential objects from the pipeline.

    .EXAMPLE
    Export-WarmUpCredential
    Exports the current warm-up credential to the default location.

    .EXAMPLE
    Export-WarmUpCredential -Path "C:\MyCredentials\warmup.clixml"
    Exports the credential to a specific file.

    .EXAMPLE
    $cred | Export-WarmUpCredential
    Exports a credential object from the pipeline.

    .NOTES
    The exported credential file can be imported using Import-WarmUpCredential.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [pscredential]
        $Credential = (Get-WarmUpCredential),

        [Parameter()]
        [string]
        $Path = (Get-ColleagueSitesConfig WarmUpCredentialPath)
    )
    
    begin {
        if (-not $PSBoundParameters.ContainsKey('Path') -and
            -not (Test-Path $Path)
        ) {
            New-Item $Path -Force | Out-Null
        }
    }

    process {
        $Credential | Export-Clixml -Path $Path
    }
}
#EndRegion '.\Public\WarmUpCredential\Export-WarmUpCredential.ps1' 57
#Region '.\Public\WarmUpCredential\Get-WarmUpCredential.ps1' -1

function Get-WarmUpCredential {
    <#
    .SYNOPSIS
    Gets the credential for warm-up operations.

    .DESCRIPTION
    Retrieves the credential that will be used for warm-up operations. If no credential is set in the configuration, attempts to import from the default location or prompts for credentials.

    .OUTPUTS
    PSCredential
    Returns the credential object for warm-up operations.

    .EXAMPLE
    $cred = Get-WarmUpCredential
    Gets the current credential for warm-up operations.

    .NOTES
    If no credential is found, it will attempt to import from the saved location, and if that fails, will prompt for credentials.
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-ColleagueSitesConfig WarmUpCredential)) {
        try {
            Import-WarmUpCredential -ErrorAction Stop |
            Set-WarmUpCredential
        }
        catch {
            $_ | Write-Warning

            Set-WarmUpCredential
        }
    }

    (Get-ColleagueSitesConfig WarmUpCredential)
}
#EndRegion '.\Public\WarmUpCredential\Get-WarmUpCredential.ps1' 37
#Region '.\Public\WarmUpCredential\Import-WarmUpCredential.ps1' -1

function Import-WarmUpCredential {
    <#
    .SYNOPSIS
    Imports warm-up credentials from a file.

    .DESCRIPTION
    Imports warm-up credentials from a CLIXML file. Used to restore previously saved credentials for warm-up operations.

    .PARAMETER Path
    Optional. The path to the credential file. If not specified, uses the default warm-up credential path from configuration.

    .OUTPUTS
    PSCredential
    Returns the imported credential object.

    .EXAMPLE
    Import-WarmUpCredential
    Imports credentials from the default location.

    .EXAMPLE
    Import-WarmUpCredential -Path "C:\MyCredentials\warmup.clixml"
    Imports credentials from a specific file.

    .NOTES
    The credential file should have been created using Export-WarmUpCredential.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $Path = (Get-ColleagueSitesConfig WarmUpCredentialPath)
    )

    try {
        Import-Clixml $Path -ErrorAction Stop
    }
    catch {
        @(
            'Could not import credentials from "{0}"' -f $Path
            'Save a credential with Export-WarmUpCredential.'
        ) -join "`n" | 
        Write-Error
    }
}
#EndRegion '.\Public\WarmUpCredential\Import-WarmUpCredential.ps1' 45
#Region '.\Public\WarmUpCredential\Set-WarmUpCredential.ps1' -1

function Set-WarmUpCredential {
    <#
    .SYNOPSIS
    Sets the credential for warm-up operations.

    .DESCRIPTION
    Sets the credential that will be used for warm-up operations. If no credential is provided, prompts the user for username and password.

    .PARAMETER Credential
    Optional. The PSCredential object to use for warm-up authentication. If not provided, prompts for credentials.

    .INPUTS
    PSCredential
    Accepts credential objects from the pipeline.

    .EXAMPLE
    Set-WarmUpCredential
    Prompts for username and password and sets the warm-up credential.

    .EXAMPLE
    $cred = Get-Credential
    Set-WarmUpCredential -Credential $cred
    Sets the warm-up credential using an existing PSCredential object.

    .EXAMPLE
    Get-Credential | Set-WarmUpCredential
    Sets the warm-up credential from pipeline input.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [pscredential]
        $Credential
    )

    process {
        if (-not $Credential) {
            try {
                # Use Read-Host to prevent Windows Powershell from trying to use the
                # GUI in certain types of remote sessions.
            
                $username = Read-Host -Prompt 'WarmUpCredential Username'
                $password = Read-Host -Prompt 'WarmUpCredential Password' -AsSecureString 
                $Credential = [pscredential]::new($username, $password)
            }
            catch {
                'Failed reading credential.' | 
                Write-Error -ErrorAction Stop
            }
        }

        $Local:config = Get-ColleagueSitesConfig
        
        $Local:config.WarmUpCredential = $Credential

        Set-ColleagueSitesConfig $local:config
    }
}
#EndRegion '.\Public\WarmUpCredential\Set-WarmUpCredential.ps1' 59
