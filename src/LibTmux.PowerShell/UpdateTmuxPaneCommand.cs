using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Refreshes a pane into a replacement captured handle.</summary>
[Cmdlet(VerbsData.Update, "TmuxPane")]
[OutputType(typeof(Pane))]
[UnsupportedOSPlatform("windows")]
public sealed class UpdateTmuxPaneCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the pane whose current state is read.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Pane Pane { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(token => Pane.RefreshAsync(token), "Tmux.PaneRefreshFailed", Pane);
}
