using System.Management.Automation;

namespace LibTmux.PowerShell;

/// <summary>Runs cancellable operations on a PowerShell pipeline callback.</summary>
public abstract class TmuxCmdlet : PSCmdlet, IDisposable
{
    private readonly object cancellationLock = new();
    private CancellationTokenSource? activeCancellation;
    private bool cancellationInProgress;
    private bool stopped;

    /// <summary>Waits for a core operation and writes its completed result.</summary>
    /// <typeparam name="T">The core result type.</typeparam>
    /// <param name="operation">The cancellable core operation.</param>
    /// <param name="errorId">The stable identifier for an operation failure.</param>
    /// <param name="target">The object whose operation failed.</param>
    /// <param name="enumerateCollection">Whether to emit collection members individually.</param>
    protected void ReadResult<T>(
        Func<CancellationToken, Task<T>> operation,
        string errorId,
        object target,
        bool enumerateCollection = false)
    {
        ArgumentNullException.ThrowIfNull(operation);
        CancellationTokenSource cancellation;
        lock (cancellationLock)
        {
            if (stopped)
            {
                throw new PipelineStoppedException();
            }

            activeCancellation = cancellation = new CancellationTokenSource();
        }

        try
        {
            T result = operation(cancellation.Token).GetAwaiter().GetResult();
            WriteObject(result, enumerateCollection);
        }
        catch (Exception exception) when (
            exception is not PipelineStoppedException and not ActionPreferenceStopException)
        {
            if (exception is OperationCanceledException && Stopping)
            {
                throw new PipelineStoppedException();
            }

            ErrorCategory category = exception switch
            {
                OperationCanceledException => ErrorCategory.OperationStopped,
                ArgumentException => ErrorCategory.InvalidArgument,
                InvalidDataException or IncompleteSnapshotException => ErrorCategory.InvalidData,
                TmuxCommandNotFoundException => ErrorCategory.ResourceUnavailable,
                _ => ErrorCategory.InvalidOperation,
            };
            WriteError(new ErrorRecord(exception, errorId, category, target));
        }
        finally
        {
            bool dispose;
            lock (cancellationLock)
            {
                activeCancellation = null;
                dispose = !cancellationInProgress;
            }

            if (dispose)
            {
                cancellation.Dispose();
            }
        }
    }

    /// <inheritdoc />
    protected override void StopProcessing() => CancelActiveOperation();

    /// <summary>Stops an active operation when PowerShell disposes the command.</summary>
    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }

    /// <summary>Cancels active work; its token source survives work and cancellation callbacks.</summary>
    /// <param name="disposing">Whether managed resources are being released.</param>
    protected virtual void Dispose(bool disposing)
    {
        if (disposing)
        {
            CancelActiveOperation();
        }
    }

    private void CancelActiveOperation()
    {
        CancellationTokenSource cancellation;
        lock (cancellationLock)
        {
            stopped = true;
            if (activeCancellation is null || cancellationInProgress)
            {
                return;
            }

            cancellation = activeCancellation;
            cancellationInProgress = true;
        }

        try
        {
            // Callbacks can complete the operation or reenter Dispose on another thread.
            cancellation.Cancel();
        }
        finally
        {
            bool dispose;
            lock (cancellationLock)
            {
                cancellationInProgress = false;
                dispose = activeCancellation is null;
            }

            // Whichever finishes last owns disposal: the operation or cancellation.
            if (dispose)
            {
                cancellation.Dispose();
            }
        }
    }
}
