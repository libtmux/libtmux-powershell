using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Inspects daemon identity and version without starting a server.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxServer")]
[OutputType(typeof(Server))]
[UnsupportedOSPlatform("windows")]
public sealed class GetTmuxServerCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the server endpoint to inspect.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        RunOperation(token =>
        {
            Server? inspected = Server.InspectAsync(token).GetAwaiter().GetResult();
            if (inspected is not null)
            {
                WriteObject(inspected);
            }
        }, "Tmux.ServerInspectionFailed", Server);
}
