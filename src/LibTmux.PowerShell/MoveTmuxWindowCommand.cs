using System.Globalization;
using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Moves one captured window placement and optionally emits its replacement.</summary>
[Cmdlet(VerbsCommon.Move, "TmuxWindow", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(Window))]
[UnsupportedOSPlatform("windows")]
public sealed class MoveTmuxWindowCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the captured source placement.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Window Window { get; set; } = null!;

    /// <summary>Gets or sets another destination session; omission keeps the source session.</summary>
    [Parameter]
    [ValidateNotNull]
    public Session? DestinationSession { get; set; }

    /// <summary>Gets or sets the session-relative destination index.</summary>
    [Parameter]
    [ValidateRange(0, int.MaxValue)]
    public int? Index { get; set; }

    /// <summary>Gets or sets insertion before or after the destination.</summary>
    [Parameter]
    public WindowDirection? Direction { get; set; }

    /// <summary>Gets or sets whether the moved window stays unselected.</summary>
    [Parameter]
    public SwitchParameter NoSelect { get; set; }

    /// <summary>Gets or sets whether a window already at the destination is replaced.</summary>
    [Parameter]
    public SwitchParameter ReplaceExisting { get; set; }

    /// <summary>Gets or sets whether to emit the replacement placement handle.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (DestinationSession is Session destination
            && (Window.Server != destination.Server || Window.Generation != destination.Generation))
        {
            WriteError(new ErrorRecord(
                new ArgumentException("Destination session must belong to the source window's server generation.", nameof(DestinationSession)),
                "Tmux.WindowMoveFailed", ErrorCategory.InvalidArgument, Window));
            return;
        }

        string destinationLabel = DestinationSession is null ? "its source session" : $"session {DestinationSession.Id}";
        if (!ShouldProcess(
            $"{TmuxOwner.Describe(Window)} to {destinationLabel}{(Index is int index ? ":" + index.ToString(CultureInfo.InvariantCulture) : string.Empty)}",
            "Move tmux window placement"))
        {
            return;
        }

        var request = new MoveWindowRequest
        {
            Session = DestinationSession?.Id.ToString(),
            Destination = Index?.ToString(CultureInfo.InvariantCulture) ?? string.Empty,
            Direction = Direction,
            NoSelect = NoSelect,
            ReplaceExisting = ReplaceExisting,
        };
        if (PassThru)
        {
            ReadResult(token => Window.MoveAsync(request, token), "Tmux.WindowMoveFailed", Window);
        }
        else
        {
            ExecuteOperation(token => Window.MoveAsync(request, token), "Tmux.WindowMoveFailed", Window);
        }
    }
}
