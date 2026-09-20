using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Unsets an option so its inherited value applies.</summary>
[Cmdlet(VerbsCommon.Remove, "TmuxOption", DefaultParameterSetName = "Server", SupportsShouldProcess = true)]
[OutputType(typeof(void))]
[UnsupportedOSPlatform("windows")]
public sealed class RemoveTmuxOptionCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the native server whose option table is used.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Server")]
    [ValidateNotNull]
    public Server? Server { get; set; }

    /// <summary>Gets or sets the native session whose option table is used.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Session")]
    [ValidateNotNull]
    public Session? Session { get; set; }

    /// <summary>Gets or sets the native window whose option table is used.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Window")]
    [ValidateNotNull]
    public Window? Window { get; set; }

    /// <summary>Gets or sets the native pane whose option table is used.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Pane")]
    [ValidateNotNull]
    public Pane? Pane { get; set; }

    /// <summary>Gets or sets the tmux option name, optionally with an array index.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    [ValidatePattern(@"\A[^\x00]*[^\s\x00][^\x00]*\z")]
    public string Name { get; set; } = string.Empty;

    /// <summary>Gets or sets an explicit option scope; omission uses the owner scope.</summary>
    [Parameter]
    [ValidateSet("Server", "Session", "Window", "Pane")]
    public OptionScope? Scope { get; set; }

    /// <summary>Gets or sets whether to use the global table.</summary>
    [Parameter]
    public SwitchParameter Global { get; set; }

    /// <summary>Gets or sets whether to remove every pane override as well.</summary>
    [Parameter]
    public SwitchParameter UnsetPaneOverrides { get; set; }

    /// <summary>Gets or sets whether tmux suppresses missing or rejected option errors.</summary>
    [Parameter]
    public SwitchParameter Quiet { get; set; }

    private object Owner => (object?)Pane ?? (object?)Window ?? (object?)Session ?? Server!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        object owner = Owner;
        string table = $"{(Global ? "global " : string.Empty)}{Scope?.ToString() ?? owner.GetType().Name}";
        string action = UnsetPaneOverrides ? "Unset option and pane overrides" : "Unset option";
        if (ShouldProcess(TmuxOwner.Describe(owner), $"{action} '{Name}' from {table} tmux table"))
        {
            var request = new UnsetOptionRequest(Name)
            {
                Scope = Scope,
                Global = Global,
                UnsetPaneOverrides = UnsetPaneOverrides,
                Quiet = Quiet,
            };
            ExecuteOperation(token => TmuxOwner.Options(owner).UnsetAsync(request, token), "Tmux.OptionRemoveFailed", owner);
        }
    }
}
