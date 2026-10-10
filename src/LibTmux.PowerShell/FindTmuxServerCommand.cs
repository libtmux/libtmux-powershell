using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Returns bounded socket discovery results together with diagnostics and truncation.</summary>
[Cmdlet(VerbsCommon.Find, "TmuxServer")]
[OutputType(typeof(ServerDiscoveryResult))]
[UnsupportedOSPlatform("windows")]
public sealed class FindTmuxServerCommand : TmuxCmdlet
{
    /// <summary>Gets or sets additional absolute socket directories to inspect without recursion.</summary>
    [Parameter(Position = 0)]
    [ValidateNotNull]
    public string[] Root { get; set; } = [];

    /// <summary>Gets or sets whether to exclude the current user's configured roots.</summary>
    [Parameter]
    public SwitchParameter NoConfiguredRoots { get; set; }

    /// <summary>Gets or sets connection settings, including child environment and executable.</summary>
    [Parameter]
    [ValidateNotNull]
    public ServerConnectionOptions Connection { get; set; } = new();

    /// <summary>Gets or sets the maximum input root entries, including duplicates.</summary>
    [Parameter]
    [ValidateRange(1, int.MaxValue)]
    public int MaximumRoots { get; set; } = 16;

    /// <summary>Gets or sets the maximum directory entries examined.</summary>
    [Parameter]
    [ValidateRange(1, int.MaxValue)]
    public int MaximumEntries { get; set; } = 256;

    /// <summary>Gets or sets the maximum candidate socket probes.</summary>
    [Parameter]
    [ValidateRange(1, int.MaxValue)]
    public int MaximumProbes { get; set; } = 64;

    /// <summary>Gets or sets the overall deadline in milliseconds.</summary>
    [Parameter]
    [ValidateRange(1, int.MaxValue)]
    public int TimeoutMilliseconds { get; set; } = 5000;

    /// <summary>Gets or sets one no-start probe's deadline in milliseconds.</summary>
    [Parameter]
    [ValidateRange(1, int.MaxValue)]
    public int ProbeTimeoutMilliseconds { get; set; } = 250;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        var options = new ServerDiscoveryOptions
        {
            Roots = Array.AsReadOnly((string[])Root.Clone()),
            IncludeConfiguredRoots = !NoConfiguredRoots,
            Connection = Connection,
            MaximumRoots = MaximumRoots,
            MaximumEntries = MaximumEntries,
            MaximumProbes = MaximumProbes,
            Timeout = TimeSpan.FromMilliseconds(TimeoutMilliseconds),
            ProbeTimeout = TimeSpan.FromMilliseconds(ProbeTimeoutMilliseconds),
        };
        ReadResult(token => Server.DiscoverAsync(options, token), "Tmux.DiscoveryFailed", options);
    }
}
