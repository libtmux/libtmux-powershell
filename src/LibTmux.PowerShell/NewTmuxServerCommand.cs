using System.Collections;
using System.Management.Automation;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Constructs an endpoint handle without contacting tmux.</summary>
/// <remarks>With Owned, starts a daemon and returns its destruction owner.</remarks>
[Cmdlet(VerbsCommon.New, "TmuxServer", DefaultParameterSetName = "Name", SupportsShouldProcess = true)]
[OutputType(typeof(Server), typeof(OwnedServerScope))]
[UnsupportedOSPlatform("windows")]
public sealed class NewTmuxServerCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the tmux socket name.</summary>
    [Parameter(ParameterSetName = "Name")]
    [ValidateNotNullOrEmpty]
    public string? SocketName { get; set; }

    /// <summary>Gets or sets the absolute socket path.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Path")]
    [ValidateNotNullOrEmpty]
    public string? SocketPath { get; set; }

    /// <summary>Gets or sets the tmux executable used by subsequent operations.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string TmuxBinaryPath { get; set; } = "tmux";

    /// <summary>Gets or sets the configuration used if a later operation starts tmux.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? ConfigurationFile { get; set; }

    /// <summary>Gets or sets copied client environment overrides; null values remove variables.</summary>
    [Parameter]
    public IDictionary? ChildEnvironment { get; set; }

    /// <summary>Gets or sets whether to start a new daemon and return its destruction owner.</summary>
    [Parameter]
    public SwitchParameter Owned { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        try
        {
            var options = new ServerConnectionOptions
            {
                TmuxBinaryPath = TmuxBinaryPath,
                SocketName = SocketName,
                SocketPath = SocketPath,
                ConfigurationFile = ConfigurationFile,
                ChildEnvironment = CopyChildEnvironment(ChildEnvironment)
            };
            if (Owned)
            {
                if (ShouldProcess(SocketPath ?? SocketName ?? "captured tmux endpoint", "Start and own a new tmux daemon"))
                {
                    ReadScopedResult(token => Server.CreateOwnedAsync(options, token), "Tmux.ServerCreateFailed", options);
                }
            }
            else
            {
                WriteObject(Server.Open(options));
            }
        }
        catch (ArgumentException exception)
        {
            ThrowTerminatingError(new ErrorRecord(
                exception, "Tmux.InvalidEndpoint", ErrorCategory.InvalidArgument,
                SocketPath ?? SocketName));
        }
    }

    private static Dictionary<string, string?>? CopyChildEnvironment(IDictionary? environment)
    {
        if (environment is null)
        {
            return null;
        }

        var result = new Dictionary<string, string?>(StringComparer.Ordinal);
        foreach (DictionaryEntry entry in environment)
        {
            object keyValue = entry.Key is PSObject keyObject ? keyObject.BaseObject : entry.Key;
            object? value = entry.Value is PSObject valueObject ? valueObject.BaseObject : entry.Value;
            if (keyValue is not string key || (value is not null && value is not string))
            {
                throw new ArgumentException("ChildEnvironment requires string names and string or null values.", nameof(environment));
            }

            result.Add(key, (string?)value);
        }

        return result;
    }
}
