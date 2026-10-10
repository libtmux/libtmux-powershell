using System.Management.Automation;

namespace LibTmux.PowerShell;

/// <summary>Disposes an owned tmux scope, retaining retry authority when cleanup fails.</summary>
[Cmdlet(VerbsCommon.Close, "TmuxScope", SupportsShouldProcess = true)]
[OutputType(typeof(void))]
public sealed class CloseTmuxScopeCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the owned resource or created-versus-reused result.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public object InputObject { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (ShouldProcess(InputObject.ToString(), "Dispose tmux ownership scope"))
        {
            RunOperation(_ => ScopeCleanup.Dispose(ScopeCleanup.AcceptCleanup(InputObject)), "Tmux.ScopeCleanupFailed", InputObject);
        }
    }
}
