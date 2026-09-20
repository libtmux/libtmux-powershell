using System.Buffers;
using System.Collections;
using System.Management.Automation;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.RegularExpressions;
using LibTmux.Query;
using LibTmux.Query.Json;

namespace LibTmux.PowerShell;

internal static class QueryCriteria
{
    private const int MaximumMembership = 128;
    private static readonly QueryJsonLimits Limits = QueryJsonLimits.Default;
    private static readonly Dictionary<QueryTarget, Dictionary<string, FieldAlias>> Aliases = CreateAliases();

    internal static QueryDocument Create(QueryTarget target, IDictionary criteria)
    {
        ValidateTarget(target);
        ArgumentNullException.ThrowIfNull(criteria);
        using var buffer = new BoundedBuffer(Limits.MaximumUtf8Bytes);
        using (var writer = new Utf8JsonWriter(buffer, new JsonWriterOptions
        {
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        }))
        {
            writer.WriteStartObject();
            writer.WriteString("schema", QueryDocument.CurrentSchema);
            writer.WriteNumber("version", QueryDocument.CurrentVersion);
            writer.WriteString("target", Wire(target));
            writer.WritePropertyName("predicate");
            new Writer(writer).Criteria(criteria, target, 1);
            writer.WriteEndObject();
        }

        return QueryJson.Deserialize(Encoding.UTF8.GetString(buffer.GetBuffer(), 0, checked((int)buffer.Length)));
    }

    internal static QueryDocument Parse(string json)
    {
        QueryDocument document = QueryJson.Deserialize(json);
        ValidateTarget(document.Target);
        return document;
    }

    private static void ValidateTarget(QueryTarget target)
    {
        if (target is not (QueryTarget.Session or QueryTarget.Window or QueryTarget.Pane))
        {
            throw Invalid("Criteria require a Session, Window or Pane target.");
        }
    }

    private static string Wire(QueryTarget target) => target switch
    {
        QueryTarget.Session => "session",
        QueryTarget.Window => "window",
        QueryTarget.Pane => "pane",
        _ => throw Invalid("Criteria require a Session, Window or Pane target."),
    };

    private static Dictionary<QueryTarget, Dictionary<string, FieldAlias>> CreateAliases()
    {
        var targets = new Dictionary<QueryTarget, Dictionary<string, FieldAlias>>();
        foreach (QueryTarget target in new[] { QueryTarget.Session, QueryTarget.Window, QueryTarget.Pane })
        {
            var aliases = new Dictionary<string, FieldAlias>(StringComparer.OrdinalIgnoreCase);
            foreach (QueryFieldDescriptor field in QueryFieldCatalog.GetFields(target))
            {
                bool scalar = field.ScalarPropertyPath is not null;
                bool relation = field.RelationPropertyPath is not null;
                if (!scalar && !relation)
                {
                    continue;
                }

                AddAlias(field.WireName, new(field, scalar, relation));
                if (field.ScalarPropertyPath is string scalarPath)
                {
                    AddAlias(scalarPath, new(field, true, false));
                }
                if (field.RelationPropertyPath is string relationPath)
                {
                    AddAlias(relationPath, new(field, false, true));
                    if (relationPath.EndsWith(".Value", StringComparison.Ordinal))
                    {
                        AddAlias(relationPath[..^6], new(field, false, true));
                    }
                }
            }
            targets.Add(target, aliases);

            void AddAlias(string name, FieldAlias alias)
            {
                if (IsBoolean(name) || !aliases.TryAdd(name, alias))
                {
                    throw new InvalidOperationException($"The native query catalog has an ambiguous criteria alias '{name}'.");
                }
            }
        }
        return targets;
    }

    private static bool IsBoolean(string name) => name.Equals("And", StringComparison.OrdinalIgnoreCase)
        || name.Equals("Or", StringComparison.OrdinalIgnoreCase) || name.Equals("Not", StringComparison.OrdinalIgnoreCase);

