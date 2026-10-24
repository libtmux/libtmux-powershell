using System.Text;
using System.Text.Json;

namespace LibTmux.PowerShell.Support;

/// <summary>What the module does where a claimed release lacks the behaviour.</summary>
internal enum ClaimHandling
{
    /// <summary>Throws before anything is sent.</summary>
    Refuse,

    /// <summary>Takes another path that gives a close answer.</summary>
    Fallback,

    /// <summary>Changes the input or the result so the operation succeeds.</summary>
    Repair,
}

/// <summary>A tmux command and the flags of it a claim depends on.</summary>
/// <param name="Command">The command name.</param>
/// <param name="Flags">Single-letter flags written with their dash, such as <c>-b</c>.</param>
internal sealed record CommandClaim(string Command, params string[] Flags);

/// <summary>A feature that exists from one tmux release on.</summary>
/// <param name="Id">The kebab-case id shared across the libtmux ports.</param>
/// <param name="Name">A short heading.</param>
/// <param name="Summary">One sentence on what a caller can do with it.</param>
/// <param name="Since">The first release that has it, spelled as tmux prints it.</param>
/// <param name="Handling">What the module does below <paramref name="Since" />.</param>
/// <param name="Error">The public error a refusal throws; required to refuse.</param>
/// <param name="Apis">Cmdlet names, as the generated API reference spells them.</param>
/// <param name="Commands">The tmux commands the claim concerns.</param>
internal sealed record CapabilityClaim(
    string Id,
    string Name,
    string Summary,
    string Since,
    ClaimHandling Handling,
    string? Error,
    IReadOnlyList<string> Apis,
    IReadOnlyList<CommandClaim> Commands)
{
    /// <summary>Gets the first release that has the behaviour.</summary>
    internal TmuxVersion SinceVersion => TmuxVersion.Parse(Since);
}

/// <summary>A defect in exact releases that the module refuses.</summary>
/// <param name="Id">The kebab-case id shared across the libtmux ports.</param>
/// <param name="Name">A short heading.</param>
/// <param name="Summary">One sentence on the defect and what the module does.</param>
/// <param name="Releases">The affected releases at or above the minimum.</param>
/// <param name="FixedIn">The first release after the defect.</param>
/// <param name="Handling">Whether the module refuses or repairs.</param>
/// <param name="Apis">Cmdlet names, as the generated API reference spells them.</param>
/// <param name="Commands">The tmux commands the claim concerns.</param>
internal sealed record WorkaroundClaim(
    string Id,
    string Name,
    string Summary,
    IReadOnlyList<string> Releases,
    string FixedIn,
    ClaimHandling Handling,
    IReadOnlyList<string> Apis,
    IReadOnlyList<CommandClaim> Commands)
{
    /// <summary>Gets the first affected release.</summary>
    internal TmuxVersion From => TmuxVersion.Parse(Releases[0]);

    /// <summary>Gets the first release after the defect.</summary>
    internal TmuxVersion Until => TmuxVersion.Parse(FixedIn);

    /// <summary>Gets whether the defect is present on a release.</summary>
    /// <param name="version">The daemon's version.</param>
    internal bool Affects(TmuxVersion version) => version >= From && version < Until;
}

/// <summary>
/// Names what a supported daemon can do release by release, and the defects the module refuses.
/// </summary>
/// <remarks>
/// One table decides both behaviour and the published manifest: the feature guards read their
/// releases from here, and <c>capabilities.json</c> at the repository root is written from it.
/// The module reads tmux's version, it does not ask tmux what it can do, so a patched build that
/// differs from its release is judged as that release. A quirk is not a capability; defects are
/// listed apart, with the exact releases they cover.
/// </remarks>
internal static class Capabilities
{
    internal const string ManifestSchema = "libtmux-capabilities/1";

    /// <summary>Gets the documentation site's slug for this port.</summary>
    internal const string Port = "powershell";

    /// <summary>Gets the capabilities, in manifest order.</summary>
    internal static IReadOnlyList<CapabilityClaim> All { get; } =
    [
        new(
            "control-mode",
            "Control mode",
            "Attach a control client and stream events.",
            "3.7",
            ClaimHandling.Refuse,
            "LibTmux.TmuxVersionTooLowException",
            ["Connect-TmuxControl", "Watch-TmuxEvent"],
            [new("attach-session")]),
        new(
            "buffer-delete-named",
            "Named buffer deletion",
            "Delete one paste buffer by name without risking another buffer.",
            "3.4",
            ClaimHandling.Refuse,
            "LibTmux.TmuxVersionTooLowException",
            ["Invoke-TmuxPaneCommand", "Invoke-TmuxCommand", "Invoke-TmuxChain"],
            [new("delete-buffer", "-b")]),
        new(
            "buffer-rename",
            "Buffer rename",
            "Rename one paste buffer by name without risking another buffer.",
            "3.4",
            ClaimHandling.Refuse,
            "LibTmux.TmuxVersionTooLowException",
            ["Invoke-TmuxCommand", "Invoke-TmuxChain"],
            [new("set-buffer", "-b", "-n")]),
        new(
            "layout-without-checksum",
            "Layouts without a checksum",
            "Apply a layout string; earlier releases crash on one that is not a checksummed layout or a preset name.",
            "3.4",
            ClaimHandling.Refuse,
            "LibTmux.TmuxWindowException",
            ["Set-TmuxLayout"],
            [new("select-layout")]),
        new(
            "clipboard-query",
            "Clipboard query",
            "Ask the attached clients for their clipboard; earlier releases can end the server when a client leaves before its terminal answers.",
            "3.6a",
            ClaimHandling.Refuse,
            "LibTmux.TmuxVersionTooLowException",
            ["Invoke-TmuxCommand", "Invoke-TmuxChain", "Invoke-TmuxControlCommand"],
            [new("refresh-client", "-l")]),
    ];

