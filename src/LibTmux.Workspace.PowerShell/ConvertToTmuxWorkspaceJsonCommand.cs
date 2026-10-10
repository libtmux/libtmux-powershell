using System.Management.Automation;
using System.Text.Json;
using YamlDotNet.Core;

namespace LibTmux.Workspace.PowerShell;

/// <summary>Converts a native workspace declaration to JSON text.</summary>
[Cmdlet(VerbsData.ConvertTo, "TmuxWorkspaceJson")]
[OutputType(typeof(string))]
public sealed class ConvertToTmuxWorkspaceJsonCommand : PSCmdlet
{
    /// <summary>Gets or sets the declaration to serialize without executing it.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public WorkspaceFile Workspace { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        try
        {
            WriteObject(WorkspaceSerialization.ToJson(Workspace));
        }
        catch (Exception exception) when (exception is WorkspaceFormatException or ArgumentException or YamlException or JsonException)
        {
            ThrowTerminatingError(new ErrorRecord(exception, "Tmux.WorkspaceJsonFailed", ErrorCategory.InvalidData, Workspace));
        }
    }
}
