# Owned NuGet v2 feed for native prerelease dependency verification. It runs
# in this process: it is listening when Start-ResourceFeed returns and stopped
# when Stop-ResourceFeed returns, so neither side waits on a process.

function New-ResourceFeedXml($Record) {
    $atom = [Xml.Linq.XNamespace] 'http://www.w3.org/2005/Atom'
    $data = [Xml.Linq.XNamespace] 'http://schemas.microsoft.com/ado/2007/08/dataservices'
    $meta = [Xml.Linq.XNamespace] 'http://schemas.microsoft.com/ado/2007/08/dataservices/metadata'
    $root = [Xml.Linq.XElement]::new($atom + 'feed',
        [Xml.Linq.XAttribute]::new([Xml.Linq.XNamespace]::Xmlns + 'd', $data.NamespaceName),
        [Xml.Linq.XAttribute]::new([Xml.Linq.XNamespace]::Xmlns + 'm', $meta.NamespaceName),
        [Xml.Linq.XElement]::new($meta + 'count', $(if ($Record) { '1' } else { '0' })))
    if ($Record) {
        $properties = [Xml.Linq.XElement]::new($meta + 'properties')
        $values = [ordered]@{
            Id = $Record.Id; Version = $Record.Version; NormalizedVersion = $Record.Version
            IsPrerelease = 'true'
            Dependencies = ($Record.Dependencies | ForEach-Object { "$($_.Id):$($_.Version):" }) -join '|'
            Tags = 'PSModule ' + $Record.Tags; Authors = $Record.Authors
            Description = $Record.Description; Published = '2026-10-10T00:00:00Z'
        }
        foreach ($name in $values.Keys) {
            $properties.Add([Xml.Linq.XElement]::new($data + $name, [string] $values[$name]))
        }
        $root.Add([Xml.Linq.XElement]::new($atom + 'entry', $properties))
    }
    [Text.Encoding]::UTF8.GetBytes('<?xml version="1.0" encoding="utf-8"?>' +
        $root.ToString([Xml.Linq.SaveOptions]::DisableFormatting))
}

function Read-ResourceFeedPackage([string] $PackageRoot, [string] $Name, [string] $Version) {
    $path = Join-Path $PackageRoot "$Name.$Version.nupkg"
    $archive = [IO.Compression.ZipFile]::OpenRead($path)
    try {
        $reader = [IO.StreamReader]::new($archive.GetEntry("$Name.nuspec").Open())
        try { $nuspec = [Xml.Linq.XDocument]::Parse($reader.ReadToEnd()) } finally { $reader.Dispose() }
    } finally { $archive.Dispose() }
    $metadata = @($nuspec.Root.Elements() | Where-Object { $_.Name.LocalName -ceq 'metadata' })[0]
    $fields = @{}
    foreach ($child in $metadata.Elements()) { $fields[$child.Name.LocalName] = $child.Value }
    $dependencies = @($metadata.Elements() | Where-Object { $_.Name.LocalName -ceq 'dependencies' } |
        ForEach-Object { $_.Elements() } | Where-Object { $_.Name.LocalName -ceq 'dependency' } |
        ForEach-Object { [pscustomobject]@{ Id = $_.Attribute('id').Value; Version = $_.Attribute('version').Value } })
    $expected = if ($Name.EndsWith('.Workspace')) { "LibTmux:[$Version]" } else { '' }
    $actual = ($dependencies | ForEach-Object { "$($_.Id):$($_.Version)" }) -join '|'
    if ($fields['id'] -cne $Name -or $fields['version'] -cne $Version -or $actual -cne $expected) {
        throw 'The fixture requires the exact tested alpha identities and dependency.'
    }
    [pscustomobject]@{
        Id = $Name; Version = $Version; Dependencies = $dependencies
        Tags = [string] $fields['tags']; Authors = [string] $fields['authors']
        Description = [string] $fields['description']
        Payload = [IO.File]::ReadAllBytes($path)
    }
}

