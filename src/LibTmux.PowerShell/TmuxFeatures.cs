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
    internal static readonly TmuxVersion NamedBuffers = TmuxVersion.Parse("3.4");

    private static readonly TmuxVersion Split34 = TmuxVersion.Parse("3.4");
    private static readonly TmuxVersion Exact37 = TmuxVersion.Parse("3.7");
    private static readonly TmuxVersion After34 = TmuxVersion.Parse("3.5");
    private static readonly TmuxVersion After37 = TmuxVersion.Parse("3.7a");

    // Short options per command; a trailing colon marks an option that takes a value.
    private static readonly Dictionary<string, string> Options = new(StringComparer.Ordinal)
    {
        ["delete-buffer"] = "b:",
        ["set-buffer"] = "ab:t:n:w",
        ["break-pane"] = "abdPF:n:s:t:",
        ["split-window"] = "bdefhIPvZc:e:F:l:p:t:",
        ["new-session"] = "AdDEPXc:e:f:F:n:s:t:x:y:",
        ["new-window"] = "abdkPSc:e:F:n:t:",
        ["rename-session"] = "t:",
        ["rename-window"] = "t:",
    };

    private static readonly Dictionary<string, string> Aliases = new(StringComparer.Ordinal)
    {
        ["deleteb"] = "delete-buffer",
        ["setb"] = "set-buffer",
        ["breakp"] = "break-pane",
        ["splitw"] = "split-window",
        ["new"] = "new-session",
        ["neww"] = "new-window",
        ["rename"] = "rename-session",
        ["renamew"] = "rename-window",
    };

    // Every command name from 3.3a to 3.8, so an abbreviation resolves as tmux resolves it.
    private static readonly string[] Commands =
    [
        "attach-session", "bind-key", "break-pane", "capture-pane", "choose-buffer", "choose-client",
        "choose-tree", "clear-history", "clear-prompt-history", "clock-mode", "command-prompt",
        "confirm-before", "copy-mode", "customize-mode", "delete-buffer", "detach-client",
        "display-menu", "display-message", "display-panes", "display-popup", "find-window",
        "has-session", "if-shell", "join-pane", "kill-pane", "kill-server", "kill-session",
        "kill-window", "last-pane", "last-window", "link-window", "list-buffers", "list-clients",
        "list-commands", "list-keys", "list-panes", "list-sessions", "list-windows", "load-buffer",
        "lock-client", "lock-server", "lock-session", "move-pane", "move-window", "new-pane",
        "new-session", "new-window", "next-layout", "next-window", "paste-buffer", "pipe-pane",
        "previous-layout", "previous-window", "refresh-client", "rename-session", "rename-window",
        "resize-pane", "resize-window", "respawn-pane", "respawn-window", "rotate-window",
        "run-shell", "save-buffer", "select-layout", "select-pane", "select-window", "send-keys",
        "send-prefix", "server-access", "set-buffer", "set-environment", "set-hook", "set-option",
        "set-window-option", "show-buffer", "show-environment", "show-hooks", "show-messages",
        "show-options", "show-prompt-history", "show-window-options", "source-file", "split-window",
        "start-server", "suspend-client", "swap-pane", "swap-window", "switch-client",
        "unbind-key", "unlink-window", "wait-for",
    ];

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
    internal static async Task RequireNameAsync(Server server, string kind, string? name, CancellationToken cancellationToken)
    {
        if (name is null || name.AsSpan().IndexOfAny(':', '.') < 0)
        {
            return;
        }

        TmuxVersion version = await VersionAsync(server, cancellationToken).ConfigureAwait(false);
        if (version == Exact37)
        {
            throw new TmuxVersionTooLowException(
                $"tmux {Exact37} rejects a {kind} name containing ':' or '.'; the name '{name}' was not sent. "
                + $"Choose another name or use tmux {After37} or newer.",
                After37,
                version);
        }
    }

    /// <summary>Checks literal native command items against the endpoint's daemon.</summary>
    internal static Task CheckCommandsAsync(Server server, IEnumerable<TmuxCommand> commands, CancellationToken cancellationToken) =>
        CheckCommandsAsync(token => VersionAsync(server, token), commands, cancellationToken);

    /// <summary>Checks literal native command items, reading the daemon version only if one could be refused.</summary>
    internal static async Task CheckCommandsAsync(
        Func<CancellationToken, Task<TmuxVersion>> daemon,
        IEnumerable<TmuxCommand> commands,
        CancellationToken cancellationToken)
    {
        Hazard[] hazards = [.. commands.SelectMany(Hazards)];
        if (hazards.Length == 0)
        {
            return;
        }

        TmuxVersion version = await daemon(cancellationToken).ConfigureAwait(false);
        foreach (Hazard hazard in hazards)
        {
            if (version >= LibTmuxInfo.MinimumTmuxVersion && hazard.Applies(version))
            {
                throw new TmuxVersionTooLowException(
                    $"tmux {hazard.Command.Name} {hazard.Reason}; the endpoint reports {version}. The command was not sent.",
                    hazard.Required,
                    version);
            }
        }
    }

    private static IEnumerable<Hazard> Hazards(TmuxCommand command)
    {
        string? name = Resolve(command.Name);
        if (name is null || !Options.TryGetValue(name, out string? specification))
        {
            yield break;
        }

        Parsed parsed = Parse(command.Arguments, specification);
        switch (name)
        {
            case "delete-buffer" when parsed.Has('b'):
                yield return new Hazard(command,
                    "deletes a buffer by name, and below 3.4 a missing name deletes an unrelated buffer",
                    NamedBuffers, version => version < NamedBuffers);
                break;
            case "set-buffer" when parsed.Has('n'):
                yield return new Hazard(command,
                    "renames a buffer by name, and below 3.4 a missing name renames an unrelated buffer",
                    NamedBuffers, version => version < NamedBuffers);
                break;
            case "split-window" when parsed.Has('p'):
                yield return new Hazard(command,
                    "uses -p, which tmux 3.4 breaks; send -l with a percentage such as 30%",
                    After34, version => version == Split34);
                break;
            case "break-pane" when !parsed.Has('n'):
                yield return new Hazard(command,
                    "has no -n window name, which crashes tmux 3.7",
                    After37, version => version == Exact37);
                break;
        }

        foreach (string? candidate in name switch
        {
            "new-session" => new[] { parsed.Value('s'), parsed.Value('n') },
            "new-window" or "break-pane" => new[] { parsed.Value('n') },
            "rename-session" or "rename-window" => new[] { parsed.Positionals.FirstOrDefault() },
            _ => [],
        })
        {
            if (candidate is not null && candidate.AsSpan().IndexOfAny(':', '.') >= 0)
            {
                yield return new Hazard(command,
                    $"names something '{candidate}' with ':' or '.', which tmux 3.7 rejects",
                    After37, version => version == Exact37);
            }
        }
    }

    private readonly record struct Hazard(TmuxCommand Command, string Reason, TmuxVersion Required, Func<TmuxVersion, bool> Applies);

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

    private static string? Resolve(string name)
    {
        if (Aliases.TryGetValue(name, out string? alias))
        {
            return alias;
        }

        if (Array.IndexOf(Commands, name) >= 0)
        {
            return name;
        }

        string[] matches = [.. Commands.Where(candidate => candidate.StartsWith(name, StringComparison.Ordinal))];
        return matches.Length == 1 ? matches[0] : null;
    }

    private static Parsed Parse(IReadOnlyList<string> arguments, string specification)
    {
        var values = new List<(char Flag, string? Value)>();
        int index = 0;
        for (; index < arguments.Count; index++)
        {
            string argument = arguments[index];
            if (argument == "--")
            {
                index++;
                break;
            }

            if (argument.Length < 2 || argument[0] != '-')
            {
                break;
            }

            for (int position = 1; position < argument.Length; position++)
            {
                char flag = argument[position];
                int declared = specification.IndexOf(flag);
                if (declared < 0)
                {
                    continue;
                }

                if (declared + 1 < specification.Length && specification[declared + 1] == ':')
                {
                    string? value = position + 1 < argument.Length
                        ? argument[(position + 1)..]
                        : index + 1 < arguments.Count ? arguments[++index] : null;
                    values.Add((flag, value));
                    break;
                }

                values.Add((flag, null));
            }
        }

        return new Parsed(values, [.. arguments.Skip(index)]);
    }

    private sealed record Parsed(List<(char Flag, string? Value)> Flags, string[] Positionals)
    {
        internal bool Has(char flag) => Flags.Exists(entry => entry.Flag == flag);

        internal string? Value(char flag) => Flags.LastOrDefault(entry => entry.Flag == flag).Value;
    }
}
