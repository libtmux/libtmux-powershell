# Filter and query tmux objects

Use `Where-Object` to filter captured objects locally. Use structured criteria
when the same selection needs reuse, serialization or an inspectable source
plan. Both return native tmux objects that can feed other cmdlets.

Import `LibTmux` and select an existing endpoint as `$server` with
[New-TmuxServer](reference/LibTmux/New-TmuxServer.md). These examples borrow
that endpoint and do not create or remove sessions. Inspect the daemon version
for source planning, then capture its complete pane graph:

<!-- example: query.01-capture -->
```powershell
$captured = $server |
    Get-TmuxServer -ErrorAction Stop |
    Get-TmuxSnapshot -ErrorAction Stop
```

## Start with PowerShell

Select panes at least 50 columns wide. Property access and filtering use the
captured data; they do not contact tmux.

<!-- example: query.02-native -->
```powershell
$captured.Panes | Where-Object { $_.Width -ge 50 -and $_.Height -gt 0 }
```

For reuse, construct the same condition as a native `QueryDocument`:

<!-- example: query.03-criteria -->
```powershell
$query = New-TmuxQuery -Target Pane -Criteria @{
    Width = @{ Ge = 50 }
    Height = @{ Gt = 0 }
}
```

Apply it to the already captured panes. Input order, duplicates and object
identity remain intact; parent and child relations retain the complete graph.

<!-- example: query.04-select -->
```powershell
$captured.Panes | Select-TmuxPane -Query $query
```

## Criteria vocabulary

`Get-TmuxQueryField` returns native catalog descriptors. Inspect the numeric
width field and its supported wire operations:

<!-- example: query.05-fields -->
```powershell
Get-TmuxQueryField -Target Pane | Where-Object WireName -CEQ 'pane_width'
```

Criteria accept a field's catalog wire name or native property path. For
example, `Width` and `pane_width` address the same field. Field and operator
keys ignore case; specifying both aliases in one map is an error. A bare
value means equality. Entries in a map are combined with `And`.

The catalog's `Operators` use JSON wire names. Use these PowerShell keys in
criteria maps; unsupported field/operator combinations fail at construction.

| Criteria key | Native wire operation | Value |
| --- | --- | --- |
| Bare value or `Eq`; `Ne` | `equal`; `notEqual` | Native scalar value |
| `Lt`, `Le`, `Gt`, `Ge` | `lessThan`, `lessThanOrEqual`, `greaterThan`, `greaterThanOrEqual` | Int64-representable integer |
| `StartsWith`, `EndsWith`, `Contains` | `startsWithOrdinal`, `endsWithOrdinal`, `containsOrdinal` | String |
| `EqualIgnoreCase` | `stringEqualOrdinalIgnoreCase` | String |
| `StartsWithIgnoreCase`, `EndsWithIgnoreCase`, `ContainsIgnoreCase` | `startsWithOrdinalIgnoreCase`, `endsWithOrdinalIgnoreCase`, `containsOrdinalIgnoreCase` | String |
| `In`, `NotIn` | `or` of `equal`, optionally `not` | Array or list of scalar values |
| `IsNull`, `IsNotNull` | `equal` or `notEqual` with null | `$true` only |
| `Regex` | `regex` | Map with `Pattern` and optional `Options` list |
| `Some`, `Every`, `None` | `any`, `all`, or negated `any` | Child criteria for a collection relation |
| `Is`, `IsNot` | `related`, optionally negated | Child criteria for a to-one relation |
| `And`, `Or`, `Not` | `and`, `or`, `not` | Criteria lists for And/Or; one criteria map for Not |

Ordinary string equality, membership and substring matching are ordinal and
case-sensitive. Compare with PowerShell `-ceq` or `-cin`, not its normally
case-insensitive `-eq` or `-in`. `EqualIgnoreCase`, `StartsWithIgnoreCase`,
`EndsWithIgnoreCase` and `ContainsIgnoreCase` explicitly request ordinal
case-insensitive matching. No wildcard expansion or string normalization is
implicit. The catalog also exposes `stringEqualOrdinal`; the criteria form
uses bare string equality or `Eq` for that behavior.

Integers are not coerced from strings, Booleans, enums, floating-point or
decimal values. IDs accept the matching native ID type or a correctly prefixed
string; single-quote session IDs such as `'$0'`. `$null` means explicit absence,
while an omitted field is unconstrained. An empty string remains a value.
ScriptBlocks belong in `Where-Object`; they are not translated into criteria.

Collection properties have separate scalar and relation paths: use
`'Windows.Count'` for a numeric comparison and `Windows` for `Some`/`Every`/`None`.
Use explicit `And` with separate maps when a condition needs both paths.
`ActivePane` and `ActivePane.Value` are aliases for the same captured to-one
relation. Uncaptured relations raise an error; they never become empty data.

These construction limits include nodes introduced when membership and
operator maps expand into the native query:

