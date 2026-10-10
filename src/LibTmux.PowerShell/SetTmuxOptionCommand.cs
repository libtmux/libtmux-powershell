using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Sets an option and optionally emits its native readback.</summary>
[Cmdlet(VerbsCommon.Set, "TmuxOption", DefaultParameterSetName = "Server", SupportsShouldProcess = true)]
[OutputType(typeof(TmuxOptionValue))]
[UnsupportedOSPlatform("windows")]
public sealed class SetTmuxOptionCommand : TmuxCmdlet
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

    /// <summary>Gets or sets the option value; an empty string remains a value.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    [AllowEmptyString]
    [ValidatePattern(@"^[^\x00]*$")]
    public string Value { get; set; } = string.Empty;

    /// <summary>Gets or sets whether to append to the existing value.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    /// <summary>Gets or sets whether to expand tmux formats in the value.</summary>
    [Parameter]
    public SwitchParameter ExpandFormat { get; set; }

    /// <summary>Gets or sets whether to refuse to replace an existing option.</summary>
    [Parameter]
    public SwitchParameter PreventOverwrite { get; set; }

    /// <summary>Gets or sets whether to emit the native value read back after setting.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    /// <summary>Gets or sets whether tmux suppresses missing or rejected option errors.</summary>
    [Parameter]
    public SwitchParameter Quiet { get; set; }

    private object Owner => (object?)Pane ?? (object?)Window ?? (object?)Session ?? Server!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        object owner = Owner;
        string table = $"{(Global ? "global " : string.Empty)}{Scope?.ToString() ?? owner.GetType().Name}";
        if (!ShouldProcess(TmuxOwner.Describe(owner), $"Set {table} tmux option '{Name}'"))
        {
            return;
        }

        TmuxOptions options = TmuxOwner.Options(owner);
        var request = new SetOptionRequest(Name, Value)
        {
            Scope = Scope,
            Global = Global,
            Append = Append,
            ExpandFormat = ExpandFormat,
            PreventOverwrite = PreventOverwrite,
            Quiet = Quiet,
        };
        if (PassThru)
        {
            ReadResult(token => options.SetAsync(request, token), "Tmux.OptionSetFailed", owner);
        }
        else
        {
            ExecuteOperation(token => options.SetAsync(request, token), "Tmux.OptionSetFailed", owner);
        }
    }
}
