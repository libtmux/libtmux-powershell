namespace LibTmux.PowerShell;

/// <summary>Declares that a cmdlet's operations never dispatch to a tmux daemon it must check.</summary>
/// <remarks>
/// Any other <see cref="TmuxCmdlet" /> that cannot resolve a server for an operation fails that
/// operation instead of running without a version check.
/// </remarks>
[AttributeUsage(AttributeTargets.Class, Inherited = false)]
public sealed class TmuxVersionCheckExemptAttribute : Attribute
{
    /// <summary>Initializes the exemption.</summary>
    /// <param name="reason">Why no daemon needs a version check.</param>
    public TmuxVersionCheckExemptAttribute(string reason) => Reason = reason;

    /// <summary>Gets why no daemon needs a version check.</summary>
    public string Reason { get; }
}
