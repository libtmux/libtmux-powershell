using System;
using System.IO;
using System.Threading.Tasks;

namespace LibTmux.Testing;

public sealed class SocketCreatedSignal : IDisposable
{
    private readonly FileSystemWatcher watcher;
    private readonly TaskCompletionSource<bool> signal =
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    public SocketCreatedSignal(string directory)
    {
        watcher = new FileSystemWatcher(directory, "socket");
        watcher.Created += (_, _) => signal.TrySetResult(true);
        watcher.Error += (_, e) => signal.TrySetException(e.GetException());
        watcher.EnableRaisingEvents = true;
    }

    public Task Ready => signal.Task;

    public void Dispose() => watcher.Dispose();
}
