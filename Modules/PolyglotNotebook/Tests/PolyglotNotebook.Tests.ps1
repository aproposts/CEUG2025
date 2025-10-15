# PolyglotNotebook Tests
# This file contains Pester tests for the PolyglotNotebook module

BeforeAll {
    # Import the module
    Import-Module $PSScriptRoot\..\PolyglotNotebook.psd1 -Force
}

Describe "Convert-PolyglotNotebookToMarkdown" {
    Context "Basic functionality" {
        It "Should convert simple C# cell to markdown" {
            $dibContent = @"
#!csharp
Console.WriteLine("Hello World");
"@
            $notebook = ConvertFrom-PolyglotNotebook -DibContent $dibContent
            $result = Convert-PolyglotNotebookToMarkdown -Notebook $notebook
            $result | Should -Match '```csharp'
            $result | Should -Match 'Console\.WriteLine\("Hello World"\);'
            $result | Should -Match '```'
        }

        It "Should convert markdown cell as-is" {
            $dibContent = @"
#!markdown
# Hello World
This is **bold** text.
"@
            $notebook = ConvertFrom-PolyglotNotebook -DibContent $dibContent
            $result = Convert-PolyglotNotebookToMarkdown -Notebook $notebook
            $result | Should -Be "# Hello World`nThis is **bold** text."
        }

        It "Should handle multiple cells" {
            $dibContent = @"
#!markdown
# Title

#!csharp
var x = 1;

#!fsharp
let y = 2
"@
            $notebook = ConvertFrom-PolyglotNotebook -DibContent $dibContent
            $result = Convert-PolyglotNotebookToMarkdown -Notebook $notebook
            $result | Should -Match '# Title'
            $result | Should -Match '```csharp'
            $result | Should -Match 'var x = 1;'
            $result | Should -Match '```fsharp'
            $result | Should -Match 'let y = 2'
        }

        It "Should handle empty cells" {
            $dibContent = @"
#!csharp

#!markdown
# Title
"@
            $notebook = ConvertFrom-PolyglotNotebook -DibContent $dibContent
            $result = Convert-PolyglotNotebookToMarkdown -Notebook $notebook
            $result | Should -Match "# Title"
        }
    }

    Context "Language mapping" {
        It "Should map PowerShell correctly" {
            $dibContent = "#!powershell`nGet-Date"
            $notebook = ConvertFrom-PolyglotNotebook -DibContent $dibContent
            $result = Convert-PolyglotNotebookToMarkdown -Notebook $notebook
            $result | Should -Match '```powershell'
        }

        It "Should map pwsh to PowerShell" {
            $dibContent = "#!pwsh`nGet-Date"
            $notebook = ConvertFrom-PolyglotNotebook -DibContent $dibContent
            $result = Convert-PolyglotNotebookToMarkdown -Notebook $notebook
            $result | Should -Match '```powershell'
        }

        It "Should map VB.NET correctly" {
            $dibContent = "#!vb`nDim x As Integer = 1"
            $notebook = ConvertFrom-PolyglotNotebook -DibContent $dibContent
            $result = Convert-PolyglotNotebookToMarkdown -Notebook $notebook
            $result | Should -Match '```vbnet'
        }

        It "Should map KQL correctly" {
            $dibContent = "#!kql`nEvents | take 10"
            $notebook = ConvertFrom-PolyglotNotebook -DibContent $dibContent
            $result = Convert-PolyglotNotebookToMarkdown -Notebook $notebook
            $result | Should -Match '```kusto'
        }

        It "Should map Mermaid correctly" {
            $dibContent = "#!mermaid`ngraph TD`n    A[Start] --> B[End]"
            $notebook = ConvertFrom-PolyglotNotebook -DibContent $dibContent
            $result = Convert-PolyglotNotebookToMarkdown -Notebook $notebook
            $result | Should -Match '```mermaid'
        }
    }

    Context "Error handling" {
        It "Should handle null input gracefully" {
            { ConvertFrom-PolyglotNotebook -DibContent $null } | Should -Throw
        }

        It "Should handle empty string" {
            $notebook = ConvertFrom-PolyglotNotebook -DibContent " "
            $result = Convert-PolyglotNotebookToMarkdown -Notebook $notebook
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe "Import-PolyglotNotebook" {
    BeforeAll {
        $testFile = "$PSScriptRoot\test.dib"
        $testContent = @"
#!markdown
# Test File

#!csharp
Console.WriteLine("Test");
"@
        $testContent | Out-File -FilePath $testFile -Encoding UTF8
    }

    AfterAll {
        Remove-Item -Path "$PSScriptRoot\test.dib" -Force -ErrorAction SilentlyContinue
    }

    It "Should read and convert file correctly" {
        $result = Import-PolyglotNotebook -Path "$PSScriptRoot\test.dib"
        $result.GetType().Name | Should -Be 'PolyglotNotebook'
        $result.GetCellCount() | Should -Be 2
        $result.GetMarkdownCells().Count | Should -Be 1
        $result.GetLanguageCells().Count | Should -Be 1
    }

    It "Should throw error for non-existent file" {
        { Import-PolyglotNotebook -Path "$PSScriptRoot\nonexistent.dib" } | Should -Throw
    }
}

Describe "Convert-NotebookCellToMarkdown" {
    BeforeAll {
        $dibContent = @"
#!markdown
# Test Markdown

#!csharp
var test = "output";

#!powershell
Get-Date
"@
        $notebook = ConvertFrom-PolyglotNotebook -DibContent $dibContent
    }

    It "Should convert markdown cell correctly" {
        $markdownCell = $notebook.GetMarkdownCells()[0]
        $result = Convert-NotebookCellToMarkdown -Cell $markdownCell
        $result | Should -Be "# Test Markdown"
    }

    It "Should convert code cell correctly" {
        $codeCell = $notebook.GetLanguageCells()[0]
        $result = Convert-NotebookCellToMarkdown -Cell $codeCell
        $result | Should -Match '```csharp'
        $result | Should -Match 'var test = "output";'
        $result | Should -Match '```'
    }

    It "Should include metadata when requested" {
        $codeCell = $notebook.GetLanguageCells()[0]
        $result = Convert-NotebookCellToMarkdown -Cell $codeCell -IncludeMetadata
        $result | Should -Match '```csharp'
        $result | Should -Match 'var test = "output";'
        $result | Should -Match '```'
    }
}

Describe "Integration Tests" {
    It "Should handle complex polyglot notebook" {
        $complexDib = @"
#!markdown
# Complex Notebook
This tests multiple languages.

#!csharp
using System;
using System.Linq;

var numbers = Enumerable.Range(1, 5);
Console.WriteLine(string.Join(", ", numbers));

#!fsharp
let factorial n = 
    let rec fact acc = function
        | 0 | 1 -> acc
        | n -> fact (acc * n) (n - 1)
    fact 1 n

printfn "5! = %d" (factorial 5)

#!powershell
# PowerShell comment
Get-Process | Select-Object -First 3 Name, CPU

#!javascript
const fibonacci = (n) => {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
};

console.log(`Fibonacci(10) = `${fibonacci(10)}`);

#!python
import math

def prime_check(n):
    if n < 2:
        return False
    return all(n % i != 0 for i in range(2, int(math.sqrt(n)) + 1))

print(f"Is 17 prime? {prime_check(17)}")

#!sql
SELECT 
    'Database' as Type,
    'SQL Server' as Name,
    GETDATE() as CurrentTime;

#!html
<div class="info-box">
    <h4>Information</h4>
    <p>This is an <em>HTML</em> cell with various elements.</p>
</div>
"@

        $notebook = ConvertFrom-PolyglotNotebook -DibContent $complexDib
        $result = Convert-PolyglotNotebookToMarkdown -Notebook $notebook
        
        # Check for all expected sections
        $result | Should -Match '# Complex Notebook'
        $result | Should -Match '```csharp'
        $result | Should -Match 'using System;'
        $result | Should -Match '```fsharp'
        $result | Should -Match 'let factorial'
        $result | Should -Match '```powershell'
        $result | Should -Match 'Get-Process'
        $result | Should -Match '```javascript'
        $result | Should -Match 'const fibonacci'
        $result | Should -Match '```python'
        $result | Should -Match 'import math'
        $result | Should -Match '```sql'
        $result | Should -Match 'SELECT'
        $result | Should -Match '```html'
        $result | Should -Match '<div class="info-box">'
    }
}

Describe "Module Structure" {
    It "Should export correct functions" {
        $module = Get-Module PolyglotNotebook
        $exportedFunctions = $module.ExportedFunctions.Keys
        
        $exportedFunctions | Should -Contain "Convert-NotebookCellToMarkdown"
        $exportedFunctions | Should -Contain "Convert-PolyglotNotebookToMarkdown"
        $exportedFunctions | Should -Contain "Import-PolyglotNotebook" 
        $exportedFunctions | Should -Contain "ConvertFrom-PolyglotNotebook"
        $exportedFunctions.Count | Should -Be 4
    }

    It "Should have proper module manifest" {
        $manifest = Test-ModuleManifest -Path "$PSScriptRoot\..\PolyglotNotebook.psd1"
        $manifest.Name | Should -Be "PolyglotNotebook"
        $manifest.PowerShellVersion | Should -Be "5.1"
        $manifest.ExportedFunctions.Count | Should -Be 4
    }
}
