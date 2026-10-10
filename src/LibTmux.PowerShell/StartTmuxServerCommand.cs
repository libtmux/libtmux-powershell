using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Returns a running server, starting one at the selected endpoint when absent.</summary>
/// <remarks>Successful handoff leaves the daemon alive without transferring a cleanup owner.</remarks>
[Cmdlet(VerbsLifecycle.Start, "TmuxServer", SupportsShouldProcess = true)]
[OutputType(typeof(Server))]
[UnsupportedOSPlatform("windows")]
public sealed class StartTmuxServerCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the captured endpoint; omission selects the normal environment defaults.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server? Server { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        try
        {
            Server endpoint = Server ?? LibTmux.Server.Open();
            if (!ShouldProcess(endpoint.ToString(), "Ensure tmux server is running"))
            {
                return;
            }

            RunOperation(token =>
            {
                FoundOrCreated<Server> result = endpoint.FindOrCreateAsync(token).GetAwaiter().GetResult();
                try
                {
                    token.ThrowIfCancellationRequested();
                    WriteObject(result.Value);
                }
                catch (Exception failure)
                {
                    // A failed handoff may destroy only this call's newly started daemon.
                    ScopeCleanup.Dispose(result, failure);
                    throw;
                }
            }, "Tmux.ServerStartFailed", endpoint);
        }
        catch (ArgumentException exception)
        {
            ThrowTerminatingError(new ErrorRecord(
                exception, "Tmux.InvalidEndpoint", ErrorCategory.InvalidArgument, Server));
        }
    }
}
