using System.Runtime.Versioning;

namespace LibTmux.PowerShell;

[UnsupportedOSPlatform("windows")]
internal static class TmuxOwner
{
    internal static TmuxOptions Options(object owner) => owner switch
    {
        Server server => server.Options,
        Session session => session.Options,
        Window window => window.Options,
        Pane pane => pane.Options,
        _ => throw new ArgumentException("Expected a native tmux owner.", nameof(owner)),
    };

    internal static TmuxHooks Hooks(object owner) => owner switch
    {
        Server server => server.Hooks,
        Session session => session.Hooks,
        Window window => window.Hooks,
        Pane pane => pane.Hooks,
        _ => throw new ArgumentException("Expected a native tmux owner.", nameof(owner)),
    };

    internal static TmuxEnvironment Environment(object owner) => owner switch
    {
        Server server => server.Environment,
        Session session => session.Environment,
        _ => throw new ArgumentException("Expected a native tmux server or session.", nameof(owner)),
    };

    internal static string Describe(object owner)
    {
        Server server = owner switch
        {
            Server endpoint => endpoint,
            Session session => session.Server,
            Window window => window.Server,
            Pane pane => pane.Server,
            _ => throw new ArgumentException("Expected a native tmux owner.", nameof(owner)),
        };
        string endpointName = server.ConnectionOptions.SocketPath ?? server.ConnectionOptions.SocketName ?? "default tmux endpoint";
        return owner switch
        {
            Session session => $"{endpointName} session {session.Id}",
            Window window => $"{endpointName} window {window.Id}",
            Pane pane => $"{endpointName} pane {pane.Id}",
            _ => endpointName,
        };
    }
}
