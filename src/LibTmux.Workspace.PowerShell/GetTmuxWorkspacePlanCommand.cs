using System.Management.Automation;
using System.Runtime.Versioning;
using LibTmux.PowerShell;

namespace LibTmux.Workspace.PowerShell;

/// <summary>Observes an explicit endpoint and prepares a native workspace plan.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxWorkspacePlan")]
[OutputType(typeof(WorkspacePlan))]
[UnsupportedOSPlatform("windows")]
public sealed class GetTmuxWorkspacePlanCommand : TmuxCmdlet
{
    private WorkspacePlanOptions policy = new();

    /// <summary>Gets or sets the immutable declaration to plan.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public WorkspaceFile Workspace { get; set; } = null!;

    /// <summary>Gets or sets the explicit endpoint to observe without starting a daemon.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <summary>Gets or sets how to handle a conflicting session.</summary>
    [Parameter]
    [ValidateSet(nameof(WorkspaceExistingSession.Error), nameof(WorkspaceExistingSession.Reuse),
        nameof(WorkspaceExistingSession.Append), nameof(WorkspaceExistingSession.Replace))]
    public WorkspaceExistingSession ExistingSession { get; set; } = WorkspaceExistingSession.Error;

    /// <summary>Gets or sets whether application may create or join an initially absent daemon.</summary>
    [Parameter]
    [ValidateSet(nameof(WorkspaceServerStartup.CreateOrJoin), nameof(WorkspaceServerStartup.RequireExisting))]
    public WorkspaceServerStartup ServerStartup { get; set; } = WorkspaceServerStartup.CreateOrJoin;

    /// <summary>Gets or sets the pane startup contract.</summary>
    [Parameter]
    [ValidateSet(nameof(WorkspaceReadiness.Immediate), nameof(WorkspaceReadiness.Cooperative))]
    public WorkspaceReadiness Readiness { get; set; } = WorkspaceReadiness.Immediate;

    /// <summary>Gets or sets each cooperative startup budget in seconds, at most one day.</summary>
    [Parameter]
    public double ReadinessTimeout { get; set; } = 10;

    /// <summary>Gets or sets whether failure compensates journal-proven creations.</summary>
    [Parameter]
    public SwitchParameter CompensateOnFailure { get; set; }

    /// <summary>Gets or sets whether the declared host script may execute during application.</summary>
    [Parameter]
    public SwitchParameter AllowHostScripts { get; set; }

    /// <summary>Gets or sets the host script and output deadline in seconds, at most one day.</summary>
    [Parameter]
    public double HostScriptTimeout { get; set; } = 30;

    /// <summary>Gets or sets the combined host stdout and stderr capture limit in UTF-8 bytes.</summary>
    [Parameter]
    public int MaxHostOutputBytes { get; set; } = 1_048_576;

    /// <summary>Gets or sets the total failure-cleanup budget in seconds, at most one day.</summary>
    [Parameter]
    public double CleanupTimeout { get; set; } = 1;

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        try
        {
            policy = WorkspacePlanPolicy.Create(ExistingSession, ServerStartup, Readiness,
                ReadinessTimeout, CompensateOnFailure, AllowHostScripts, HostScriptTimeout,
                MaxHostOutputBytes, CleanupTimeout);
        }
        catch (ArgumentException exception)
        {
            ThrowTerminatingError(new ErrorRecord(exception, "Tmux.InvalidWorkspacePolicy",
                ErrorCategory.InvalidArgument, null));
        }
    }

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(token => new WorkspaceBuilder(Server).PlanAsync(Workspace, policy, token),
            "Tmux.WorkspacePlanFailed", Workspace);
}
