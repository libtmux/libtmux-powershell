using System.Management.Automation;
using System.Text;
using LibTmux.PowerShell;

namespace LibTmux.Workspace.PowerShell;

/// <summary>Discovers declaration files without loading tmux sessions.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxWorkspace", DefaultParameterSetName = "Discover")]
[OutputType(typeof(FileInfo))]
public sealed class GetTmuxWorkspaceCommand : TmuxCmdlet
{
    /// <summary>Gets or sets one literal filesystem path, bypassing discovery.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "LiteralPath")]
    [ValidateNotNullOrEmpty]
    public string? LiteralPath { get; set; }

    /// <summary>Gets or sets a literal global declaration basename, with an optional supported extension.</summary>
    [Parameter(Mandatory = true, Position = 0, ParameterSetName = "Name")]
    [ValidateNotNullOrEmpty]
    public string? Name { get; set; }

    /// <summary>Gets or sets a directory whose local .tmuxp declarations are listed without ancestor or global discovery.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Directory")]
    [ValidateNotNullOrEmpty]
    public string? Directory { get; set; }

    /// <summary>Gets or sets the highest-precedence global configuration directory.</summary>
    [Parameter(ParameterSetName = "Discover")]
    [Parameter(ParameterSetName = "Name")]
    [Parameter(ParameterSetName = "Search")]
    [ValidateNotNullOrEmpty]
    public string? ConfigurationDirectory { get; set; }

    /// <summary>Gets or sets whether all existing global locations are included instead of only the first.</summary>
    [Parameter(ParameterSetName = "Discover")]
    [Parameter(ParameterSetName = "Name")]
    [Parameter(ParameterSetName = "Search")]
    public SwitchParameter AllLocations { get; set; }

    /// <summary>Gets or sets literal substring text to search for.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Search")]
    [ValidateLength(1, 4096)]
    [ValidateNotNullOrEmpty]
    public string? Search { get; set; }

    /// <summary>Gets or sets searched fields; declaration fields opt into bounded parsing.</summary>
    [Parameter(ParameterSetName = "Search")]
    [ValidateNotNullOrEmpty]
    [ValidateCount(1, 6)]
    [ValidateSet("FileName", "Path", "Session", "Window", "Command", "Directory")]
    public string[] SearchIn { get; set; } = ["FileName"];

    /// <summary>Gets or sets ordinal case-sensitive substring search instead of ordinal-ignore-case search.</summary>
    [Parameter(ParameterSetName = "Search")]
    public SwitchParameter CaseSensitive { get; set; }

    /// <inheritdoc />
    protected override ErrorCategory GetErrorCategory(Exception exception) => exception switch
    {
        InvalidDataException or DecoderFallbackException or WorkspaceFormatException => ErrorCategory.InvalidData,
        FileNotFoundException or DirectoryNotFoundException => ErrorCategory.ObjectNotFound,
        UnauthorizedAccessException => ErrorCategory.PermissionDenied,
        IOException => ErrorCategory.ReadError,
        _ => base.GetErrorCategory(exception),
    };

    /// <inheritdoc />
    protected override void ProcessRecord() => ReadResult(DiscoverAsync, "Tmux.WorkspaceDiscoveryFailed",
        (object?)LiteralPath ?? Name ?? Directory ?? Search ?? ConfigurationDirectory ?? SessionState.Path.CurrentFileSystemLocation.Path,
        enumerateCollection: true);

    private Task<IReadOnlyList<FileInfo>> DiscoverAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var discovery = new WorkspaceDiscovery(cancellationToken);
        if (LiteralPath is not null)
        {
            discovery.AddLiteral(WorkspaceDocument.FileSystemPath(SessionState.Path, LiteralPath));
        }
        else if (Directory is not null)
        {
            discovery.AddLocal(WorkspaceDocument.FileSystemPath(SessionState.Path, Directory), null, ancestors: false);
        }
        else
        {
            if (Name is not null) { WorkspaceDiscovery.ValidateName(Name); }
            string current = SessionState.Path.CurrentFileSystemLocation.ProviderPath;
            string? home = Environment.GetEnvironmentVariable("HOME");
            if (string.IsNullOrEmpty(home)) { home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile); }
            home = string.IsNullOrEmpty(home) ? null : Path.TrimEndingDirectorySeparator(WorkspaceDocument.FileSystemPath(SessionState.Path, home));
            IReadOnlyList<string> locations = GlobalDirectories(home, cancellationToken);
            if (Name is null) { discovery.AddLocal(current, home, ancestors: true); }
            discovery.AddGlobal(locations, Name);
        }
        return discovery.CompleteAsync(Search, SearchIn, CaseSensitive);
    }

    private List<string> GlobalDirectories(string? home, CancellationToken cancellationToken)
    {
        List<string> candidates = [];
        if (ConfigurationDirectory is not null) { candidates.Add(ConfigurationDirectory); }
        string? configured = Environment.GetEnvironmentVariable("TMUXP_CONFIGDIR");
        if (!string.IsNullOrEmpty(configured)) { candidates.Add(configured); }
        string? xdg = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        if (!string.IsNullOrEmpty(xdg)) { candidates.Add(Path.Combine(xdg, "tmuxp")); }
        else if (home is not null) { candidates.Add(Path.Combine(home, ".config", "tmuxp")); }
        if (home is not null) { candidates.Add(Path.Combine(home, ".tmuxp")); }

        List<string> selected = [];
        StringComparer comparer = OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;
        HashSet<string> seen = new(comparer);
        for (int index = 0; index < candidates.Count; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            string candidate = candidates[index];
            string path = WorkspaceDocument.FileSystemPath(SessionState.Path, candidate);
            path = Path.TrimEndingDirectorySeparator(path);
            if (!seen.Add(path)) { continue; }
            bool required = ConfigurationDirectory is not null && index == 0;
            if (!WorkspaceDiscovery.IsDirectory(path, required)) { continue; }
            selected.Add(path);
            if (!AllLocations) { break; }
        }
        return selected;
    }
}
