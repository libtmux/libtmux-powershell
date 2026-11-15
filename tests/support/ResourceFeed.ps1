# An owned NuGet v2 feed for the native package dependency checks. It serves the
# two tested archives from a package root on a loopback port, in the Atom shape
# PSResourceGet reads from FindPackagesById(), and the archive bytes for a
# download. Start-ResourceFeed returns once the listener accepts connections,
# and Stop-ResourceFeed ends it.
function Read-ResourceFeedPackage([string] $PackageRoot, [string] $Version) {
    $packages = @{}
    foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
        $path = Join-Path $PackageRoot "$name.$Version.nupkg"
        $archive = [IO.Compression.ZipFile]::OpenRead($path)
        try {
            $entry = $archive.GetEntry("$name.nuspec")
            $reader = [IO.StreamReader]::new($entry.Open())
            try { $nuspec = [xml] $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $archive.Dispose() }
        $metadata = $nuspec.DocumentElement.ChildNodes | Where-Object { $_.LocalName -ceq 'metadata' } | Select-Object -First 1
        $fields = @{}
        foreach ($child in $metadata.ChildNodes) { if ($child.NodeType -eq 'Element') { $fields[$child.LocalName] = $child.InnerText } }
        $dependencies = @($metadata.SelectNodes("//*[local-name()='dependencies']/*[local-name()='dependency']") |
            ForEach-Object { , @($_.GetAttribute('id'), $_.GetAttribute('version')) })
        $expected = @()
        if ($name.EndsWith('.Workspace')) { $expected = @(, @('LibTmux', "[$Version]")) }
        $same = $dependencies.Count -eq $expected.Count
        for ($index = 0; $same -and $index -lt $expected.Count; $index++) {
            $same = $dependencies[$index][0] -ceq $expected[$index][0] -and $dependencies[$index][1] -ceq $expected[$index][1]
        }
        if ($fields['id'] -cne $name -or $fields['version'] -cne $Version -or !$same) {
            throw 'The fixture requires the exact tested identities and dependency'
        }
        $packages[$name.ToLowerInvariant()] = @{ Fields = $fields; Dependencies = $dependencies; Payload = [IO.File]::ReadAllBytes($path) }
    }
    $packages
}

function Format-ResourceFeed {
    param($Record, [string] $Version)
    $escape = { param($value) [Security.SecurityElement]::Escape([string] $value) }
    $entry = ''
    if ($Record) {
        $fields = $Record.Fields
        $values = [ordered]@{
            Id = $fields['id']
            Version = $fields['version']
            NormalizedVersion = $fields['version']
            IsPrerelease = if ($Version.Contains('-')) { 'true' } else { 'false' }
            Dependencies = (@($Record.Dependencies | ForEach-Object { "$($_[0]):$($_[1]):" }) -join '|')
            Tags = 'PSModule ' + $(if ($fields.ContainsKey('tags')) { $fields['tags'] } else { '' })
            Authors = $(if ($fields.ContainsKey('authors')) { $fields['authors'] } else { '' })
            Description = $(if ($fields.ContainsKey('description')) { $fields['description'] } else { '' })
            Published = '2026-10-10T00:00:00Z'
        }
        $properties = ($values.GetEnumerator() | ForEach-Object { "<d:$($_.Key)>$(& $escape $_.Value)</d:$($_.Key)>" }) -join ''
        $entry = "<entry><m:properties>$properties</m:properties></entry>"
    }
    $count = if ($Record) { 1 } else { 0 }
    $atom = 'http://www.w3.org/2005/Atom'
    $data = 'http://schemas.microsoft.com/ado/2007/08/dataservices'
    $meta = 'http://schemas.microsoft.com/ado/2007/08/dataservices/metadata'
    '<?xml version="1.0" encoding="utf-8"?>' +
        "<feed xmlns=`"$atom`" xmlns:d=`"$data`" xmlns:m=`"$meta`"><m:count>$count</m:count>$entry</feed>"
}

function Start-ResourceFeed {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $PackageRoot, [Parameter(Mandatory)] [string] $Version)

    $packages = Read-ResourceFeedPackage $PackageRoot $Version
    $listener = $null
    for ($attempt = 0; $attempt -lt 10 -and !$listener; $attempt++) {
        # HttpListener cannot bind port 0, so ask the system for a free port first.
        $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $probe.Start()
        $port = $probe.LocalEndpoint.Port
        $probe.Stop()
        $candidate = [Net.HttpListener]::new()
        $candidate.Prefixes.Add("http://127.0.0.1:$port/")
        try { $candidate.Start(); $listener = $candidate } catch [Net.HttpListenerException] { $candidate.Close() }
    }
    if (!$listener) { throw 'The owned package feed could not bind a loopback port.' }

    $serve = {
        param($listener, $packages, $version, $formatText)
        $format = [scriptblock]::Create($formatText)
        while ($true) {
            try { $context = $listener.GetContext() } catch { break }
            $response = $context.Response
            try {
                $raw = $context.Request.RawUrl
                $path, $query = $raw.Split('?', 2)
                $body = $null
                if ($path -ceq '/api/v2/FindPackagesById()') {
                    $id = [Web.HttpUtility]::ParseQueryString([string] $query)['id']
                    $name = ([string] $id).Trim("'").ToLowerInvariant()
                    $record = if ($packages.ContainsKey($name)) { $packages[$name] } else { $null }
                    $body = [Text.Encoding]::UTF8.GetBytes((& $format $record $version))
                    $type = 'application/atom+xml'
                } elseif ($path.ToLowerInvariant().StartsWith('/api/v2/package/')) {
                    $parts = [Uri]::UnescapeDataString($path).Split('/')
                    if ($parts.Count -eq 6 -and $parts[5] -ceq $version -and $packages.ContainsKey($parts[4].ToLowerInvariant())) {
                        $body = $packages[$parts[4].ToLowerInvariant()].Payload
                        $type = 'application/octet-stream'
                    }
                }
                if ($null -eq $body) {
                    $response.StatusCode = 404
                } else {
                    $response.ContentType = $type
                    $response.ContentLength64 = $body.Length
                    $response.OutputStream.Write($body, 0, $body.Length)
                }
            } finally { $response.Close() }
        }
    }
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $worker = [powershell]::Create()
    $worker.Runspace = $runspace
    $formatter = (Get-Command Format-ResourceFeed -CommandType Function).ScriptBlock.ToString()
    $null = $worker.AddScript($serve).AddArgument($listener).AddArgument($packages).AddArgument($Version).AddArgument($formatter)
    $pending = $worker.BeginInvoke()
    [pscustomobject]@{
        Uri = "http://127.0.0.1:$port/api/v2"
        Listener = $listener
        Worker = $worker
        Pending = $pending
        Runspace = $runspace
    }
}

function Stop-ResourceFeed($Feed) {
    if (!$Feed) { return }
    try {
        $Feed.Listener.Stop()
        if (!$Feed.Pending.AsyncWaitHandle.WaitOne(1000)) { throw 'The owned package feed did not stop when asked.' }
        $null = $Feed.Worker.EndInvoke($Feed.Pending)
        if ($Feed.Worker.Streams.Error.Count) { throw "The owned package feed failed: $($Feed.Worker.Streams.Error[0])" }
    } finally {
        $Feed.Listener.Close()
        $Feed.Worker.Dispose()
        $Feed.Runspace.Dispose()
    }
}
