using System;
using System.Management.Automation;
using System.Threading;
using System.Threading.Tasks;
using LibTmux;
using LibTmux.PowerShell;

namespace LibTmux.Testing;

// Runs the installed base class inside a real pipeline while fencing the race.
public sealed class RuntimeProbeState : IDisposable
{
    public ManualResetEventSlim Started { get; } = new(false);
    public ManualResetEventSlim RecordExited { get; } = new(false);
    public TaskCompletionSource<int> Completion { get; } =
        new(TaskCreationOptions.RunContinuationsAsynchronously);
    public CancellationTokenRegistration Registration;
    public Task ConcurrentDispose;
    public bool DisposeFinishedDuringCallback;
    public bool RecordFinishedDuringCallback;
    public bool TokenAliveDuringCallback;
    public bool StopBeforeRecord;
    public bool OperationStarted;
    public TmuxOperationCanceledException NativeCancellation;

    public void Dispose()
    {
        Registration.Dispose();
        ConcurrentDispose?.GetAwaiter().GetResult();
        Started.Dispose();
        RecordExited.Dispose();
    }
}

[Cmdlet(VerbsDiagnostic.Test, "TmuxRuntimeProbe")]
public sealed class RuntimeProbeCommand : TmuxCmdlet
{
    [Parameter(Mandatory = true)]
    public RuntimeProbeState State { get; set; }

    [Parameter]
    public Server Server { get; set; }

    protected override void BeginProcessing()
    {
        if (State.StopBeforeRecord)
        {
            StopProcessing();
        }
    }

    protected override void ProcessRecord()
    {
        try
        {
            if (Server is null)
            {
                ReadResult(StartFencedOperation, "Test.RuntimeFailed", State);
            }
            else
            {
                ReadResult(RunNativeOperation, "Test.NativeRuntimeFailed", Server);
            }
        }
        finally
        {
            State.RecordExited.Set();
        }
    }

    private Task<int> StartFencedOperation(CancellationToken cancellationToken)
    {
        State.OperationStarted = true;
        State.Registration = cancellationToken.Register(() =>
        {
            State.Completion.TrySetCanceled(cancellationToken);
            State.ConcurrentDispose = Task.Run(Dispose);
            State.DisposeFinishedDuringCallback = State.ConcurrentDispose.Wait(500);
            State.RecordFinishedDuringCallback = State.RecordExited.Wait(500);
            try
            {
                // Token lifetime must cover both operation completion and callbacks.
                _ = cancellationToken.WaitHandle;
                State.TokenAliveDuringCallback = true;
            }
            catch (ObjectDisposedException)
            {
                State.TokenAliveDuringCallback = false;
            }
        });
        State.Started.Set();
        return State.Completion.Task;
    }

    private async Task<TmuxCommandResult> RunNativeOperation(CancellationToken cancellationToken)
    {
        State.OperationStarted = true;
        State.Started.Set();
        try
        {
            return await Server.Chain()
                .Then("wait-for", "-S", "runtime-ready")
                .Then("wait-for", "runtime-blocked")
                .ExecuteAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (TmuxOperationCanceledException exception)
        {
            State.NativeCancellation = exception;
            throw;
        }
    }
}
