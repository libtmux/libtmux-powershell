using System.Management.Automation;

namespace LibTmux.Workspace.PowerShell;

/// <summary>Parses a tmuxp declaration without running it.</summary>
[Cmdlet(VerbsData.Import, "TmuxWorkspace", DefaultParameterSetName = "Path")]
[OutputType(typeof(WorkspaceFile))]
public sealed class ImportTmuxWorkspaceCommand : PSCmdlet
{
    /// <summary>Gets or sets the literal file path to read.</summary>
    [Parameter(Mandatory = true, Position = 0, ParameterSetName = "Path")]
    [ValidateNotNullOrEmpty]
    public string LiteralPath { get; set; } = string.Empty;

    /// <summary>Gets or sets YAML declaration text.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Yaml")]
    [ValidateNotNullOrEmpty]
    public string Yaml { get; set; } = string.Empty;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        try
        {
            string text = ParameterSetName == "Yaml"
                ? Yaml
                : File.ReadAllText(GetUnresolvedProviderPathFromPSPath(LiteralPath));
            WriteObject(WorkspaceFile.Parse(text));
        }
        catch (Exception exception) when (exception is WorkspaceFormatException
            or IOException or UnauthorizedAccessException)
        {
            WriteError(new ErrorRecord(
                exception, "Tmux.InvalidWorkspace", ErrorCategory.InvalidData,
                ParameterSetName == "Yaml" ? null : LiteralPath));
        }
    }
}
