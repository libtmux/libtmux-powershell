using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Refreshes a client into a replacement captured handle.</summary>
[Cmdlet(VerbsData.Update, "TmuxClient")]
[OutputType(typeof(Client))]
[UnsupportedOSPlatform("windows")]
public sealed class UpdateTmuxClientCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the client whose current state is read.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Client Client { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(token => Client.RefreshAsync(token), "Tmux.ClientRefreshFailed", Client);
}
