using System.Text.Json;
using YamlDotNet.Serialization;

namespace LibTmux.Workspace.PowerShell;

internal static class WorkspaceSerialization
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    internal static string ToYaml(WorkspaceFile workspace)
    {
        string text = new SerializerBuilder()
            .WithQuotingNecessaryStrings(quoteYaml1_1Strings: true)
            .DisableAliases()
            .Build()
            .Serialize(Project(workspace));
        _ = WorkspaceFile.Parse(text);
        return text;
    }

    internal static string ToJson(WorkspaceFile workspace)
    {
        string text = JsonSerializer.Serialize(Project(workspace), JsonOptions);
        _ = WorkspaceFile.Parse(text);
        return text;
    }

    private static Dictionary<string, object?> Project(WorkspaceFile workspace)
    {
        ArgumentNullException.ThrowIfNull(workspace);
        bool resolved = workspace.DocumentDirectory is not null;
        Dictionary<string, object?> result = new(StringComparer.Ordinal)
        {
            ["session_name"] = workspace.SessionName,
            ["start_directory"] = Directory(workspace.StartDirectory, resolved),
            ["options"] = workspace.Options,
            ["environment"] = workspace.Environment,
            ["shell_command_before"] = ProjectCommands(workspace.BeforeCommands),
            ["windows"] = workspace.Windows.Select(window => Project(window, resolved)).ToArray(),
        };
        // Unlike nullable path/name fields, the parser rejects an explicit null host command.
        if (workspace.BeforeScript is not null)
        {
            result.Add("before_script", workspace.BeforeScript);
        }
        return result;
    }

    private static Dictionary<string, object?> Project(WorkspaceWindow window, bool resolved)
    {
        Dictionary<string, object?> result = new(StringComparer.Ordinal)
        {
            ["window_name"] = window.WindowName,
        };
        if (window.WindowIndex is int index)
            result.Add("window_index", index);
        result.Add("start_directory", Directory(window.StartDirectory, resolved));
        result.Add("layout", window.Layout);
        result.Add("focus", window.Focus);
        result.Add("options", window.Options);
        result.Add("environment", window.Environment);
        result.Add("shell_command_before", ProjectCommands(window.BeforeCommands));
        result.Add("panes", window.Panes.Select(pane => Project(pane, resolved)).ToArray());
        return result;
    }

    private static Dictionary<string, object?> Project(WorkspacePane pane, bool resolved)
    {
        Dictionary<string, object?> result = new(StringComparer.Ordinal)
        {
            ["shell_command"] = ProjectCommands(pane.Commands),
            ["start_directory"] = Directory(pane.StartDirectory, resolved),
            ["focus"] = pane.Focus,
            ["options"] = pane.Options,
            ["environment"] = pane.Environment,
            ["shell_command_before"] = ProjectCommands(pane.BeforeCommands),
        };
        if (pane.Enter is bool enter)
            result.Add("enter", enter);
        return result;
    }

    private static object[] ProjectCommands(IReadOnlyList<WorkspaceCommand> commands) =>
        commands.Select(command => command.Enter is bool enter
            ? (object)new Dictionary<string, object?> { ["cmd"] = command.Text, ["enter"] = enter }
            : command.Text).ToArray();

    private static string? Directory(string? path, bool resolved) =>
        resolved ? path?.Replace("$", "$$", StringComparison.Ordinal) : path;
}
