using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Executes literal tmux arguments against an explicit server.</summary>
[Cmdlet(VerbsLifecycle.Invoke, "TmuxCommand", SupportsShouldProcess = true)]
[OutputType(typeof(TmuxCommandResult))]
[UnsupportedOSPlatform("windows")]
public sealed class InvokeTmuxCommandCommand : TmuxCmdlet
{
    private string[] commandArguments = [];

    /// <summary>Gets or sets the endpoint that receives the command.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <summary>Gets or sets literal arguments beginning with the tmux command name.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNull]
    [ValidateCount(1, int.MaxValue)]
    [AllowEmptyString]
    public string[] Arguments { get; set; } = [];

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        if (Arguments.Length == 0 || string.IsNullOrWhiteSpace(Arguments[0]) || Arguments[0].StartsWith('-') ||
            Arguments.Any(static argument => argument is null))
        {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentException("Arguments require a tmux command name, not a global option, and cannot contain null values."),
                "Tmux.InvalidCommand", ErrorCategory.InvalidArgument, Arguments));
        }

        commandArguments = (string[])Arguments.Clone();
    }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        string endpoint = Server.ConnectionOptions.SocketPath ?? Server.ConnectionOptions.SocketName ?? "default tmux endpoint";
        if (ShouldProcess(endpoint, $"Invoke tmux command {commandArguments[0]}"))
        {
            ReadResult(ExecuteAsync, "Tmux.CommandFailed", Server);
        }
    }

    private async Task<TmuxCommandResult> ExecuteAsync(CancellationToken cancellationToken)
    {
        TmuxCommandResult result = await Server.ExecuteCommandAsync(commandArguments, cancellationToken)
            .ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            throw new TmuxCommandException(
                $"tmux {commandArguments[0]} failed with exit code {result.ExitCode}.", result);
        }

        return result;
    }
}
