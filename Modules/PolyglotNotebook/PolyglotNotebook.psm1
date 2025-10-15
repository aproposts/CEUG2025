# PolyglotNotebook PowerShell Module
# Converts polyglot notebooks in DIB format to structured objects and various output formats

# Module-level variables
$script:SupportedLanguages = @{
    'csharp' = 'C#'
    'fsharp' = 'F#'
    'vb' = 'VB.NET'
    'powershell' = 'PowerShell'
    'pwsh' = 'PowerShell'
    'javascript' = 'JavaScript'
    'html' = 'HTML'
    'sql' = 'SQL'
    'python' = 'Python'
    'kql' = 'KQL'
    'markdown' = 'Markdown'
    'mermaid' = 'Mermaid'
}

# Define custom types for the notebook structure
enum CellType {
    Language
    MagicCommand
    Metadata
    Markdown
}

class NotebookCell {
    [CellType]$Type
    [string]$Language
    [string]$MagicCommand
    [string]$Content
    [hashtable]$Parameters
    [string]$RawMetadata
    [int]$Index
    
    NotebookCell([CellType]$type, [string]$languageOrCommand, [string]$content, [hashtable]$parameters, [string]$rawMetadata, [int]$index) {
        $this.Type = $type
        $this.Content = $content
        $this.Parameters = $parameters
        $this.RawMetadata = $rawMetadata
        $this.Index = $index
        
        if ($type -eq [CellType]::Language) {
            $this.Language = $languageOrCommand
            $this.MagicCommand = ""
        } elseif ($type -eq [CellType]::MagicCommand) {
            $this.MagicCommand = $languageOrCommand
            $this.Language = ""
        } else {
            $this.Language = if ($type -eq [CellType]::Markdown) { "markdown" } else { "" }
            $this.MagicCommand = ""
        }
    }
    
    [bool] IsLanguageCell() {
        return $this.Type -eq [CellType]::Language
    }
    
    [bool] IsMagicCommand() {
        return $this.Type -eq [CellType]::MagicCommand
    }
    
    [bool] IsMarkdown() {
        return $this.Type -eq [CellType]::Markdown
    }
}

class PolyglotNotebook {
    [NotebookCell[]]$Cells
    [string]$SourcePath
    [datetime]$ParsedAt
    [hashtable]$Metadata
    
    PolyglotNotebook() {
        $this.Cells = @()
        $this.ParsedAt = Get-Date
        $this.Metadata = @{}
    }
    
    [void] AddCell([NotebookCell]$cell) {
        $this.Cells += $cell
    }
    
    [int] GetCellCount() {
        return $this.Cells.Count
    }
    
    [NotebookCell[]] GetCellsByLanguage([string]$language) {
        return $this.Cells | Where-Object { $_.IsLanguageCell() -and $_.Language -eq $language.ToLower() }
    }
    
    [NotebookCell[]] GetCellsByMagicCommand([string]$command) {
        return $this.Cells | Where-Object { $_.IsMagicCommand() -and $_.MagicCommand -eq $command.ToLower() }
    }
    
    [NotebookCell[]] GetMarkdownCells() {
        return $this.Cells | Where-Object { $_.IsMarkdown() }
    }
    
    [NotebookCell[]] GetLanguageCells() {
        return $this.Cells | Where-Object { $_.IsLanguageCell() }
    }
}

#region Private Functions

function Parse-DibContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    # Define known language kernels vs magic commands
    $languageKernels = @('csharp', 'fsharp', 'vb', 'powershell', 'pwsh', 'javascript', 'html', 'sql', 'python', 'kql', 'markdown', 'mermaid')
    $magicCommands = @('connect', 'lsmagic', 'about', 'who', 'whos', 'time', 'set', 'value', 'share', 'import', 'log', 'meta')

    $cells = @()
    $lines = $Content -split "`r?`n"
    $currentCell = $null
    $cellContent = @()
    $cellIndex = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        
        # Check for cell delimiter
        if ($line -match '^#!([a-zA-Z0-9]+)(?:\s+(.*))?$') {
            $commandOrLanguage = $matches[1].ToLower()
            $parameters = if ($matches[2]) { $matches[2] } else { '' }
            
            # Save previous cell if exists
            if ($currentCell) {
                $currentCell.Content = ($cellContent -join "`n").Trim()
                if ($currentCell.Content -or $currentCell.Type -ne [CellType]::Markdown) {
                    $cells += $currentCell
                    $cellIndex++
                }
            }

            # Determine cell type
            $cellType = [CellType]::Language
            if ($magicCommands -contains $commandOrLanguage) {
                $cellType = [CellType]::MagicCommand
            } elseif ($commandOrLanguage -eq 'markdown') {
                $cellType = [CellType]::Markdown
            } elseif ($languageKernels -notcontains $commandOrLanguage) {
                # Unknown command - treat as magic command
                $cellType = [CellType]::MagicCommand
            }

            # Parse parameters into hashtable
            $paramHash = @{}
            if ($parameters) {
                # Simple parameter parsing - can be enhanced for complex scenarios
                $paramPairs = $parameters -split '\s+--?' | Where-Object { $_ }
                foreach ($param in $paramPairs) {
                    if ($param -match '^(\w+)(?:=(.+))?') {
                        $paramHash[$matches[1]] = if ($matches[2]) { $matches[2] } else { $true }
                    }
                }
            }

            # Start new cell
            $currentCell = [PSCustomObject]@{
                Type = $cellType
                CommandOrLanguage = $commandOrLanguage
                Content = ''
                Parameters = $paramHash
                RawMetadata = $parameters
                Index = $cellIndex
            }
            $cellContent = @()
        }
        elseif ($currentCell) {
            # Add content to current cell
            $cellContent += $line
        }
        elseif ($line.Trim() -ne '') {
            # Content without explicit cell marker - treat as markdown
            if (-not $currentCell) {
                $currentCell = [PSCustomObject]@{
                    Type = [CellType]::Markdown
                    CommandOrLanguage = 'markdown'
                    Content = ''
                    Parameters = @{}
                    RawMetadata = ''
                    Index = $cellIndex
                }
                $cellContent = @()
            }
            $cellContent += $line
        }
    }

    # Add the last cell
    if ($currentCell) {
        $currentCell.Content = ($cellContent -join "`n").Trim()
        if ($currentCell.Content -or $currentCell.Type -ne [CellType]::Markdown) {
            $cells += $currentCell
        }
    }

    return $cells
}

