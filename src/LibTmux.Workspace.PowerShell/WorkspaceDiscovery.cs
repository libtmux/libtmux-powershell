using System.Text;

namespace LibTmux.Workspace.PowerShell;

internal sealed class WorkspaceDiscovery(CancellationToken cancellationToken)
{
    internal const string SourcePathDataKey = "WorkspacePath";
    private const int MaximumEntries = 1024;
    private static readonly string[] Extensions = [".yaml", ".yml", ".json"];
    private static readonly StringComparer PathComparer = OperatingSystem.IsWindows()
        ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;
    private readonly HashSet<string> seen = new(PathComparer);
    private readonly List<FileInfo> files = [];
    private int examined;

    internal static void ValidateName(string name)
    {
        if (name.Length == 0 || name is "." or ".." || name.IndexOfAny(['/', '\\', '\0']) >= 0)
        {
            throw new ArgumentException("Name must be a literal declaration basename; use LiteralPath for a path.", nameof(name));
        }
    }

    internal static bool IsDirectory(string path, bool required)
    {
        FileAttributes? attributes = Attributes(path, missingAllowed: !required);
        if (attributes is null) { return false; }
        if ((attributes & FileAttributes.Directory) != 0) { return true; }
        if (required) { throw new ArgumentException($"Workspace directory '{path}' is not a directory.", nameof(path)); }
        return false;
    }

    internal void AddLiteral(string path)
    {
        cancellationToken.ThrowIfCancellationRequested();
        AddFile(path, missingAllowed: false, directoryAllowed: false);
    }

