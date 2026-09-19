using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Removes a physical window and all its links without emitting a success object.</summary>
[Cmdlet(VerbsCommon.Remove, "TmuxWindow", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(void))]
[UnsupportedOSPlatform("windows")]
public sealed class RemoveTmuxWindowCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the physical window to remove from every session.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Window Window { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        Server server = Window.Server;
        string endpoint = server.ConnectionOptions.SocketPath ?? server.ConnectionOptions.SocketName ?? "default tmux endpoint";
        if (ShouldProcess($"{endpoint} window {Window.Id}", "Remove tmux window and all its links"))
        {
            ExecuteOperation(token => Window.KillAsync(cancellationToken: token), "Tmux.WindowRemoveFailed", Window);
        }
    }
}
