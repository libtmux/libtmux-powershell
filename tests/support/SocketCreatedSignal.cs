using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace LibTmux.Testing;

public sealed class SocketCreatedSignal : IDisposable
{
    private readonly FileSystemWatcher watcher;
    private readonly TaskCompletionSource<bool> signal =
        new(TaskCreationOptions.RunContinuationsAsynchronously);
    private int createdEvents;
    private int errorEvents;

    public SocketCreatedSignal(string directory)
    {
        watcher = new FileSystemWatcher(directory, "socket");
        watcher.Created += (_, _) =>
        {
            Interlocked.Increment(ref createdEvents);
            signal.TrySetResult(true);
        };
        watcher.Error += (_, e) =>
        {
            Interlocked.Increment(ref errorEvents);
            signal.TrySetException(e.GetException());
        };
        watcher.EnableRaisingEvents = true;
    }

    public Task Ready => signal.Task;

    public int CreatedEvents => Volatile.Read(ref createdEvents);

    public int ErrorEvents => Volatile.Read(ref errorEvents);

    public void Dispose() => watcher.Dispose();
}
