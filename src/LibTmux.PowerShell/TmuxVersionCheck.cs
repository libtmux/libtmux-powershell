using System.Diagnostics;
using System.Runtime.Versioning;
using System.Security.Cryptography;

namespace LibTmux.PowerShell;

/// <summary>Checks the connected tmux daemon's version before a cmdlet dispatches to it.</summary>
/// <remarks>
/// The probe is <c>run-shell -C</c>: it has no after-hook, and tmux fails while
/// parsing the expanded string, so no <c>after-*</c> or <c>command-error</c> hook
/// fires and the version arrives in the error text.
/// </remarks>
internal static class TmuxVersionCheck
{
    internal static readonly TmuxVersion Minimum = TmuxVersion.Parse("3.3a");

    private const string UnknownCommand = "unknown command: ";
    private static readonly TimeSpan BinaryTimeout = TimeSpan.FromSeconds(10);

    /// <summary>The checked version and whether a daemon was answering.</summary>
    /// <param name="Version">The daemon version, or the executable's for an absent endpoint.</param>
    /// <param name="Live">Whether a daemon answered the probe.</param>
    internal readonly record struct CheckedVersion(TmuxVersion Version, bool Live);

    private static readonly System.Runtime.CompilerServices.ConditionalWeakTable<IControlModeSession, object> ControlVersions = new();

    /// <summary>Records the daemon version a control connection was acquired under.</summary>
    internal static void Remember(IControlModeSession connection, TmuxVersion version) =>
        ControlVersions.AddOrUpdate(connection, version);

    /// <summary>Checks the daemon behind a control connection.</summary>
    /// <remarks>
    /// A connection the cmdlets attached carries its checked version. A connection opened elsewhere
    /// exposes no endpoint, so the caller names the server and the usual hook-free subprocess probe
    /// runs against it; the connection could in principle belong to a different daemon on that
    /// endpoint if it was replaced between the attach and this call, a window the version cannot close.
    /// </remarks>
    [UnsupportedOSPlatform("windows")]
    internal static async Task<CheckedVersion> CheckControlAsync(
        IControlModeSession connection, Server? server, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(connection);
        if (ControlVersions.TryGetValue(connection, out object? known))
        {
            return new CheckedVersion(Require(((TmuxVersion)known).Raw), Live: true);
        }

        if (server is null)
        {
            throw new LibTmuxException(
                "This control connection was not opened by Connect-TmuxControl, so its daemon is unknown and no command was sent. Pass -Server with the endpoint it belongs to.");
        }

        CheckedVersion daemon = await CheckAsync(server, cancellationToken).ConfigureAwait(false);
        Remember(connection, daemon.Version);
        return daemon;
    }

    internal static Server? ServerOf(object? target) => target switch
    {
        Server server => server,
        Session session => session.Server,
        Window window => window.Server,
        Pane pane => pane.Server,
        Client client => client.Server,
        _ => null,
    };

    [UnsupportedOSPlatform("windows")]
    internal static async Task<CheckedVersion> CheckAsync(Server server, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(server);
        string marker = NewMarker() + "-";
        TmuxCommandResult probe = await server
            .ExecuteCommandAsync(["-N", "run-shell", "-C", marker + "#{version}"], cancellationToken)
            .ConfigureAwait(false);
        string report = UnknownCommand + marker;
        string[] reports = [.. probe.StandardErrorLines
            .Where(line => line.StartsWith(report, StringComparison.Ordinal))
            .Select(line => line[report.Length..])];
        if (probe.ExitCode == 1 && reports.Length == 1)
        {
            return new CheckedVersion(Require(reports[0]), Live: true);
        }

        string text = string.Join('\n', probe.StandardErrorLines);
        if (IsAbsentEndpoint(text))
        {
            string binary = server.ConnectionOptions.TmuxBinaryPath;
            return new CheckedVersion(Require(await ReadExecutableVersionAsync(binary, cancellationToken).ConfigureAwait(false)), Live: false);
        }

        throw new LibTmuxException(text.Length == 0
            ? "tmux did not report a daemon version, so no command was dispatched."
            : $"tmux did not report a daemon version, so no command was dispatched: {text}");
    }

