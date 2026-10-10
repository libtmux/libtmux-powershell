using System.Collections;
using System.Management.Automation;
using LibTmux.Query;

namespace LibTmux.PowerShell;

/// <summary>Filters captured native sessions without contacting tmux.</summary>
[Cmdlet(VerbsCommon.Select, "TmuxSession", DefaultParameterSetName = "Criteria")]
[OutputType(typeof(Session))]
public sealed class SelectTmuxSessionCommand : TmuxCmdlet
{
    private readonly QuerySelection<Session> selection = new(QueryTarget.Session);

    /// <summary>Gets or sets native sessions; validation occurs before any retained match is emitted.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [AllowNull]
    [AllowEmptyCollection]
    public object?[]? InputObject { get; set; } = [];

    /// <summary>Gets or sets the criteria copied before reading input.</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Criteria")]
    [ValidateNotNull]
    [AllowEmptyCollection]
    public IDictionary? Criteria { get; set; }

    /// <summary>Gets or sets an existing native session query.</summary>
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