    private static object? Unwrap(object? value) => value is PSObject wrapper ? wrapper.BaseObject : value;

    private static ArgumentException Invalid(string message) => new(message);

    private static void ValidateString(string text, int maximum, string description)
    {
        int scalars = 0;
        ReadOnlySpan<char> remaining = text;
        while (!remaining.IsEmpty)
        {
            if (++scalars > maximum || Rune.DecodeFromUtf16(remaining, out _, out int consumed) != OperationStatus.Done)
            {
                throw Invalid($"{description} exceeds its Unicode scalar limit or contains invalid UTF-16.");
            }
            remaining = remaining[consumed..];
        }
    }

    private static List<KeyValuePair<string, object?>> Entries(IDictionary map)
    {
        if (map.Count > Limits.MaximumNodes)
        {
            throw Invalid("Criteria map exceeds the entry limit.");
        }
        List<KeyValuePair<string, object?>> entries = [];
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (DictionaryEntry entry in map)
        {
            if (entries.Count >= Limits.MaximumNodes || Unwrap(entry.Key) is not string name)
            {
                throw Invalid("Criteria maps require bounded string keys.");
            }
            ValidateString(name, Limits.MaximumStringLength, "Criteria key");
            if (!seen.Add(name))
            {
                throw Invalid($"Criteria map repeats the case-insensitive key '{name}'.");
            }
            entries.Add(new(name, Unwrap(entry.Value)));
        }
        return entries;
    }

    private static IDictionary Map(object? value) => Unwrap(value) is IDictionary map
        ? map : throw Invalid("Boolean and relationship criteria require a data map.");

    private static IList List(object? value, int maximum)
    {
        value = Unwrap(value);
        if (value is not IList list || value is Array { Rank: not 1 } || list.Count > maximum)
        {
            throw Invalid($"Criteria require an array or list containing at most {maximum} entries.");
        }
        return list;
    }

    private readonly record struct FieldAlias(QueryFieldDescriptor Field, bool Scalar, bool Relation);

    private sealed class Writer(Utf8JsonWriter writer)
    {
        private readonly HashSet<object> active = new(ReferenceEqualityComparer.Instance);
        private int nodes;

        internal void Criteria(IDictionary map, QueryTarget target, int depth)
        {
            Enter(map);
            try
            {
                List<KeyValuePair<string, object?>> entries = Entries(map);
                var fields = new HashSet<string>(StringComparer.Ordinal);
                bool group = entries.Count != 1;
                if (group)
                {
                    Start("and", depth);
                    writer.WriteStartArray("operands");
                }
                foreach ((string name, object? value) in entries)
                {
                    int childDepth = group ? depth + 1 : depth;
                    if (IsBoolean(name))
                    {
                        Boolean(name, value, target, childDepth);
                    }
                    else
                    {
                        if (!Aliases[target].TryGetValue(name, out FieldAlias alias))
                        {
                            throw Invalid($"'{name}' is not a native query field for {target}; use Get-TmuxQueryField.");
                        }
                        if (!fields.Add(alias.Field.WireName))
                        {
                            throw Invalid($"Criteria repeat field '{alias.Field.WireName}' through multiple aliases; combine separate maps with And.");
                        }
                        Field(alias, value, childDepth);
                    }
                }
                if (group)
                {
                    writer.WriteEndArray();
                    End();
                }
            }
            finally { active.Remove(map); }
        }

        private void Boolean(string name, object? value, QueryTarget target, int depth)
        {
            if (name.Equals("Not", StringComparison.OrdinalIgnoreCase))
            {
                Start("not", depth);
                writer.WritePropertyName("operand");
                Criteria(Map(value), target, depth + 1);
                End();
                return;
            }
            IList operands = List(value, Limits.MaximumNodes);
            Enter(operands);
            try
            {
                Start(name.Equals("And", StringComparison.OrdinalIgnoreCase) ? "and" : "or", depth);
                writer.WriteStartArray("operands");
                for (int index = 0; index < operands.Count; index++)
                {
                    if (index >= Limits.MaximumNodes)
                    {
                        throw Invalid("Boolean criteria exceed the operand limit.");
                    }
                    Criteria(Map(operands[index]), target, depth + 1);
                }
                writer.WriteEndArray();
                End();
            }
            finally { active.Remove(operands); }
        }

