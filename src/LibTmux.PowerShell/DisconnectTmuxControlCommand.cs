using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Closes a native control client without ending its borrowed tmux daemon.</summary>
[Cmdlet(VerbsCommunications.Disconnect, "TmuxControl", SupportsShouldProcess = true)]
[UnsupportedOSPlatform("windows")]
public sealed class DisconnectTmuxControlCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the native control connection to dispose.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public IControlModeSession Connection { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (ShouldProcess("supplied tmux control connection", "Disconnect tmux control client"))
        {
            ExecuteOperation(_ => Connection.DisposeAsync().AsTask(), "Tmux.ControlDisconnectFailed", Connection);
        }
    }
}
