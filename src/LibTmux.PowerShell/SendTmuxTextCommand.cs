using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Sends literal text and an optional Enter to a pane.</summary>
[Cmdlet(VerbsCommunications.Send, "TmuxText", SupportsShouldProcess = true)]
[OutputType(typeof(void))]
[UnsupportedOSPlatform("windows")]
public sealed class SendTmuxTextCommand : TmuxCmdlet
{
    private SendKeysRequest request = null!;

    /// <summary>Gets or sets the pane that receives the text.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Pane Pane { get; set; } = null!;

    /// <summary>Gets or sets the literal text to send.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNull]
    [AllowEmptyString]
    public string Text { get; set; } = string.Empty;

    /// <summary>Gets or sets whether an Enter key follows the text.</summary>
    [Parameter]
    public SwitchParameter Enter { get; set; }

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        if (Text.Contains('\0'))
        {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentException("Text cannot contain NUL characters."),
                "Tmux.InvalidInput", ErrorCategory.InvalidArgument, nameof(Text)));
        }

        request = new SendKeysRequest { Text = Text, Enter = Enter, Literal = true };
    }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        Server server = Pane.Server;
        string endpoint = server.ConnectionOptions.SocketPath ?? server.ConnectionOptions.SocketName ?? "default tmux endpoint";
        string action = request.Enter ? "Send literal text followed by Enter" : "Send literal text";
        if (ShouldProcess($"{endpoint} pane {Pane.Id}", action))
        {
            ExecuteOperation(token => Pane.SendKeysAsync(request, token), "Tmux.TextSendFailed", Pane);
        }
    }
}
