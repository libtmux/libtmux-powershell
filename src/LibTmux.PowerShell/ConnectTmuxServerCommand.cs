using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Discovers a live server from an endpoint handle.</summary>
[Cmdlet(VerbsCommunications.Connect, "TmuxServer")]
[OutputType(typeof(Server))]
[UnsupportedOSPlatform("windows")]
public sealed class ConnectTmuxServerCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the endpoint handle to connect.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(Server.ConnectAsync, "Tmux.ConnectFailed", Server);
}
