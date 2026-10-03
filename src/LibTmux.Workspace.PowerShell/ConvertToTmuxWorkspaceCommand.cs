using System.Management.Automation;
using System.Runtime.Versioning;
using LibTmux.PowerShell;

namespace LibTmux.Workspace.PowerShell;

/// <summary>Converts a captured session to a native workspace declaration.</summary>
[Cmdlet(VerbsData.ConvertTo, "TmuxWorkspace")]
[OutputType(typeof(WorkspaceFile))]
[UnsupportedOSPlatform("windows")]
public sealed class ConvertToTmuxWorkspaceCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the session whose required hierarchy is already captured.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Session Session { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(_ =>
        {
            WorkspaceFile workspace = WorkspaceFile.FromSnapshot(Session);
            WriteWarning("Workspace conversion omits commands and shell state, environment, options, terminal text, entity IDs, pane indices, and shared-link identity. Custom layouts do not guarantee which pane occupies each position.");
            return Task.FromResult(workspace);
        }, "Tmux.WorkspaceFreezeFailed", Session);
}
