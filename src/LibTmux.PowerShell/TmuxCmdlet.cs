using System.Management.Automation;

namespace LibTmux.PowerShell;

/// <summary>Runs cancellable operations on a PowerShell pipeline callback.</summary>
public abstract class TmuxCmdlet : PSCmdlet, IDisposable
{
    private readonly object cancellationLock = new();
    private CancellationTokenSource? activeCancellation;
    private bool cancellationInProgress;
    private bool stopped;

    /// <summary>Gets the version check the running operation was dispatched under.</summary>
    private protected TmuxVersionCheck.CheckedVersion? VersionCheck { get; private set; }

    /// <summary>Checks the daemon behind a caller-supplied control connection for the running operation.</summary>
    /// <param name="connection">The connection about to carry a command.</param>
    /// <param name="cancellationToken">Cancels the check.</param>
    /// <param name="server">The endpoint the connection belongs to, needed when the cmdlets did not open it.</param>
    protected void CheckConnection(IControlModeSession connection, Server? server, CancellationToken cancellationToken)
    {
        if (!OperatingSystem.IsWindows())
        {
            VersionCheck = TmuxVersionCheck.CheckControlAsync(connection, server, cancellationToken).GetAwaiter().GetResult();
        }
    }

    /// <summary>Refuses a session or window name that the checked daemon rejects.</summary>
    /// <param name="kind">The kind of object named, for the error text.</param>
    /// <param name="name">The name an operation is about to send.</param>
    protected void RejectUnsendableName(string kind, string? name)
    {
        if (VersionCheck is { } daemon)
        {
            TmuxFeatures.RequireName(daemon, kind, name);
        }
    }

    /// <summary>Selects the server whose daemon must be checked before an operation runs.</summary>
    /// <param name="target">The object the operation acts on.</param>
    /// <returns>The server to check, or null when the operation never dispatches to tmux.</returns>
    protected virtual Server? ResolveServer(object target) => TmuxVersionCheck.ServerOf(target);

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

        Server? server = null;
        try
        {
            VersionCheck = null;
            server = target is null ? null : ResolveServer(target);
            if (server is null && !GetType().IsDefined(typeof(TmuxVersionCheckExemptAttribute), inherit: false))
            {
                // Fail closed: a cmdlet that resolves no server must say why it needs none.
                throw new InvalidOperationException(
                    $"{GetType().Name} resolved no tmux server for its operation and is not marked TmuxVersionCheckExempt, so nothing was dispatched.");
            }

            if (server is not null)
            {
                if (OperatingSystem.IsWindows())
                {
                    throw new PlatformNotSupportedException("libtmux for PowerShell drives tmux on Linux, macOS and WSL, not native Windows.");
                }

                VersionCheck = TmuxVersionCheck.CheckAsync(server, cancellation.Token).GetAwaiter().GetResult();
            }

            operation(cancellation.Token);
        }
        catch (Exception exception) when (
            exception is not PipelineStoppedException and not ActionPreferenceStopException)
        {
            if (exception is OperationCanceledException && Stopping)
            {
                throw new PipelineStoppedException();
            }

            if (server is not null && exception is TmuxTransportException or StaleServerGenerationException)
            {
                // The daemon may have gone or been replaced; the next operation checks it afresh.
                TmuxVersionCheck.Forget(server);
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
        TmuxVersionTooLowException => ErrorCategory.NotImplemented,
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
