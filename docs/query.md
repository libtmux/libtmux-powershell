# Filter and query tmux objects

Use `Where-Object` to filter captured objects locally. Use structured criteria
when a selection needs reuse, serialization or an inspectable source plan. Both
return native tmux objects that feed other cmdlets.

Import `LibTmux` and select an existing endpoint as `$server` with
[New-TmuxServer](reference/LibTmux/New-TmuxServer.md). The examples borrow it and
create or remove no sessions. Read the daemon version for source planning, then
capture its complete pane graph:

<!-- example: query.01-capture -->
```powershell
$captured = $server |
    Get-TmuxServer -ErrorAction Stop |
    Get-TmuxSnapshot -ErrorAction Stop
```

## Start with PowerShell

Select panes at least 50 columns wide. Property access and filtering use the
captured data and never contact tmux.

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

Apply it to the captured panes. Input order, duplicates and object identity stay
intact, and parent and child relations keep the complete graph.

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

- Criteria accept a field's catalog wire name or its native property path:
  [`Width`][criteria-parser] and `pane_width` name the same field.
- Field and operator keys ignore case. Giving both aliases in one map is an
  error.
- A bare value means equality, and the entries of a map combine with
  [`And`][criteria-parser].

The catalog's `Operators` use JSON wire names. In criteria maps use these
PowerShell keys; an unsupported field and operator pair fails at construction.

| Criteria key | Native wire operation | Value |
| --- | --- | --- |
| Bare value or [`Eq`][criteria-parser]; [`Ne`][criteria-parser] | `equal`; `notEqual` | Native scalar value |
| [`Lt`][criteria-parser], [`Le`][criteria-parser], [`Gt`][criteria-parser], [`Ge`][criteria-parser] | `lessThan`, `lessThanOrEqual`, `greaterThan`, `greaterThanOrEqual` | Int64-representable integer |
| [`StartsWith`][criteria-parser], [`EndsWith`][criteria-parser], [`Contains`][criteria-parser] | `startsWithOrdinal`, `endsWithOrdinal`, `containsOrdinal` | String |
| [`EqualIgnoreCase`][criteria-parser] | `stringEqualOrdinalIgnoreCase` | String |
| [`StartsWithIgnoreCase`][criteria-parser], [`EndsWithIgnoreCase`][criteria-parser], [`ContainsIgnoreCase`][criteria-parser] | `startsWithOrdinalIgnoreCase`, `endsWithOrdinalIgnoreCase`, `containsOrdinalIgnoreCase` | String |
| [`In`][criteria-parser], [`NotIn`][criteria-parser] | `or` of `equal`, optionally `not` | Array or list of scalar values |
| [`IsNull`][criteria-parser], [`IsNotNull`][criteria-parser] | `equal` or `notEqual` with null | `$true` only |
| [`Regex`][criteria-parser] | `regex` | Map with [`Pattern`][criteria-parser] and optional [`Options`][criteria-parser] list |
| [`Some`][criteria-parser], [`Every`][criteria-parser], [`None`][criteria-parser] | `any`, `all`, or negated `any` | Child criteria for a collection relation |
| [`Is`][criteria-parser], [`IsNot`][criteria-parser] | `related`, optionally negated | Child criteria for a to-one relation |
| [`And`][criteria-parser], [`Or`][criteria-parser], [`Not`][criteria-parser] | `and`, `or`, `not` | Criteria lists for And/Or; one criteria map for Not |

### Strings

- Equality, membership and substring matching are ordinal and case-sensitive.
  In PowerShell compare with `-ceq` or `-cin`, not `-eq` or `-in`.
- [`EqualIgnoreCase`][criteria-parser], [`StartsWithIgnoreCase`][criteria-parser],
  [`EndsWithIgnoreCase`][criteria-parser] and
  [`ContainsIgnoreCase`][criteria-parser] ask for ordinal case-insensitive
  matching.
- Nothing expands wildcards or normalizes strings.
- The catalog also lists `stringEqualOrdinal`; in criteria that is bare string
  equality or [`Eq`][criteria-parser].

### Values

- Integers are not coerced from strings, Booleans, enums, floating-point or
  decimal values.
- IDs take the matching native ID type or a correctly prefixed string. Single-
  quote session IDs such as `'$0'`.
- `$null` means explicit absence, and an omitted field is unconstrained. An empty
  string is a value.
- ScriptBlocks belong in `Where-Object`; they are not translated into criteria.

### Collections

- A collection property has a scalar path and a relation path. Use
  `'Windows.Count'` for a numeric comparison and [`Windows`][criteria-parser]
  with [`Some`][criteria-parser], [`Every`][criteria-parser] or
  [`None`][criteria-parser].
- A condition that needs both paths takes an explicit [`And`][criteria-parser]
  with separate maps.
- [`ActivePane`][criteria-parser] and [`ActivePane.Value`][criteria-parser] name
  the same captured to-one relation.
- An uncaptured relation raises an error; it never becomes empty data.

### Limits

These construction limits count the nodes that membership and operator maps
expand into:

| Limit | Maximum |
| --- | ---: |
| Predicate depth | 32 |
| Predicate node occurrences | 512 |
| String length | 4,096 Unicode scalar values |
| Regex pattern length | 1,024 Unicode scalar values |
| Encoded JSON | 262,144 UTF-8 bytes |
| Membership entries | 128 |

Cycles, duplicate aliases, invalid Unicode and values past these limits are
rejected. A document owns its values, so editing the original hashtable or list
does not change a query. Serialization uses one schema, `libtmux-query` version
2, and the module includes its JSON schema file.

## Match captured relationships

Select windows with at least one pane that meets both size conditions:

