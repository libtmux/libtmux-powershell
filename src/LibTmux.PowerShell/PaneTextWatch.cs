using System.Diagnostics;
using System.Runtime.Versioning;
using System.Text.RegularExpressions;

namespace LibTmux.PowerShell;

/// <summary>Completes a pane text wait where the package's own wait cannot.</summary>
/// <remarks>
/// The package matches one rendered row at a time, so text that wraps across rows never matches
/// while it polls. The wait runs beside a watcher that joins wrapped rows before it matches, and
/// it turns a failure caused by a killed server into a finished wait. The package's result is
/// preferred whenever it arrives. A result produced here carries only the outcome, the matched
/// pattern and the elapsed time, because the package gives callers no way to fill the tail or the
/// pane identity of a result it did not produce.
/// </remarks>
[UnsupportedOSPlatform("windows")]
internal static class PaneTextWatch
{
    internal static readonly TimeSpan Interval = TimeSpan.FromMilliseconds(100);

    // How long the package's own result is awaited after the watcher has matched, so that an
    // ordinary match keeps its tail.
    internal static readonly TimeSpan Grace = TimeSpan.FromMilliseconds(300);

    internal static async Task<PaneWaitResult> WaitAsync(Pane pane, PaneWaitRequest request, CancellationToken cancellationToken)
    {
        var clock = Stopwatch.StartNew();
        bool polling = await TmuxFeatures.VersionAsync(pane.Server, cancellationToken).ConfigureAwait(false) < TmuxFeatures.Control;
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        Task<PaneWaitResult> package = pane.WaitForTextAsync(request, linked.Token);
        Task<PaneWaitResult?> watcher = polling && (request.Patterns.Count > 0 || request.StopPatterns.Count > 0)
            ? WatchAsync(pane, request, clock, package, linked.Token)
            : Task.FromResult<PaneWaitResult?>(null);
        try
        {
            await Task.WhenAny((Task)package, watcher).ConfigureAwait(false);
            if (!package.IsCompleted && watcher.IsCompletedSuccessfully && watcher.Result is { } joined)
            {
                return joined;
            }

            return await package.ConfigureAwait(false);
        }
        catch (Exception failure) when (
            failure is TmuxCommandException or TmuxTransportException && !cancellationToken.IsCancellationRequested)
        {
            // A server killed while the wait ran leaves nothing to wait for: the wait has finished.
            if (await pane.Server.IsAliveAsync(cancellationToken).ConfigureAwait(false))
            {
                throw;
            }

            return new PaneWaitResult(PaneWaitOutcome.PaneExited, null, clock.Elapsed);
        }
        finally
        {
            await linked.CancelAsync().ConfigureAwait(false);
            await Settle(package).ConfigureAwait(false);
            await Settle(watcher).ConfigureAwait(false);
        }
    }

    private static async Task Settle(Task task)
    {
        try
        {
            await task.ConfigureAwait(false);
        }
        catch (Exception) when (task.IsFaulted || task.IsCanceled)
        {
            // The outcome was taken from the other task.
        }
    }

    private static async Task<PaneWaitResult?> WatchAsync(
        Pane pane,
        PaneWaitRequest request,
        Stopwatch clock,
        Task<PaneWaitResult> package,
        CancellationToken cancellationToken)
    {
        bool first = true;
        while (true)
        {
            await Task.Delay(Interval, cancellationToken).ConfigureAwait(false);
            IReadOnlyList<string> lines;
            try
            {
                lines = await pane.CaptureAsync(new CapturePaneRequest { JoinWrappedLines = true }, cancellationToken).ConfigureAwait(false);
            }
            catch (Exception failure) when (failure is TmuxObjectNotFoundException or TmuxCommandException or TmuxTransportException)
            {
                // The pane or the server went away; the package wait reports how.
                return null;
            }

            PaneWaitResult? decided = Decide(request, lines, first, clock.Elapsed);
            first = false;
            if (decided is null)
            {
                continue;
            }

            // Let the package finish an ordinary match first, since only its result has a tail.
            Task finished = await Task.WhenAny(package, Task.Delay(Grace, cancellationToken)).ConfigureAwait(false);
            return ReferenceEquals(finished, package) ? null : decided with { Elapsed = clock.Elapsed };
        }
    }

    private static PaneWaitResult? Decide(PaneWaitRequest request, IReadOnlyList<string> lines, bool atEntry, TimeSpan elapsed)
    {
        // Joined rows keep their trailing spaces, which a rendered row does not.
        string[] joined = [.. lines.Select(static line => line.TrimEnd(' '))];
        if (FirstMatch(request.Patterns, joined) is { } matched)
        {
            return new PaneWaitResult(atEntry ? PaneWaitOutcome.PresentAtEntry : PaneWaitOutcome.Matched, matched, elapsed);
        }

        return FirstMatch(request.StopPatterns, joined) is { } stop
            ? new PaneWaitResult(PaneWaitOutcome.Stopped, stop, elapsed)
            : null;
    }

    private static string? FirstMatch(IReadOnlyList<Regex> patterns, string[] lines)
    {
        foreach (Regex pattern in patterns)
        {
            if (lines.Any(pattern.IsMatch))
            {
                return pattern.ToString();
            }
        }

        return null;
    }
}
