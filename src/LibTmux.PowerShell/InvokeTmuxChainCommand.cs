using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Runs an ordered native command sequence and returns its merged result.</summary>
[Cmdlet(VerbsLifecycle.Invoke, "TmuxChain", SupportsShouldProcess = true)]
[OutputType(typeof(TmuxCommandResult))]
[UnsupportedOSPlatform("windows")]
public sealed class InvokeTmuxChainCommand : TmuxCmdlet
{
    private TmuxCommand[] commands = [];

    /// <summary>Gets or sets the server that receives the chain.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <summary>Gets or sets the ordered native commands, including their identity guards.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public TmuxCommand[] Command { get; set; } = [];

    /// <summary>Gets or sets the maximum admitted command count.</summary>
    [Parameter]
    [ValidateRange(1, int.MaxValue)]
    public int MaxCommands { get; set; } = 1024;

    /// <summary>Gets or sets the UTF-8 byte budget for command names, argument text and their NUL terminators.</summary>
    [Parameter]
    [ValidateRange(1L, long.MaxValue)]
    public long MaxInputBytes { get; set; } = 1024 * 1024;

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        try
        {
            commands = CommandAdmission.CopyChain(Command, MaxCommands, MaxInputBytes);
        }
        catch (ArgumentException exception)
        {
            ThrowTerminatingError(new ErrorRecord(exception, "Tmux.InvalidChain", ErrorCategory.InvalidArgument, Command));
        }
    }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (ShouldProcess(TmuxOwner.Describe(Server), $"Run tmux chain of {commands.Length} commands"))
        {
            ReadResult(token => Server.Chain().Then(commands).ExecuteAsync(token), "Tmux.ChainFailed", Server);
        }
    }
}
