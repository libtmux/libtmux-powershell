using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Reads native entries from a server or session environment.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxEnvironment", DefaultParameterSetName = "Server")]
[OutputType(typeof(TmuxEnvironmentEntry))]
[UnsupportedOSPlatform("windows")]
public sealed class GetTmuxEnvironmentCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the native server whose environment is used.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Server")]
    [ValidateNotNull]
    public Server? Server { get; set; }

    /// <summary>Gets or sets the native session whose environment is used.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Session")]
    [ValidateNotNull]
    public Session? Session { get; set; }

    /// <summary>Gets or sets the environment variable name.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    [ValidatePattern(@"\A[^\x00]*[^\s\x00][^\x00]*\z")]
    public string? Name { get; set; }

    private object Owner => (object?)Session ?? Server!;

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(ReadAsync, "Tmux.EnvironmentReadFailed", Owner, enumerateCollection: true);

    private async Task<IReadOnlyList<TmuxEnvironmentEntry>> ReadAsync(CancellationToken cancellationToken)
    {
        TmuxEnvironment environment = TmuxOwner.Environment(Owner);
        if (Name is null)
        {
            return await environment.GetAllAsync(cancellationToken).ConfigureAwait(false);
        }

        TmuxEnvironmentEntry? entry = await environment.GetAsync(Name, cancellationToken).ConfigureAwait(false);
        return entry is null ? [] : [entry];
    }
}