    /// <summary>Gets the release-specific defects, in manifest order.</summary>
    internal static IReadOnlyList<WorkaroundClaim> Workarounds { get; } =
    [
        new(
            "break-pane-misnames-windows",
            "break-pane without a name",
            "break-pane without -n crashes tmux 3.7; the module refuses it.",
            ["3.7"],
            "3.7a",
            ClaimHandling.Refuse,
            ["Invoke-TmuxCommand", "Invoke-TmuxChain", "Invoke-TmuxControlCommand"],
            [new("break-pane", "-n")]),
        new(
            "split-window-percent-size",
            "split-window -p",
            "split-window -p reads its value from -l on tmux 3.4; the module refuses it.",
            ["3.4"],
            "3.5",
            ClaimHandling.Refuse,
            ["Invoke-TmuxCommand", "Invoke-TmuxChain", "Invoke-TmuxControlCommand"],
            [new("split-window", "-p")]),
        new(
            "name-separators-rejected",
            "Colon and period in names",
            "tmux 3.7 rejects ':' and '.' in session and window names; the module refuses them.",
            ["3.7"],
            "3.7a",
            ClaimHandling.Refuse,
            [
                "New-TmuxSession",
                "New-TmuxWindow",
                "Invoke-TmuxWorkspace",
                "Invoke-TmuxCommand",
                "Invoke-TmuxChain",
                "Invoke-TmuxControlCommand",
            ],
            [
                new("new-session", "-n", "-s"),
                new("new-window", "-n"),
                new("break-pane", "-n"),
                new("rename-session"),
                new("rename-window"),
            ]),
    ];

    /// <summary>Gets the first release that has a capability.</summary>
    /// <param name="id">The capability's id.</param>
    internal static TmuxVersion SinceOf(string id) =>
        All.Single(claim => claim.Id == id).SinceVersion;

    /// <summary>Gets a workaround by id.</summary>
    /// <param name="id">The workaround's id.</param>
    internal static WorkaroundClaim Workaround(string id) =>
        Workarounds.Single(claim => claim.Id == id);

    /// <summary>Renders the manifest the documentation reads, as the committed file spells it.</summary>
    internal static string ToManifestJson()
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true }))
        {
            writer.WriteStartObject();
            writer.WriteString("schema", ManifestSchema);
            writer.WriteString("port", Port);
            writer.WriteStartObject("floor");
            writer.WriteString("minimum", LibTmuxInfo.MinimumTmuxVersion.Raw);
            writer.WriteEndObject();
            writer.WriteStartArray("capabilities");
            foreach (CapabilityClaim claim in All)
            {
                writer.WriteStartObject();
                writer.WriteString("id", claim.Id);
                writer.WriteString("name", claim.Name);
                writer.WriteString("summary", claim.Summary);
                writer.WriteString("since", claim.SinceVersion.Raw);
                writer.WriteString("handling", Handling(claim.Handling));
                if (claim.Error is not null)
                {
                    writer.WriteString("error", claim.Error);
                }

                WriteStrings(writer, "apis", claim.Apis);
                WriteCommands(writer, claim.Commands);
                writer.WriteEndObject();
            }

            writer.WriteEndArray();
            writer.WriteStartArray("workarounds");
            foreach (WorkaroundClaim claim in Workarounds)
            {
                writer.WriteStartObject();
                writer.WriteString("id", claim.Id);
                writer.WriteString("name", claim.Name);
                writer.WriteString("summary", claim.Summary);
                WriteStrings(writer, "releases", claim.Releases);
                writer.WriteString("handling", Handling(claim.Handling));
                WriteStrings(writer, "apis", claim.Apis);
                WriteCommands(writer, claim.Commands);
                writer.WriteEndObject();
            }

            writer.WriteEndArray();
            writer.WriteEndObject();
        }

        // The writer separates lines with the platform's newline; the manifest uses one spelling everywhere.
        return Encoding.UTF8.GetString(stream.ToArray()).Replace("\r\n", "\n", StringComparison.Ordinal) + "\n";
    }

    private static string Handling(ClaimHandling handling) => handling switch
    {
        ClaimHandling.Refuse => "refuse",
        ClaimHandling.Fallback => "fallback",
        _ => "repair",
    };

    private static void WriteStrings(Utf8JsonWriter writer, string name, IReadOnlyList<string> values)
    {
        writer.WriteStartArray(name);
        foreach (string value in values)
        {
            writer.WriteStringValue(value);
        }

        writer.WriteEndArray();
    }

    private static void WriteCommands(Utf8JsonWriter writer, IReadOnlyList<CommandClaim> commands)
    {
        writer.WriteStartArray("commands");
        foreach (CommandClaim command in commands)
        {
            writer.WriteStartObject();
            writer.WriteString("command", command.Command);
            if (command.Flags.Length > 0)
            {
                WriteStrings(writer, "flags", command.Flags);
            }

            writer.WriteEndObject();
        }

        writer.WriteEndArray();
    }
}
