using System.Collections;
using System.Management.Automation;
using LibTmux.Query;

namespace LibTmux.PowerShell;

/// <summary>Filters captured native panes without contacting tmux.</summary>
[Cmdlet(VerbsCommon.Select, "TmuxPane", DefaultParameterSetName = "Criteria")]
[OutputType(typeof(Pane))]
public sealed class SelectTmuxPaneCommand : TmuxCmdlet
{
    private readonly QuerySelection<Pane> selection = new(QueryTarget.Pane);

    /// <summary>Gets or sets native panes; validation rejects nulls and arbitrary ID-shaped objects.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [AllowNull]
    [AllowEmptyCollection]
    public object?[]? InputObject { get; set; } = [];

    /// <summary>Gets or sets the criteria copied before reading input.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Criteria")]
    [ValidateNotNull]
    [AllowEmptyCollection]
    public IDictionary? Criteria { get; set; }

    /// <summary>Gets or sets an existing native pane query.</summary>
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
