# The root settings plus the layout rules the support scripts follow: four-space
# indentation and aligned hashtable assignments. eng/Lint.ps1 analyses scripts/ with
# this file and every other directory with the root one.
@{
    IncludeDefaultRules = $true
    IncludeRules        = @(
        'PSPlaceOpenBrace', 'PSUseConsistentWhitespace',
        'PSUseConsistentIndentation', 'PSAlignAssignmentStatement'
    )
    Rules               = @{
        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSUseConsistentWhitespace  = @{
            Enable                                  = $true
            CheckInnerBrace                         = $true
            CheckOpenBrace                          = $true
            CheckOpenParen                          = $true
            CheckOperator                           = $true
            CheckPipe                               = $true
            CheckSeparator                          = $true
            CheckParameter                          = $false
            IgnoreAssignmentOperatorInsideHashTable = $true
        }
        PSUseConsistentIndentation = @{
            Enable              = $true
            IndentationSize     = 4
            Kind                = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }
    }
}
