using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Reads clients attached to a server and applies an exact local name selector.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxClient")]
[OutputType(typeof(Client))]
[UnsupportedOSPlatform("windows")]
public sealed class GetTmuxClientCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the server whose clients are read.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <summary>Gets or sets an ordinal, literal client name selector.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? Name { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(ReadAsync, "Tmux.ClientReadFailed", Server, enumerateCollection: true);

    private async Task<Client[]> ReadAsync(CancellationToken cancellationToken)
    {
        IReadOnlyList<Client> clients = await Server.GetClientsAsync(cancellationToken).ConfigureAwait(false);
        return [.. clients.Where(client => Name is null || string.Equals(client.Name, Name, StringComparison.Ordinal))];
    }
}
