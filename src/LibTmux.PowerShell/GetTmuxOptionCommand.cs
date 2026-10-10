using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Reads native option rows from an explicit owner.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxOption", DefaultParameterSetName = "Server")]
[OutputType(typeof(TmuxOption))]
[UnsupportedOSPlatform("windows")]
public sealed class GetTmuxOptionCommand : TmuxCmdlet
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
    [Parameter]
    [ValidateNotNullOrEmpty]
    [ValidatePattern(@"\A[^\x00]*[^\s\x00][^\x00]*\z")]
    public string? Name { get; set; }

    /// <summary>Gets or sets an explicit option scope; omission uses the owner scope.</summary>
    [Parameter]
    [ValidateSet("Server", "Session", "Window", "Pane")]
    public OptionScope? Scope { get; set; }

    /// <summary>Gets or sets whether to use the global table.</summary>
    [Parameter]
    public SwitchParameter Global { get; set; }

    /// <summary>Gets or sets whether to include values inherited from a parent scope.</summary>
    [Parameter]
    public SwitchParameter IncludeInherited { get; set; }

    /// <summary>Gets or sets whether to include hook options.</summary>
    [Parameter]
    public SwitchParameter IncludeHooks { get; set; }

    /// <summary>Gets or sets whether tmux suppresses missing or rejected option errors.</summary>
    [Parameter]
    public SwitchParameter Quiet { get; set; }

    private object Owner => (object?)Pane ?? (object?)Window ?? (object?)Session ?? Server!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        object owner = Owner;
        TmuxOptions options = TmuxOwner.Options(owner);
        ReadResult(token => Name is null
            ? options.GetAllAsync(new GetOptionsRequest
            {
                Scope = Scope,
                Global = Global,
                IncludeInherited = IncludeInherited,
                IncludeHooks = IncludeHooks,
                Quiet = Quiet,
            }, token)
            : options.GetAsync(new GetOptionRequest(Name)
            {
                Scope = Scope,
                Global = Global,
                IncludeInherited = IncludeInherited,
                IncludeHooks = IncludeHooks,
                Quiet = Quiet,
            }, token), "Tmux.OptionReadFailed", owner, enumerateCollection: true);
    }
}
