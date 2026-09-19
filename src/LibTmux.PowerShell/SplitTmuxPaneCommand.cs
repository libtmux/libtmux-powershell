using System.Collections;
using System.Globalization;
using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Splits a pane and returns the created pane's captured core object.</summary>
[Cmdlet(VerbsCommon.Split, "TmuxPane", SupportsShouldProcess = true, DefaultParameterSetName = "Cells")]
[OutputType(typeof(Pane))]
[UnsupportedOSPlatform("windows")]
public sealed class SplitTmuxPaneCommand : TmuxCmdlet
{
    private SplitPaneRequest request = null!;

    /// <summary>Gets or sets the pane to split.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Pane Pane { get; set; } = null!;

    /// <summary>Gets or sets whether the split runs left to right instead of top to bottom.</summary>
    [Parameter]
    public SwitchParameter Horizontal { get; set; }

    /// <summary>Gets or sets whether the new pane goes above or left of the target.</summary>
    [Parameter]
    public SwitchParameter Before { get; set; }

    /// <summary>Gets or sets the new pane's size in cells.</summary>
    [Parameter(ParameterSetName = "Cells")]
    [ValidateRange(1, int.MaxValue)]
    public int? Size { get; set; }

    /// <summary>Gets or sets the new pane's size as a percentage.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Percentage")]
    [ValidateRange(1, 100)]
    public int? Percentage { get; set; }

    /// <summary>Gets or sets the new pane's working directory.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? StartDirectory { get; set; }

    /// <summary>Gets or sets one shell-command string for the new pane.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? Command { get; set; }

    /// <summary>Gets or sets process environment entries with string keys and values.</summary>
    [Parameter]
    [ValidateNotNull]
    public IDictionary? Environment { get; set; }

    /// <summary>Gets or sets whether the new pane becomes active.</summary>
    [Parameter]
    public SwitchParameter Activate { get; set; }

    /// <summary>Gets or sets whether the split spans the whole window.</summary>
    [Parameter]
    public SwitchParameter FullWindow { get; set; }

    /// <summary>Gets or sets whether tmux zooms the new pane.</summary>
    [Parameter]
    public SwitchParameter Zoom { get; set; }

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        try
        {
            PaneDirection direction = Horizontal
                ? Before ? PaneDirection.Left : PaneDirection.Right
                : Before ? PaneDirection.Above : PaneDirection.Below;
            request = new SplitPaneRequest(
                direction: direction,
                size: Size?.ToString(CultureInfo.InvariantCulture),
                percentage: Percentage,
                startDirectory: StartDirectory,
                command: Command,
                attach: Activate,
                fullWindow: FullWindow,
                zoom: Zoom,
                environment: CreationEnvironment.Copy(Environment));
        }
        catch (ArgumentException exception)
        {
            ThrowTerminatingError(new ErrorRecord(
                exception, "Tmux.InvalidCreation", ErrorCategory.InvalidArgument, null));
        }
    }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (ShouldProcess($"{CreationEnvironment.Endpoint(Pane.Server)} pane {Pane.Id}", "Split tmux pane"))
        {
            ReadResult(token => Pane.SplitAsync(request, token), "Tmux.PaneSplitFailed", Pane);
        }
    }
}
