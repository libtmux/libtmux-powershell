using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Reads native tmux events through a bounded callback handoff.</summary>
[Cmdlet(VerbsCommon.Watch, "TmuxEvent", DefaultParameterSetName = "Connection", SupportsShouldProcess = true)]
[OutputType(typeof(TmuxEvent))]
[UnsupportedOSPlatform("windows")]
public sealed class WatchTmuxEventCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the borrowed single-reader control client.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Connection")]
    [ValidateNotNull]
    public IControlModeSession Connection { get; set; } = null!;

    /// <summary>Gets or sets the endpoint on which to create an owned control client.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Server")]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <summary>Gets or sets the raw tmux target for an owned control client.</summary>
    [Parameter(Mandatory = true, Position = 1, ParameterSetName = "Server")]
    [ValidateNotNullOrEmpty]
    [ValidatePattern(@"\A[^\x00]*[^\s\x00][^\x00]*\z")]
    public string Target { get; set; } = string.Empty;

    /// <summary>Gets or sets the maximum UTF-8 text payload bytes in the one-event handoff.</summary>
    [Parameter]
    [ValidateRange(1, int.MaxValue)]
    public int MaxEventBytes { get; set; } = 1024 * 1024;

    /// <summary>Gets or sets the maximum emitted event count.</summary>
    [Parameter]
    [ValidateRange(1L, long.MaxValue)]
    public long MaxEvents { get; set; } = long.MaxValue;

    /// <summary>Gets or sets the maximum cumulative emitted UTF-8 text payload bytes.</summary>
    [Parameter]
    [ValidateRange(1L, long.MaxValue)]
    public long MaxOutputBytes { get; set; } = long.MaxValue;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        bool ownsConnection = ParameterSetName == "Server";
        object target = ownsConnection ? Server : Connection;
        string description = ownsConnection ? $"{TmuxOwner.Describe(Server)} target {Target}" : "supplied tmux control connection";
        if (!ShouldProcess(description, "Read tmux events"))
        {
            return;
        }

        RunOperation(token =>
        {
            Guid runspaceId = Runspace.DefaultRunspace?.InstanceId
                ?? throw new InvalidOperationException("Event watching requires an active PowerShell runspace.");
            IControlModeSession control = ownsConnection
                ? Server.EnterControlModeAsync(Target, token).GetAwaiter().GetResult()
                : Connection;
            Exception? primary = null;
            try
            {
                using IDisposable registration = TmuxWatchRegistry.Register(control, runspaceId, StopProcessing);
                TmuxEventWatch.Run(control, WriteObject, MaxEventBytes, MaxEvents, MaxOutputBytes, token);
            }
            catch (Exception failure)
            {
                primary = failure;
                throw;
            }
            finally
            {
                if (ownsConnection)
                {
                    try
                    {
                        control.DisposeAsync().AsTask().GetAwaiter().GetResult();
                    }
                    catch (Exception cleanup) when (primary is not null)
                    {
                        primary.Data["LibTmux.ControlModeCleanupFailure"] = cleanup;
                    }
                }
            }
        }, "Tmux.WatchFailed", target);
    }
}