| Limit | Maximum |
| --- | ---: |
| Predicate depth | 32 |
| Predicate node occurrences | 512 |
| String length | 4,096 Unicode scalar values |
| Regex pattern length | 1,024 Unicode scalar values |
| Encoded JSON | 262,144 UTF-8 bytes |
| Membership entries | 128 |

Cycles, duplicate aliases, invalid Unicode and values beyond these limits are
rejected. Accepted documents own their values; editing the original hashtable
or list does not change a query. Serialization uses the one current schema,
`libtmux-query` version 2; the module includes its JSON schema file.

## Match captured relationships

Select windows with at least one pane that meets both size conditions:

<!-- example: query.06-related -->
```powershell
$captured.Windows | Select-TmuxWindow -Criteria @{
    Panes = @{ Some = @{ Width = @{ Ge = 50 }; Height = @{ Gt = 0 } } }
}
```

Both conditions apply to the same pane. Two separate `Some` clauses may match
different panes. `Every` is true for an empty captured collection; `Some` is
false and `None` is true. `Is` and `IsNot` traverse one captured related object.
Linked windows retain their session/index placement; a pane ID can therefore
appear in several input placements. Selection does not deduplicate them.

Combine alternatives and exclusions to select API or log windows while
excluding scratch windows:

<!-- example: query.07-boolean -->
```powershell
$captured.Windows | Select-TmuxWindow -Criteria @{ Or = @(@{ Name = @{ StartsWith = 'api-' } }, @{ Name = 'logs' }); Not = @{ Name = @{ Contains = 'scratch' } } }
```

For a regular expression, pass an explicit pattern and semantic option list:

<!-- example: query.08-regex -->
```powershell
$captured.Windows | Select-TmuxWindow -Criteria @{ Name = @{ Regex = @{ Pattern = '^API-'; Options = @('IgnoreCase') } } }
```

Regex uses the .NET dialect with `CultureInvariant` always enabled. Options
accept `IgnoreCase`, `Multiline`, `ExplicitCapture`, `Singleline`,
`IgnorePatternWhitespace` and `CultureInvariant`; execution-only flags such as
`Compiled` are rejected. A running match has the native one-second timeout.
This is the shared .NET query contract, not a claim of cross-language regex
compatibility.

## Store a query or acquire a fresh result

`ConvertTo-TmuxQueryJson` returns a JSON string suitable for storage. Restore
that string with `New-TmuxQuery -Json`; this round-trip does not read tmux:

<!-- example: query.09-json -->
```powershell
New-TmuxQuery -Json ($query | ConvertTo-TmuxQueryJson)
```

Prepare a plan using the daemon version from the earlier capture. Planning
and inspecting `$queryPlan` perform no I/O:

<!-- example: query.10-plan -->
```powershell
$queryPlan = $query | Get-TmuxQueryPlan -DaemonVersion $captured.DaemonVersion
```

`PushedPredicate`, `ResidualPredicate`, `RequiredFields`,
`RequiredSnapshotDepth` and `FallbackReasons` explain its execution.
`-Pushdown Auto` uses exact supported source evaluation; `Never` evaluates
locally; `Require` rejects any local residual. A plan does not acquire data.

Execute it against the selected endpoint when a fresh result is needed:

<!-- example: query.11-execute -->
```powershell
$server | Invoke-TmuxQuery -Plan $queryPlan -AsResult -ErrorAction Stop
```

`-AsResult` emits one native `QueryResult`, even with no matches. Its indexed
rows refer to the complete `Snapshot`; filtering does not prune that graph.
Without `-AsResult`, matching native objects flow individually down the
pipeline. Alternatively, `Invoke-TmuxQuery -Query $query` plans against a fresh
observed daemon version. Execution never starts an absent daemon; a prepared
plan must match the observed version. Acquisition is not an atomic transaction.

`-NativeFilter` with `-Target` is a separate expert escape hatch for raw tmux
format filtering. It cannot combine with `-Query`, `-Plan`, `-Pushdown` or
`-AsResult`, and its rows do not promise a complete structured-query snapshot.

## Require exactly one match

Resolve the captured development session before handing it to another command:

<!-- example: query.12-one -->
```powershell
$captured.Sessions | Select-TmuxSession -Criteria @{ Name = 'development' } -ExactlyOne
```

`-ExactlyOne` holds the match until finite input completes. Zero or multiple
matches terminate with `Tmux.NoMatch` or `Tmux.MultipleMatches`. Invalid inputs,
unavailable relations, evaluation errors and pipeline stop suppress the
retained object. An infinite stream cannot establish exact cardinality.

The guarantee concerns successful objects received by the selector. An
upstream nonterminating error can skip a requested source while still leaving
one match. Use `-ErrorAction Stop` on every upstream acquisition when complete
input is required before mutation. It does not roll back changes already
made by another command. Local selection never refreshes captured objects;
use an explicit acquisition to observe changes.