        private void Field(FieldAlias alias, object? value, int depth)
        {
            if (value is not IDictionary map)
            {
                Comparison(alias, "equal", value, depth);
                return;
            }
            Enter(map);
            try
            {
                List<KeyValuePair<string, object?>> operations = Entries(map);
                if (operations.Count == 0)
                {
                    throw Invalid("A field operator map cannot be empty; use an empty criteria map for an unconstrained predicate.");
                }
                bool group = operations.Count > 1;
                if (group)
                {
                    Start("and", depth);
                    writer.WriteStartArray("operands");
                }
                foreach ((string operation, object? operand) in operations)
                {
                    Operation(alias, operation, operand, group ? depth + 1 : depth);
                }
                if (group)
                {
                    writer.WriteEndArray();
                    End();
                }
            }
            finally { active.Remove(map); }
        }

        private void Operation(FieldAlias alias, string operation, object? value, int depth)
        {
            switch (operation.ToUpperInvariant())
            {
                case "EQ": Comparison(alias, "equal", value, depth); break;
                case "NE": Comparison(alias, "notEqual", value, depth); break;
                case "LT": Comparison(alias, "lessThan", value, depth); break;
                case "LE": Comparison(alias, "lessThanOrEqual", value, depth); break;
                case "GT": Comparison(alias, "greaterThan", value, depth); break;
                case "GE": Comparison(alias, "greaterThanOrEqual", value, depth); break;
                case "STARTSWITH": Comparison(alias, "startsWithOrdinal", value, depth); break;
                case "ENDSWITH": Comparison(alias, "endsWithOrdinal", value, depth); break;
                case "CONTAINS": Comparison(alias, "containsOrdinal", value, depth); break;
                case "EQUALIGNORECASE": Comparison(alias, "stringEqualOrdinalIgnoreCase", value, depth); break;
                case "ISNULL":
                case "ISNOTNULL":
                    if (value is not true)
                    {
                        throw Invalid("IsNull and IsNotNull require the Boolean value true.");
                    }
                    Comparison(alias, operation.Equals("IsNull", StringComparison.OrdinalIgnoreCase) ? "equal" : "notEqual", null, depth);
                    break;
                case "IN": Membership(alias, value, false, depth); break;
                case "NOTIN": Membership(alias, value, true, depth); break;
                case "REGEX": Regex(alias, Map(value), depth); break;
                case "SOME": Relation(alias, Map(value), false, false, false, depth); break;
                case "EVERY": Relation(alias, Map(value), false, true, false, depth); break;
                case "NONE": Relation(alias, Map(value), false, false, true, depth); break;
                case "IS": Relation(alias, Map(value), true, false, false, depth); break;
                case "ISNOT": Relation(alias, Map(value), true, false, true, depth); break;
                default: throw Invalid($"'{operation}' is not a criteria operator.");
            }
        }

        private void Comparison(FieldAlias alias, string operation, object? value, int depth)
        {
            Require(alias, operation, relation: false);
            value = Scalar(alias.Field, Unwrap(value));
            if (value is null && operation is not ("equal" or "notEqual"))
            {
                throw Invalid("Null only supports equality and inequality.");
            }
            Start("comparison", depth);
            writer.WriteString("operator", operation);
            writer.WritePropertyName("left");
            FieldNode(alias.Field, depth + 1);
            writer.WritePropertyName("right");
            Start("constant", depth + 1);
            writer.WriteStartObject("value");
            switch (value)
            {
                case null: writer.WriteString("kind", "null"); break;
                case bool boolean:
                    writer.WriteString("kind", "boolean");
                    writer.WriteBoolean("value", boolean);
                    break;
                case long number:
                    writer.WriteString("kind", "int64");
                    writer.WriteNumber("value", number);
                    break;
                case string text:
                    writer.WriteString("kind", alias.Field.ValueKind == QueryValueKind.TypedId ? "typedId" : "string");
                    if (alias.Field.ValueKind == QueryValueKind.TypedId)
                    {
                        writer.WriteString("type", Wire(alias.Field.Target));
                    }
                    writer.WriteString("value", text);
                    break;
            }
            writer.WriteEndObject();
            End();
            End();
        }

