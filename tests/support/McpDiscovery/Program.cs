using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;

if (args.Length != 7)
{
    throw new ArgumentException("Expected launcher, tmux executable, socket path, tool version, receipt path, process ID path and guide path.");
}

using CancellationTokenSource deadline = new(TimeSpan.FromSeconds(30));
CancellationToken token = deadline.Token;
string guide = await File.ReadAllTextAsync(args[6], token).ConfigureAwait(false);
Dictionary<string, JsonElement> examples = ReadExamples(guide);
Dictionary<string, string?> environment = StdioClientTransportOptions.GetDefaultEnvironmentVariables();
environment["DOTNET_ROOT"] = Environment.GetEnvironmentVariable("DOTNET_ROOT");
environment["LIBTMUX_TMUX"] = Path.GetFullPath(args[1]);
environment["LIBTMUX_SOCKET_PATH"] = Path.GetFullPath(args[2]);
environment["LIBTMUX_TMUX_CONFIG"] = "/dev/null";
environment["LIBTMUX_TOOLSETS"] = "inspect";
environment["LIBTMUX_MCP_ALLOW_POLLING_FALLBACK"] = "false";
var transport = new StdioClientTransport(new StdioClientTransportOptions
{
    Command = Path.GetFullPath(args[0]),
    InheritEnvironmentVariables = false,
    EnvironmentVariables = environment,
    ShutdownTimeout = TimeSpan.FromSeconds(1),
});

