using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Runs one native command on an explicit control connection.</summary>
[Cmdlet(VerbsLifecycle.Invoke, "TmuxControlCommand", SupportsShouldProcess = true)]
[OutputType(typeof(string))]
[UnsupportedOSPlatform("windows")]
public sealed class InvokeTmuxControlCommandCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the borrowed native control connection.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public IControlModeSession Connection { get; set; } = null!;

    /// <summary>Gets or sets the native command, including its captured identity guards.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNull]
    public TmuxCommand Command { get; set; } = null!;

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        try
        {
            CommandAdmission.ValidateName(Command.Name);
        }
        catch (ArgumentException exception)
        {
            ThrowTerminatingError(new ErrorRecord(exception, "Tmux.InvalidCommand", ErrorCategory.InvalidArgument, Command));
        }
    }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (ShouldProcess("supplied tmux control connection", $"Run tmux command {Command.Name}"))
        {
            ReadResult(token => Connection.SendAsync(Command, token), "Tmux.ControlCommandFailed", Connection, enumerateCollection: true);
        }
    }
}
