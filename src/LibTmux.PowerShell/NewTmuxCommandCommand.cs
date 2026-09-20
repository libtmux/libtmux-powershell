using System.Management.Automation;

namespace LibTmux.PowerShell;

/// <summary>Constructs one native tmux command without running it.</summary>
[Cmdlet(VerbsCommon.New, "TmuxCommand")]
[OutputType(typeof(TmuxCommand))]
public sealed class NewTmuxCommandCommand : PSCmdlet
{
    /// <summary>Gets or sets the tmux command name.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Name { get; set; } = string.Empty;

    /// <summary>Gets or sets literal arguments; an empty string remains one argument.</summary>
    [Parameter(Position = 1)]
    [ValidateNotNull]
    [AllowEmptyCollection]
    [AllowEmptyString]
    public string[] Arguments { get; set; } = [];

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        try
        {
            CommandAdmission.ValidateName(Name);
            WriteObject(TmuxCommand.Create(Name, Arguments));
        }
        catch (ArgumentException exception)
        {
            ThrowTerminatingError(new ErrorRecord(exception, "Tmux.InvalidCommand", ErrorCategory.InvalidArgument, Name));
        }
    }
}
