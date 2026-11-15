using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Renames a window and optionally emits its replacement handle.</summary>
[Cmdlet(VerbsCommon.Rename, "TmuxWindow", SupportsShouldProcess = true)]
[OutputType(typeof(Window))]
[UnsupportedOSPlatform("windows")]
public sealed class RenameTmuxWindowCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the window to rename.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Window Window { get; set; } = null!;

    /// <summary>Gets or sets the new window name.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string Name { get; set; } = null!;

    /// <summary>Gets or sets whether to emit the replacement window handle.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (!ShouldProcess(TmuxOwner.Describe(Window), "Rename tmux window"))
        {
            return;
        }

        if (PassThru)
        {
            ReadResult(token => Window.RenameAsync(Name, token), "Tmux.WindowRenameFailed", Window);
        }
        else
        {
            ExecuteOperation(token => Window.RenameAsync(Name, token), "Tmux.WindowRenameFailed", Window);
        }
    }
}
