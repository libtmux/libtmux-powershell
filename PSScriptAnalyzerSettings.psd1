@{
    IncludeDefaultRules = $true
    IncludeRules = @('PSPlaceOpenBrace', 'PSUseConsistentWhitespace')
    Rules        = @{
        PSPlaceOpenBrace          = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSUseConsistentWhitespace = @{
            Enable          = $true
            CheckInnerBrace = $true
            CheckOpenBrace  = $true
            CheckOpenParen  = $true
            CheckOperator   = $true
            CheckPipe       = $true
            CheckSeparator  = $true
            CheckParameter  = $false
        }
    }
}
