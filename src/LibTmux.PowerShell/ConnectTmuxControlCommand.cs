using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Attaches a caller-owned native control client to an explicit tmux target.</summary>
[Cmdlet(VerbsCommunications.Connect, "TmuxControl", SupportsShouldProcess = true)]
[OutputType(typeof(IControlModeSession))]
[UnsupportedOSPlatform("windows")]
public sealed class ConnectTmuxControlCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the borrowed server endpoint.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <summary>Gets or sets the raw tmux session target; this carries no captured identity guard.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    [ValidatePattern(@"\A[^\x00]*[^\s\x00][^\x00]*\z")]
    public string Target { get; set; } = string.Empty;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (!ShouldProcess($"{TmuxOwner.Describe(Server)} target {Target}", "Attach tmux control client"))
        {
            return;
        }

        RunOperation(token =>
        {
            IControlModeSession control = Server.EnterControlModeAsync(Target, token).GetAwaiter().GetResult();
            try
            {
                WriteObject(control);
            }
            catch (Exception failure)
            {
                try
                {
                    control.DisposeAsync().AsTask().GetAwaiter().GetResult();
                }
                catch (Exception cleanupFailure)
                {
                    failure.Data["LibTmux.ControlModeCleanupFailure"] = cleanupFailure;
                }

                throw;
            }
        }, "Tmux.ControlConnectFailed", Server);
    }
}