    internal void AddLocal(string directory, string? homeDirectory, bool ancestors)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _ = IsDirectory(directory, required: true);
        int visited = 0;
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (++visited > MaximumEntries) { throw Limit(); }
            foreach (string extension in Extensions)
            {
                AddFile(Path.Combine(directory, ".tmuxp" + extension), missingAllowed: true, directoryAllowed: true);
            }
            if (!ancestors || PathComparer.Equals(directory, homeDirectory)) { return; }
            string? parent = Path.GetDirectoryName(Path.TrimEndingDirectorySeparator(directory));
            if (parent is null || PathComparer.Equals(parent, directory)) { return; }
            directory = parent;
        }
    }

    internal void AddGlobal(IReadOnlyList<string> directories, string? name)
    {
        foreach (string directory in directories)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (name is not null)
            {
                List<string> candidates = [];
                string[] names = Extensions.Contains(Path.GetExtension(name), StringComparer.Ordinal)
                    ? [name] : [.. Extensions.Select(extension => name + extension)];
                foreach (string filename in names)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    string path = Path.Combine(directory, filename);
                    FileAttributes? attributes = Attributes(path, missingAllowed: true);
                    if (attributes is null) { continue; }
                    Examine();
                    if ((attributes & FileAttributes.Directory) == 0) { candidates.Add(path); }
                }
                if (candidates.Count > 1)
                {
                    throw new ArgumentException($"Workspace name '{name}' is ambiguous: {string.Join(", ", candidates)}. Use LiteralPath to select one file.", nameof(name));
                }
                foreach (string path in candidates) { Admit(path); }
                continue;
            }

            List<string> entries = [];
            using IEnumerator<string> enumerator = Directory.EnumerateFileSystemEntries(directory).GetEnumerator();
            while (true)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (!enumerator.MoveNext()) { break; }
                Examine();
                entries.Add(enumerator.Current);
            }
            entries.Sort(StringComparer.Ordinal);
            foreach (string path in entries)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (!Extensions.Contains(Path.GetExtension(path), StringComparer.Ordinal)) { continue; }
                FileAttributes? attributes = Attributes(path, missingAllowed: false);
                if ((attributes & FileAttributes.Directory) == 0) { Admit(path); }
            }
        }
    }

    internal async Task<IReadOnlyList<FileInfo>> CompleteAsync(string? search, IReadOnlyList<string> searchIn, bool caseSensitive)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (search is null) { return files.ToArray(); }
        StringComparison comparison = caseSensitive ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase;
        bool filename = searchIn.Contains("FileName", StringComparer.OrdinalIgnoreCase);
        bool content = searchIn.Any(field => !field.Equals("FileName", StringComparison.OrdinalIgnoreCase));
        List<FileInfo> selected = [];
        foreach (FileInfo file in files)
        {
            cancellationToken.ThrowIfCancellationRequested();
            bool matched = filename && file.Name.Contains(search, comparison);
            if (content)
            {
                WorkspaceFile document;
                try { document = await WorkspaceDocument.ReadAsync(file.FullName, cancellationToken).ConfigureAwait(false); }
                catch (Exception exception) when (IsFileFailure(exception))
                {
                    exception.Data[SourcePathDataKey] = file.FullName;
                    throw;
                }
                foreach (string? value in Values(document, searchIn, cancellationToken))
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    if (value?.Contains(search, comparison) == true) { matched = true; }
                }
            }
            if (matched) { selected.Add(file); }
        }
        cancellationToken.ThrowIfCancellationRequested();
        return selected.ToArray();
    }

    private static IEnumerable<string?> Values(WorkspaceFile document, IReadOnlyList<string> fields, CancellationToken cancellationToken)
    {
        bool commands = fields.Contains("Command", StringComparer.OrdinalIgnoreCase);
        bool directories = fields.Contains("Directory", StringComparer.OrdinalIgnoreCase);
        bool windows = fields.Contains("Window", StringComparer.OrdinalIgnoreCase);
        if (fields.Contains("Session", StringComparer.OrdinalIgnoreCase)) { yield return document.SessionName; }
        if (directories) { yield return document.StartDirectory; }
        if (commands)
        {
            yield return document.BeforeScript;
            foreach (string value in document.ShellCommandsBefore) { yield return value; }
        }
        foreach (WorkspaceWindow window in document.Windows)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (windows) { yield return window.WindowName; }
            if (directories) { yield return window.StartDirectory; }
            if (commands)
            {
                foreach (string value in window.ShellCommandsBefore) { yield return value; }
            }
            foreach (WorkspacePane pane in window.Panes)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (directories) { yield return pane.StartDirectory; }
                if (commands)
                {
                    foreach (string value in pane.ShellCommandsBefore) { yield return value; }
                    foreach (string value in pane.ShellCommands) { yield return value; }
                }
            }
        }
    }

    private void AddFile(string path, bool missingAllowed, bool directoryAllowed)
    {
        cancellationToken.ThrowIfCancellationRequested();
        FileAttributes? attributes = Attributes(path, missingAllowed);
        if (attributes is null) { return; }
        Examine();
        if ((attributes & FileAttributes.Directory) != 0)
        {
            if (directoryAllowed) { return; }
            throw new ArgumentException($"Workspace path '{path}' is a directory.", nameof(path));
        }
        Admit(path);
    }

    private void Admit(string path)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!seen.Add(path)) { return; }
        try
        {
            using FileStream input = WorkspaceDocument.OpenRead(path);
            cancellationToken.ThrowIfCancellationRequested();
            files.Add(new FileInfo(path));
        }
        catch (Exception exception) when (IsFileFailure(exception))
        {
            exception.Data[SourcePathDataKey] = path;
            throw;
        }
    }

    private void Examine()
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (++examined > MaximumEntries) { throw Limit(); }
    }

    private static InvalidDataException Limit() => new("Workspace discovery exceeds 1024 examined entries. Select a narrower Directory, Name or LiteralPath.");

    private static bool IsFileFailure(Exception exception) =>
        exception is IOException or UnauthorizedAccessException or DecoderFallbackException or WorkspaceFormatException;

    private static FileAttributes? Attributes(string path, bool missingAllowed)
    {
        try { return File.GetAttributes(path); }
        catch (FileNotFoundException) when (missingAllowed) { return null; }
        catch (DirectoryNotFoundException) when (missingAllowed) { return null; }
    }
}
