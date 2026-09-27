using System.Collections;
using System.Management.Automation;
using System.Management.Automation.Language;

namespace LibTmux.PowerShell;

internal static class CapturedSelectorCompletion
{
    internal static T? Bound<T>(IDictionary parameters, string name) where T : class
    {
        object? value = parameters[name];
        return value is T typed ? typed : value is PSObject { BaseObject: T unwrapped } ? unwrapped : null;
    }

    internal static IEnumerable<CompletionResult> Values<T>(
        CapturedRelation<T>? relation, Func<T, string> select, string wordToComplete, string kind)
    {
        if (relation?.IsCaptured != true)
        {
            yield break;
        }

        string prefix = wordToComplete.TrimStart('\'', '"');
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (T item in relation)
        {
            string value = select(item);
            if (!value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) || !seen.Add(value))
            {
                continue;
            }

            yield return new CompletionResult(
                $"'{value.Replace("'", "''", StringComparison.Ordinal)}'",
                value, CompletionResultType.ParameterValue, $"Captured {kind}: {value}");
            if (seen.Count == 100)
            {
                yield break;
            }
        }
    }
}

internal sealed class SessionSelectorCompleter : IArgumentCompleter
{
    public IEnumerable<CompletionResult> CompleteArgument(
        string commandName, string parameterName, string wordToComplete,
        CommandAst commandAst, IDictionary fakeBoundParameters)
    {
        Server? server = CapturedSelectorCompletion.Bound<Server>(fakeBoundParameters, "Server");
        return parameterName.Equals("Name", StringComparison.OrdinalIgnoreCase)
            ? CapturedSelectorCompletion.Values(server?.Sessions, session => session.Name, wordToComplete, "session name")
            : CapturedSelectorCompletion.Values(server?.Sessions, session => session.Id.ToString(), wordToComplete, "session ID");
    }
}

internal sealed class WindowSelectorCompleter : IArgumentCompleter
{
    public IEnumerable<CompletionResult> CompleteArgument(
        string commandName, string parameterName, string wordToComplete,
        CommandAst commandAst, IDictionary fakeBoundParameters)
    {
        CapturedRelation<Window>? windows = CapturedSelectorCompletion.Bound<Session>(fakeBoundParameters, "Session")?.Windows
            ?? CapturedSelectorCompletion.Bound<Server>(fakeBoundParameters, "Server")?.Windows;
        return parameterName.Equals("Name", StringComparison.OrdinalIgnoreCase)
            ? CapturedSelectorCompletion.Values(windows, window => window.Name, wordToComplete, "window name")
            : CapturedSelectorCompletion.Values(windows, window => window.Id.ToString(), wordToComplete, "window ID");
    }
}

internal sealed class PaneSelectorCompleter : IArgumentCompleter
{
    public IEnumerable<CompletionResult> CompleteArgument(
        string commandName, string parameterName, string wordToComplete,
        CommandAst commandAst, IDictionary fakeBoundParameters)
    {
        CapturedRelation<Pane>? panes = CapturedSelectorCompletion.Bound<Window>(fakeBoundParameters, "Window")?.Panes
            ?? CapturedSelectorCompletion.Bound<Session>(fakeBoundParameters, "Session")?.Panes
            ?? CapturedSelectorCompletion.Bound<Server>(fakeBoundParameters, "Server")?.Panes;
        return CapturedSelectorCompletion.Values(panes, pane => pane.Id.ToString(), wordToComplete, "pane ID");
    }
}