#endregion

#region Public Functions

<#
.SYNOPSIS
    Converts a NotebookCell to Markdown format.

.DESCRIPTION
    This function takes a NotebookCell object and converts it to Markdown format
    with appropriate code blocks based on the cell type and language.

.PARAMETER Cell
    The NotebookCell object to convert.

.PARAMETER IncludeMetadata
    Switch to include cell metadata as HTML comments in the output.

.EXAMPLE
    $cell = $notebook.Cells[0]
    $markdown = Convert-NotebookCellToMarkdown -Cell $cell

.EXAMPLE
    Convert-NotebookCellToMarkdown -Cell $cell -IncludeMetadata

.OUTPUTS
    String containing the converted Markdown content for the cell.
#>
function Convert-NotebookCellToMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [NotebookCell]$Cell,

        [switch]$IncludeMetadata
    )

    begin {
        Write-Verbose "Converting notebook cell to Markdown"
    }

    process {
        try {
            $content = $Cell.Content

            if ($Cell.IsMarkdown()) {
                # Return markdown content as-is
                $result = $content
            }
            elseif ($Cell.IsLanguageCell()) {
                # Create code block with appropriate language identifier
                $language = $Cell.Language.ToLower()
                $markdownLanguage = switch ($language) {
                    'csharp' { 'csharp' }
                    'fsharp' { 'fsharp' }
                    'vb' { 'vbnet' }
                    'powershell' { 'powershell' }
                    'pwsh' { 'powershell' }
                    'javascript' { 'javascript' }
                    'html' { 'html' }
                    'sql' { 'sql' }
                    'python' { 'python' }
                    'kql' { 'kusto' }
                    'mermaid' { 'mermaid' }
                    default { $language }
                }

                $result = "``````$markdownLanguage`n$content`n``````"
            }
            elseif ($Cell.IsMagicCommand()) {
                # Handle magic commands - show as code block with command info
                $commandInfo = "Magic Command: #!$($Cell.MagicCommand)"
                if ($Cell.Parameters.Count -gt 0) {
                    $paramStr = ($Cell.Parameters.GetEnumerator() | ForEach-Object { 
                        if ($_.Value -eq $true) { "--$($_.Key)" } else { "--$($_.Key)=$($_.Value)" }
                    }) -join " "
                    $commandInfo += " $paramStr"
                }
                
                $result = "``````text`n$commandInfo`n$content`n``````"
            }
            else {
                # Fallback for unknown cell types
                $result = "``````text`n$content`n``````"
            }
            
            # Add metadata as comment if present and requested
            if ($IncludeMetadata -and $Cell.RawMetadata -and $Cell.RawMetadata.Trim() -ne '') {
                $result = "<!-- $($Cell.RawMetadata) -->`n$result"
            }

            Write-Verbose "Cell conversion completed successfully"
            return $result
        }
        catch {
            Write-Error "Error converting cell to Markdown: $($_.Exception.Message)"
            throw
        }
    }
}

<#
.SYNOPSIS
    Converts a DIB format string to a PolyglotNotebook object.

.DESCRIPTION
    This function takes a string containing polyglot notebook content in DIB format
    and converts it to a structured PolyglotNotebook object with parsed cells.

.PARAMETER DibContent
    The DIB format content as a string.

.PARAMETER SourcePath
    Optional path to the source file for metadata tracking.

.EXAMPLE
    $dibContent = Get-Content -Path "notebook.dib" -Raw
    $notebook = ConvertFrom-PolyglotNotebook -DibContent $dibContent

.EXAMPLE
    $notebook = ConvertFrom-PolyglotNotebook -DibContent $dibText -SourcePath "C:\notebooks\example.dib"

.OUTPUTS
    PolyglotNotebook object containing the parsed cells and metadata.
