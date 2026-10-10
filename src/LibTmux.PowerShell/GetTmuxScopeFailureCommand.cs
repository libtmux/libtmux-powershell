using System.Management.Automation;

namespace LibTmux.PowerShell;

/// <summary>Retains the latest failed cmdlet cleanup on an owner, including after pipeline cancellation.</summary>
/// <param name="Owner">The same scope accepted by Close-TmuxScope for another attempt.</param>
/// <param name="BodyFailure">The original body or handoff failure, or null when the body succeeded.</param>
/// <param name="CleanupFailure">The cleanup exception from the failed attempt.</param>
public sealed record TmuxScopeFailure(IAsyncDisposable Owner, Exception? BodyFailure, Exception CleanupFailure);

/// <summary>Reads the latest failed cmdlet cleanup retained on an owned tmux scope.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxScopeFailure", DefaultParameterSetName = "Owner")]
[OutputType(typeof(TmuxScopeFailure))]
public sealed class GetTmuxScopeFailureCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the owner or created-versus-reused result to inspect.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Owner")]
    [ValidateNotNull]
    public object InputObject { get; set; } = null!;

    /// <summary>Gets or sets whether to return unresolved cmdlet cleanup failures across runspaces in this process.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Pending")]
    public SwitchParameter Pending { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord() => RunOperation(_ =>
    {
        if (ParameterSetName == "Pending")
        {
            WriteObject(ScopeCleanup.Pending(), true);
        }
        else if (ScopeCleanup.Failure(ScopeCleanup.AcceptCleanup(InputObject)) is { } failure)
        {
            WriteObject(failure);
        }
    }, "Tmux.ScopeFailureReadFailed", InputObject);
}
