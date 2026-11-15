// Stands in for tmux where a test checks what a tmux client is handed. Each call
// appends its argument list and the names of the selector variables it inherited
// to $LIBTMUX_TEST_RECORD, never a value, and fails as a tmux with no server does.
// RecordingTmux.ps1 reads the record. It is a program, not a script, because a
// test starts it dozens of times and a PowerShell start costs a second under load.
using System.Collections;
using System.Text;

string? record = Environment.GetEnvironmentVariable("LIBTMUX_TEST_RECORD");
if (string.IsNullOrEmpty(record))
{
    Console.Error.WriteLine("LIBTMUX_TEST_RECORD must name the file to append to");
    return 2;
}

HashSet<string> names = Environment.GetEnvironmentVariables().Keys.Cast<string>().ToHashSet(StringComparer.Ordinal);
var lines = new List<string> { "call" };
lines.AddRange(args.Select(argument => "arg\t" + argument));
foreach (string selector in new[] { "TMUX", "TMUX_PANE" })
{
    if (names.Contains(selector))
    {
        lines.Add("set\t" + selector);
    }
}

// Every variable with the prefix, by name.
const string prefix = "LIBTMUX_SOCKET";
foreach (string name in names.Where(n => n.StartsWith(prefix, StringComparison.Ordinal) &&
    n.Skip(prefix.Length).All(c => char.IsAsciiLetterOrDigit(c) || c == '_')).Order(StringComparer.Ordinal))
{
    lines.Add("set\t" + name);
}

string sandbox = Environment.GetEnvironmentVariable("LIBTMUX_TEST_SANDBOX") ?? string.Empty;
string? tmpdir = names.Contains("TMUX_TMPDIR") ? Environment.GetEnvironmentVariable("TMUX_TMPDIR") ?? string.Empty : null;
lines.Add(tmpdir is null ? "tmpdir\tunset" : tmpdir == sandbox ? "tmpdir\tsandbox" : "tmpdir\tother");
File.AppendAllText(record, string.Join('\n', lines) + "\n", new UTF8Encoding(false));

if (args.Length > 0 && args[0] == "-V")
{
    Console.Out.Write("tmux 3.8\n");
    return 0;
}

Console.Error.WriteLine("recording tmux: no server running");
return 1;
