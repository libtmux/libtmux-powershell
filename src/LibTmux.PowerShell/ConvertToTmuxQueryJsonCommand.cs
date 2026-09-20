using System.Management.Automation;
using LibTmux.Query;
using LibTmux.Query.Json;

namespace LibTmux.PowerShell;

/// <summary>Serializes a native query document in the current wire schema.</summary>
[Cmdlet(VerbsData.ConvertTo, "TmuxQueryJson")]
[OutputType(typeof(string))]
public sealed class ConvertToTmuxQueryJsonCommand : PSCmdlet
{
    /// <summary>Gets or sets the native document to serialize.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public QueryDocument Query { get; set; } = null!;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        try
        {
            WriteObject(QueryJson.Serialize(Query));
        }
        catch (Exception exception) when (exception is ArgumentException or UnsupportedQueryExpressionException)
        {
            ThrowTerminatingError(new ErrorRecord(exception, "Tmux.QueryJsonFailed", ErrorCategory.InvalidData, Query));
        }
    }
}
