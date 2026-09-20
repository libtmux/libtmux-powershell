using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Unsets an environment entry or marks it removed for future processes.</summary>
[Cmdlet(VerbsCommon.Remove, "TmuxEnvironment", DefaultParameterSetName = "Server", SupportsShouldProcess = true)]
[OutputType(typeof(void))]
[UnsupportedOSPlatform("windows")]
public sealed class RemoveTmuxEnvironmentCommand : TmuxCmdlet
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
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    [ValidatePattern(@"\A[^\x00]*[^\s\x00][^\x00]*\z")]
    public string Name { get; set; } = string.Empty;

    /// <summary>Gets or sets whether to retain a removal marker instead of forgetting the entry.</summary>
    [Parameter]
    public SwitchParameter MarkRemoved { get; set; }

    private object Owner => (object?)Session ?? Server!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        object owner = Owner;
        string table = owner is Server ? "global" : "session";
        string action = MarkRemoved ? "Mark removed" : "Unset";
        if (ShouldProcess(TmuxOwner.Describe(owner), $"{action} {table} tmux environment variable '{Name}'"))
        {
            TmuxEnvironment environment = TmuxOwner.Environment(owner);
            ExecuteOperation(token => MarkRemoved
                ? environment.RemoveAsync(Name, token)
                : environment.UnsetAsync(Name, token), "Tmux.EnvironmentRemoveFailed", owner);
        }
    }
}
