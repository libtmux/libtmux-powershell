using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;
using LibTmux;

namespace LibTmux.Testing;

// Fences native enumerator work independently of PowerShell's output callback.
public sealed class WatchProbe : IControlModeSession
{
    private readonly Channel<TmuxEvent> events = Channel.CreateUnbounded<TmuxEvent>(
        new UnboundedChannelOptions { AllowSynchronousContinuations = false });
    public ManualResetEventSlim Subscribed { get; } = new(false);
    public Exception EnumerationCleanupFailure;
    public int Reads;
    public int EnumeratorDisposals;
    public int ConnectionDisposals;
    public int CallbackCount;
    public int WorkerThread;
    public int CallbackThread;
    public bool IsRunning => ConnectionDisposals == 0;
    public IAsyncEnumerable<TmuxEvent> Events => Read();
    public void Write(TmuxEvent item) => events.Writer.TryWrite(item);
    public void Complete(Exception error = null) => events.Writer.TryComplete(error);
    public Task<IReadOnlyList<string>> SendAsync(TmuxCommand command, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!IsRunning) throw new InvalidOperationException("Probe was disposed.");
        return Task.FromResult<IReadOnlyList<string>>(new[] { "probe-reply" });
    }
    public ValueTask DisposeAsync()
    {
        Interlocked.Increment(ref ConnectionDisposals);
        events.Writer.TryComplete();
        return ValueTask.CompletedTask;
    }
    public void RecordCallback()
    {
        CallbackThread = Environment.CurrentManagedThreadId;
        if (WorkerThread == CallbackThread) throw new InvalidOperationException("Worker wrote pipeline output.");
        if (Reads != ++CallbackCount) throw new InvalidOperationException("Watcher prefetched before downstream returned.");
    }
    private async IAsyncEnumerable<TmuxEvent> Read([EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        Subscribed.Set();
        try
        {
            while (await events.Reader.WaitToReadAsync(cancellationToken).ConfigureAwait(false))
            {
                while (events.Reader.TryRead(out TmuxEvent item))
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    WorkerThread = Environment.CurrentManagedThreadId;
                    Interlocked.Increment(ref Reads);
                    yield return item;
                }
            }
        }
        finally
        {
            Interlocked.Increment(ref EnumeratorDisposals);
            if (EnumerationCleanupFailure is not null) throw EnumerationCleanupFailure;
        }
    }
}
