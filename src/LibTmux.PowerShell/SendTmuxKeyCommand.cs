using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Sends tmux key tokens to a pane in input order.</summary>
[Cmdlet(VerbsCommunications.Send, "TmuxKey", SupportsShouldProcess = true)]
[OutputType(typeof(void))]
[UnsupportedOSPlatform("windows")]
public sealed class SendTmuxKeyCommand : TmuxCmdlet
{
    private SendKeysRequest[] requests = [];

    /// <summary>Gets or sets the pane that receives the keys.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Pane Pane { get; set; } = null!;

    /// <summary>Gets or sets key tokens, such as C-a or Enter, in sending order.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNull]
    [ValidateCount(1, int.MaxValue)]
    public string[] Key { get; set; } = [];

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        if (Key.Any(static key => string.IsNullOrEmpty(key) || key.Contains('\0')))
        {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentException("Key tokens cannot be null, empty, or contain NUL characters."),
                "Tmux.InvalidInput", ErrorCategory.InvalidArgument, nameof(Key)));
        }

        requests = [.. Key.Select(static key => new SendKeysRequest(key, enter: false))];
    }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        Server server = Pane.Server;
        string endpoint = server.ConnectionOptions.SocketPath ?? server.ConnectionOptions.SocketName ?? "default tmux endpoint";
        if (ShouldProcess($"{endpoint} pane {Pane.Id}", "Send tmux key tokens"))
        {
            ExecuteOperation(token => server.Chain()
                .Then(requests.Select(request => request.ToCommand(Pane)))
                .ExecuteAsync(token), "Tmux.KeySendFailed", Pane);
        }
    }
}
