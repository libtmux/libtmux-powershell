using System.Collections;
using System.Globalization;
using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Creates a detached session and returns its captured core object.</summary>
[Cmdlet(VerbsCommon.New, "TmuxSession", SupportsShouldProcess = true)]
[OutputType(typeof(Session), typeof(OwnedSessionScope))]
[UnsupportedOSPlatform("windows")]
public sealed class NewTmuxSessionCommand : TmuxCmdlet
{
    private NewSessionRequest request = null!;

    /// <summary>Gets or sets the endpoint in which to create the session.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Server Server { get; set; } = null!;

    /// <summary>Gets or sets the session name; omission lets tmux choose.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? Name { get; set; }

    /// <summary>Gets or sets the first window's name.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? WindowName { get; set; }

    /// <summary>Gets or sets the first pane's working directory.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? StartDirectory { get; set; }

    /// <summary>Gets or sets one shell-command string for the first pane.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? Command { get; set; }

    /// <summary>Gets or sets the initial width in cells.</summary>
    [Parameter]
    [ValidateRange(1, int.MaxValue)]
    public int? Width { get; set; }

    /// <summary>Gets or sets the initial height in cells.</summary>
    [Parameter]
    [ValidateRange(1, int.MaxValue)]
    public int? Height { get; set; }

    /// <summary>Gets or sets session environment entries with string keys and values.</summary>
    [Parameter]
    [ValidateNotNull]
    public IDictionary? Environment { get; set; }

    /// <summary>Gets or sets whether to return an owner whose disposal destroys the created resource.</summary>
    [Parameter]
    public SwitchParameter Owned { get; set; }

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        try
        {
            request = new NewSessionRequest
            {
                Name = Name,
                WindowName = WindowName,
                StartDirectory = StartDirectory,
                Command = Command,
                Width = Width?.ToString(CultureInfo.InvariantCulture),
                Height = Height?.ToString(CultureInfo.InvariantCulture),
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
        if (ShouldProcess(CreationEnvironment.Endpoint(Server), "Create detached tmux session"))
        {
            if (Owned)
            {
                ReadScopedResult(token => Server.CreateOwnedSessionAsync(request, token), "Tmux.SessionCreateFailed", Server);
            }
            else
            {
                ReadResult(token => Server.CreateSessionAsync(request, token), "Tmux.SessionCreateFailed", Server);
            }
        }
    }
}