        private void Membership(FieldAlias alias, object? value, bool negate, int depth)
        {
            Require(alias, "equal", relation: false);
            IList values = List(value, MaximumMembership);
            Enter(values);
            try
            {
                if (negate)
                {
                    Start("not", depth++);
                    writer.WritePropertyName("operand");
                }
                Start("or", depth);
                writer.WriteStartArray("operands");
                for (int index = 0; index < values.Count; index++)
                {
                    if (index >= MaximumMembership)
                    {
                        throw Invalid("Membership exceeds 128 entries.");
                    }
                    Comparison(alias, "equal", values[index], depth + 1);
                }
                writer.WriteEndArray();
                End();
                if (negate) { End(); }
            }
            finally { active.Remove(values); }
        }

        private void Relation(FieldAlias alias, IDictionary criteria, bool one, bool every, bool negate, int depth)
        {
            string operation = one ? "related" : every ? "all" : "any";
            Require(alias, operation, relation: true);
            if (alias.Field.Cardinality != (one ? QueryRelationCardinality.One : QueryRelationCardinality.Many)
                || alias.Field.RelatedTarget is not QueryTarget target)
            {
                throw Invalid("The relationship operator does not match the field cardinality.");
            }
            if (negate)
            {
                Start("not", depth++);
                writer.WritePropertyName("operand");
            }
            Start(one ? "related" : "quantifier", depth);
            if (!one) { writer.WriteString("quantifier", operation); }
            writer.WritePropertyName("relation");
            FieldNode(alias.Field, depth + 1);
            writer.WritePropertyName("predicate");
            Criteria(criteria, target, depth + 1);
            End();
            if (negate) { End(); }
        }

        private void Regex(FieldAlias alias, IDictionary map, int depth)
        {
            Require(alias, "regex", relation: false);
            Enter(map);
            try
            {
                string? pattern = null;
                RegexOptions options = RegexOptions.CultureInvariant;
                foreach ((string key, object? value) in Entries(map))
                {
                    if (key.Equals("Pattern", StringComparison.OrdinalIgnoreCase) && value is string text)
                    {
                        ValidateString(text, Limits.MaximumPatternLength, "Regex pattern");
                        pattern = text;
                    }
                    else if (key.Equals("Options", StringComparison.OrdinalIgnoreCase))
                    {
                        IList flags = List(value, 6);
                        for (int index = 0; index < flags.Count; index++)
                        {
                            if (index >= 6 || Unwrap(flags[index]) is not string flag)
                            {
                                throw Invalid("Regex Options require at most six semantic flag names.");
                            }
                            ValidateString(flag, Limits.MaximumStringLength, "Regex option");
                            options |= flag.ToUpperInvariant() switch
                            {
                                "IGNORECASE" => RegexOptions.IgnoreCase,
                                "MULTILINE" => RegexOptions.Multiline,
                                "EXPLICITCAPTURE" => RegexOptions.ExplicitCapture,
                                "SINGLELINE" => RegexOptions.Singleline,
                                "IGNOREPATTERNWHITESPACE" => RegexOptions.IgnorePatternWhitespace,
                                "CULTUREINVARIANT" => RegexOptions.CultureInvariant,
                                _ => throw Invalid("Regex Options contain an unsupported semantic flag."),
                            };
                        }
                    }
                    else { throw Invalid("Regex accepts a string Pattern and an optional Options list only."); }
                }
                if (pattern is null) { throw Invalid("Regex requires a string Pattern."); }
                Start("regex", depth);
                writer.WritePropertyName("input");
                FieldNode(alias.Field, depth + 1);
                writer.WriteString("dialect", "dotnet");
                writer.WriteString("pattern", pattern);
                writer.WriteNumber("semanticOptions", (int)options);
                End();
            }
            finally { active.Remove(map); }
        }

