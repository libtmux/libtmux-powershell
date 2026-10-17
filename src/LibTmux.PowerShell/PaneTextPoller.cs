using System.Diagnostics;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Waits for pane text by polling capture-pane, for daemons below the control-client floor.</summary>
/// <remarks>
/// It matches rendered rows, so output that scrolls past between two polls can be missed; the control
/// path remains the lossless one. The result carries the outcome, matched pattern and elapsed time; the
/// tail, drop counts and effective timeout are only filled by the control path.
/// </remarks>
[UnsupportedOSPlatform("windows")]
internal static class PaneTextPoller
{
    internal static readonly TimeSpan Interval = TimeSpan.FromMilliseconds(100);

    internal static async Task<PaneWaitResult> WaitAsync(Pane pane, PaneWaitRequest request, CancellationToken cancellationToken)
    {
        var clock = Stopwatch.StartNew();
        IReadOnlyList<string> baseline = await pane.CaptureAsync(null, cancellationToken).ConfigureAwait(false);
        string? present = FirstMatch(request.Patterns, baseline);
        if (present is not null)
        {
            return new PaneWaitResult(PaneWaitOutcome.PresentAtEntry, present, clock.Elapsed);
        }

        string joinedBaseline = string.Join('\n', baseline);
        while (true)
        {
            if (clock.Elapsed >= request.Timeout)
            {
                return new PaneWaitResult(PaneWaitOutcome.TimedOut, null, clock.Elapsed);
            }

            TimeSpan step = request.Timeout - clock.Elapsed;
            await Task.Delay(step < Interval ? step : Interval, cancellationToken).ConfigureAwait(false);
            IReadOnlyList<string> rows;
            try
            {
                rows = await pane.CaptureAsync(null, cancellationToken).ConfigureAwait(false);
            }
            catch (TmuxObjectNotFoundException)
            {
                return new PaneWaitResult(PaneWaitOutcome.PaneExited, null, clock.Elapsed);
            }

            if (FirstMatch(request.StopPatterns, rows) is { } stop)
            {
                return new PaneWaitResult(PaneWaitOutcome.Stopped, stop, clock.Elapsed);
            }

            if (FirstMatch(request.Patterns, rows) is { } matched)
            {
                return new PaneWaitResult(PaneWaitOutcome.Matched, matched, clock.Elapsed);
            }

            if (request.Patterns.Count == 0 && !string.Equals(string.Join('\n', rows), joinedBaseline, StringComparison.Ordinal))
            {
                return new PaneWaitResult(PaneWaitOutcome.AnyOutput, null, clock.Elapsed);
            }

            Pane current = await pane.RefreshAsync(cancellationToken).ConfigureAwait(false);
            if (current.Dead)
            {
                return new PaneWaitResult(PaneWaitOutcome.PaneExited, null, clock.Elapsed);
            }
        }
    }

    private static string? FirstMatch(IReadOnlyList<System.Text.RegularExpressions.Regex> patterns, IReadOnlyList<string> rows)
    {
        foreach (System.Text.RegularExpressions.Regex pattern in patterns)
        {
            foreach (string row in rows)
            {
                if (pattern.IsMatch(row))
                {
                    return pattern.ToString();
                }
            }
        }

        return null;
    }
}
