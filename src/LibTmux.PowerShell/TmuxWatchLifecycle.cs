using System.Management.Automation;
using System.Management.Automation.Runspaces;

namespace LibTmux.PowerShell;

/// <summary>Cancels this runspace's active event readers when PowerShell removes the module.</summary>
public sealed class TmuxWatchLifecycle : IModuleAssemblyCleanup
{
    /// <inheritdoc />
    public void OnRemove(PSModuleInfo psModuleInfo)
    {
        if (Runspace.DefaultRunspace is Runspace runspace)
        {
            TmuxWatchRegistry.Cancel(runspace.InstanceId);
        }
    }
}

internal static class TmuxWatchRegistry
{
    private static readonly object Gate = new();
    private static readonly Dictionary<IControlModeSession, Registration> Active = new(ReferenceEqualityComparer.Instance);

    internal static IDisposable Register(IControlModeSession connection, Guid runspaceId, Action stop)
    {
        var registration = new Registration(connection, runspaceId, stop);
        lock (Gate)
        {
            if (!Active.TryAdd(connection, registration))
            {
                throw new InvalidOperationException("This control connection already has an active Watch-TmuxEvent reader. Its event stream has one consumer.");
            }
        }

        return registration;
    }

    internal static void Cancel(Guid runspaceId)
    {
        Registration[] registrations;
        lock (Gate)
        {
            registrations = Active.Values.Where(item => item.RunspaceId == runspaceId).ToArray();
        }

        List<Exception>? failures = null;
        foreach (Registration registration in registrations)
        {
            try
            {
                registration.Stop();
            }
            catch (Exception failure)
            {
                (failures ??= []).Add(failure);
            }
        }

        if (failures is not null)
        {
            throw new AggregateException("Cancelling active tmux event readers failed.", failures);
        }
    }

    private sealed class Registration(IControlModeSession connection, Guid runspaceId, Action stop) : IDisposable
    {
        internal Guid RunspaceId { get; } = runspaceId;

        internal void Stop() => stop();

        public void Dispose()
        {
            lock (Gate)
            {
                Active.Remove(connection);
            }
        }
    }
}
