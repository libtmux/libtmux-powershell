using System.Globalization;
using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Links a captured window placement into another session.</summary>
[Cmdlet(VerbsCommon.New, "TmuxWindowLink", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(void))]
[UnsupportedOSPlatform("windows")]
public sealed class NewTmuxWindowLinkCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the captured source placement.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Window Window { get; set; } = null!;

    /// <summary>Gets or sets the destination session on the same server generation.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    public Session Session { get; set; } = null!;

    /// <summary>Gets or sets the session-relative destination index.</summary>
    [Parameter]
    [ValidateRange(0, int.MaxValue)]
    public int? Index { get; set; }

    /// <summary>Gets or sets insertion before or after the destination.</summary>
    [Parameter]
    public WindowDirection? Direction { get; set; }

    /// <summary>Gets or sets whether a window already at the destination is replaced.</summary>
    [Parameter]
    public SwitchParameter ReplaceExisting { get; set; }

    /// <summary>Gets or sets whether the linked window stays unselected.</summary>
    [Parameter]
    public SwitchParameter NoSelect { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (Window.Server != Session.Server || Window.Generation != Session.Generation)
        {
            WriteError(new ErrorRecord(
                new ArgumentException("Destination session must belong to the source window's server generation.", nameof(Session)),
                "Tmux.WindowLinkFailed", ErrorCategory.InvalidArgument, Window));
            return;
        }

        if (!ShouldProcess(
            $"{TmuxOwner.Describe(Window)} to session {Session.Id}{(Index is int index ? ":" + index.ToString(CultureInfo.InvariantCulture) : string.Empty)}",
            "Link tmux window placement"))
        {
            return;
        }

        var request = new LinkWindowRequest(Session.Id.ToString())
        {
            TargetIndex = Index?.ToString(CultureInfo.InvariantCulture),
            Direction = Direction,
            ReplaceExisting = ReplaceExisting,
            Detach = NoSelect,
        };
        ExecuteOperation(token => Window.LinkAsync(request, token), "Tmux.WindowLinkFailed", Window);
    }
}
