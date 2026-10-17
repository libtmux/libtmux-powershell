namespace LibTmux.PowerShell;

/// <summary>Per-feature tmux requirements above the core floor, decided before any effect.</summary>
internal static class TmuxFeatures
{
    internal static readonly TmuxVersion Control = TmuxVersion.Parse("3.7");

    /// <summary>Refuses a control client below 3.7 before any attach.</summary>
    internal static void RequireControl(TmuxVersionCheck.CheckedVersion daemon, string operation)
    {
        if (daemon.Version < Control)
        {
            throw new TmuxVersionTooLowException(
                $"{operation} attaches a control client, which needs tmux {Control} or newer; "
                + $"the endpoint reports {daemon.Version}. No control client was started.",
                Control,
                daemon.Version);
        }
    }
}
