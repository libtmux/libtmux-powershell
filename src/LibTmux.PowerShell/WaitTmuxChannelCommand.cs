using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Waits for a tmux channel signal and withdraws on timeout or cancellation.</summary>
[Cmdlet(VerbsLifecycle.Wait, "TmuxChannel")]
[OutputType(typeof(bool))]
[UnsupportedOSPlatform("windows")]
public sealed class WaitTmuxChannelCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the server that owns the channel.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <summary>Gets or sets the channel reserved for this wait.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string Channel { get; set; } = string.Empty;

    /// <summary>Gets or sets the wait budget in seconds, at most one day.</summary>
    [Parameter]
    public double Timeout { get; set; } = 10;

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        if (string.IsNullOrWhiteSpace(Channel) || Channel.Contains('\0'))
        {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentException("Channel must contain non-whitespace text and cannot contain NUL."),
                "Tmux.InvalidChannel", ErrorCategory.InvalidArgument, Channel));
        }

        if (!double.IsFinite(Timeout) || Timeout < 1d / TimeSpan.TicksPerSecond || Timeout > 86400)
        {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentOutOfRangeException(nameof(Timeout), "Timeout must be a finite number of seconds between 0.0000001 and 86400."),
                "Tmux.InvalidTimeout", ErrorCategory.InvalidArgument, Timeout));
        }
    }

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(WaitAsync, "Tmux.ChannelWaitFailed", Server);

    private async Task<bool> WaitAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        TmuxWaitChannel wait = Server.OpenWaitChannel(Channel);
        await using (wait.ConfigureAwait(false))
        {
            if (await wait.WaitAsync(TimeSpan.FromSeconds(Timeout), cancellationToken).ConfigureAwait(false))
            {
                return true;
            }

            throw new TimeoutException($"No signal was observed on tmux channel '{Channel}' within {Timeout} seconds.");
        }
    }
}
