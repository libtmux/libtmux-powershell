using System.Collections;
using System.Management.Automation;
using System.Text;
using LibTmux.PowerShell;

namespace LibTmux.Workspace.PowerShell;

/// <summary>Resolves workspace directories against an explicit base and variable map.</summary>
[Cmdlet(VerbsDiagnostic.Resolve, "TmuxWorkspace", DefaultParameterSetName = "Workspace")]
[OutputType(typeof(WorkspaceFile))]
public sealed class ResolveTmuxWorkspaceCommand : TmuxCmdlet
{
    private readonly Dictionary<string, string> variables = new(StringComparer.Ordinal);

    /// <summary>Gets or sets the parsed declaration to resolve locally.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Workspace")]
    [ValidateNotNull]
    public WorkspaceFile Workspace { get; set; } = null!;

    /// <summary>Gets or sets the explicit base directory for a parsed declaration.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Workspace")]
    [ValidateNotNullOrEmpty]
    public string BaseDirectory { get; set; } = string.Empty;

    /// <summary>Gets or sets the literal file whose parent supplies the document base.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Path")]
    [ValidateNotNullOrEmpty]
    public string LiteralPath { get; set; } = string.Empty;

    /// <summary>Gets or sets a file whose parent supplies the document base.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "File")]
    [ValidateNotNull]
    public FileInfo File { get; set; } = null!;

    /// <summary>Gets or sets explicitly allowed, case-sensitive expansion variables.</summary>
    [Parameter]
    [ValidateNotNull]
    public IDictionary Variables { get; set; } = new Hashtable();

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        try
        {
            foreach (DictionaryEntry entry in Variables)
            {
                object? key = entry.Key is PSObject wrappedKey ? wrappedKey.BaseObject : entry.Key;
                object? value = entry.Value is PSObject wrappedValue ? wrappedValue.BaseObject : entry.Value;
                if (key is not string name || value is not string text || !variables.TryAdd(name, text))
                {
                    throw new ArgumentException("Workspace variables require distinct string keys and string values.", nameof(Variables));
                }
            }
        }
        catch (ArgumentException exception)
        {
            ThrowTerminatingError(new ErrorRecord(exception, "Tmux.InvalidWorkspaceVariables",
                ErrorCategory.InvalidArgument, Variables));
        }
    }

    /// <inheritdoc />
    protected override ErrorCategory GetErrorCategory(Exception exception) =>
        exception is WorkspaceFormatException or DecoderFallbackException
            ? ErrorCategory.InvalidData
            : base.GetErrorCategory(exception);

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(ResolveAsync, "Tmux.WorkspaceResolutionFailed",
            ParameterSetName == "Workspace" ? Workspace : ParameterSetName == "File" ? File : LiteralPath);

    private Task<WorkspaceFile> ResolveAsync(CancellationToken cancellationToken)
    {
        if (ParameterSetName == "Workspace")
        {
            string directory = WorkspaceDocument.FileSystemPath(SessionState.Path, BaseDirectory);
            return Task.FromResult(Workspace.Resolve(directory, variables));
        }
        string path = WorkspaceDocument.FileSystemPath(SessionState.Path,
            ParameterSetName == "File" ? File.FullName : LiteralPath);
        return ResolveFileAsync(path, cancellationToken);
    }

    private async Task<WorkspaceFile> ResolveFileAsync(string path, CancellationToken cancellationToken)
    {
        string directory = Path.GetDirectoryName(path)!;
        WorkspaceFile declaration = await WorkspaceDocument.ReadAsync(path, cancellationToken).ConfigureAwait(false);
        cancellationToken.ThrowIfCancellationRequested();
        return declaration.Resolve(directory, variables);
    }
}
