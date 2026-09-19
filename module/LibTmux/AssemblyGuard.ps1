function Import-TmuxAssembly {
    param([string] $Path, [switch] $ExactBuild)

    $expected = [Reflection.AssemblyName]::GetAssemblyName($Path)
    $loaded = @([AppDomain]::CurrentDomain.GetAssemblies().Where({
        $_.GetName().Name -ceq $expected.Name
    }))
    if ($loaded.Count -gt 1) {
        throw "Multiple $($expected.Name) assemblies are loaded. Import compatible modules in a fresh PowerShell process."
    }
    if ($loaded.Count -eq 1) {
        $actual = $loaded[0]
        $actualName = $actual.GetName()
        if ($ExactBuild) {
            $stream = [IO.File]::OpenRead($Path)
            $reader = [System.Reflection.PortableExecutable.PEReader]::new($stream)
            try {
                $metadata = [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($reader)
                $moduleId = $metadata.GetGuid($metadata.GetModuleDefinition().Mvid)
            } finally { $reader.Dispose(); $stream.Dispose() }
            if ($actual.FullName -cne $expected.FullName -or
                $actual.ManifestModule.ModuleVersionId -ne $moduleId -or !$actual.Location -or
                (Get-FileHash -LiteralPath $actual.Location).Hash -cne (Get-FileHash -LiteralPath $Path).Hash) {
                throw "Incompatible $($expected.Name) build is already loaded. Import compatible modules in a fresh PowerShell process."
            }
        } elseif ($actualName.Version -lt $expected.Version -or
            $actualName.CultureName -ine $expected.CultureName -or
            ($actualName.GetPublicKeyToken() -join ',') -cne ($expected.GetPublicKeyToken() -join ',')) {
            throw "Incompatible $($expected.Name) assembly identity is already loaded. Start a fresh PowerShell process."
        }
        return
    }
    $null = [Reflection.Assembly]::LoadFrom($Path)
}