object receipt;
Process? serverProcess = null;
DateTime serverStarted = default;
try
{
    await using (McpClient client = await McpClient.CreateAsync(transport, new McpClientOptions
    {
        ProtocolVersion = "2025-06-18",
        ClientInfo = new() { Name = "libtmux-powershell-discovery", Version = "1" },
    }, cancellationToken: token).ConfigureAwait(false))
    {
        int serverPid = int.Parse(await File.ReadAllTextAsync(args[5], token).ConfigureAwait(false), CultureInfo.InvariantCulture);
        serverProcess = Process.GetProcessById(serverPid);
        serverProcess.EnableRaisingEvents = true;
        serverStarted = serverProcess.StartTime.ToUniversalTime();
        Require(!serverProcess.HasExited, "MCP process exited before discovery.");
        Require(client.NegotiatedProtocolVersion == "2025-06-18", "Initialization protocol differs.");
        Require(client.ServerInfo.Name == "tmux" && client.ServerInfo.Version == args[3], "Installed tool version differs.");
        string instructions = client.ServerInstructions ?? string.Empty;
        Require(Encoding.UTF8.GetByteCount(instructions) <= 2048 && instructions.Contains("tmux://capabilities", StringComparison.Ordinal)
            && instructions.Contains("capture_since", StringComparison.Ordinal), "Routing instructions are missing or oversized.");

        IList<McpClientTool> tools = await client.ListToolsAsync(cancellationToken: token).ConfigureAwait(false);
        IList<McpClientResource> resources = await client.ListResourcesAsync(cancellationToken: token).ConfigureAwait(false);
        Require(resources.Any(resource => resource.Uri == "tmux://capabilities"), "Capabilities resource was not advertised.");
        ReadResourceResult read = await client.ReadResourceAsync("tmux://capabilities", cancellationToken: token).ConfigureAwait(false);
        Require(read.Contents.Count == 1 && read.Contents[0] is TextResourceContents, "Capabilities must be one text resource.");
        string text = ((TextResourceContents)read.Contents[0]).Text;
        Require(Encoding.UTF8.GetByteCount(text) <= 1_000_000, "Capabilities exceeded the discovery ceiling.");
        JsonObject capabilities = JsonNode.Parse(text)!.AsObject();
        Require(capabilities["frozen"]!.GetValue<bool>(), "Capability selection is not frozen.");
        Require(capabilities["connection"]!["resolvedSocketPath"]!.GetValue<string>() == Path.GetFullPath(args[2]), "Capabilities identify the wrong socket.");
        Require(capabilities["toolsets"]!.AsArray().Select(row => row!.GetValue<string>()).SequenceEqual(["inspect"]), "Expected inspect-only tool selection.");
        Require(capabilities["paneObservation"]!["controlRequired"]!.GetValue<bool>()
            && !capabilities["paneObservation"]!["pollingFallbackAllowed"]!.GetValue<bool>(), "Unexpected polling fallback policy.");
        string[] names = tools.Select(tool => tool.Name).Order(StringComparer.Ordinal).ToArray();
        string[] advertised = capabilities["effectiveTools"]!.AsArray().Select(row => row!.GetValue<string>()).Order(StringComparer.Ordinal).ToArray();
        Require(names.Length > 0 && names.Distinct(StringComparer.Ordinal).Count() == names.Length
            && names.SequenceEqual(advertised) && capabilities["toolCount"]!.GetValue<int>() == names.Length,
            "Tool discovery and capabilities disagree.");
        Require(names.Contains("capture_pane", StringComparer.Ordinal) && names.Contains("list_sessions", StringComparer.Ordinal)
            && !names.Contains("create_session", StringComparer.Ordinal) && !names.Contains("kill_session", StringComparer.Ordinal)
            && !names.Contains("run_shell_command", StringComparer.Ordinal), "Inspect-only routing includes mutations or lacks inspection.");
        JsonObject[] rows = capabilities["tools"]!.AsArray().Select(row => row!.AsObject()).ToArray();
        foreach (McpClientTool tool in tools)
        {
            Require(!string.IsNullOrWhiteSpace(tool.ProtocolTool.Description) && tool.ProtocolTool.Annotations is not null
                && tool.ProtocolTool.InputSchema.ValueKind == JsonValueKind.Object, "Tool lacks description, annotations or schema: " + tool.Name);
            JsonObject row = rows.Single(row => row["name"]!.GetValue<string>() == tool.Name);
            Require(JsonNode.DeepEquals(row, tool.ProtocolTool.Meta?["com.git-pull.libtmux-mcp/capability"]), "Tool capability metadata differs: " + tool.Name);
        }
        CallToolResult listed = await client.CallToolAsync("list_sessions", new Dictionary<string, object?>(), cancellationToken: token)
            .ConfigureAwait(false);
        if (listed.IsError is true || listed.StructuredContent is not JsonElement structured ||
            structured.ValueKind != JsonValueKind.Object || !structured.TryGetProperty("result", out JsonElement sessions) ||
            sessions.ValueKind != JsonValueKind.Array || sessions.GetArrayLength() != 1)
        {
            throw new InvalidDataException("list_sessions did not return one structured session.");
        }
        JsonElement session = sessions[0];
        string? sessionName = session.GetProperty("name").GetString();
        string? sessionId = session.GetProperty("sessionId").GetString();
        Require(sessionName == "fixture" && sessionId is { Length: > 1 } && sessionId[0] == '$',
            "list_sessions did not identify the owned fixture session.");
        CallToolResult paneList = await client.CallToolAsync("list_panes",
            ExampleArguments(examples, "list_panes", "session", sessionId!), cancellationToken: token).ConfigureAwait(false);
        JsonElement panes = ToolPayload(paneList, "list_panes", list: true);
        Require(panes.ValueKind == JsonValueKind.Array && panes.GetArrayLength() == 1,
            "list_panes did not return the owned session's single pane.");
        string paneId = panes[0].GetProperty("paneId").GetString()!;
        Require(panes[0].GetProperty("sessionId").GetString() == sessionId && paneId.StartsWith('%'),
            "Pane discovery returned a different owner.");

        CallToolResult capture = await client.CallToolAsync("capture_pane",
            ExampleArguments(examples, "capture_pane", "paneId", paneId), cancellationToken: token).ConfigureAwait(false);
        JsonElement captured = ToolPayload(capture, "capture_pane");
        bool captureContainsReady = captured.GetProperty("content").GetProperty("lines").EnumerateArray()
            .Any(line => line.GetString() == "Service ready");
        Require(captured.GetProperty("paneId").GetString() == paneId && captureContainsReady
            && Complete(captured.GetProperty("content")),
            "Capture did not read the discovered pane's rendered ready line.");

        CallToolResult wait = await client.CallToolAsync("wait_for_text",
            ExampleArguments(examples, "wait_for_text", "paneId", paneId), cancellationToken: token).ConfigureAwait(false);
        JsonElement waited = ToolPayload(wait, "wait_for_text");
        string outcome = waited.GetProperty("outcome").GetString()!;
        bool pollingFallback = waited.GetProperty("pollingFallback").GetBoolean();
        long eventsDropped = waited.GetProperty("eventsDropped").GetInt64();
        bool tailContainsReady = waited.GetProperty("tail").GetProperty("lines").EnumerateArray()
            .Any(line => line.GetString() == "Service ready");
        Require(waited.GetProperty("paneId").GetString() == paneId && outcome == "PresentAtEntry"
            && waited.GetProperty("matchedPattern").GetString() == "^Service ready$"
            && !pollingFallback && eventsDropped == 0 && tailContainsReady && Complete(waited.GetProperty("tail")),
            "Readiness wait did not report the existing match without fallback or loss.");
        receipt = new
        {
            protocol = client.NegotiatedProtocolVersion,
            server = client.ServerInfo,
            sdk = typeof(McpClient).Assembly.GetName().Version!.ToString(),
            effectiveTools = names,
            capabilities,
            listedSession = new { name = sessionName, sessionId },
            paneWorkflow = new { paneId, captureContainsReady, tailContainsReady, outcome, pollingFallback, eventsDropped },
            guideSha256 = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(guide))),
            launcherSha256 = Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(args[0], token).ConfigureAwait(false))),
        };
    }
}
finally
{
    if (serverProcess is not null)
    {
        try
        {
            bool exited = serverProcess.HasExited;
            await File.WriteAllTextAsync(args[5] + ".identity", JsonSerializer.Serialize(new
            {
                id = serverProcess.Id,
                startedUtc = serverStarted,
                exited,
            })).ConfigureAwait(false);
            Require(exited, "MCP transport left its initialized process running.");
        }
        finally
        {
            serverProcess.Dispose();
        }
    }
}
await File.WriteAllTextAsync(args[4], JsonSerializer.Serialize(receipt)).ConfigureAwait(false);
Console.WriteLine("PASS MCP discovery, pane capture, ready-text wait and stdio shutdown");

