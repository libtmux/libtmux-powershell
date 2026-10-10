using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.Workspace.PowerShell;

/// <summary>Checks workspace declaration and policy constraints without contacting tmux.</summary>
[Cmdlet(VerbsDiagnostic.Test, "TmuxWorkspace")]
[OutputType(typeof(bool))]
[UnsupportedOSPlatform("windows")]
public sealed class TestTmuxWorkspaceCommand : PSCmdlet
{
    private WorkspacePlanOptions policy = null!;

    /// <summary>Gets or sets the immutable declaration to validate.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public WorkspaceFile Workspace { get; set; } = null!;

    /// <summary>Gets or sets the existing-session policy.</summary>
    [Parameter]
    [ValidateSet(nameof(WorkspaceExistingSession.Error), nameof(WorkspaceExistingSession.Reuse),
        nameof(WorkspaceExistingSession.Append), nameof(WorkspaceExistingSession.Replace))]
    public WorkspaceExistingSession ExistingSession { get; set; } = WorkspaceExistingSession.Error;

    /// <summary>Gets or sets whether application may start an absent daemon.</summary>
    [Parameter]
    [ValidateSet(nameof(WorkspaceServerStartup.CreateOrJoin), nameof(WorkspaceServerStartup.RequireExisting))]
    public WorkspaceServerStartup ServerStartup { get; set; } = WorkspaceServerStartup.CreateOrJoin;

    /// <summary>Gets or sets the declared pane startup contract.</summary>
    [Parameter]
    [ValidateSet(nameof(WorkspaceReadiness.Immediate), nameof(WorkspaceReadiness.Cooperative))]
    public WorkspaceReadiness Readiness { get; set; } = WorkspaceReadiness.Immediate;

    /// <summary>Gets or sets the per-pane readiness budget in seconds.</summary>
    [Parameter]
    public double ReadinessTimeout { get; set; } = 10;

    /// <summary>Gets or sets whether application may compensate owned creations.</summary>
    [Parameter]
    public SwitchParameter CompensateOnFailure { get; set; }

    /// <summary>Gets or sets whether declared host scripts are admitted.</summary>
    [Parameter]
    public SwitchParameter AllowHostScripts { get; set; }

    /// <summary>Gets or sets the host script deadline in seconds.</summary>
    [Parameter]
    public double HostScriptTimeout { get; set; } = 30;

    /// <summary>Gets or sets the combined host output capture limit in UTF-8 bytes.</summary>
    [Parameter]
    public int MaxHostOutputBytes { get; set; } = 1_048_576;

    /// <summary>Gets or sets the application cleanup budget in seconds.</summary>
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
    protected override void ProcessRecord()
    {
        try
        {
            WorkspaceBuilder.Validate(Workspace, policy);
            WriteObject(true);
        }
        catch (Exception exception) when (exception is WorkspaceFormatException or ArgumentException)
        {
            WriteError(new ErrorRecord(exception, "Tmux.WorkspaceValidationFailed",
                ErrorCategory.InvalidData, Workspace));
            WriteObject(false);
        }
    }
}
