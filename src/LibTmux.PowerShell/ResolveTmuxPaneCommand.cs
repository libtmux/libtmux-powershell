using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Finds one application pane identity or splits and owns a pane.</summary>
[Cmdlet(VerbsDiagnostic.Resolve, "TmuxPane", SupportsShouldProcess = true)]
[OutputType(typeof(FoundOrCreated<Pane>))]
[UnsupportedOSPlatform("windows")]
public sealed class ResolveTmuxPaneCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the captured parent to search.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Window Window { get; set; } = null!;

    /// <summary>Gets or sets the application identity stored in the pane's local @libtmux-identity option.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string Identity { get; set; } = null!;

    /// <summary>Gets or sets native creation options used only when no match exists.</summary>
    [Parameter]
    [ValidateNotNull]
    public SplitPaneRequest? Request { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (ShouldProcess(Window.ToString(), "Find or create tmux pane"))
        {
            ReadScopedResult(token => Window.FindOrCreatePaneAsync(Identity, Request, token), "Tmux.PaneResolveFailed", Window);
        }
    }
}
