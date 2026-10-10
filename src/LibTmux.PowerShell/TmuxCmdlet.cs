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
        RunOperation(token =>
        {
            T result = operation(token).GetAwaiter().GetResult();
            WriteObject(result, enumerateCollection);
        }, errorId, target);
    }

    /// <summary>Publishes an owned result, cleaning it up if cancellation or output stops the handoff.</summary>
    /// <typeparam name="T">The owner or created-versus-reused result.</typeparam>
    /// <param name="operation">Acquires the result with the pipeline's cancellation token.</param>
    /// <param name="errorId">The stable identifier for an operation failure.</param>
    /// <param name="target">The object whose operation failed.</param>
    private protected void ReadScopedResult<T>(Func<CancellationToken, Task<T>> operation, string errorId, object target)
        where T : IAsyncDisposable
    {
        RunOperation(token =>
        {
            T result = operation(token).GetAwaiter().GetResult();
            try
            {
                token.ThrowIfCancellationRequested();
                WriteObject(result);
            }
            catch (Exception failure)
            {
                ScopeCleanup.Dispose(result, failure);
                throw;
            }
        }, errorId, target);
    }

    /// <summary>Waits for a core operation without emitting a success object.</summary>
    /// <param name="operation">The cancellable core operation.</param>
    /// <param name="errorId">The stable identifier for an operation failure.</param>
    /// <param name="target">The object whose operation failed.</param>
    private protected void ExecuteOperation(
        Func<CancellationToken, Task> operation,
        string errorId,
        object target)
    {
        ArgumentNullException.ThrowIfNull(operation);
        RunOperation(token => operation(token).GetAwaiter().GetResult(), errorId, target);
    }

    /// <summary>Runs one cancellable operation on the active pipeline callback.</summary>
    /// <param name="operation">Callback work; workers must not invoke PowerShell output APIs.</param>
    /// <param name="errorId">The stable identifier for an operation failure.</param>
    /// <param name="target">The object whose operation failed.</param>
    private protected void RunOperation(Action<CancellationToken> operation, string errorId, object target)
    {
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
            operation(cancellation.Token);
        }
        catch (Exception exception)
        {
            // Acquisition may fail before returning an owner, and PowerShell may
            // replace its exception. Retain the core's accepted retry authority first.
            ScopeCleanup.Retain(exception);
            if (exception is PipelineStoppedException or ActionPreferenceStopException)
            {
                throw;
            }

            if (exception is OperationCanceledException && Stopping)
            {
                throw new PipelineStoppedException();
            }

            ErrorCategory category = GetErrorCategory(exception);
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

    /// <summary>Classifies an operation failure for the PowerShell error stream.</summary>
    /// <param name="exception">The original operation exception.</param>
    /// <returns>The category emitted without replacing the exception.</returns>
    protected virtual ErrorCategory GetErrorCategory(Exception exception) => exception switch
    {
        OperationCanceledException => ErrorCategory.OperationStopped,
        TimeoutException => ErrorCategory.OperationTimeout,
        ArgumentException => ErrorCategory.InvalidArgument,
        InvalidDataException or IncompleteSnapshotException or InconsistentSnapshotException => ErrorCategory.InvalidData,
        TmuxCommandNotFoundException => ErrorCategory.ResourceUnavailable,
        _ => ErrorCategory.InvalidOperation,
    };

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
