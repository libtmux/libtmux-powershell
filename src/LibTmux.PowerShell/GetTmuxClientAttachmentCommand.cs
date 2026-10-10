using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Resolves the session, window and pane a client currently views.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxClientAttachment")]
[OutputType(typeof(ClientAttachment))]
[UnsupportedOSPlatform("windows")]
public sealed class GetTmuxClientAttachmentCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the client whose attachment is read.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Client Client { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(ReadAsync, "Tmux.ClientAttachmentReadFailed", Client, enumerateCollection: true);

    private async Task<ClientAttachment[]> ReadAsync(CancellationToken cancellationToken)
    {
        ClientAttachment? attachment = await Client.ResolveAttachmentAsync(cancellationToken).ConfigureAwait(false);
        return attachment is null ? [] : [attachment];
    }
}
