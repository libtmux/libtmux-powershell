using System.ComponentModel;
using System.Management.Automation;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace LibTmux.Workspace.PowerShell;

internal static class WorkspaceDocument
{
    // Match the native parser's character admission limit before retaining file data.
    private const int MaximumCharacters = 1_048_576;

    internal static string FileSystemPath(PathIntrinsics paths, string path)
    {
        string resolved = paths.GetUnresolvedProviderPathFromPSPath(path, out ProviderInfo provider, out _);
        if (!provider.Name.Equals("FileSystem", StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("Workspace paths must use the FileSystem provider.", nameof(path));
        }
        return resolved;
    }

    internal static async Task<WorkspaceFile> ReadAsync(string path, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await using FileStream input = OpenRead(path);
        using var reader = new StreamReader(input, new UTF8Encoding(false, true),
            detectEncodingFromByteOrderMarks: false, bufferSize: 4096, leaveOpen: true);
        var text = new StringBuilder();
        char[] buffer = new char[4096];
        bool first = true;
        while (true)
        {
            int count = await reader.ReadAsync(buffer.AsMemory(), cancellationToken).ConfigureAwait(false);
            if (count == 0)
            {
                break;
            }
            int start = first && buffer[0] == '\uFEFF' ? 1 : 0;
            first = false;
            if (count - start > MaximumCharacters - text.Length)
            {
                throw new InvalidDataException("Workspace input exceeds 1048576 characters.");
            }
            text.Append(buffer, start, count - start);
        }
        cancellationToken.ThrowIfCancellationRequested();
        return WorkspaceFile.Parse(text.ToString());
    }

    internal static FileStream OpenRead(string path)
    {
        ArgumentException.ThrowIfNullOrEmpty(path);
        if (path.Contains('\0'))
        {
            throw new ArgumentException("Workspace paths must not contain a NUL character.", nameof(path));
        }

        // O_NONBLOCK | O_CLOEXEC | O_NOCTTY; O_RDONLY is zero on both platforms.
        int flags = OperatingSystem.IsLinux() ? 0x800 | 0x80000 | 0x100
            : OperatingSystem.IsMacOS() ? 0x4 | 0x1000000 | 0x20000
            : throw new PlatformNotSupportedException("Workspace file reading requires Linux or macOS.");
        int descriptor;
        do
        {
            descriptor = Open(path, flags);
        } while (descriptor < 0 && Marshal.GetLastPInvokeError() == 4);
        if (descriptor < 0)
        {
            throw new IOException($"Could not open workspace file '{path}'.", new Win32Exception(Marshal.GetLastPInvokeError()));
        }

        SafeFileHandle handle = new(new IntPtr(descriptor), ownsHandle: true);
        FileStream? input = null;
        try
        {
            input = new FileStream(handle, FileAccess.Read, bufferSize: 4096);
            // Inspect the opened handle: a prior path check could race replacement by a FIFO.
            if (!input.CanSeek)
            {
                throw new InvalidDataException("Workspace input must be a seekable UTF-8 file.");
            }
            return input;
        }
        catch
        {
            input?.Dispose();
            handle.Dispose();
            throw;
        }
    }

    [DefaultDllImportSearchPaths(DllImportSearchPath.SafeDirectories)]
    [DllImport("libc", EntryPoint = "open", ExactSpelling = true, SetLastError = true,
        BestFitMapping = false, ThrowOnUnmappableChar = true)]
    private static extern int Open([MarshalAs(UnmanagedType.LPUTF8Str)] string path, int flags);

}
