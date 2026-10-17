using System.Diagnostics;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Per-feature tmux requirements above the core floor, decided before any effect.</summary>
/// <remarks>
/// The package refuses a daemon below the floor itself. A feature that needs a newer release asks
/// the endpoint for its version first, so a refusal arrives before anything is sent. A version
/// below the floor is left to the package, whose refusal says what to do.
/// </remarks>
[UnsupportedOSPlatform("windows")]
internal static class TmuxFeatures
{
    internal static readonly TmuxVersion Control = TmuxVersion.Parse("3.7");

    private static readonly TimeSpan BinaryTimeout = TimeSpan.FromSeconds(10);

    /// <summary>Refuses a control client below 3.7 before any attach.</summary>
    internal static async Task RequireControlAsync(Server server, string operation, CancellationToken cancellationToken)
    {
        TmuxVersion version = await VersionAsync(server, cancellationToken).ConfigureAwait(false);
        if (version >= LibTmuxInfo.MinimumTmuxVersion && version < Control)
        {
            throw new TmuxVersionTooLowException(
                $"{operation} attaches a control client, which needs tmux {Control} or newer; "
                + $"the endpoint reports {version}. No control client was started.",
                Control,
                version);
        }
    }

    /// <summary>Reads the version of the daemon on the endpoint, or of the executable that would start one.</summary>
    internal static async Task<TmuxVersion> VersionAsync(Server server, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(server);
        if ((server.DaemonVersion ?? server.Version) is { } known)
        {
            return known;
        }

        // Connecting reads the version with the package's own check, which fires no tmux hook; an
        // inspection would ask with display-message. No handle comes back when no daemon answers.
        try
        {
            Server connected = await server.ConnectAsync(cancellationToken).ConfigureAwait(false);
            if ((connected.DaemonVersion ?? connected.Version) is { } live)
            {
                return live;
            }
        }
        catch (TmuxCommandException) when (!cancellationToken.IsCancellationRequested)
        {
            // No daemon answers: the executable that would start one decides.
        }

        return await ReadExecutableVersionAsync(server.ConnectionOptions.TmuxBinaryPath, cancellationToken).ConfigureAwait(false);
    }

    private static async Task<TmuxVersion> ReadExecutableVersionAsync(string binary, CancellationToken cancellationToken)
    {
        var start = new ProcessStartInfo(binary)
        {
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        start.ArgumentList.Add("-V");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(BinaryTimeout);
        Process process;
        try
        {
            process = Process.Start(start) ?? throw new InvalidOperationException("The tmux client process did not start.");
        }
        catch (System.ComponentModel.Win32Exception error)
        {
            throw new TmuxCommandNotFoundException($"The configured tmux executable '{binary}' was not found.", binary, error);
        }

        using (process)
        {
            Task<string> output = process.StandardOutput.ReadToEndAsync(deadline.Token);
            try
            {
                await process.WaitForExitAsync(deadline.Token).ConfigureAwait(false);
                // The banner is the executable's name and its version: "tmux 3.3a", "tmux next-3.9".
                string text = (await output.ConfigureAwait(false)).Trim();
                int space = text.IndexOf(' ', StringComparison.Ordinal);
                if (process.ExitCode == 0 && space > 0 && TmuxVersion.TryParse(text[(space + 1)..], out TmuxVersion version))
                {
                    return version;
                }

                throw new LibTmuxException($"tmux -V reported '{text}', so the executable's version is unknown.");
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                throw new TimeoutException("tmux -V did not answer in time.");
            }
            finally
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
        }
    }
}
