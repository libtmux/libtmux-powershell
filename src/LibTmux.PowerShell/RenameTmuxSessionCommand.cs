using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Renames a session and optionally emits its replacement handle.</summary>
[Cmdlet(VerbsCommon.Rename, "TmuxSession", SupportsShouldProcess = true)]
[OutputType(typeof(Session))]
[UnsupportedOSPlatform("windows")]
public sealed class RenameTmuxSessionCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the session to rename.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Session Session { get; set; } = null!;

    /// <summary>Gets or sets the new session name.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string Name { get; set; } = null!;

    /// <summary>Gets or sets whether to emit the replacement session handle.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (!ShouldProcess($"{CreationEnvironment.Endpoint(Session.Server)} session {Session.Id}", "Rename tmux session"))
        {
            return;
        }

        if (PassThru)
        {
            ReadResult(token => Session.RenameAsync(Name, token), "Tmux.SessionRenameFailed", Session);
        }
        else
        {
            ExecuteOperation(token => Session.RenameAsync(Name, token), "Tmux.SessionRenameFailed", Session);
        }
    }
}