        private static void Require(FieldAlias alias, string operation, bool relation)
        {
            if (!(relation ? alias.Relation : alias.Scalar) || !alias.Field.Operators.Contains(operation, StringComparer.Ordinal))
            {
                throw Invalid($"Field '{alias.Field.WireName}' does not support '{operation}' through this alias. Use a scalar path such as Windows.Count for counts, or the relation path for relationship operators.");
            }
        }

        private void FieldNode(QueryFieldDescriptor field, int depth)
        {
            Start("field", depth);
            writer.WriteString("target", Wire(field.Target));
            writer.WriteString("wireName", field.WireName);
            End();
        }

        private void Enter(object container)
        {
            if (!active.Add(container)) { throw Invalid("Criteria contain a reference cycle."); }
        }

        private void Start(string kind, int depth)
        {
            if (depth > Limits.MaximumDepth || ++nodes > Limits.MaximumNodes)
            {
                throw Invalid("Expanded criteria exceed the native query depth or node limit.");
            }
            writer.WriteStartObject();
            writer.WriteString("kind", kind);
        }

        private void End()
        {
            writer.WriteEndObject();
            writer.Flush();
        }
    }

    private static object? Scalar(QueryFieldDescriptor field, object? value)
    {
        if (value is null) { return null; }
        switch (field.ValueKind)
        {
            case QueryValueKind.Boolean when value is bool:
                return value;
            case QueryValueKind.String when value is string text:
                ValidateString(text, Limits.MaximumStringLength, "String value");
                return text;
            case QueryValueKind.Int64:
                return value switch
                {
                    sbyte number => (long)number,
                    byte number => (long)number,
                    short number => (long)number,
                    ushort number => (long)number,
                    int number => (long)number,
                    uint number => (long)number,
                    long number => number,
                    ulong number when number <= long.MaxValue => (long)number,
                    _ => throw Invalid("Integer criteria require an exact Int64-representable integer; Boolean, floating, decimal, enum and string values are not integers."),
                };
            case QueryValueKind.TypedId:
                if (value is string idText) { ValidateString(idText, Limits.MaximumStringLength, "Typed ID"); }
                return (field.Target, value) switch
                {
                    (QueryTarget.Session, SessionId id) => id.ToString(),
                    (QueryTarget.Window, WindowId id) => id.ToString(),
                    (QueryTarget.Pane, PaneId id) => id.ToString(),
                    (QueryTarget.Session, string id) when SessionId.TryParse(id, out SessionId parsed) => parsed.ToString(),
                    (QueryTarget.Window, string id) when WindowId.TryParse(id, out WindowId parsed) => parsed.ToString(),
                    (QueryTarget.Pane, string id) when PaneId.TryParse(id, out PaneId parsed) => parsed.ToString(),
                    _ => throw Invalid("ID criteria require the matching native ID type or a correctly prefixed ID string."),
                };
            default:
                throw Invalid($"Field '{field.WireName}' requires a value of kind {field.ValueKind}.");
        }
    }

    private sealed class BoundedBuffer(int maximum) : MemoryStream(Math.Min(maximum, 4096))
    {
        public override void Write(ReadOnlySpan<byte> buffer)
        {
            Check(buffer.Length);
            base.Write(buffer);
        }

        public override void Write(byte[] buffer, int offset, int count)
        {
            Check(count);
            base.Write(buffer, offset, count);
        }

        public override void WriteByte(byte value)
        {
            Check(1);
            base.WriteByte(value);
        }

        private void Check(int count)
        {
            if (count > maximum - Position)
            {
                throw Invalid("Criteria exceed the maximum encoded query size.");
            }
        }
    }
}
