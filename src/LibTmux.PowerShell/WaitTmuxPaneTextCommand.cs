using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Waits for rendered text in a native pane.</summary>
[Cmdlet(VerbsLifecycle.Wait, "TmuxPaneText", SupportsShouldProcess = true)]
[OutputType(typeof(PaneWaitResult))]
[UnsupportedOSPlatform("windows")]
public sealed class WaitTmuxPaneTextCommand : TmuxCmdlet
{
    private PaneWaitRequest? request;

    /// <summary>Gets or sets the pane to observe.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Pane Pane { get; set; } = null!;

    /// <summary>Gets or sets the regular expressions to match, or null for any new output.</summary>
    [Parameter(Position = 1)]
    public string[]? Pattern { get; set; }

    /// <summary>Gets or sets the regular expressions that stop the wait.</summary>
    [Parameter]
    public string[]? StopPattern { get; set; }

    /// <summary>Gets or sets case-sensitive matching.</summary>
    [Parameter]
    public SwitchParameter CaseSensitive { get; set; }

    /// <summary>Gets or sets literal matching instead of regular expressions.</summary>
    [Parameter]
    public SwitchParameter SimpleMatch { get; set; }

    /// <summary>Gets or sets the wait budget in seconds, at most one day.</summary>
    [Parameter]
    public double Timeout { get; set; } = 10;

    /// <summary>Gets or sets whether control failure may use bounded polling.</summary>
    [Parameter]
    public SwitchParameter AllowPollingFallback { get; set; }

    /// <summary>Gets or sets the maximum lines in the result tail.</summary>
    [Parameter]
    [ValidateRange(1, 1000)]
    public int TailLines { get; set; } = 20;

    /// <summary>Gets or sets the maximum UTF-8 bytes in the result tail.</summary>
    [Parameter]
    [ValidateRange(1, 1_048_576)]
    public int MaxOutputBytes { get; set; } = 65_536;

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
            request = PaneWaitRequest.FromTextPatterns(
                Pattern, StopPattern, ignoreCase: !CaseSensitive.IsPresent,
                simpleMatch: SimpleMatch.IsPresent) with
            {
                Timeout = TimeSpan.FromSeconds(Timeout),
                AllowPollingFallback = AllowPollingFallback.IsPresent,
                TailLines = TailLines,
                MaxOutputBytes = MaxOutputBytes,
            };
            request.Validate();
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException)
        {
            ThrowTerminatingError(new ErrorRecord(error,
                "Tmux.InvalidPaneTextRequest", ErrorCategory.InvalidArgument,
                request ?? (object?)Pattern ?? StopPattern));
        }
    }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        Pane pane = Pane;
        string endpoint = pane.Server.ConnectionOptions.SocketPath
            ?? pane.Server.ConnectionOptions.SocketName
            ?? "default tmux endpoint";
        if (!ShouldProcess($"{endpoint} pane {pane.Id}", "Wait for rendered pane text"))
        {
            return;
        }

        ReadResult(token => pane.WaitForTextAsync(request!, token),
            "Tmux.PaneTextWaitFailed", pane);
    }
}
