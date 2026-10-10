using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Reads native grouped hooks from an explicit owner.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxHook", DefaultParameterSetName = "Server")]
[OutputType(typeof(TmuxHook))]
[UnsupportedOSPlatform("windows")]
public sealed class GetTmuxHookCommand : TmuxCmdlet
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
    [Parameter]
    [ValidateNotNullOrEmpty]
    [ValidatePattern(@"\A[^\x00]*[^\s\x00][^\x00]*\z")]
    public string? Name { get; set; }

    /// <summary>Gets or sets an explicit table scope; omission uses the owner scope.</summary>
    [Parameter]
    [ValidateSet("Server", "Session", "Window", "Pane")]
    public OptionScope? Scope { get; set; }

    /// <summary>Gets or sets whether to use the global table.</summary>
    [Parameter]
    public SwitchParameter Global { get; set; }

    private object Owner => (object?)Pane ?? (object?)Window ?? (object?)Session ?? Server!;

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        if (Name is not null && (Name.Contains('[') || Name.Contains(']')))
        {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentException("Get-TmuxHook requires a base hook name; inspect Values for indexed entries."),
                "Tmux.IndexedHookReadNotSupported", ErrorCategory.InvalidArgument, Name));
        }
    }

    /// <inheritdoc />
    protected override void ProcessRecord() =>
        ReadResult(ReadAsync, "Tmux.HookReadFailed", Owner, enumerateCollection: true);

    private async Task<IReadOnlyList<TmuxHook>> ReadAsync(CancellationToken cancellationToken)
    {
        TmuxHooks hooks = TmuxOwner.Hooks(Owner);
        if (Name is null)
        {
            return await hooks.GetAllAsync(new ListHooksRequest { Scope = Scope, Global = Global }, cancellationToken)
                .ConfigureAwait(false);
        }

        TmuxHook? hook = await hooks.GetAsync(new HookRequest(Name) { Scope = Scope, Global = Global }, cancellationToken)
            .ConfigureAwait(false);
        return hook is null ? [] : [hook];
    }
}
