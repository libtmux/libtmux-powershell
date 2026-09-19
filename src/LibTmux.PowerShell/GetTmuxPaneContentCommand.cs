using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Captures rendered pane content as lines or one string.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxPaneContent", DefaultParameterSetName = "Range")]
[OutputType(typeof(string))]
[UnsupportedOSPlatform("windows")]
public sealed class GetTmuxPaneContentCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the pane to capture.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Pane Pane { get; set; } = null!;

    /// <summary>Gets or sets the first line; negative values address scrollback.</summary>
    [Parameter(ParameterSetName = "Range")]
    public int? StartLine { get; set; }

    /// <summary>Gets or sets the last line, relative to the visible pane.</summary>
    [Parameter]
    public int? EndLine { get; set; }

    /// <summary>Gets or sets whether capture starts at the oldest retained history.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "History")]
    public SwitchParameter History { get; set; }

    /// <summary>Gets or sets whether lines are joined with LF into one rendered string.</summary>
    [Parameter]
    public SwitchParameter Raw { get; set; }

    /// <summary>Gets or sets whether terminal escape sequences are retained.</summary>
    [Parameter]
    public SwitchParameter EscapeSequences { get; set; }

    /// <summary>Gets or sets whether nonprintable bytes use octal escapes.</summary>
    [Parameter]
    public SwitchParameter EscapeNonPrintable { get; set; }

    /// <summary>Gets or sets whether wrapped screen lines are joined.</summary>
    [Parameter]
    public SwitchParameter JoinWrappedLines { get; set; }

    /// <summary>Gets or sets whether trailing spaces are retained.</summary>
    [Parameter]
    public SwitchParameter PreserveTrailingSpaces { get; set; }

    /// <summary>Gets or sets whether trailing spaces are removed.</summary>
    [Parameter]
    public SwitchParameter TrimTrailingSpaces { get; set; }

    /// <summary>Gets or sets whether the alternate screen is captured.</summary>
    [Parameter]
    public SwitchParameter AlternateScreen { get; set; }

    /// <summary>Gets or sets whether a missing alternate screen returns empty content.</summary>
    [Parameter]
    public SwitchParameter Quiet { get; set; }

    /// <summary>Gets or sets whether the pane's mode screen is captured.</summary>
    [Parameter]
    public SwitchParameter ModeScreen { get; set; }

    /// <summary>Gets or sets whether incomplete pending output is captured.</summary>
    [Parameter]
    public SwitchParameter Pending { get; set; }

    /// <summary>Gets or sets whether supported captures include hyperlinks.</summary>
    [Parameter]
    public SwitchParameter Hyperlinks { get; set; }

    /// <summary>Gets or sets whether supported captures include line numbers.</summary>
    [Parameter]
    public SwitchParameter LineNumbers { get; set; }

    /// <summary>Gets or sets whether supported captures include line flags.</summary>
    [Parameter]
    public SwitchParameter LineFlags { get; set; }

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        if (PreserveTrailingSpaces && TrimTrailingSpaces)
        {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentException("PreserveTrailingSpaces and TrimTrailingSpaces cannot be combined."),
                "Tmux.InvalidCapture", ErrorCategory.InvalidArgument, null));
        }
    }

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(CaptureAsync, "Tmux.PaneCaptureFailed", Pane, enumerateCollection: !Raw);

    private async Task<object> CaptureAsync(CancellationToken cancellationToken)
    {
        CapturePanePosition? start = History
            ? CapturePanePosition.BeginningOfHistory
            : StartLine is int first ? new CapturePanePosition(first) : null;
        CapturePanePosition? end = EndLine is int last ? new CapturePanePosition(last) : null;
        var request = new CapturePaneRequest(
            startLine: start,
            endLine: end,
            escapeSequences: EscapeSequences,
            escapeNonPrintable: EscapeNonPrintable,
            joinWrappedLines: JoinWrappedLines,
            preserveTrailingSpaces: PreserveTrailingSpaces,
            trimTrailingSpaces: TrimTrailingSpaces,
            alternateScreen: AlternateScreen,
            quiet: Quiet,
            modeScreen: ModeScreen,
            pending: Pending,
            hyperlinks: Hyperlinks,
            lineNumbers: LineNumbers,
            lineFlags: LineFlags);
        IReadOnlyList<string> lines = await Pane.CaptureAsync(request, cancellationToken).ConfigureAwait(false);
        return Raw ? string.Join('\n', lines) : lines;
    }
}
