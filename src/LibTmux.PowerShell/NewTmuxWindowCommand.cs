using System.Collections;
using System.Globalization;
using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Creates a window in a session and returns its captured core object.</summary>
[Cmdlet(VerbsCommon.New, "TmuxWindow", SupportsShouldProcess = true)]
[OutputType(typeof(Window))]
[UnsupportedOSPlatform("windows")]
public sealed class NewTmuxWindowCommand : TmuxCmdlet
{
    private NewWindowRequest request = null!;

    /// <summary>Gets or sets the session in which to create the window.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Session Session { get; set; } = null!;

    /// <summary>Gets or sets the window name.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? Name { get; set; }

    /// <summary>Gets or sets the session-relative index; omission lets tmux choose.</summary>
    [Parameter]
    [ValidateRange(0, int.MaxValue)]
    public int? Index { get; set; }

    /// <summary>Gets or sets the first pane's working directory.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? StartDirectory { get; set; }

    /// <summary>Gets or sets one shell-command string for the first pane.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? Command { get; set; }

    /// <summary>Gets or sets process environment entries with string keys and values.</summary>
    [Parameter]
    [ValidateNotNull]
    public IDictionary? Environment { get; set; }

    /// <summary>Gets or sets whether the created window becomes current.</summary>
    [Parameter]
    public SwitchParameter Activate { get; set; }

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        try
        {
            request = new NewWindowRequest
            {
                Name = Name,
                Index = Index?.ToString(CultureInfo.InvariantCulture),
                StartDirectory = StartDirectory,
                Command = Command,
                Attach = Activate,
                Environment = CreationEnvironment.Copy(Environment)
            };
        }
        catch (ArgumentException exception)
        {
            ThrowTerminatingError(new ErrorRecord(
                exception, "Tmux.InvalidCreation", ErrorCategory.InvalidArgument, null));
        }
    }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (ShouldProcess($"{CreationEnvironment.Endpoint(Session.Server)} session {Session.Id}", "Create tmux window"))
        {
            ReadResult(token => Session.CreateWindowAsync(request, token), "Tmux.WindowCreateFailed", Session);
        }
    }
}
