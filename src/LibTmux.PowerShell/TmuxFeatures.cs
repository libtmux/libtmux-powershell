namespace LibTmux.PowerShell;

/// <summary>Per-feature tmux requirements above the core floor, decided before any effect.</summary>
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

    /// <summary>Refuses a control client below 3.7 before any attach.</summary>
    internal static void RequireControl(TmuxVersionCheck.CheckedVersion daemon, string operation)
    {
        if (daemon.Version < Control)
        {
            throw new TmuxVersionTooLowException(
                $"{operation} attaches a control client, which needs tmux {Control} or newer; "
                + $"the endpoint reports {daemon.Version}. No control client was started.",
                Control,
                daemon.Version);
        }
    }

    /// <summary>Refuses an operation that stages a named buffer it must delete again below 3.4.</summary>
    internal static void RequireNamedBuffers(TmuxVersionCheck.CheckedVersion daemon, string operation)
    {
        if (daemon.Version < NamedBuffers)
        {
            throw new TmuxVersionTooLowException(
                $"{operation} stages a temporary tmux buffer and deletes it by name, which needs "
                + $"tmux {NamedBuffers} or newer; the endpoint reports {daemon.Version}. No buffer was created.",
                NamedBuffers,
                daemon.Version);
        }
    }

    /// <summary>Refuses a window or session name that exactly tmux 3.7 rejects.</summary>
    internal static void RequireName(TmuxVersionCheck.CheckedVersion daemon, string kind, string? name)
    {
        if (name is not null && daemon.Version == Exact37 && name.AsSpan().IndexOfAny(':', '.') >= 0)
        {
            throw new TmuxVersionTooLowException(
                $"tmux {Exact37} rejects a {kind} name containing ':' or '.'; the name '{name}' was not sent. "
                + $"Choose another name or use tmux {After37} or newer.",
                After37,
                daemon.Version);
        }
    }

    /// <summary>Checks literal native command items against the checked daemon.</summary>
    internal static void CheckCommands(TmuxVersionCheck.CheckedVersion daemon, IEnumerable<TmuxCommand> commands)
    {
        foreach (TmuxCommand command in commands)
        {
            string? name = Resolve(command.Name);
            if (name is null || !Options.TryGetValue(name, out string? specification))
            {
                continue;
            }

            Parsed parsed = Parse(command.Arguments, specification);
            TmuxVersion version = daemon.Version;
            switch (name)
            {
                case "delete-buffer" when version < NamedBuffers && parsed.Has('b'):
                    throw Refusal(command, version, NamedBuffers,
                        "deletes a buffer by name, and below 3.4 a missing name deletes an unrelated buffer");
                case "set-buffer" when version < NamedBuffers && parsed.Has('n'):
                    throw Refusal(command, version, NamedBuffers,
                        "renames a buffer by name, and below 3.4 a missing name renames an unrelated buffer");
                case "split-window" when version == Split34 && parsed.Has('p'):
                    throw Refusal(command, version, After34, "uses -p, which tmux 3.4 breaks; send -l with a percentage such as 30%");
                case "break-pane" when version == Exact37 && !parsed.Has('n'):
                    throw Refusal(command, version, After37, "has no -n window name, which crashes tmux 3.7");
            }

            if (version == Exact37)
            {
                CheckNames(command, name, parsed);
            }
        }
    }

    private static void CheckNames(TmuxCommand command, string name, Parsed parsed)
    {
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
                throw Refusal(command, Exact37, After37, $"names something '{candidate}' with ':' or '.', which tmux 3.7 rejects");
            }
        }
    }

    private static TmuxVersionTooLowException Refusal(
        TmuxCommand command, TmuxVersion actual, TmuxVersion required, string reason) =>
        new($"tmux {command.Name} {reason}; the endpoint reports {actual}. The command was not sent.",
            required, actual);

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
