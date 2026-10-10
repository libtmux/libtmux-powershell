using System.Management.Automation;
using System.Text.Json;
using YamlDotNet.Core;

namespace LibTmux.Workspace.PowerShell;

/// <summary>Converts a native workspace declaration to YAML text.</summary>
[Cmdlet(VerbsData.ConvertTo, "TmuxWorkspaceYaml")]
[OutputType(typeof(string))]
public sealed class ConvertToTmuxWorkspaceYamlCommand : PSCmdlet
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
            WriteObject(WorkspaceSerialization.ToYaml(Workspace));
        }
        catch (Exception exception) when (exception is WorkspaceFormatException or ArgumentException or YamlException or JsonException)
        {
            ThrowTerminatingError(new ErrorRecord(exception, "Tmux.WorkspaceYamlFailed", ErrorCategory.InvalidData, Workspace));
        }
    }
}