<!-- example: query.06-related -->
```powershell
$captured.Windows | Select-TmuxWindow -Criteria @{
    Panes = @{ Some = @{ Width = @{ Ge = 50 }; Height = @{ Gt = 0 } } }
}
```

- Both conditions apply to the same pane. Two separate
  [`Some`][criteria-parser] clauses may match different panes.
- On an empty captured collection [`Every`][criteria-parser] is true,
  [`Some`][criteria-parser] is false and [`None`][criteria-parser] is true.
- [`Is`][criteria-parser] and [`IsNot`][criteria-parser] traverse one captured
  related object.
- Linked windows keep their session and index placement, so a pane ID can appear
  in several input placements. Selection does not deduplicate them.

Combine alternatives and exclusions to select API or log windows while
excluding scratch windows:

<!-- example: query.07-boolean -->
```powershell
$captured.Windows | Select-TmuxWindow -Criteria @{
    Or = @(@{ Name = @{ StartsWith = 'api-' } }, @{ Name = 'logs' })
    Not = @{ Name = @{ Contains = 'scratch' } }
}
```

For a regular expression, pass an explicit pattern and semantic option list:

<!-- example: query.08-regex -->
```powershell
$captured.Windows | Select-TmuxWindow -Criteria @{
    Name = @{ Regex = @{ Pattern = '^API-'; Options = @('IgnoreCase') } }
}
```

Regex uses the .NET dialect, with
[`CultureInvariant`][regexoptions-cultureinvariant] always on. Options accept
[`IgnoreCase`][regexoptions-ignorecase], [`Multiline`][regexoptions-multiline],
[`ExplicitCapture`][regexoptions-explicitcapture],
[`Singleline`][regexoptions-singleline],
[`IgnorePatternWhitespace`][regexoptions-ignorepatternwhitespace] and
[`CultureInvariant`][regexoptions-cultureinvariant]. Execution-only flags such as
[`Compiled`][regexoptions-compiled] are rejected, and a running match has a
one-second timeout. This is the .NET dialect, not a promise of regex
compatibility with other languages.

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
[`RequiredSnapshotDepth`][query-queryplan-requiredsnapshotdepth] and
`FallbackReasons` explain how it runs. A plan reads no data.

- `-Pushdown Auto` uses exact supported source evaluation.
- `Never` evaluates locally.
- `Require` rejects any local residual.

Execute it against the selected endpoint when a fresh result is needed:

<!-- example: query.11-execute -->
```powershell
$server | Invoke-TmuxQuery -Plan $queryPlan -AsResult -ErrorAction Stop
```

- `-AsResult` emits one `QueryResult`, even with no matches. Its indexed rows
  refer to the complete `Snapshot`; filtering does not prune that graph. Without
  it, matching objects flow down the pipeline one by one.
- `Invoke-TmuxQuery -Query $query` plans against a freshly observed daemon
  version instead.
- Execution never starts an absent daemon, and a prepared plan must match the
  observed version.
- Acquisition is not an atomic transaction.

`-NativeFilter` with `-Target` is a separate expert escape hatch for raw tmux
format filtering. It cannot combine with `-Query`, `-Plan`, `-Pushdown` or
`-AsResult`, and its rows promise no complete structured-query snapshot.

## Require exactly one match

Resolve the captured development session before handing it to another command:

<!-- example: query.12-one -->
```powershell
$captured.Sessions |
    Select-TmuxSession -Criteria @{ Name = 'development' } -ExactlyOne
```

- `-ExactlyOne` holds the match until finite input completes.
- Zero or several matches end with [`Tmux.NoMatch`][queryselection] or
  [`Tmux.MultipleMatches`][queryselection].
- Invalid inputs, unavailable relations, evaluation errors and a pipeline stop
  suppress the held object.
- An infinite stream cannot establish exact cardinality.

The guarantee covers the objects the selector received. A non-terminating error
upstream can skip a source and still leave one match, so use `-ErrorAction Stop`
on every upstream acquisition when you need complete input before a mutation. It
does not roll back changes another command already made. Local selection never
refreshes captured objects; acquire again to see changes.

[criteria-parser]: ../src/LibTmux.PowerShell/QueryCriteria.cs
[regexoptions-cultureinvariant]: https://learn.microsoft.com/en-us/dotnet/api/system.text.regularexpressions.regexoptions#system-text-regularexpressions-regexoptions-cultureinvariant
[regexoptions-multiline]: https://learn.microsoft.com/en-us/dotnet/api/system.text.regularexpressions.regexoptions#system-text-regularexpressions-regexoptions-multiline
[regexoptions-explicitcapture]: https://learn.microsoft.com/en-us/dotnet/api/system.text.regularexpressions.regexoptions#system-text-regularexpressions-regexoptions-explicitcapture
[regexoptions-singleline]: https://learn.microsoft.com/en-us/dotnet/api/system.text.regularexpressions.regexoptions#system-text-regularexpressions-regexoptions-singleline
[regexoptions-ignorepatternwhitespace]: https://learn.microsoft.com/en-us/dotnet/api/system.text.regularexpressions.regexoptions#system-text-regularexpressions-regexoptions-ignorepatternwhitespace
[regexoptions-compiled]: https://learn.microsoft.com/en-us/dotnet/api/system.text.regularexpressions.regexoptions#system-text-regularexpressions-regexoptions-compiled
[query-queryplan-requiredsnapshotdepth]: https://libtmux.org/en/csharp/latest/reference/libtmux-query-queryplan-requiredsnapshotdepth/
[queryselection]: ../src/LibTmux.PowerShell/QuerySelection.cs
[regexoptions-ignorecase]: https://learn.microsoft.com/en-us/dotnet/api/system.text.regularexpressions.regexoptions#system-text-regularexpressions-regexoptions-ignorecase
