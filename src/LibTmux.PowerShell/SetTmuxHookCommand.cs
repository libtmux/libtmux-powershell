using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Sets a hook entry and optionally emits its native readback.</summary>
[Cmdlet(VerbsCommon.Set, "TmuxHook", DefaultParameterSetName = "Server", SupportsShouldProcess = true)]
[OutputType(typeof(TmuxHook))]
[UnsupportedOSPlatform("windows")]
public sealed class SetTmuxHookCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the native server whose hook table is used.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Server")]
    [ValidateNotNull]
    public Server? Server { get; set; }

    /// <summary>Gets or sets the native session whose hook table is used.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Session")]
    [ValidateNotNull]
    public Session? Session { get; set; }

    /// <summary>Gets or sets the native window whose hook table is used.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Window")]
    [ValidateNotNull]
    public Window? Window { get; set; }

    /// <summary>Gets or sets the native pane whose hook table is used.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Pane")]
    [ValidateNotNull]
    public Pane? Pane { get; set; }

    /// <summary>Gets or sets the hook name; indexed mutation targets one entry.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    [ValidatePattern(@"\A[^\x00]*[^\s\x00][^\x00]*\z")]
    public string Name { get; set; } = string.Empty;

    /// <summary>Gets or sets an explicit table scope; omission uses the owner scope.</summary>
    [Parameter]
    [ValidateSet("Server", "Session", "Window", "Pane")]
    public OptionScope? Scope { get; set; }

    /// <summary>Gets or sets whether to use the global table.</summary>
    [Parameter]
    public SwitchParameter Global { get; set; }

    /// <summary>Gets or sets the tmux command text executed by the hook.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    [AllowEmptyString]
    [ValidatePattern(@"^[^\x00]*$")]
    public string Command { get; set; } = string.Empty;

    /// <summary>Gets or sets whether the command joins the existing entries.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    /// <summary>Gets or sets whether to emit the native grouped hook readback.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    private object Owner => (object?)Pane ?? (object?)Window ?? (object?)Session ?? Server!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        object owner = Owner;
        string table = $"{(Global ? "global " : string.Empty)}{Scope?.ToString() ?? owner.GetType().Name}";
        if (!ShouldProcess(TmuxOwner.Describe(owner), $"Set {table} tmux hook '{Name}'"))
        {
            return;
        }

        TmuxHooks hooks = TmuxOwner.Hooks(owner);
        var request = new SetHookRequest(Name, Command) { Scope = Scope, Global = Global, Append = Append };
        if (PassThru)
        {
            ReadResult(token => hooks.SetAsync(request, token), "Tmux.HookSetFailed", owner);
        }
        else
        {
            ExecuteOperation(token => hooks.SetAsync(request, token), "Tmux.HookSetFailed", owner);
        }
    }
}
