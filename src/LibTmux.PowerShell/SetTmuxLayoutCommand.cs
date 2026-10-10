using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Applies a named or captured layout, or cycles the layout of a window.</summary>
[Cmdlet(VerbsCommon.Set, "TmuxLayout", DefaultParameterSetName = "Layout", SupportsShouldProcess = true)]
[OutputType(typeof(Window))]
[UnsupportedOSPlatform("windows")]
public sealed class SetTmuxLayoutCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the window whose panes are arranged.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Window Window { get; set; } = null!;

    /// <summary>Gets or sets the layout preset or captured layout string.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Layout")]
    [ValidateNotNullOrEmpty]
    [ValidatePattern(@"\A[^\x00]*[^\s\x00][^\x00]*\z")]
    public string? Layout { get; set; }

    /// <summary>Gets or sets whether to spread panes or select the next or previous layout.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Mode")]
    [ValidateSet("Spread", "Next", "Previous")]
    public SelectLayoutMode Mode { get; set; }

    /// <summary>Gets or sets whether to emit the native replacement window.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        var request = new SelectLayoutRequest
        {
            Layout = Layout,
            Mode = ParameterSetName == "Mode" ? Mode : null,
        };
        if (ShouldProcess(TmuxOwner.Describe(Window), "Set tmux window layout"))
        {
            if (PassThru)
            {
                ReadResult(token => Window.SelectLayoutAsync(request, token), "Tmux.LayoutSetFailed", Window);
            }
            else
            {
                ExecuteOperation(token => Window.SelectLayoutAsync(request, token), "Tmux.LayoutSetFailed", Window);
            }
        }
    }
}
