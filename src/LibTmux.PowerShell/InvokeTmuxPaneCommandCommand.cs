using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Runs a shell command in one pane and reports its exit status.</summary>
[Cmdlet(VerbsLifecycle.Invoke, "TmuxPaneCommand", SupportsShouldProcess = true)]
[OutputType(typeof(PaneRunResult))]
[UnsupportedOSPlatform("windows")]
public sealed class InvokeTmuxPaneCommandCommand : TmuxCmdlet
{
    private PaneRunRequest request = null!;

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
        if (!double.IsFinite(Timeout) || Timeout < 1d / TimeSpan.TicksPerSecond || Timeout > 86400)
        {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentOutOfRangeException(nameof(Timeout),
                    "Timeout must be a finite number of seconds between 0.0000001 and 86400."),
                "Tmux.InvalidTimeout", ErrorCategory.InvalidArgument, Timeout));
        }

        try
        {
            request = new PaneRunRequest(Command)
            {
                Timeout = TimeSpan.FromSeconds(Timeout),
                KeepOutOfHistory = SuppressHistory,
            };
            request.Validate();
        }
        catch (ArgumentException error)
        {
            ThrowTerminatingError(new ErrorRecord(error,
                "Tmux.InvalidPaneCommand", ErrorCategory.InvalidArgument, Command));
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
                token => Pane.RunAsync(request, token),
                "Tmux.PaneCommandFailed",
                Pane);
        }
    }
}