#>
function ConvertFrom-PolyglotNotebook {
    [CmdletBinding()]
    [OutputType([PolyglotNotebook])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$DibContent,

        [string]$SourcePath
    )

    begin {
        Write-Verbose "Starting DIB content parsing"
    }

    process {
        try {
            # Create new notebook object
            $notebook = [PolyglotNotebook]::new()
            
            if ($SourcePath) {
                $notebook.SourcePath = $SourcePath
            }

            # Parse the DIB content into cell data
            $cellData = Parse-DibContent -Content $DibContent
            Write-Verbose "Parsed $($cellData.Count) cells from DIB content"

            # Convert parsed data to NotebookCell objects and add to notebook
            foreach ($cell in $cellData) {
                $notebookCell = [NotebookCell]::new(
                    $cell.Type,
                    $cell.CommandOrLanguage,
                    $cell.Content,
                    $cell.Parameters,
                    $cell.RawMetadata,
                    $cell.Index
                )
                $notebook.AddCell($notebookCell)
            }
            
            Write-Verbose "Conversion to notebook object completed successfully"
            return $notebook
        }
        catch {
            Write-Error "Error converting DIB content to notebook object: $($_.Exception.Message)"
            throw
        }
    }
}

<#
.SYNOPSIS
    Converts a DIB file to a PolyglotNotebook object.

.DESCRIPTION
    This function reads a DIB format file and converts it to a structured PolyglotNotebook object.

.PARAMETER Path
    Path to the DIB format file.

.PARAMETER Encoding
    Text encoding for reading the file. Default is UTF8.

.EXAMPLE
    $notebook = Import-PolyglotNotebook -Path "C:\notebooks\example.dib"

.EXAMPLE
    Import-PolyglotNotebook -Path "notebook.dib" -Encoding ASCII

.OUTPUTS
    PolyglotNotebook object containing the parsed cells and metadata.
#>
function Import-PolyglotNotebook {
    [CmdletBinding()]
    [OutputType([PolyglotNotebook])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateScript({Test-Path $_ -PathType Leaf})]
        [string]$Path,

        [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8
    )

    begin {
        Write-Verbose "Reading DIB file for conversion"
    }

    process {
        try {
            $resolvedPath = Resolve-Path -Path $Path
            Write-Verbose "Reading file: $resolvedPath"
            
            $dibContent = Get-Content -Path $resolvedPath -Raw -Encoding $Encoding
            
            if ([string]::IsNullOrWhiteSpace($dibContent)) {
                Write-Warning "File appears to be empty: $resolvedPath"
                return [PolyglotNotebook]::new()
            }

            return ConvertFrom-PolyglotNotebook -DibContent $dibContent -SourcePath $resolvedPath
        }
        catch {
            Write-Error "Error reading DIB file '$Path': $($_.Exception.Message)"
            throw
        }
    }
}

<#
.SYNOPSIS
    Converts a PolyglotNotebook object to Markdown format.

.DESCRIPTION
    This function takes a PolyglotNotebook object and converts it to Markdown format
    with appropriate code blocks and front matter handling.

.PARAMETER Notebook
    The PolyglotNotebook object to convert.

.PARAMETER IncludeMetadata
    Switch to include cell metadata as HTML comments in the output.

.EXAMPLE
    $notebook = Import-PolyglotNotebook -Path "notebook.dib"
    $markdown = Convert-PolyglotNotebookToMarkdown -Notebook $notebook

.EXAMPLE
    Convert-PolyglotNotebookToMarkdown -Notebook $notebook -IncludeMetadata

.OUTPUTS
    String containing the converted Markdown content.
#>
function Convert-PolyglotNotebookToMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PolyglotNotebook]$Notebook,

        [switch]$IncludeMetadata
    )

    begin {
        Write-Verbose "Converting PolyglotNotebook to Markdown"
    }

    process {
        try {
            $markdownSections = @()
            $frontMatter = $null
            
            foreach ($cell in $Notebook.Cells) {
                # Check if this is a meta cell that should become front matter
                if ($cell.Type -eq [CellType]::MagicCommand -and $cell.MagicCommand -eq 'meta') {
                    # Use the JSON content directly as the value for the notebook key
                    $frontMatter = @"
---
notebook: $($cell.Content)
---

"@
                }
                else {
                    $markdownCell = Convert-NotebookCellToMarkdown -Cell $cell -IncludeMetadata:$IncludeMetadata
                    if ($markdownCell.Trim() -ne '') {
                        $markdownSections += $markdownCell
                    }
                }
            }

            # Combine front matter with content
            if ($frontMatter) {
                $result = $frontMatter + ($markdownSections -join "`n`n")
            } else {
                $result = $markdownSections -join "`n`n"
            }
            
            Write-Verbose "Notebook conversion completed successfully"
            return $result
        }
        catch {
            Write-Error "Error converting PolyglotNotebook to Markdown: $($_.Exception.Message)"
            throw
        }
    }
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    'ConvertFrom-PolyglotNotebook',
    'Import-PolyglotNotebook',
    'Convert-NotebookCellToMarkdown',
    'Convert-PolyglotNotebookToMarkdown'
)
