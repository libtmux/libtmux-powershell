using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Reads windows owned by a server or session.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxWindow", DefaultParameterSetName = "Server")]
[OutputType(typeof(Window))]
[UnsupportedOSPlatform("windows")]
public sealed class GetTmuxWindowCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the server whose windows are read.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Server")]
    [ValidateNotNull]
    public Server? Server { get; set; }

    /// <summary>Gets or sets the session whose windows are read.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Session")]
    [ValidateNotNull]
    public Session? Session { get; set; }

    /// <summary>Gets or sets an ordinal, literal window identifier selector.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? Id { get; set; }

    /// <summary>Gets or sets an ordinal, literal window name selector.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? Name { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(ReadAsync, "Tmux.WindowReadFailed", (object?)Session ?? Server!, enumerateCollection: true);

    private async Task<Window[]> ReadAsync(CancellationToken cancellationToken)
    {
        IReadOnlyList<Window> windows;
        if (ParameterSetName == "Session")
        {
            windows = await Session!.GetWindowsAsync(cancellationToken).ConfigureAwait(false);
        }
        else
        {
            Server snapshot = await Server!.CaptureSnapshotAsync(SnapshotDepth.Windows, cancellationToken)
                .ConfigureAwait(false);
            windows = snapshot.Windows;
        }

        return [.. windows.Where(window =>
            (Id is null || string.Equals(window.Id.ToString(), Id, StringComparison.Ordinal))
            && (Name is null || string.Equals(window.Name, Name, StringComparison.Ordinal)))];
    }
}
