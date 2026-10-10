using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Resizes a window by cells, an edge adjustment, or its client sizes.</summary>
[Cmdlet(VerbsCommon.Set, "TmuxWindowSize", DefaultParameterSetName = "Size", SupportsShouldProcess = true)]
[OutputType(typeof(Window))]
[UnsupportedOSPlatform("windows")]
public sealed class SetTmuxWindowSizeCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the window to resize.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Window Window { get; set; } = null!;

    /// <summary>Gets or sets the positive width in cells.</summary>
    [Parameter(ParameterSetName = "Size")]
    [ValidateRange(1, int.MaxValue)]
    public int? Width { get; set; }

    /// <summary>Gets or sets the positive height in cells.</summary>
    [Parameter(ParameterSetName = "Size")]
    [ValidateRange(1, int.MaxValue)]
    public int? Height { get; set; }

    /// <summary>Gets or sets the edge to move.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Direction")]
    [ValidateSet("Up", "Down", "Left", "Right")]
    public ResizeDirection Direction { get; set; }

    /// <summary>Gets or sets the positive number of cells to move the edge.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Direction")]
    [ValidateRange(1, int.MaxValue)]
    public int Adjustment { get; set; }

    /// <summary>Gets or sets whether to size to the largest or smallest client.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Mode")]
    [ValidateSet("Expand", "Shrink")]
    public WindowResizeMode Mode { get; set; }

    /// <summary>Gets or sets whether to emit the native replacement window.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        if (ParameterSetName == "Size" && Width is null && Height is null)
        {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentException("Specify Width or Height, Direction with Adjustment, or Mode."),
                "Tmux.InvalidWindowSize", ErrorCategory.InvalidArgument, null));
        }
    }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        var request = new ResizeWindowRequest
        {
            Width = Width,
            Height = Height,
            Direction = ParameterSetName == "Direction" ? Direction : null,
            Adjustment = ParameterSetName == "Direction" ? Adjustment : null,
            Mode = ParameterSetName == "Mode" ? Mode : null,
        };
        if (ShouldProcess(TmuxOwner.Describe(Window), "Resize tmux window"))
        {
            if (PassThru)
            {
                ReadResult(token => Window.ResizeAsync(request, token), "Tmux.WindowResizeFailed", Window);
            }
            else
            {
                ExecuteOperation(token => Window.ResizeAsync(request, token), "Tmux.WindowResizeFailed", Window);
            }
        }
    }
}
