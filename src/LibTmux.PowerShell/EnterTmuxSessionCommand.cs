using System.Management.Automation;
using System.Runtime.ExceptionServices;
using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

/// <summary>Attaches the foreground terminal to an explicit native session.</summary>
[Cmdlet(VerbsCommon.Enter, "TmuxSession", SupportsShouldProcess = true)]
[OutputType(typeof(Session))]
[UnsupportedOSPlatform("windows")]
public sealed class EnterTmuxSessionCommand : TmuxCmdlet
{
    /// <summary>Gets or sets the session whose endpoint and generation are used.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public Session Session { get; set; } = null!;

    /// <summary>Gets or sets whether the attached client is read-only.</summary>
    [Parameter]
    public SwitchParameter ReadOnly { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        if (!ShouldProcess(TmuxOwner.Describe(Session), ReadOnly
            ? "Attach foreground terminal read-only" : "Attach foreground terminal"))
        {
            return;
        }

        RunOperation(token =>
        {
            token.ThrowIfCancellationRequested();
            if (Console.IsInputRedirected)
            {
                throw new InvalidOperationException("Enter-TmuxSession requires terminal stdin. Run it in a foreground terminal.");
            }
            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("TMUX")))
            {
                throw new InvalidOperationException("Enter-TmuxSession does not attach inside another tmux client. Detach first.");
            }

            Session? attached = null;
            Exception? failure = null;
            // Host callbacks, including restoration, stay on the pipeline callback thread.
            Host.NotifyBeginApplication();
            try
            {
                attached = Session.AttachAsync(new AttachSessionRequest { ReadOnly = ReadOnly }, token)
                    .GetAwaiter().GetResult();
            }
            catch (Exception exception)
            {
                failure = exception;
            }

            try
            {
                Host.NotifyEndApplication();
            }
            catch (Exception restorationFailure) when (failure is not null)
            {
                throw new AggregateException("Attachment and host restoration failed.", failure, restorationFailure);
            }

            if (failure is not null)
            {
                ExceptionDispatchInfo.Capture(failure).Throw();
            }
            WriteObject(attached);
        }, "Tmux.SessionAttachFailed", Session);
    }
}
