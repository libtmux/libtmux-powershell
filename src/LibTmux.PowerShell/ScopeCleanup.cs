using System.Collections.Concurrent;
using System.Management.Automation;
using System.Runtime.CompilerServices;

namespace LibTmux.PowerShell;

internal static class ScopeCleanup
{
    private static readonly ConditionalWeakTable<IAsyncDisposable, FailureState> Failures = new();
    private static readonly ConditionalWeakTable<Exception, HashSet<IAsyncDisposable>> Registrations = new();
    private static readonly ConcurrentDictionary<IAsyncDisposable, TmuxScopeFailure> PendingFailures =
        new(ReferenceEqualityComparer.Instance);

    private sealed class FailureState
    {
        internal TmuxScopeFailure? Latest;
        internal bool Resolved;
    }

    internal static TmuxScopeFailure? Failure(IAsyncDisposable owner) =>
        Failures.TryGetValue(owner, out FailureState? state) ? Volatile.Read(ref state.Latest) : null;

    internal static TmuxScopeFailure[] Pending() => PendingFailures.Values.ToArray();

    internal static object Unwrap(object input) => input is PSObject wrapped ? wrapped.BaseObject : input;

    internal static (IAsyncDisposable Owner, object Value) Accept(object input) => Unwrap(input) switch
    {
        IOwnedTmuxResource<object> owner => (owner, owner.Value),
        FoundOrCreated<Server> result => (result, result.Value),
        FoundOrCreated<Session> result => (result, result.Value),
        FoundOrCreated<Window> result => (result, result.Value),
        FoundOrCreated<Pane> result => (result, result.Value),
        _ => throw new ArgumentException("Supply an owned tmux scope or a Resolve-Tmux result. Borrowed handles do not carry cleanup authority.", nameof(input)),
    };

    internal static IAsyncDisposable AcceptCleanup(object input)
    {
        object value = Unwrap(input);
        // Raw acquisition receipts expose only IAsyncDisposable. Admission here
        // requires the exact owner previously retained by the failure registry.
        return value is IAsyncDisposable owner && Failures.TryGetValue(owner, out _)
            ? owner : Accept(value).Owner;
    }

    internal static void Retain(Exception error)
    {
        HashSet<Exception> seen = new(ReferenceEqualityComparer.Instance);
        Queue<Exception> pending = new();
        pending.Enqueue(error);
        while (pending.TryDequeue(out Exception? failure))
        {
            if (!seen.Add(failure))
            {
                continue;
            }

            HashSet<IAsyncDisposable> registered = Registrations.GetValue(failure,
                static _ => new(ReferenceEqualityComparer.Instance));
            lock (registered)
            {
                foreach (IAsyncDisposable owner in OwnedScope.CleanupOwners(failure))
                {
                    if (!registered.Add(owner))
                    {
                        continue;
                    }
                    FailureState state = Failures.GetValue(owner, static _ => new());
                    lock (state)
                    {
                        if (state.Resolved)
                        {
                            continue;
                        }
                        Exception? cleanup = OwnedScope.CleanupFailure(failure);
                        TmuxScopeFailure record = new(owner, cleanup is null ? null : failure, cleanup ?? failure);
                        Volatile.Write(ref state.Latest, record);
                        PendingFailures[owner] = record;
                    }
                }
            }

            if (failure.InnerException is { } inner)
            {
                pending.Enqueue(inner);
            }
            if (failure is AggregateException aggregate)
            {
                foreach (Exception child in aggregate.InnerExceptions)
                {
                    pending.Enqueue(child);
                }
            }
            if (failure is RuntimeException runtime && runtime.ErrorRecord?.Exception is { } recorded)
            {
                pending.Enqueue(recorded);
            }
        }
    }

    internal static void Dispose(IAsyncDisposable owner, Exception? bodyFailure = null)
    {
        FailureState state = Failures.GetValue(owner, static _ => new());
        // Serialize cmdlet attempts so an older failure cannot overwrite a later
        // successful retry in the process-wide unresolved-failure collection.
        lock (state)
        {
            DisposeCore(owner, bodyFailure, state);
        }
    }

    private static void DisposeCore(IAsyncDisposable owner, Exception? bodyFailure, FailureState state)
    {
        try
        {
            owner.DisposeAsync().AsTask().GetAwaiter().GetResult();
            state.Resolved = true;
            PendingFailures.TryRemove(owner, out _);
        }
        catch (Exception cleanupFailure)
        {
            state.Resolved = false;
            // A stopped PowerShell pipeline can replace its original exception. Keep
            // the paired failure on the same owner so its caller can inspect and retry.
            TmuxScopeFailure record = new(owner, bodyFailure, cleanupFailure);
            Volatile.Write(ref state.Latest, record);
            // A canceled output handoff may never give the caller this owner.
            // Retain its retry authority until a cmdlet cleanup succeeds.
            PendingFailures[owner] = record;
            // Keep the same owner available for a later disposal attempt.
            cleanupFailure.Data["LibTmux.PowerShell.Owner"] = owner;
            if (bodyFailure is null)
            {
                throw;
            }

            HashSet<Exception> seen = new(ReferenceEqualityComparer.Instance);
            Queue<Exception> pending = new();
            pending.Enqueue(bodyFailure);
            while (pending.TryDequeue(out Exception? failure))
            {
                if (!seen.Add(failure))
                {
                    continue;
                }
                failure.Data["LibTmux.PowerShell.Owner"] = owner;
                failure.Data["LibTmux.CleanupFailure"] = OwnedScope.CleanupFailure(failure) is { } previous
                    ? new AggregateException(previous, cleanupFailure)
                    : cleanupFailure;
                if (failure.InnerException is { } inner)
                {
                    pending.Enqueue(inner);
                }
                // ErrorAction Stop later exposes the ErrorRecord's exception rather
                // than its ActionPreferenceStopException wrapper to the caller.
                if (failure is RuntimeException runtime && runtime.ErrorRecord?.Exception is { } recorded)
                {
                    pending.Enqueue(recorded);
                }
            }
        }
    }
}
