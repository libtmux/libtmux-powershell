using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Stops a tmux server without emitting a success object.</summary>
[Cmdlet(VerbsLifecycle.Stop, "TmuxServer", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(void))]
[UnsupportedOSPlatform("windows")]
public sealed class StopTmuxServerCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the server to stop.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (ShouldProcess(CreationEnvironment.Endpoint(Server), "Stop tmux server"))
        {
            ExecuteOperation(token => Server.KillAsync(token), "Tmux.ServerStopFailed", Server);
        }
    }
}
