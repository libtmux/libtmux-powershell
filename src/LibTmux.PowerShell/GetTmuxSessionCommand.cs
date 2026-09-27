using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Reads the server's sessions and applies exact local selectors.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxSession")]
[OutputType(typeof(Session))]
[UnsupportedOSPlatform("windows")]
public sealed class GetTmuxSessionCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the server whose sessions are read.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <summary>Gets or sets an ordinal, literal session identifier selector.</summary>
    [Parameter]
    [ArgumentCompleter(typeof(SessionSelectorCompleter))]
    [ValidateNotNullOrEmpty]
    public string? Id { get; set; }

    /// <summary>Gets or sets an ordinal, literal session name selector.</summary>
    [Parameter]
    [ArgumentCompleter(typeof(SessionSelectorCompleter))]
    [ValidateNotNullOrEmpty]
    public string? Name { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(ReadAsync, "Tmux.SessionReadFailed", Server, enumerateCollection: true);

    private async Task<Session[]> ReadAsync(CancellationToken cancellationToken)
    {
        Server snapshot = await Server.CaptureSnapshotAsync(SnapshotDepth.Sessions, cancellationToken)
            .ConfigureAwait(false);
        return [.. snapshot.Sessions.Where(session =>
            (Id is null || string.Equals(session.Id.ToString(), Id, StringComparison.Ordinal))
            && (Name is null || string.Equals(session.Name, Name, StringComparison.Ordinal)))];
    }
}
