using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Sets a tmux environment variable for future processes or formats.</summary>
[Cmdlet(VerbsCommon.Set, "TmuxEnvironment", DefaultParameterSetName = "Server", SupportsShouldProcess = true)]
[OutputType(typeof(TmuxEnvironmentEntry))]
[UnsupportedOSPlatform("windows")]
public sealed class SetTmuxEnvironmentCommand : TmuxCmdlet
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

    /// <summary>Gets or sets the value; an empty string remains present.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    [AllowEmptyString]
    [ValidatePattern(@"^[^\x00]*$")]
    public string Value { get; set; } = string.Empty;

    /// <summary>Gets or sets whether tmux expands formats in the value.</summary>
    [Parameter]
    public SwitchParameter ExpandFormats { get; set; }

    /// <summary>Gets or sets whether the variable is available only to tmux formats.</summary>
    [Parameter]
    public SwitchParameter Hidden { get; set; }

    /// <summary>Gets or sets whether to emit the native readback entry.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    private object Owner => (object?)Session ?? Server!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        object owner = Owner;
        string table = owner is Server ? "global" : "session";
        if (!ShouldProcess(TmuxOwner.Describe(owner), $"Set {table} tmux environment variable '{Name}'"))
        {
            return;
        }

        TmuxEnvironment environment = TmuxOwner.Environment(owner);
        if (PassThru)
        {
            ReadResult(token => environment.SetAsync(Name, Value, ExpandFormats, Hidden, token), "Tmux.EnvironmentSetFailed", owner);
        }
        else
        {
            ExecuteOperation(token => environment.SetAsync(Name, Value, ExpandFormats, Hidden, token), "Tmux.EnvironmentSetFailed", owner);
        }
    }
}