function Start-ResourceFeed([string] $PackageRoot, [string] $Version) {
    $responses = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $responses['/api/v2/FindPackagesById()'] = @{ Type = 'application/atom+xml'; Body = (New-ResourceFeedXml $null) }
    foreach ($name in 'LibTmux', 'LibTmux.Workspace') {
        $record = Read-ResourceFeedPackage $PackageRoot $name $Version
        $responses["/api/v2/FindPackagesById()?$($name.ToLowerInvariant())"] = @{
            Type = 'application/atom+xml'; Body = (New-ResourceFeedXml $record)
        }
        $responses["/api/v2/package/$($name.ToLowerInvariant())/$Version"] = @{
            Type = 'application/octet-stream'; Body = $record.Payload
        }
    }
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $stop = [Threading.CancellationTokenSource]::new()
    $shell = [PowerShell]::Create()
    $null = $shell.AddScript({
            param($Listener, $Token, $Responses)
            $ErrorActionPreference = 'Stop'
            $notFound = [Text.Encoding]::ASCII.GetBytes("HTTP/1.0 404 Not Found`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
            while ($true) {
                try { $client = $Listener.AcceptTcpClientAsync($Token).AsTask().GetAwaiter().GetResult() }
                catch [OperationCanceledException] { return }
                try {
                    $stream = $client.GetStream()
                    $head = [IO.MemoryStream]::new()
                    $buffer = [byte[]]::new(4096)
                    while ($true) {
                        $read = $stream.ReadAsync($buffer, 0, $buffer.Length, $Token).GetAwaiter().GetResult()
                        if ($read -eq 0) { break }
                        $head.Write($buffer, 0, $read)
                        if ([Text.Encoding]::ASCII.GetString($head.ToArray()).Contains("`r`n`r`n")) { break }
                    }
                    $line = ([Text.Encoding]::ASCII.GetString($head.ToArray()) -split "`r`n")[0]
                    $target = [Uri]::UnescapeDataString(($line -split ' ')[1])
                    $path, $query = $target -split '\?', 2
                    $key = if ($path -ceq '/api/v2/FindPackagesById()') {
                        $id = [regex]::Match([string] $query, "(?:^|&)id='?([^'&]*)'?").Groups[1].Value.ToLowerInvariant()
                        if ($Responses.ContainsKey("${path}?$id")) { "${path}?$id" } else { $path }
                    } elseif ($path.ToLowerInvariant().StartsWith('/api/v2/package/')) {
                        $parts = $path.Split('/')
                        if ($parts.Count -eq 6) { "/api/v2/package/$($parts[4].ToLowerInvariant())/$($parts[5])" }
                    }
                    $response = if ($key) { $Responses[$key] }
                    if ($response) {
                        $header = "HTTP/1.0 200 OK`r`nContent-Type: $($response.Type)`r`nContent-Length: $($response.Body.Length)`r`nConnection: close`r`n`r`n"
                        $bytes = [Text.Encoding]::ASCII.GetBytes($header)
                        $stream.Write($bytes, 0, $bytes.Length)
                        $stream.Write($response.Body, 0, $response.Body.Length)
                    } else {
                        $stream.Write($notFound, 0, $notFound.Length)
                    }
                } catch [OperationCanceledException] {
                    return
                } finally { $client.Dispose() }
            }
        }).AddArgument($listener).AddArgument($stop.Token).AddArgument($responses)
    $invocation = $shell.BeginInvoke()
    [pscustomobject]@{
        Uri = "http://127.0.0.1:$($listener.LocalEndpoint.Port)/api/v2"
        Listener = $listener; Stop = $stop; Shell = $shell; Invocation = $invocation
    }
}

function Stop-ResourceFeed($Feed) {
    try {
        $Feed.Stop.Cancel()
        $Feed.Listener.Stop()
        $null = $Feed.Shell.EndInvoke($Feed.Invocation)
        if ($Feed.Shell.HadErrors) { throw 'The owned package feed failed while serving.' }
    } finally {
        $Feed.Shell.Dispose()
        $Feed.Stop.Dispose()
    }
}
