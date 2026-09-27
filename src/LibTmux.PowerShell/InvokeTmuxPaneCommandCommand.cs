using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Runs a shell command in one pane and reports its exit status.</summary>
[Cmdlet(VerbsLifecycle.Invoke, "TmuxPaneCommand", SupportsShouldProcess = true)]
[OutputType(typeof(PaneCommandResult))]
[UnsupportedOSPlatform("windows")]
public sealed class InvokeTmuxPaneCommandCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the native pane that receives the command.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Pane Pane { get; set; } = null!;

    /// <summary>Gets or sets the shell command to run in a subshell.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNull]
    [AllowEmptyString]
    public string Command { get; set; } = string.Empty;

    /// <summary>Gets or sets the completion wait in seconds, at most one day.</summary>
    [Parameter]
    public double Timeout { get; set; } = 30;

    /// <summary>Gets or sets whether input gets a leading history-suppression space.</summary>
    [Parameter]
    public bool SuppressHistory { get; set; } = true;

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        if (string.IsNullOrWhiteSpace(Command) || Command.Contains('\0'))
        {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentException("Command must contain non-whitespace text and cannot contain NUL."),
                "Tmux.InvalidPaneCommand", ErrorCategory.InvalidArgument, Command));
        }

        if (!double.IsFinite(Timeout) || Timeout < 1d / TimeSpan.TicksPerSecond || Timeout > 86400)
        {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentOutOfRangeException(nameof(Timeout),
                    "Timeout must be a finite number of seconds between 0.0000001 and 86400."),
                "Tmux.InvalidTimeout", ErrorCategory.InvalidArgument, Timeout));
        }
    }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        string endpoint = Pane.Server.ConnectionOptions.SocketPath
            ?? Pane.Server.ConnectionOptions.SocketName
            ?? "default tmux endpoint";
        if (ShouldProcess($"{endpoint} pane {Pane.Id}", "Run shell command"))
        {
            ReadResult(
                token => Pane.RunCommandAsync(
                    Command,
                    TimeSpan.FromSeconds(Timeout),
                    SuppressHistory,
                    token),
                "Tmux.PaneCommandFailed",
                Pane);
        }
    }
}
