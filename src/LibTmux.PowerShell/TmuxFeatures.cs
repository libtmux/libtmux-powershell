using System.Diagnostics;
using System.Runtime.Versioning;
using LibTmux.PowerShell.Support;

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
    internal static readonly TmuxVersion Control = Capabilities.SinceOf("control-mode");
    internal static readonly TmuxVersion NamedBuffers = Capabilities.SinceOf("buffer-delete-named");

    private static readonly WorkaroundClaim NameSeparators = Capabilities.Workaround("name-separators-rejected");

    private static readonly TimeSpan BinaryTimeout = TimeSpan.FromSeconds(10);

    /// <summary>Refuses a control client below 3.7 before any attach.</summary>
    /// <returns>The version the client will attach to.</returns>
    internal static async Task<TmuxVersion> RequireControlAsync(Server server, string operation, CancellationToken cancellationToken)
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

        return version;
    }

    /// <summary>Refuses an operation that stages a named buffer it must delete again below 3.4.</summary>
    internal static async Task RequireNamedBuffersAsync(Server server, string operation, CancellationToken cancellationToken)
    {
        TmuxVersion version = await VersionAsync(server, cancellationToken).ConfigureAwait(false);
        if (version >= LibTmuxInfo.MinimumTmuxVersion && version < NamedBuffers)
        {
            throw new TmuxVersionTooLowException(
                $"{operation} stages a temporary tmux buffer and deletes it by name, which needs "
                + $"tmux {NamedBuffers} or newer; the endpoint reports {version}. No buffer was created.",
                NamedBuffers,
                version);
        }
    }

    /// <summary>Refuses a window or session name that exactly tmux 3.7 rejects.</summary>
    /// <remarks>
    /// Only a caller that sends several actions needs this, so that nothing is created before the
    /// refusal; the package refuses a single typed creation itself, before dispatch. The refusal is
    /// the package's <see cref="TmuxUnsupportedOnReleaseException" />, as the package raises it for
    /// the same name in a literal command. A session name with either character is a caller error
    /// on every release, which the package refuses as <see cref="ArgumentException" />.
    /// </remarks>
    internal static async Task RequireNameAsync(Server server, string kind, string? name, CancellationToken cancellationToken, string? command = null)
    {
        if (name is null || name.AsSpan().IndexOfAny(':', '.') < 0)
        {
            return;
        }

        TmuxVersion version = await VersionAsync(server, cancellationToken).ConfigureAwait(false);
        if (NameSeparators.Affects(version))
        {
            throw new TmuxUnsupportedOnReleaseException(
                $"tmux {version} rejects ':' and '.' in the {kind} name '{name}'; the name was not sent. "
                + $"Choose another name or use tmux {NameSeparators.Until} or newer.",
                version,
                NameSeparators.SafeReleases,
                NameSeparators.Id,
                command);
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
