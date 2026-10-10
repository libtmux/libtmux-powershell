using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Accepts explicit destruction responsibility for an existing tmux object.</summary>
[Cmdlet(VerbsData.ConvertTo, "TmuxOwnedResource", SupportsShouldProcess = true)]
[OutputType(typeof(OwnedServerScope), typeof(OwnedSessionScope), typeof(OwnedWindowScope), typeof(OwnedPaneScope))]
[UnsupportedOSPlatform("windows")]
public sealed class ConvertToTmuxOwnedResourceCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the borrowed server, session, window or pane to adopt.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public object InputObject { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (ShouldProcess(InputObject.ToString(), "Accept responsibility for destroying this tmux object"))
        {
            ReadScopedResult<IAsyncDisposable>(async token => ScopeCleanup.Unwrap(InputObject) switch
            {
                Server server => await server.AdoptAsync(token).ConfigureAwait(false),
                Session session => await session.AdoptAsync(token).ConfigureAwait(false),
                Window window => await window.AdoptAsync(token).ConfigureAwait(false),
                Pane pane => await pane.AdoptAsync(token).ConfigureAwait(false),
                _ => throw new ArgumentException("Supply a native tmux server, session, window or pane.", nameof(InputObject)),
            }, "Tmux.OwnershipFailed", InputObject);
        }
    }
}
