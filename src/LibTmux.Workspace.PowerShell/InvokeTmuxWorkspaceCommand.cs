using System.Management.Automation;
using System.Runtime.Versioning;
using LibTmux.PowerShell;

namespace LibTmux.Workspace.PowerShell;

/// <summary>Applies the exact reviewed workspace plan after one PowerShell confirmation.</summary>
[Cmdlet(VerbsLifecycle.Invoke, "TmuxWorkspace", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
[OutputType(typeof(WorkspaceResult))]
[UnsupportedOSPlatform("windows")]
public sealed class InvokeTmuxWorkspaceCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the native plan whose endpoint, actions and policies will be used unchanged.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public WorkspacePlan Plan { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        WorkspacePlan plan = Plan;
        ServerConnectionOptions endpoint = plan.Endpoint.ConnectionOptions;
        string socket = endpoint.SocketPath ?? endpoint.SocketName ?? "default tmux endpoint";
        bool hostScript = plan.Actions.Any(action => action.Kind == WorkspaceActionKind.RunHostScript);
        string action = $"Apply workspace (existing session: {plan.ExistingSessionPolicy}; startup: {plan.ServerStartup}; "
            + $"readiness: {plan.Readiness}; compensation: {plan.CompensateOnFailure}; host script: {hostScript}; "
            + $"request values redacted){Environment.NewLine}"
            + $"Actions ({plan.Actions.Count}, in order):{Environment.NewLine}{DescribeActions(plan.Actions)}{Environment.NewLine}"
            + $"Conditional cleanup ({plan.CompensationActions.Count}, only after failure):{Environment.NewLine}"
            + DescribeActions(plan.CompensationActions);
        if (ShouldProcess($"{endpoint.TmuxBinaryPath} at {socket} session '{plan.SessionName}'", action))
        {
            ReadResult(token => new WorkspaceBuilder(plan.Endpoint).ApplyAsync(plan, token),
                "Tmux.WorkspaceApplyFailed", plan);
        }
    }

    private static string DescribeActions(IReadOnlyList<WorkspaceAction> actions) => actions.Count == 0
        ? "  (none)"
        : string.Join(Environment.NewLine, actions.Select((step, index) =>
            $"  {index + 1}. {step.Kind} {step.Target}"
            + (step.SourceTarget is null ? string.Empty : $" <= {step.SourceTarget}")));
}
