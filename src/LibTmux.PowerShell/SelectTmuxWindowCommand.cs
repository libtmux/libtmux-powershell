using System.Collections;
using System.Management.Automation;
using LibTmux.Query;

namespace LibTmux.PowerShell;

/// <summary>Filters captured native window placements without contacting tmux.</summary>
[Cmdlet(VerbsCommon.Select, "TmuxWindow", DefaultParameterSetName = "Criteria")]
[OutputType(typeof(Window))]
public sealed class SelectTmuxWindowCommand : TmuxCmdlet
{
    private readonly QuerySelection<Window> selection = new(QueryTarget.Window);

    /// <summary>Gets or sets native window placements; duplicate inputs remain distinct matches.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [AllowNull]
    [AllowEmptyCollection]
    public object?[]? InputObject { get; set; } = [];

    /// <summary>Gets or sets the criteria copied before reading input.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Criteria")]
    [ValidateNotNull]
    [AllowEmptyCollection]
    public IDictionary? Criteria { get; set; }

    /// <summary>Gets or sets an existing native window query.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Query")]
    [ValidateNotNull]
    public QueryDocument? Query { get; set; }

    /// <summary>Gets or sets whether only a single match from successfully completed input is emitted.</summary>
    [Parameter]
    public SwitchParameter ExactlyOne { get; set; }

    /// <inheritdoc />
    protected override void BeginProcessing() => RunOperation(token =>
        selection.Initialize(Query, Criteria, ExactlyOne, ThrowTerminatingError, () => Stopping, token),
        "Tmux.InvalidQuery", (object?)Query ?? Criteria!);

    /// <inheritdoc />
    protected override void ProcessRecord() => RunOperation(token =>
        selection.Process(InputObject, WriteObject, ThrowTerminatingError, () => Stopping, token),
        "Tmux.QuerySelectionFailed", InputObject!);

    /// <inheritdoc />
    protected override void EndProcessing() => RunOperation(token =>
        selection.Complete(WriteObject, ThrowTerminatingError, () => Stopping, token),
        "Tmux.QuerySelectionFailed", (object?)Query ?? Criteria!);
}
