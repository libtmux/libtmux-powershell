using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Resizes a pane or toggles its zoom.</summary>
[Cmdlet(VerbsCommon.Set, "TmuxPaneSize", DefaultParameterSetName = "Size", SupportsShouldProcess = true)]
[OutputType(typeof(Pane))]
[UnsupportedOSPlatform("windows")]
public sealed class SetTmuxPaneSizeCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the pane to resize.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Pane Pane { get; set; } = null!;

    /// <summary>Gets or sets the positive width in cells or as a percentage.</summary>
    [Parameter(ParameterSetName = "Size")]
    [ValidateNotNullOrEmpty]
    [ValidatePattern(@"\A0*[1-9][0-9]*%?\z")]
    public string? Width { get; set; }

    /// <summary>Gets or sets the positive height in cells or as a percentage.</summary>
    [Parameter(ParameterSetName = "Size")]
    [ValidateNotNullOrEmpty]
    [ValidatePattern(@"\A0*[1-9][0-9]*%?\z")]
    public string? Height { get; set; }

    /// <summary>Gets or sets the edge to move.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Direction")]
    [ValidateSet("Up", "Down", "Left", "Right")]
    public ResizeDirection Direction { get; set; }

    /// <summary>Gets or sets the positive number of cells to move the edge.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Direction")]
    [ValidateRange(1, int.MaxValue)]
    public int Adjustment { get; set; }

    /// <summary>Gets or sets whether to toggle zoom on or off.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Zoom")]
    public SwitchParameter Zoom { get; set; }

    /// <summary>Gets or sets whether to emit the native replacement pane.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        if ((ParameterSetName == "Size" && Width is null && Height is null)
            || (ParameterSetName == "Zoom" && !Zoom))
        {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentException("Specify Width or Height, Direction with Adjustment, or Zoom."),
                "Tmux.InvalidPaneSize", ErrorCategory.InvalidArgument, null));
        }
    }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        var request = new ResizePaneRequest
        {
            Width = Width,
            Height = Height,
            Direction = ParameterSetName == "Direction" ? Direction : null,
            Adjustment = ParameterSetName == "Direction" ? Adjustment : null,
            Zoom = Zoom,
        };
        if (ShouldProcess(TmuxOwner.Describe(Pane), Zoom ? "Toggle tmux pane zoom" : "Resize tmux pane"))
        {
            if (PassThru)
            {
                ReadResult(token => Pane.ResizeAsync(request, token), "Tmux.PaneResizeFailed", Pane);
            }
            else
            {
                ExecuteOperation(token => Pane.ResizeAsync(request, token), "Tmux.PaneResizeFailed", Pane);
            }
        }
    }
}