static Dictionary<string, JsonElement> ReadExamples(string guide)
{
    MatchCollection matches = Regex.Matches(guide,
        @"<!-- mcp-example: (?<name>[a-z_]+) -->\s*```json\r?\n(?<json>[\s\S]*?)\r?\n```",
        RegexOptions.CultureInvariant, TimeSpan.FromSeconds(1));
    Require(matches.Count == 3, "The MCP guide must contain the three registered request examples.");
    Dictionary<string, JsonElement> examples = new(StringComparer.Ordinal);
    foreach (Match match in matches)
    {
        string name = match.Groups["name"].Value;
        JsonElement request = JsonSerializer.Deserialize<JsonElement>(match.Groups["json"].Value);
        Require(request.ValueKind == JsonValueKind.Object && request.GetProperty("name").GetString() == name
            && request.GetProperty("arguments").ValueKind == JsonValueKind.Object && examples.TryAdd(name, request),
            "Invalid or duplicate MCP guide request: " + name);
    }

    Require(examples.ContainsKey("list_panes") && examples.ContainsKey("capture_pane")
        && examples.ContainsKey("wait_for_text"), "The MCP guide's request registry differs from the client workflow.");
    return examples;
}

static Dictionary<string, object?> ExampleArguments(Dictionary<string, JsonElement> examples,
    string name, string targetField, string targetValue)
{
    Dictionary<string, object?> arguments = examples[name].GetProperty("arguments")
        .Deserialize<Dictionary<string, object?>>()!;
    string placeholder = targetField == "session" ? "$0" : "%0";
    Require(arguments.TryGetValue(targetField, out object? value) && value is JsonElement target
        && target.ValueKind == JsonValueKind.String && target.GetString() == placeholder,
        "MCP guide request lacks its documented target placeholder: " + name);
    arguments[targetField] = targetValue;
    return arguments;
}

static bool Complete(JsonElement text) => !text.GetProperty("truncated").GetBoolean()
    && text.GetProperty("droppedLines").GetInt64() == 0 && text.GetProperty("droppedBytes").GetInt64() == 0;

static JsonElement ToolPayload(CallToolResult result, string name, bool list = false)
{
    if (result.IsError is true || result.StructuredContent is not JsonElement structured
        || structured.ValueKind != JsonValueKind.Object)
    {
        throw new InvalidDataException(name + " did not return a structured result.");
    }

    if (!list)
    {
        return structured;
    }

    if (!structured.TryGetProperty("result", out JsonElement payload) || payload.ValueKind != JsonValueKind.Array)
    {
        throw new InvalidDataException(name + " did not return a structured list.");
    }

    return payload;
}

static void Require(bool condition, string message)
{
    if (!condition)
    {
        throw new InvalidDataException(message);
    }
}
