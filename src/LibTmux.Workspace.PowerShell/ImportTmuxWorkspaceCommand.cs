using System.Management.Automation;
using System.Text;
using LibTmux.PowerShell;

namespace LibTmux.Workspace.PowerShell;

/// <summary>Parses a tmuxp declaration without running it.</summary>
[Cmdlet(VerbsData.Import, "TmuxWorkspace", DefaultParameterSetName = "Path")]
[OutputType(typeof(WorkspaceFile))]
public sealed class ImportTmuxWorkspaceCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the literal file path to read.</summary>
    [Parameter(Mandatory = true, Position = 0, ParameterSetName = "Path")]
    [ValidateNotNullOrEmpty]
    public string LiteralPath { get; set; } = string.Empty;

    /// <summary>Gets or sets a file selected by a filesystem pipeline.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "File")]
    [ValidateNotNull]
    public FileInfo File { get; set; } = null!;

    /// <summary>Gets or sets YAML or JSON declaration text.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Yaml")]
    [ValidateNotNullOrEmpty]
    public string Yaml { get; set; } = string.Empty;

    /// <inheritdoc />
    protected override ErrorCategory GetErrorCategory(Exception exception) =>
        exception is WorkspaceFormatException or DecoderFallbackException
            ? ErrorCategory.InvalidData
            : base.GetErrorCategory(exception);

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(token =>
        {
            if (ParameterSetName == "Yaml")
            {
                return Task.FromResult(WorkspaceFile.Parse(Yaml));
            }
            string path = WorkspaceDocument.FileSystemPath(SessionState.Path,
                ParameterSetName == "File" ? File.FullName : LiteralPath);
            return WorkspaceDocument.ReadAsync(path, token);
        }, "Tmux.InvalidWorkspace", ParameterSetName == "Yaml" ? null! : ParameterSetName == "File" ? File : LiteralPath);
}
