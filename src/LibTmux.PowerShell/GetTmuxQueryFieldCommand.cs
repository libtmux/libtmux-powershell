using System.Management.Automation;
using LibTmux.Query;

namespace LibTmux.PowerShell;

/// <summary>Lists native query fields and their captured-entity bindings.</summary>
[Cmdlet(VerbsCommon.Get, "TmuxQueryField")]
[OutputType(typeof(QueryFieldDescriptor))]
public sealed class GetTmuxQueryFieldCommand : PSCmdlet
{
    /// <summary>Gets or sets the target whose native descriptors are returned.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateSet("Session", "Window", "Pane", "Client")]
    public QueryTarget Target { get; set; }

    /// <inheritdoc />
    protected override void ProcessRecord() => WriteObject(QueryFieldCatalog.GetFields(Target), enumerateCollection: true);
}
