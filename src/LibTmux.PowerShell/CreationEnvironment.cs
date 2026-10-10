using System.Collections;

namespace LibTmux.PowerShell;

internal static class CreationEnvironment
{
    internal static string Endpoint(Server server) =>
        server.ConnectionOptions.SocketPath ?? server.ConnectionOptions.SocketName ?? "default tmux endpoint";

    internal static IReadOnlyDictionary<string, string>? Copy(IDictionary? environment)
    {
        if (environment is null)
        {
            return null;
        }

        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (DictionaryEntry entry in environment)
        {
            if (entry.Key is not string key || entry.Value is not string value)
            {
                throw new ArgumentException("Environment requires string keys and string values; null values are not supported.", nameof(environment));
            }

            if (key.Length == 0 || key.Contains('=') || key.Contains('\0'))
            {
                throw new ArgumentException("Environment names cannot be empty or contain '=' or NUL.", nameof(environment));
            }

            if (value.Contains('\0'))
            {
                throw new ArgumentException("Environment values cannot contain NUL.", nameof(environment));
            }

            result.Add(key, value);
        }

        return result;
    }
}
