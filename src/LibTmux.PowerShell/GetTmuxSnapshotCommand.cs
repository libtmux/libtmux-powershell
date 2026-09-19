using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Captures a replacement server snapshot from tmux.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxSnapshot")]
[OutputType(typeof(Server))]
[UnsupportedOSPlatform("windows")]
public sealed class GetTmuxSnapshotCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the server to read.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <summary>Gets or sets the deepest hierarchy level to capture.</summary>
    [Parameter]
    [ValidateSet(nameof(SnapshotDepth.Server), nameof(SnapshotDepth.Sessions), nameof(SnapshotDepth.Windows), nameof(SnapshotDepth.Panes))]
    public SnapshotDepth Depth { get; set; } = SnapshotDepth.Panes;

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(token => Server.CaptureSnapshotAsync(Depth, token), "Tmux.SnapshotFailed", Server);
}
