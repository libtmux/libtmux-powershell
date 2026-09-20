using System.Text;

namespace LibTmux.PowerShell;

internal static class CommandAdmission
{
    internal static void ValidateName(string name)
    {
        if (string.IsNullOrWhiteSpace(name) || name.StartsWith('-') || name.Contains('\0'))
        {
            throw new ArgumentException("Use a tmux command name, not a global option, without NUL.", nameof(name));
        }
    }

    internal static TmuxCommand[] CopyChain(TmuxCommand[] commands, int maxCommands, long maxInputBytes)
    {
        if (commands.Length == 0 || commands.Length > maxCommands)
        {
            throw new ArgumentException($"A chain requires between 1 and {maxCommands} commands.", nameof(commands));
        }

        long bytes = 0;
        foreach (TmuxCommand command in commands)
        {
            ArgumentNullException.ThrowIfNull(command);
            ValidateName(command.Name);
            Count(command.Name);
            foreach (string argument in command.Arguments)
            {
                Count(argument);
            }
        }

        return (TmuxCommand[])commands.Clone();

        void Count(string text)
        {
            long size = (long)Encoding.UTF8.GetByteCount(text) + 1;
            if (size > maxInputBytes - bytes)
            {
                throw new ArgumentException($"Chain command names, arguments and NUL terminators exceed {maxInputBytes} UTF-8 bytes.", nameof(commands));
            }

            bytes += size;
        }
    }
}
