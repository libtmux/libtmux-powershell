using System.Management.Automation;

namespace LibTmux.PowerShell;

/// <summary>Constructs an endpoint handle without contacting tmux.</summary>
[Cmdlet(VerbsCommon.New, "TmuxServer", DefaultParameterSetName = "Name")]
[OutputType(typeof(Server))]
public sealed class NewTmuxServerCommand : PSCmdlet
{
    /// <summary>Gets or sets the tmux socket name.</summary>
    [Parameter(ParameterSetName = "Name")]
    [ValidateNotNullOrEmpty]
    public string? SocketName { get; set; }

    /// <summary>Gets or sets the absolute socket path.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Path")]
    [ValidateNotNullOrEmpty]
    public string? SocketPath { get; set; }

    /// <summary>Gets or sets the tmux executable used by subsequent operations.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string TmuxBinaryPath { get; set; } = "tmux";

    /// <summary>Gets or sets the configuration used if a later operation starts tmux.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? ConfigurationFile { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        try
        {
            WriteObject(Server.Open(new ServerConnectionOptions(
                tmuxBinaryPath: TmuxBinaryPath,
                socketName: SocketName,
                socketPath: SocketPath,
                configurationFile: ConfigurationFile)));
        }
        catch (ArgumentException exception)
        {
            ThrowTerminatingError(new ErrorRecord(
                exception, "Tmux.InvalidEndpoint", ErrorCategory.InvalidArgument,
                SocketPath ?? SocketName));
        }
    }
}
