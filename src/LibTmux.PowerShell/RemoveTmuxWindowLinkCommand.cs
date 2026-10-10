using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Removes only the captured session placement of a window.</summary>
[Cmdlet(VerbsCommon.Remove, "TmuxWindowLink", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(void))]
[UnsupportedOSPlatform("windows")]
public sealed class RemoveTmuxWindowLinkCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the captured window placement to unlink.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Window Window { get; set; } = null!;

    /// <summary>Gets or sets whether tmux may kill the window if this is its last link.</summary>
    [Parameter]
    public SwitchParameter KillIfLast { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (ShouldProcess(TmuxOwner.Describe(Window), KillIfLast
            ? "Unlink tmux window placement; kill window if last link"
            : "Unlink tmux window placement"))
        {
            ExecuteOperation(token => Window.UnlinkAsync(KillIfLast, token), "Tmux.WindowUnlinkFailed", Window);
        }
    }
}
