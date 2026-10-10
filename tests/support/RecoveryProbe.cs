using System;
using System.IO;
using System.Management.Automation;
using System.Threading.Tasks;
using LibTmux;
using LibTmux.PowerShell;

namespace LibTmux.Testing;

// Creates one real nested-core failure, then presents it through native pipeline wrappers.
public static class RecoveryProbe
{
    public static async Task<Exception> FailNestedAsync(OwnedSessionScope outer, OwnedSessionScope inner)
    {
        var original = new IOException("nested acquisition recovery sentinel");
        try
        {
            await outer.UseAsync((_, _) => inner.UseAsync(
                (_, _) => Task.FromException<int>(original)));
        }
        catch (Exception failure)
        {
            return failure;
        }
        throw new InvalidOperationException("The nested failure did not propagate.");
    }

    public static Exception Wrap(Exception error, string kind) => kind switch
    {
        "aggregate" => new AggregateException(new IOException("unrelated first branch"), error, error),
        "action" => new ActionPreferenceStopException("wrapped action stop", error),
        "stopped" => new PipelineStoppedException("wrapped pipeline stop", error),
        _ => error,
    };
}

[Cmdlet(VerbsDiagnostic.Test, "TmuxRecoveryProbe")]
public sealed class RecoveryProbeCommand : TmuxCmdlet
{
    [Parameter(Mandatory = true)]
    public Exception Failure { get; set; }

    protected override void ProcessRecord() =>
        ReadResult<int>(_ => Task.FromException<int>(Failure), "Test.RecoveryFailed", Failure);
}
