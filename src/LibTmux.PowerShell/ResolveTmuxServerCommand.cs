using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Finds the captured endpoint or starts and owns a daemon.</summary>
[Cmdlet(VerbsDiagnostic.Resolve, "TmuxServer", SupportsShouldProcess = true)]
[OutputType(typeof(FoundOrCreated<Server>))]
[UnsupportedOSPlatform("windows")]
public sealed class ResolveTmuxServerCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the captured endpoint to search.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (ShouldProcess(Server.ToString(), "Find or create tmux server"))
        {
            ReadScopedResult(token => Server.FindOrCreateAsync(token), "Tmux.ServerResolveFailed", Server);
        }
    }
}
