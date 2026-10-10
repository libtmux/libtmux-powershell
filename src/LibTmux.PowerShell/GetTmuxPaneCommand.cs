using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Reads panes owned by a server, session, or window.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxPane", DefaultParameterSetName = "Server")]
[OutputType(typeof(Pane))]
[UnsupportedOSPlatform("windows")]
public sealed class GetTmuxPaneCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the server whose panes are read.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Server")]
    [ValidateNotNull]
    public Server? Server { get; set; }

    /// <summary>Gets or sets the session whose panes are read.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Session")]
    [ValidateNotNull]
    public Session? Session { get; set; }

    /// <summary>Gets or sets the window whose panes are read.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Window")]
    [ValidateNotNull]
    public Window? Window { get; set; }

    /// <summary>Gets or sets an ordinal, literal pane identifier selector.</summary>
    [Parameter]
    [ArgumentCompleter(typeof(PaneSelectorCompleter))]
    [ValidateNotNullOrEmpty]
    public string? Id { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(ReadAsync, "Tmux.PaneReadFailed", (object?)Window ?? (object?)Session ?? Server!, enumerateCollection: true);

    private async Task<Pane[]> ReadAsync(CancellationToken cancellationToken)
    {
        IReadOnlyList<Pane> panes;
        switch (ParameterSetName)
        {
            case "Window":
                panes = await Window!.GetPanesAsync(cancellationToken).ConfigureAwait(false);
                break;
            case "Session":
                panes = await Session!.GetPanesAsync(cancellationToken).ConfigureAwait(false);
                break;
            default:
                Server snapshot = await Server!.CaptureSnapshotAsync(SnapshotDepth.Panes, cancellationToken)
                    .ConfigureAwait(false);
                panes = snapshot.Panes;
                break;
        }

        return [.. panes.Where(pane =>
            Id is null || string.Equals(pane.Id.ToString(), Id, StringComparison.Ordinal))];
    }
}
