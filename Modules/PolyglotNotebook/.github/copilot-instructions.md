<!-- Use this file to provide workspace-specific custom instructions to Copilot. For more details, visit https://code.visualstudio.com/docs/copilot/copilot-customization#_use-a-githubcopilotinstructionsmd-file -->

# PolyglotNotebook Module Instructions

This is a PowerShell module project that converts polyglot notebooks in DIB (dotnet interactive) format to Markdown.

## Key Concepts

- **DIB Format**: Polyglot notebook format used by .NET Interactive with cell delimiters like `#!csharp`, `#!fsharp`, `#!markdown`, etc.
- **Cell Types**: The module supports various language cells including C#, F#, PowerShell, JavaScript, Python, SQL, KQL, HTML, Mermaid, and Markdown
- **Conversion Logic**: Each code cell becomes a fenced code block in Markdown with appropriate language syntax highlighting

## Code Style Guidelines

- Follow PowerShell best practices and naming conventions
- Use approved verbs for function names (Convert, Get, Set, etc.)
- Include comprehensive help documentation with examples
- Use proper error handling with try-catch blocks
- Support pipeline input where appropriate
- Include verbose output for debugging

## Testing Considerations

- Test with various DIB file formats and language combinations
- Verify proper handling of empty cells and metadata
- Ensure encoding is handled correctly for international characters
- Test edge cases like malformed DIB syntax

## Dependencies

- PowerShell 5.1 or later
- No external dependencies required - uses built-in PowerShell cmdlets only
