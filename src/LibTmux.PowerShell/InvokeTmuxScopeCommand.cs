using System.Management.Automation;

namespace LibTmux.PowerShell;

/// <summary>Runs a script block and disposes its owned tmux resource before emitting body output.</summary>
[Cmdlet(VerbsLifecycle.Invoke, "TmuxScope")]
[OutputType(typeof(object))]
public sealed class InvokeTmuxScopeCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the owned resource or created-versus-reused result.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true)]
    [ValidateNotNull]
    public object InputObject { get; set; } = null!;

    /// <summary>Gets or sets the script receiving the borrowed resource as its first argument.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNull]
    public ScriptBlock Body { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord() => RunOperation(token =>
    {
        (IAsyncDisposable owner, object value) = ScopeCleanup.Accept(InputObject);
        Exception? bodyFailure = null;
        System.Collections.ObjectModel.Collection<PSObject> output;
        try
        {
            token.ThrowIfCancellationRequested();
            output = InvokeCommand.InvokeScript(true, Body, null, value);
            token.ThrowIfCancellationRequested();
        }
        catch (Exception failure)
        {
            bodyFailure = failure;
            throw;
        }
        finally
        {
            // Cleanup has its own core deadline and must survive pipeline cancellation.
            ScopeCleanup.Dispose(owner, bodyFailure);
        }

        WriteObject(output, true);
    }, "Tmux.ScopeFailed", InputObject);
}
