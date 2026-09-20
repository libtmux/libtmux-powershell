using System.Collections;
using System.Management.Automation;
using System.Text.Json;
using LibTmux.Query;

namespace LibTmux.PowerShell;

/// <summary>Constructs one native query document without contacting tmux.</summary>
[Cmdlet(VerbsCommon.New, "TmuxQuery", DefaultParameterSetName = "Criteria")]
[OutputType(typeof(QueryDocument))]
public sealed class NewTmuxQueryCommand : PSCmdlet
{
    /// <summary>Gets or sets the native entity selected by criteria.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Criteria")]
    [ValidateSet("Session", "Window", "Pane")]
    public QueryTarget Target { get; set; }

    /// <summary>Gets or sets the bounded data map copied into the query.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Criteria")]
    [ValidateNotNull]
    [AllowEmptyCollection]
    public IDictionary Criteria { get; set; } = null!;

    /// <summary>Gets or sets a current-schema native query document.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Json")]
    [ValidateNotNullOrEmpty]
    public string Json { get; set; } = string.Empty;

    /// <inheritdoc />
    protected override void ProcessRecord()
    {
        try
        {
            QueryDocument document = ParameterSetName == "Json"
                ? QueryCriteria.Parse(Json) : QueryCriteria.Create(Target, Criteria);
            WriteObject(document);
        }
        catch (Exception exception) when (exception is ArgumentException or UnsupportedQueryExpressionException or JsonException)
        {
            ThrowTerminatingError(new ErrorRecord(exception, "Tmux.InvalidQuery", ErrorCategory.InvalidArgument,
                ParameterSetName == "Json" ? Json : Criteria));
        }
    }
}
