using System.Management.Automation;
using System.Runtime.Versioning;
using LibTmux.Query;

namespace LibTmux.PowerShell;

/// <summary>Executes a native query or explicit raw filter against a supplied server.</summary>
[Cmdlet(VerbsLifecycle.Invoke, "TmuxQuery", DefaultParameterSetName = "Query")]
[OutputType(typeof(Session), typeof(Window), typeof(Pane),
    typeof(QueryResult<Session>), typeof(QueryResult<Window>), typeof(QueryResult<Pane>))]
[UnsupportedOSPlatform("windows")]
public sealed class InvokeTmuxQueryCommand : TmuxCmdlet
{
    private object? acceptedPlan;
    private UnsafeTmuxFilter? acceptedFilter;

    /// <summary>Gets or sets the explicit endpoint to inspect and query.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <summary>Gets or sets the document planned using the inspected daemon version.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Query")]
    [ValidateNotNull]
    public QueryDocument? Query { get; set; }

    /// <summary>Gets or sets a native Session, Window, or Pane plan prepared for this daemon version.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Plan")]
    [ValidateNotNull]
    public object? Plan { get; set; }

    /// <summary>Gets or sets source evaluation policy when executing a document.</summary>
    [Parameter(ParameterSetName = "Query")]
    [ValidateSet(nameof(QueryPushdown.Auto), nameof(QueryPushdown.Never), nameof(QueryPushdown.Require))]
    public QueryPushdown Pushdown { get; set; } = QueryPushdown.Auto;

    /// <summary>Gets or sets whether to emit one native result retaining its complete snapshot.</summary>
    [Parameter(ParameterSetName = "Query")]
    [Parameter(ParameterSetName = "Plan")]
    public SwitchParameter AsResult { get; set; }

    /// <summary>Gets or sets the entity searched by the raw native filter.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "NativeFilter")]
    [ValidateSet("Session", "Window", "Pane")]
    public QueryTarget Target { get; set; }

    /// <summary>Gets or sets uninterpreted tmux filter text; raw rows do not form a complete query snapshot.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "NativeFilter")]
    [ValidateNotNullOrEmpty]
    public string? NativeFilter { get; set; }

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        try
        {
            switch (ParameterSetName)
            {
                case "Plan":
                    acceptedPlan = QuerySource.ValidatePlan(Plan is PSObject wrapper ? wrapper.BaseObject : Plan!);
                    break;
                case "NativeFilter":
                    QuerySource.ValidateTarget(Target);
                    if (NativeFilter!.Contains('\0'))
                    {
                        throw new ArgumentException("A native tmux filter cannot contain a NUL character.", nameof(NativeFilter));
                    }
                    acceptedFilter = new UnsafeTmuxFilter(NativeFilter);
                    break;
                default:
                    QuerySource.ValidateTarget(Query!.Target);
                    break;
            }
        }
        catch (Exception exception) when (exception is ArgumentException or UnsupportedQueryExpressionException)
        {
            ThrowTerminatingError(new ErrorRecord(exception, "Tmux.InvalidQuerySource", ErrorCategory.InvalidArgument,
                ParameterSetName == "Plan" ? Plan : ParameterSetName == "NativeFilter" ? NativeFilter : Query));
        }
    }

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(ExecuteAsync, "Tmux.QueryExecutionFailed", Server, enumerateCollection: !AsResult);

    private Task<object> ExecuteAsync(CancellationToken cancellationToken) => ParameterSetName switch
    {
        "Plan" => QuerySource.ExecutePlanAsync(Server, acceptedPlan!, cancellationToken),
        "NativeFilter" => QuerySource.ExecuteNativeAsync(Server, Target, acceptedFilter!, cancellationToken),
        _ => QuerySource.ExecuteDocumentAsync(Server, Query!, Pushdown, cancellationToken),
    };
}
