# PolyglotNotebook

A PowerShell module for converting polyglot notebooks in DIB format to Markdown.

## Overview

This module provides functionality to convert .NET Interactive notebook files (DIB format) to Markdown format. It supports multiple programming languages and preserves the structure and content of the original notebook while converting code cells to appropriate Markdown code blocks.

## Features

- **Multi-language Support**: Converts cells in C#, F#, VB.NET, PowerShell, JavaScript, Python, SQL, KQL, HTML, and Markdown
- **Metadata Preservation**: Optionally includes cell metadata as HTML comments
- **Pipeline Support**: Works with PowerShell pipeline for batch processing
- **Flexible Input/Output**: Can work with strings, files, or save directly to files
- **Error Handling**: Comprehensive error handling with detailed error messages

## Supported Languages

The module recognizes and properly converts the following cell types:

| DIB Language | Markdown Code Block | Display Name |
|--------------|-------------------|--------------|
| `csharp` | `csharp` | C# |
| `fsharp` | `fsharp` | F# |
| `vb` | `vbnet` | VB.NET |
| `powershell`/`pwsh` | `powershell` | PowerShell |
| `javascript` | `javascript` | JavaScript |
| `html` | `html` | HTML |
| `sql` | `sql` | SQL |
| `python` | `python` | Python |
| `kql` | `kusto` | KQL |
| `markdown` | (as-is) | Markdown |

## Installation

1. Download or clone this repository
2. Import the module:

```powershell
Import-Module .\PolyglotNotebook.psd1
```

Or copy the module to your PowerShell modules directory and import:

```powershell
Import-Module PolyglotNotebook
```

## Usage

### Convert DIB Content to PolyglotNotebook Object

```powershell
# Convert a DIB string to a structured notebook object
$dibContent = @"
#!markdown
# My Notebook
This is a sample notebook.

#!csharp
Console.WriteLine("Hello, World!");

#!fsharp
printfn "Hello from F#!"
"@

$notebook = ConvertFrom-PolyglotNotebook -DibContent $dibContent
$notebook | Format-List
$notebook.Cells | Format-Table Language, Content
```

### Import a DIB File to Notebook Object

```powershell
# Import a DIB file to PolyglotNotebook object
$notebook = Import-PolyglotNotebook -Path "C:\notebooks\example.dib"

# Examine the notebook structure
$notebook.GetCellCount()
$csharpCells = $notebook.GetCellsByLanguage("csharp")
```

### Convert to Markdown

```powershell
# Convert notebook object to Markdown
$markdown = ConvertFrom-NotebookToMarkdown -Notebook $notebook

# Or convert DIB content directly to Markdown (uses intermediary object)
$markdown = Convert-DibToMarkdown -DibContent $dibContent

# Include metadata in the output
$markdown = ConvertFrom-NotebookToMarkdown -Notebook $notebook -IncludeMetadata
```

### Convert and Save to File

```powershell
# Convert notebook object and save to a Markdown file
$notebook = Import-PolyglotNotebook -Path "input.dib"
ConvertTo-MarkdownFile -Notebook $notebook -OutputPath "output.md"

# Include metadata and force overwrite
ConvertTo-MarkdownFile -Notebook $notebook -OutputPath "output.md" -Force -IncludeMetadata
```

### Batch Processing

```powershell
# Convert multiple DIB files
Get-ChildItem -Path "C:\notebooks\*.dib" | ForEach-Object {
    $outputPath = $_.FullName -replace '\.dib$', '.md'
    $notebook = Import-PolyglotNotebook -Path $_.FullName
    ConvertTo-MarkdownFile -Notebook $notebook -OutputPath $outputPath -Force
}
```

## Functions

### Convert-DibToMarkdown

Converts DIB format string content to Markdown.

**Parameters:**
- `DibContent` (string, mandatory): The DIB content to convert
- `IncludeMetadata` (switch): Include cell metadata as HTML comments

### Import-PolyglotNotebook

Reads a DIB file and converts it to Markdown.

**Parameters:**
- `Path` (string, mandatory): Path to the DIB file
- `Encoding` (Encoding): Text encoding for reading the file (default: UTF8)

### ConvertTo-MarkdownFile

Converts DIB content to Markdown and saves to a file.

**Parameters:**
- `DibContent` (string, mandatory): The DIB content to convert
- `OutputPath` (string, mandatory): Output file path
- `Force` (switch): Overwrite existing files without prompting
- `Encoding` (Encoding): Text encoding for writing the file (default: UTF8)

## Examples

### Example DIB Input

```
#!markdown
# Sample Polyglot Notebook

This notebook demonstrates multiple languages.

#!csharp
using System;

Console.WriteLine("Hello from C#!");
var number = 42;
Console.WriteLine($"The answer is {number}");

#!fsharp
let message = "Hello from F#!"
printfn "%s" message

#!powershell
Write-Host "Hello from PowerShell!"
Get-Date

#!javascript
console.log("Hello from JavaScript!");
const numbers = [1, 2, 3, 4, 5];
console.log(numbers.map(x => x * 2));
```

### Example Markdown Output

```markdown
# Sample Polyglot Notebook

This notebook demonstrates multiple languages.

```csharp
using System;

Console.WriteLine("Hello from C#!");
var number = 42;
Console.WriteLine($"The answer is {number}");
```

```fsharp
let message = "Hello from F#!"
printfn "%s" message
```

```powershell
Write-Host "Hello from PowerShell!"
Get-Date
```

```javascript
console.log("Hello from JavaScript!");
const numbers = [1, 2, 3, 4, 5];
console.log(numbers.map(x => x * 2));
```
```

## Requirements

- PowerShell 5.1 or later
- No external dependencies

## Contributing

Contributions are welcome! Please ensure all changes include appropriate tests and documentation.

## License

This project is available under the MIT License.
