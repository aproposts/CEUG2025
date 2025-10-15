@{
    # Use Severity levels to specify which rules to include or exclude
    Severity = @('Error', 'Warning', 'Information')
    
    # Specify which rules to exclude
    ExcludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidUsingWriteHost'
    )
    
    # Specify which rules to include  
    IncludeRules = @(
        'PSUseCmdletCorrectly',
        'PSUseApprovedVerbs',
        'PSUseSingularNouns',
        'PSAvoidUsingCmdletAliases',
        'PSAvoidUsingPlainTextForPassword',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUseBOMForUnicodeEncodedFile',
        'PSMissingModuleManifestField',
        'PSReservedCmdletChar',
        'PSReservedParams',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSupportsShouldProcess',
        'PSMisleadingBacktick',
        'PSPossibleIncorrectComparisonWithNull',
        'PSPossibleIncorrectUsageOfRedirectionOperator',
        'PSPossibleIncorrectUsageOfAssignmentOperator',
        'PSUseCompatibleCmdlets',
        'PSUseCompatibleSyntax'
    )
    
    Rules = @{
        PSUseCompatibleCmdlets = @{
            compatibility = @("core-6.1.0-windows")
        }
        PSUseCompatibleSyntax = @{
            Enable = $true
            TargetVersions = @(
                '5.1',
                '6.2',
                '7.0'
            )
        }
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
            NewLineAfter = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace = @{
            Enable = $true
            NewLineAfter = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore = $false
        }
        PSUseConsistentIndentation = @{
            Enable = $true
            Kind = 'space'
            PipelineIndentation = 'IncreaseIndentationAfterEveryPipeline'
            IndentationSize = 4
        }
        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckSeparator = $true
            CheckParameter = $false
        }
        PSAlignAssignmentStatement = @{
            Enable = $true
            CheckHashtable = $true
        }
        PSUseCorrectCasing = @{
            Enable = $true
        }
    }
}
