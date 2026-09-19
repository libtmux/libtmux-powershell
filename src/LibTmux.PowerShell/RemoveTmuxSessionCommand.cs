using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Removes a session without emitting a success object.</summary>
[Cmdlet(VerbsCommon.Remove, "TmuxSession", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(void))]
[UnsupportedOSPlatform("windows")]
public sealed class RemoveTmuxSessionCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the session to remove.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Session Session { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        Server server = Session.Server;
        string endpoint = server.ConnectionOptions.SocketPath ?? server.ConnectionOptions.SocketName ?? "default tmux endpoint";
        if (ShouldProcess($"{endpoint} session {Session.Id}", "Remove tmux session"))
        {
            ExecuteOperation(token => Session.KillAsync(cancellationToken: token), "Tmux.SessionRemoveFailed", Session);
        }
    }
}
