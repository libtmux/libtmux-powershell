using System.Runtime.Versioning;
using LibTmux.Query;

namespace LibTmux.PowerShell;

internal static class QuerySource
{
    internal static object CreatePlan(QueryDocument document, TmuxVersion daemonVersion, QueryPushdown pushdown) =>
        document.Target switch
        {
            QueryTarget.Session => document.Plan<Session>(daemonVersion, pushdown),
            QueryTarget.Window => document.Plan<Window>(daemonVersion, pushdown),
            QueryTarget.Pane => document.Plan<Pane>(daemonVersion, pushdown),
            _ => throw UnsupportedTarget(),
        };

    internal static void ValidateTarget(QueryTarget target)
    {
        if (target is not (QueryTarget.Session or QueryTarget.Window or QueryTarget.Pane))
        {
            throw UnsupportedTarget();
        }
    }

    internal static object ValidatePlan(object value) => value switch
    {
        QueryPlan<Session> or QueryPlan<Window> or QueryPlan<Pane> => value,
        _ => throw new ArgumentException("Plan must be a native QueryPlan<Session>, QueryPlan<Window>, or QueryPlan<Pane>.", nameof(value)),
    };

    [UnsupportedOSPlatform("windows")]
    internal static async Task<object> ExecuteDocumentAsync(Server server, QueryDocument document,
        QueryPushdown pushdown, CancellationToken cancellationToken)
    {
        Server live = await InspectAsync(server, cancellationToken).ConfigureAwait(false);
        TmuxVersion version = live.DaemonVersion
            ?? throw new InvalidOperationException("The inspected server did not provide its daemon version.");
        object plan = CreatePlan(document, version, pushdown);
        return await ExecutePlanAsync(live, plan, cancellationToken).ConfigureAwait(false);
    }

    [UnsupportedOSPlatform("windows")]
    internal static async Task<object> ExecutePlanAsync(Server server, object plan, CancellationToken cancellationToken)
    {
        object result = plan switch
        {
            QueryPlan<Session> sessions => await sessions.ExecuteAsync(server, cancellationToken).ConfigureAwait(false),
            QueryPlan<Window> windows => await windows.ExecuteAsync(server, cancellationToken).ConfigureAwait(false),
            QueryPlan<Pane> panes => await panes.ExecuteAsync(server, cancellationToken).ConfigureAwait(false),
            _ => throw new ArgumentException("The supplied value is not a supported native query plan.", nameof(plan)),
        };
        cancellationToken.ThrowIfCancellationRequested();
        return result;
    }

    [UnsupportedOSPlatform("windows")]
    internal static async Task<object> ExecuteNativeAsync(Server server, QueryTarget target,
        UnsafeTmuxFilter filter, CancellationToken cancellationToken)
    {
        Server live = await InspectAsync(server, cancellationToken).ConfigureAwait(false);
        object result = target switch
        {
            QueryTarget.Session => await live.SearchSessionsAsync(filter, cancellationToken).ConfigureAwait(false),
            QueryTarget.Window => await live.SearchWindowsAsync(filter, cancellationToken).ConfigureAwait(false),
            QueryTarget.Pane => await live.SearchPanesAsync(filter, cancellationToken).ConfigureAwait(false),
            _ => throw UnsupportedTarget(),
        };
        cancellationToken.ThrowIfCancellationRequested();
        return result;
    }

    [UnsupportedOSPlatform("windows")]
    private static async Task<Server> InspectAsync(Server server, CancellationToken cancellationToken) =>
        await server.InspectAsync(cancellationToken).ConfigureAwait(false)
            ?? throw new InvalidOperationException("The tmux daemon is absent.");

    private static UnsupportedQueryExpressionException UnsupportedTarget() =>
        new("Source queries support native Session, Window, and Pane targets only.");
}
