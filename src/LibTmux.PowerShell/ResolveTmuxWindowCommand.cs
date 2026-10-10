using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Finds one exact window name or creates and owns a window.</summary>
[Cmdlet(VerbsDiagnostic.Resolve, "TmuxWindow", SupportsShouldProcess = true)]
[OutputType(typeof(FoundOrCreated<Window>))]
[UnsupportedOSPlatform("windows")]
public sealed class ResolveTmuxWindowCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the captured parent to search.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Session Session { get; set; } = null!;

    /// <summary>Gets or sets the literal name to match in full.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string Name { get; set; } = null!;

    /// <summary>Gets or sets native creation options used only when no match exists.</summary>
    [Parameter]
    [ValidateNotNull]
    public NewWindowRequest? Request { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (ShouldProcess(Session.ToString(), "Find or create tmux window"))
        {
            ReadScopedResult(token => Session.FindOrCreateWindowAsync(Name, Request, token), "Tmux.WindowResolveFailed", Session);
        }
    }
}
