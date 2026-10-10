namespace LibTmux.Workspace.PowerShell;

internal static class WorkspacePlanPolicy
{
    internal static WorkspacePlanOptions Create(
        WorkspaceExistingSession existingSession,
        WorkspaceServerStartup serverStartup,
        WorkspaceReadiness readiness,
        double readinessTimeout,
        bool compensateOnFailure,
        bool allowHostScripts,
        double hostScriptTimeout,
        int maxHostOutputBytes,
        double cleanupTimeout)
    {
        if (!Enum.IsDefined(existingSession))
        {
            throw new ArgumentOutOfRangeException(nameof(existingSession));
        }

        if (!Enum.IsDefined(serverStartup))
        {
            throw new ArgumentOutOfRangeException(nameof(serverStartup));
        }

        if (!Enum.IsDefined(readiness))
        {
            throw new ArgumentOutOfRangeException(nameof(readiness));
        }

        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maxHostOutputBytes);
        return new WorkspacePlanOptions
        {
            ExistingSession = existingSession,
            ServerStartup = serverStartup,
            Readiness = readiness,
            ReadinessTimeout = Seconds(readinessTimeout, nameof(readinessTimeout)),
            CompensateOnFailure = compensateOnFailure,
            AllowHostScripts = allowHostScripts,
            HostScriptTimeout = Seconds(hostScriptTimeout, nameof(hostScriptTimeout)),
            MaxHostOutputBytes = maxHostOutputBytes,
            CleanupTimeout = Seconds(cleanupTimeout, nameof(cleanupTimeout))
        };
    }

    private static TimeSpan Seconds(double value, string name)
    {
        if (!double.IsFinite(value) || value < 1d / TimeSpan.TicksPerSecond || value > 86400)
        {
            throw new ArgumentOutOfRangeException(name,
                "Timeout must be a finite number of seconds between 0.0000001 and 86400.");
        }

        return TimeSpan.FromSeconds(value);
    }
}
