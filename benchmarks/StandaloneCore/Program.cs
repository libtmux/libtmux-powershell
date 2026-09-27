using System.Diagnostics;
using System.Globalization;
using System.Reflection;
using System.Text.Json;
using LibTmux;

internal static class Program
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private static async Task<int> Main(string[] args)
    {
        try
        {
            if (args.Length is not (4 or 6) ||
                args[0] is not ("once" or "warm") ||
                (args[0] == "once" && args.Length != 4) ||
                (args[0] == "warm" && args.Length != 6))
            {
                throw new ArgumentException(
                    "Usage: once|warm <socket> <tmux binary> <expected IDs> [warmups samples].");
            }

            string[] expected = args[3].Split(',', StringSplitOptions.RemoveEmptyEntries);
            Array.Sort(expected, StringComparer.Ordinal);
            if (expected.Length != 16 || expected.Distinct(StringComparer.Ordinal).Count() != 16 ||
                expected.Any(id => !id.StartsWith('%')))
            {
                throw new ArgumentException("Expected IDs must contain sixteen distinct tmux pane IDs.");
            }

            int warmups = args[0] == "warm" ? int.Parse(args[4], CultureInfo.InvariantCulture) : 0;
            int samples = args[0] == "warm" ? int.Parse(args[5], CultureInfo.InvariantCulture) : 0;
            if (warmups is < 0 or > 20 || samples is < 0 or > 100)
            {
                throw new ArgumentOutOfRangeException(nameof(args), "Warmups and samples exceed benchmark limits.");
            }

            Environment.SetEnvironmentVariable("TMUX", null);
            Environment.SetEnvironmentVariable("TMUX_PANE", null);
            Server server = Server.Open(new ServerConnectionOptions
            {
                SocketPath = args[1],
                TmuxBinaryPath = args[2],
                ConfigurationFile = "/dev/null"
            });

            await CaptureAsync(server, expected, "first", 0);
            for (int round = 0; round < warmups; round++)
            {
                await CaptureAsync(server, expected, "warmup", round);
            }
            for (int round = 0; round < samples; round++)
            {
                await CaptureAsync(server, expected, "sample", round);
            }

            Emit(new
            {
                kind = "complete",
                processId = Environment.ProcessId,
                runtimeVersion = Environment.Version.ToString(),
                coreAssemblyMvid = typeof(Server).Assembly.ManifestModule.ModuleVersionId,
                benchmarkAssemblyMvid = Assembly.GetExecutingAssembly().ManifestModule.ModuleVersionId
            });
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error);
            return 1;
        }
    }

    private static async Task CaptureAsync(Server server, string[] expected, string phase, int round)
    {
        if (OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("tmux capture requires Linux or macOS.");
        }

        long started = Stopwatch.GetTimestamp();
        Server snapshot = await server.CaptureSnapshotAsync(SnapshotDepth.Panes);
        long elapsed = Stopwatch.GetTimestamp() - started;
        string[] paneIds = snapshot.Panes.Select(pane => pane.Id.ToString()).ToArray();
        Array.Sort(paneIds, StringComparer.Ordinal);
        if (!paneIds.SequenceEqual(expected, StringComparer.Ordinal))
        {
            throw new InvalidOperationException($"{phase}/{round} returned different pane IDs.");
        }

        Emit(new
        {
            kind = "capture",
            phase,
            round,
            elapsedNanoseconds = (long)Math.Round(elapsed * 1_000_000_000.0 / Stopwatch.Frequency),
            paneIds
        });
    }

    private static void Emit<T>(T value)
    {
        Console.WriteLine(JsonSerializer.Serialize(value, JsonOptions));
        Console.Out.Flush();
    }
}
