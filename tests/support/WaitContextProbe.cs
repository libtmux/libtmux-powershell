using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using LibTmux;
using LibTmux.PowerShell;

namespace LibTmux.Testing;

public static class WaitContextProbe
{
    public static void AssertCancellationDoesNotCaptureContext(TimeSpan hangGuard)
    {
        using var cancellation = new CancellationTokenSource();
        using var context = new DeferredContext();
        var waiter = new TaskCompletionSource<TmuxCommandResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        var withdrawal = new TaskCompletionSource<TmuxCommandResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        int signals = 0;
        bool cancelledOnCaller = false;
        var server = Server.Open(new ServerConnectionOptions
        {
            SocketName = "libtmux-powershell-context-probe",
            Interceptor = (invocation, next, token) =>
            {
                IReadOnlyList<string> arguments = invocation.Arguments;
                if (arguments.Count == 1 && arguments[0] == "-V")
                {
                    return Task.FromResult(Success(arguments, "tmux 3.7c\n"));
                }

                if (arguments[0] != "wait-for")
                {
                    throw new InvalidOperationException("Unexpected wait probe invocation.");
                }

                if (arguments[1] == "-S")
                {
                    signals++;
                    return withdrawal.Task;
                }

                // OpenWaitChannel dispatches before the cmdlet calls WaitAsync.
                // Cancel at that boundary while the caller context is still installed.
                cancelledOnCaller = ReferenceEquals(SynchronizationContext.Current, context);
                cancellation.Cancel();
                return waiter.Task;
            }
        });
        using var command = new WaitTmuxChannelCommand { Server = server, Channel = "context-race", Timeout = 10 };
        MethodInfo method = typeof(WaitTmuxChannelCommand).GetMethod("WaitAsync", BindingFlags.Instance | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("The cmdlet wait operation was not found.");
        SynchronizationContext previous = SynchronizationContext.Current;
        Task<bool> operation;
        try
        {
            SynchronizationContext.SetSynchronizationContext(context);
            operation = (Task<bool>)method.Invoke(command, new object[] { cancellation.Token });
        }
        finally
        {
            SynchronizationContext.SetSynchronizationContext(previous);
        }

        bool racedBeforeSuspending = cancelledOnCaller && signals == 1 && !operation.IsCompleted;
        waiter.SetResult(Success(new[] { "wait-for", "context-race" }));
        withdrawal.SetResult(Success(new[] { "wait-for", "-S", "context-race" }));
        int completed = WaitHandle.WaitAny(new[] { ((IAsyncResult)operation).AsyncWaitHandle, context.Posted.WaitHandle }, (int)hangGuard.TotalMilliseconds);
        bool capturedCaller = context.PostCount != 0;

        // Drain only after observing the failure so a red run leaves no queued work.
        context.Drain();
        if (!((IAsyncResult)operation).AsyncWaitHandle.WaitOne(hangGuard))
        {
            throw new InvalidOperationException("Channel withdrawal did not finish after releasing the probe.");
        }

        bool cancelled = false;
        try { operation.GetAwaiter().GetResult(); }
        catch (OperationCanceledException) { cancelled = true; }
        if (!racedBeforeSuspending || !cancelled)
        {
            throw new InvalidOperationException("The probe did not exercise cancellation before the first suspended await.");
        }

        if (completed != 0 || capturedCaller)
        {
            throw new InvalidOperationException("Wait disposal captured the non-pumping caller SynchronizationContext.");
        }
    }

    private static TmuxCommandResult Success(IReadOnlyList<string> arguments, string output = "") =>
        new TmuxCommandResult(arguments, 0, Encoding.UTF8.GetBytes(output), ReadOnlyMemory<byte>.Empty,
            output.Length == 0 ? Array.Empty<string>() : new[] { output.TrimEnd('\n') }, Array.Empty<string>());

    private sealed class DeferredContext : SynchronizationContext, IDisposable
    {
        private readonly ConcurrentQueue<(SendOrPostCallback Callback, object State)> callbacks = new();
        internal ManualResetEventSlim Posted { get; } = new(false);
        internal int PostCount { get; private set; }

        public override void Post(SendOrPostCallback callback, object state)
        {
            callbacks.Enqueue((callback, state));
            PostCount++;
            Posted.Set();
        }

        internal void Drain()
        {
            while (callbacks.TryDequeue(out var work)) { work.Callback(work.State); }
        }

        public void Dispose() => Posted.Dispose();
    }
}