    /// <summary>Runs native commands as one batch that fails before any of them if the daemon changed.</summary>
    /// <remarks>
    /// The batch is a native command list, so the fence is the first command and a mismatch
    /// aborts the rest. A failed batch still throws the library's command exception.
    /// </remarks>
    [UnsupportedOSPlatform("windows")]
    internal static async Task<TmuxCommandResult> ExecuteFencedAsync(
        Server server,
        CheckedVersion daemon,
        IEnumerable<TmuxCommand> commands,
        CancellationToken cancellationToken)
    {
        string marker = NewMarker();
        TmuxCommand fence = FenceCommand(daemon.Version, marker);
        // A live endpoint adds -N as the batch's first word so a vanished daemon is not restarted.
        // A batch carrying a generation guard is already bound to one daemon and is wrapped by the package.
        if (daemon.Live && commands.All(static command => command.RequiredGeneration is null))
        {
            fence = new TmuxCommand("-N", [fence.Name, .. fence.Arguments]);
        }

        try
        {
            TmuxCommandResult result = await server.Chain().Then(fence).Then(commands)
                .ExecuteAsync(cancellationToken).ConfigureAwait(false);
            return Unfence(result, [.. fence.ToArguments(), ";"]);
        }
        catch (TmuxCommandException failure)
        {
            ThrowIfReplaced(failure.Result, marker, daemon);
            // The caller never sent the fence, so the error must not carry it.
            throw new TmuxCommandException(
                failure.Message, Unfence(failure.Result, [.. fence.ToArguments(), ";"]), failure);
        }
    }

    /// <summary>Gets the command that fails the rest of a batch when the daemon changed.</summary>
    internal static TmuxCommand FenceCommand(TmuxVersion version, string marker) =>
        new("if-shell", Fence(version, marker)[1..]);

    internal static string NewMarker() =>
        "libtmux-version-" + RandomNumberGenerator.GetHexString(16, lowercase: true);

    internal static void ThrowIfReplaced(TmuxCommandResult result, string marker, CheckedVersion daemon)
    {
        string report = UnknownCommand + marker;
        if (result.StandardErrorLines.Any(line => string.Equals(line, report, StringComparison.Ordinal)))
        {
            throw new TmuxVersionTooLowException(
                $"The tmux daemon changed after its version check as {daemon.Version}; no command ran. Retry the command.",
                Minimum,
                daemon.Version);
        }
    }

    internal static TmuxCommandResult Unfence(TmuxCommandResult result, IReadOnlyList<string> fence)
    {
        if (result.Arguments.Count < fence.Count
            || !result.Arguments.Take(fence.Count).SequenceEqual(fence, StringComparer.Ordinal))
        {
            return result;
        }

        return new TmuxCommandResult(
            [.. result.Arguments.Skip(fence.Count)],
            result.ExitCode,
            result.StandardOutput,
            result.StandardError,
            result.StandardOutputLines,
            result.StandardErrorLines);
    }

    internal static TmuxVersion Require(string reported)
    {
        string version = reported.Trim();
        if (!TmuxVersion.TryParse(version, out TmuxVersion parsed))
        {
            throw new LibTmuxException(
                $"tmux reports '{version}', which names no dated release; libtmux for PowerShell requires tmux {Minimum} or newer.");
        }

        if (parsed < Minimum)
        {
            throw new TmuxVersionTooLowException(
                $"libtmux for PowerShell requires tmux {Minimum} or newer; the endpoint reports {parsed}.",
                Minimum,
                parsed);
        }

        return parsed;
    }

    private static string[] Fence(TmuxVersion version, string marker) =>
        ["if-shell", "-F", "#{==:#{version}," + version.Raw + "}", string.Empty, marker];

    private static bool IsAbsentEndpoint(string stderr) =>
        stderr.Contains("no server running", StringComparison.Ordinal)
        || (stderr.Contains("error connecting to", StringComparison.Ordinal)
            && (stderr.Contains("No such file or directory", StringComparison.Ordinal)
                || stderr.Contains("Connection refused", StringComparison.Ordinal)));

    private static async Task<string> ReadExecutableVersionAsync(string binary, CancellationToken cancellationToken)
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
            Task<string> error = process.StandardError.ReadToEndAsync(deadline.Token);
            try
            {
                await process.WaitForExitAsync(deadline.Token).ConfigureAwait(false);
                string text = await output.ConfigureAwait(false);
                string diagnostic = await error.ConfigureAwait(false);
                // tmux 3.3a prints the executable's own name, not "tmux".
                string name = Path.GetFileName(binary);
                foreach (string prefix in new[] { name + " ", "tmux " })
                {
                    if (process.ExitCode == 0 && text.StartsWith(prefix, StringComparison.Ordinal))
                    {
                        return text[prefix.Length..].Trim();
                    }
                }

                throw new LibTmuxException(
                    $"tmux -V reported '{(text.Length == 0 ? diagnostic : text).Trim()}', so the executable's version is unknown and no command was dispatched.");
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                throw new TimeoutException("tmux -V did not answer before the version check timed out.");
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
