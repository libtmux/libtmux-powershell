using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Removes a pane without emitting a success object.</summary>
[Cmdlet(VerbsCommon.Remove, "TmuxPane", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(void))]
[UnsupportedOSPlatform("windows")]
public sealed class RemoveTmuxPaneCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the pane to remove.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Pane Pane { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        Server server = Pane.Server;
        string endpoint = server.ConnectionOptions.SocketPath ?? server.ConnectionOptions.SocketName ?? "default tmux endpoint";
        if (ShouldProcess($"{endpoint} pane {Pane.Id}", "Remove tmux pane"))
        {
            ExecuteOperation(token => Pane.KillAsync(cancellationToken: token), "Tmux.PaneRemoveFailed", Pane);
        }
    }
}
