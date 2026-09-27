using System.Collections;
using System.Management.Automation;
using LibTmux.Query;

namespace LibTmux.PowerShell;

internal sealed class QuerySelection<T>(QueryTarget target) where T : class
{
    private QueryDocument? document;
    private T? retained;
    private bool exactlyOne;
    private bool failed;

    internal void Initialize(QueryDocument? query, IDictionary? criteria, bool requireOne,
        Action<ErrorRecord> terminate, Func<bool> stopping, CancellationToken cancellationToken) =>
        Guard(() =>
        {
            QueryDocument accepted = query ?? QueryCriteria.Create(target, criteria!);
            if (accepted.Target != target)
            {
                throw new ArgumentException($"This selector requires a {target} query, not {accepted.Target}.", nameof(query));
            }
            _ = QueryExtensions.Matching(Array.Empty<T>(), accepted, cancellationToken);
            document = accepted;
            exactlyOne = requireOne;
        }, "Tmux.InvalidQuery", (object?)query ?? criteria, terminate, stopping);

    internal void Process(object?[]? values, Action<object> write,
        Action<ErrorRecord> terminate, Func<bool> stopping, CancellationToken cancellationToken)
    {
        if (failed) { return; }
        if (values is null)
        {
            Guard(() => throw new ArgumentNullException(nameof(values), "A selector input cannot be null."),
                "Tmux.QuerySelectionFailed", null, terminate, stopping);
            return;
        }
        foreach (object? input in values)
        {
            object? value = input is PSObject wrapper ? wrapper.BaseObject : input;
            Guard(() =>
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (value is not T entity)
                {
                    throw new ArgumentException($"This selector accepts native {typeof(T).Name} objects only, including in input arrays.", nameof(values));
                }
                IReadOnlyList<T> matches = QueryExtensions.Matching(new[] { entity }, document!, cancellationToken);
                cancellationToken.ThrowIfCancellationRequested();
                if (matches.Count == 0) { return; }
                if (!exactlyOne)
                {
                    write(entity);
                }
                else if (retained is not null)
                {
                    throw new CardinalityException(multiple: true);
                }
                else
                {
                    retained = entity;
                }
            }, "Tmux.QuerySelectionFailed", value, terminate, stopping);
        }
    }

    internal void Complete(Action<object> write,
        Action<ErrorRecord> terminate, Func<bool> stopping, CancellationToken cancellationToken)
    {
        if (failed || !exactlyOne) { return; }
        Guard(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (stopping()) { throw new PipelineStoppedException(); }
            if (retained is null) { throw new CardinalityException(multiple: false); }
            T selected = retained;
            retained = null;
            write(selected);
        }, "Tmux.QuerySelectionFailed", document, terminate, stopping);
    }

    private void Guard(Action action, string errorId, object? errorTarget, Action<ErrorRecord> terminate, Func<bool> stopping)
    {
        try { action(); }
        catch (Exception exception)
        {
            failed = true;
            retained = null;
            if (exception is PipelineStoppedException or ActionPreferenceStopException) { throw; }
            if (exception is OperationCanceledException && stopping()) { throw new PipelineStoppedException(); }
            ErrorCategory category = exception switch
            {
                CardinalityException { Multiple: true } => ErrorCategory.InvalidResult,
                CardinalityException => ErrorCategory.ObjectNotFound,
                OperationCanceledException => ErrorCategory.OperationStopped,
                TimeoutException => ErrorCategory.OperationTimeout,
                ArgumentException or UnsupportedQueryExpressionException => ErrorCategory.InvalidArgument,
                InvalidDataException or IncompleteSnapshotException or InconsistentSnapshotException => ErrorCategory.InvalidData,
                _ => ErrorCategory.InvalidOperation,
            };
            if (exception is CardinalityException cardinality)
            {
                errorId = cardinality.Multiple ? "Tmux.MultipleMatches" : "Tmux.NoMatch";
            }
            terminate(new ErrorRecord(exception, errorId, category, errorTarget));
        }
    }

    private sealed class CardinalityException(bool multiple) : InvalidOperationException(multiple
        ? "ExactlyOne requires one match; a second matching input was received."
        : "ExactlyOne requires one match; the input completed without a match.")
    {
        internal bool Multiple { get; } = multiple;
    }
}
