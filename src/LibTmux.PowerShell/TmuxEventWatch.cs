using System.Runtime.ExceptionServices;
using System.Text;
using System.Threading.Channels;

namespace LibTmux.PowerShell;

internal static class TmuxEventWatch
{
    internal static void Run(
        IControlModeSession connection,
        Action<TmuxEvent> write,
        int maxEventBytes,
        long maxEvents,
        long maxOutputBytes,
        CancellationToken cancellationToken)
    {
        using var stopped = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        using var acknowledged = new SemaphoreSlim(0, 1);
        var handoff = Channel.CreateBounded<(TmuxEvent Event, long Bytes)>(new BoundedChannelOptions(1)
        {
            SingleReader = true,
            SingleWriter = true,
            AllowSynchronousContinuations = false,
        });
        Exception? producerFailure = null;
        Task producer = Task.Run(async () =>
        {
            try
            {
                await foreach (TmuxEvent item in connection.Events.WithCancellation(stopped.Token).ConfigureAwait(false))
                {
                    long bytes = TextBytes(item);
                    if (bytes > maxEventBytes)
                    {
                        throw new InvalidDataException($"The next tmux event contains {bytes} UTF-8 text bytes, exceeding MaxEventBytes {maxEventBytes}.");
                    }

                    await handoff.Writer.WriteAsync((item, bytes), stopped.Token).ConfigureAwait(false);
                    // Do not prefetch while downstream is processing this record.
                    await acknowledged.WaitAsync(stopped.Token).ConfigureAwait(false);
                }
            }
            catch (Exception error)
            {
                producerFailure = error;
            }
            finally
            {
                handoff.Writer.TryComplete(producerFailure);
            }
        }, CancellationToken.None);

        Exception? callbackFailure = null;
        try
        {
            long count = 0;
            long bytes = 0;
            while (handoff.Reader.WaitToReadAsync(stopped.Token).AsTask().GetAwaiter().GetResult())
            {
                while (handoff.Reader.TryRead(out (TmuxEvent Event, long Bytes) item))
                {
                    stopped.Token.ThrowIfCancellationRequested();
                    if (item.Bytes > maxOutputBytes - bytes)
                    {
                        throw new InvalidDataException($"The next tmux event exceeds the remaining MaxOutputBytes budget of {maxOutputBytes - bytes} UTF-8 text bytes. Earlier output remains valid; this consumed event was not emitted.");
                    }

                    // Only the active PowerShell callback invokes this delegate; no lock is held.
                    write(item.Event);
                    bytes += item.Bytes;
                    if (++count == maxEvents || bytes == maxOutputBytes)
                    {
                        return;
                    }

                    acknowledged.Release();
                }
            }
        }
        catch (Exception error)
        {
            callbackFailure = error;
            throw;
        }
        finally
        {
            stopped.Cancel();
            producer.GetAwaiter().GetResult();
            bool expectedStop = producerFailure is OperationCanceledException cancelled
                && cancelled.CancellationToken == stopped.Token;
            if (producerFailure is not null && !expectedStop
                && !ReferenceEquals(callbackFailure, producerFailure))
            {
                if (callbackFailure is not null)
                {
                    callbackFailure.Data["LibTmux.WatchCleanupFailure"] = producerFailure;
                }
                else
                {
                    ExceptionDispatchInfo.Capture(producerFailure).Throw();
                }
            }
        }
    }

    private static long TextBytes(TmuxEvent item) => item switch
    {
        TmuxOutputEvent output => Bytes(output.PaneId.ToString()) + Bytes(output.Data),
        TmuxNotificationEvent notification => Bytes(notification.Name) + notification.Arguments.Sum(Bytes),
        TmuxExitEvent exit => Bytes(exit.Reason),
        TmuxEventsDroppedEvent => 0,
        TmuxPaneGoneEvent gone => Bytes(gone.PaneId.ToString()),
        _ => throw new InvalidDataException($"Cannot bound the text payload of tmux event type {item.GetType().FullName}."),
    };

    private static long Bytes(string? text) => text is null ? 0 : Encoding.UTF8.GetByteCount(text);
}
