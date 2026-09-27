# Cmdlet reference

Start with a task below, or browse every command in
[LibTmux](LibTmux) and [LibTmux.Workspace](LibTmux.Workspace). These pages are
the source for the help installed with each module.

| Task | Start with | Walkthrough |
| --- | --- | --- |
| Select an endpoint and read objects | [New-TmuxServer](LibTmux/New-TmuxServer.md), [Get-TmuxSnapshot](LibTmux/Get-TmuxSnapshot.md), [Get-TmuxPane](LibTmux/Get-TmuxPane.md) | [Read tmux objects](../read.md) |
| Create a session and split a pane | [New-TmuxSession](LibTmux/New-TmuxSession.md), [Split-TmuxPane](LibTmux/Split-TmuxPane.md) | [Create sessions, windows and panes](../create.md) |
| Run a command and inspect its exit status | [Invoke-TmuxPaneCommand](LibTmux/Invoke-TmuxPaneCommand.md) | [Run to completion](../input.md#run-a-command-to-completion) |
| Send input and read the screen | [Send-TmuxText](LibTmux/Send-TmuxText.md), [Wait-TmuxChannel](LibTmux/Wait-TmuxChannel.md), [Get-TmuxPaneContent](LibTmux/Get-TmuxPaneContent.md) | [Send a command and wait for its output](../input.md#send-a-command-and-wait-for-its-output) |
| Filter a capture or query fresh state | [Get-TmuxQueryField](LibTmux/Get-TmuxQueryField.md), [New-TmuxQuery](LibTmux/New-TmuxQuery.md), [Invoke-TmuxQuery](LibTmux/Invoke-TmuxQuery.md) | [Filter and query](../query.md) |
| Run batches or watch events | [Invoke-TmuxChain](LibTmux/Invoke-TmuxChain.md), [Connect-TmuxControl](LibTmux/Connect-TmuxControl.md), [Watch-TmuxEvent](LibTmux/Watch-TmuxEvent.md) | [Commands](../commands.md), [events](../watch.md) |
| Load and apply a workspace | [Import-TmuxWorkspace](LibTmux.Workspace/Import-TmuxWorkspace.md), [Get-TmuxWorkspacePlan](LibTmux.Workspace/Get-TmuxWorkspacePlan.md), [Invoke-TmuxWorkspace](LibTmux.Workspace/Invoke-TmuxWorkspace.md) | [Build a workspace](../workspace.md) |

In a shell with the modules installed, `Get-Command -Module LibTmux` and
`Get-Command -Module LibTmux.Workspace` list the available cmdlets. For example,
`Get-Help LibTmux\Get-TmuxPane -Examples` shows pane-selection examples;
`Get-Help LibTmux\Get-TmuxPane -Full` includes parameters and pipeline binding.
Help for the workspace module works the same way.

The [MCP server](../mcp.md) is a separate .NET tool. Its tools are discovered
through the MCP client rather than these PowerShell modules.
