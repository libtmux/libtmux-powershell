using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Finds an exact session name or creates and owns a session.</summary>
[Cmdlet(VerbsDiagnostic.Resolve, "TmuxSession", SupportsShouldProcess = true)]
[OutputType(typeof(FoundOrCreated<Session>))]
[UnsupportedOSPlatform("windows")]
public sealed class ResolveTmuxSessionCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the captured parent to search.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <summary>Gets or sets the literal name to match in full.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string Name { get; set; } = null!;

    /// <summary>Gets or sets native creation options used only when no match exists.</summary>
    [Parameter]
    [ValidateNotNull]
    public NewSessionRequest? Request { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (ShouldProcess(Server.ToString(), "Find or create tmux session"))
        {
            ReadScopedResult(token => Server.FindOrCreateSessionAsync(Name, Request, token), "Tmux.SessionResolveFailed", Server);
        }
    }
}
