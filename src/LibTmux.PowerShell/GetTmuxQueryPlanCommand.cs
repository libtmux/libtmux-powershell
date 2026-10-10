using System.Management.Automation;
using LibTmux.Query;

namespace LibTmux.PowerShell;

/// <summary>Prepares a native query plan for an explicit daemon version without I/O.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxQueryPlan")]
[OutputType(typeof(QueryPlan<Session>), typeof(QueryPlan<Window>), typeof(QueryPlan<Pane>))]
public sealed class GetTmuxQueryPlanCommand : PSCmdlet
{
    /// <summary>Gets or sets the native query document to plan.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public QueryDocument Query { get; set; } = null!;

    /// <summary>Gets or sets the known daemon version; planning does not discover it.</summary>
    [Parameter(Mandatory = true)]
    public TmuxVersion DaemonVersion { get; set; }

    /// <summary>Gets or sets whether predicates may be evaluated inside tmux.</summary>
    [Parameter]
    [ValidateSet(nameof(QueryPushdown.Auto), nameof(QueryPushdown.Never), nameof(QueryPushdown.Require))]
    public QueryPushdown Pushdown { get; set; } = QueryPushdown.Auto;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        try
        {
            WriteObject(QuerySource.CreatePlan(Query, DaemonVersion, Pushdown));
        }
        catch (Exception exception) when (exception is ArgumentException or UnsupportedQueryExpressionException)
        {
            ThrowTerminatingError(new ErrorRecord(exception, "Tmux.QueryPlanFailed", ErrorCategory.InvalidArgument, Query));
        }
    }
}
