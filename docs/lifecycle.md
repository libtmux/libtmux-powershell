# Ownership and cleanup

Use `-Owned` when creating a session, window or pane to return a resource owner. Pass that owner to `Invoke-TmuxScope`; its script block receives the normal native object. Cleanup destroys the owned object after the body returns, throws a terminating error or stops its pipeline. The cmdlet emits the body's captured output after cleanup succeeds.

The following ordinary example uses normal tmux defaults. It creates a unique session, captures its initial window, and destroys the session before returning that window snapshot. The test harness supplies socket defaults outside this file.

<!-- example: lifecycle.scope -->

```powershell
Import-Module LibTmux

$name = 'example-' + [Guid]::NewGuid().ToString('N')
New-TmuxServer | New-TmuxSession -Name $name -Owned |
    Invoke-TmuxScope {
        param($session)
        $session | Get-TmuxWindow
    }
```

`New-TmuxServer` without `-Owned` constructs a borrowed endpoint handle. Existing `New-TmuxSession`, `New-TmuxWindow` and `Split-TmuxPane` calls keep returning borrowed native objects unless you add `-Owned`. Disposing a client connection does not destroy remote tmux objects.

For ordinary usage, `Start-TmuxServer` starts or reuses the normal endpoint and returns a native server without requiring a cleanup scope. See the [copyable quick start](../README.md#start-or-reuse-a-workspace) and [external example checks](ordinary-examples.md). The examples below demonstrate ownership and destruction.

## Accept responsibility for existing objects

`ConvertTo-TmuxOwnedResource` accepts a borrowed server, session, window or pane and returns its native owner. Session cleanup destroys its children. Window cleanup destroys the window and all its session links. Pane cleanup follows the pane ID after moves. Server cleanup destroys its accepted daemon and waits for its process to exit; use disposable endpoints for that operation.

Cleanup retains the captured endpoint, object ID, daemon generation and reserved `@libtmux_owner_generation` token. The core initializes an absent token with 32 hexadecimal characters, preserves an existing valid token and rejects malformed values. Do not shadow or change this server option. A replacement daemon cannot acquire the old owner's cleanup authority.

## Find or create

The `Resolve-TmuxServer`, `Resolve-TmuxSession`, `Resolve-TmuxWindow` and `Resolve-TmuxPane` cmdlets return the core's `FoundOrCreated<T>` result. Read `Value`, `Created` and `Owner`. Closing a created result destroys its resource. Closing a reused result leaves the borrowed resource alive.

| Cmdlet | Matching rule |
| --- | --- |
| `Resolve-TmuxServer` | The handle's captured endpoint; startup ownership requires the core's per-call nonce. |
| `Resolve-TmuxSession` | Exact literal session name. |
| `Resolve-TmuxWindow` | One exact literal window name within the supplied session. Duplicate names fail. |
| `Resolve-TmuxPane` | One local `@libtmux-identity` pane option within the supplied window. Duplicate identities fail. |

Calls at the same captured socket path spelling serialize within this process. Other clients can rename, replace or create objects. Applications must coordinate cross-process window names and pane identities if they need uniqueness. `Request` supplies the core's native creation options without changing a reused object.

## Inspect and retry cleanup failures

Keep the owner in a variable when you need to inspect failures or retry cleanup. `Close-TmuxScope` retries a failed attempt on that same owner; a successful repeated close has no effect. The cmdlet preserves the original body error and attaches a paired cleanup exception for normal PowerShell error handling.

PowerShell can replace its original exception while stopping a pipeline. `Get-TmuxScopeFailure` therefore reads the latest failed cmdlet cleanup from the retained owner. Its result contains `BodyFailure`, `CleanupFailure` and `Owner`; a successful retry leaves that diagnostic available. It returns no result before a cleanup failure. Use `Get-TmuxScopeFailure -Pending` to recover unresolved failures across runspaces in the current process, including an owner whose canceled output handoff never reached a caller variable. Each pending record keeps its owner reachable until a cmdlet cleanup succeeds. The core's own `DisposeAsync()` method does not populate or retire these PowerShell records.

Creation can fail before the cmdlet returns an owner. When the core accepted a creation receipt and rollback fails, the cmdlet retains the core's retry owners in `Get-TmuxScopeFailure -Pending` before PowerShell wraps or replaces the error. The records retain the acquisition or cancellation error and the rollback error. Pass a record's `Owner` to `Close-TmuxScope`; the same owner still checks its captured daemon generation and resource ID. A lost receipt that established no authority remains an unknown outcome, with no pending owner. Inspect the native exception's `Dispatch` before another creation attempt.

`Invoke-TmuxScope` treats nonterminating errors according to PowerShell's normal `ErrorAction` rules. Use `-ErrorAction Stop` on commands whose errors should stop the body. Scope cleanup uses an independent five-second deadline. Process termination, a crashed runtime or host loss requires cleanup outside the worker process.

## Find running servers

`Find-TmuxServer` searches immediate socket-directory children and returns one result containing `Servers`, `Diagnostics`, `Truncated`, `EntriesVisited` and `ProbesAttempted`. Supply `-Root` entries and `-NoConfiguredRoots` for a fixed search. Without that switch, the core includes the current user's configured and selected socket directories. It skips symbolic links and sockets owned by another user; probes cannot start daemons. Root, entry, probe and time limits bound the search. A slow filesystem call can exceed its deadline before the next boundary check.

## Defaults and external example tests

The precedence remains explicit socket path or name, nonempty `LIBTMUX_SOCKET_PATH`, nonempty `LIBTMUX_SOCKET_NAME`, selected `TMUX`, then tmux's named default. `TMUX_TMPDIR` controls the named socket root. `-ChildEnvironment` on `New-TmuxServer` supplies a copied map for that handle and its launched processes; null values remove inherited variables. The handle captures the effective environment and executable lookup. Later host changes cannot redirect cleanup.

There is no `LIBTMUX_SOCKET_ENV`. Use `Set-TmuxEnvironment` for tmux's own environment tables. Those tables and the client process environment serve different purposes.

The lifecycle runner executes the same source under a path selector or a name selector. Its parent owns foreground tmux process handles and pidfds, observes exit before deleting its exact root, and cleans up after worker failures, timeout and forced termination. It rejects source/document drift. Native Markdown example and MAML checks remain part of this repository's tooling; reusable Astro, Sphinx/MyST and doctest integrations belong to the broader adapter work and have no PowerShell execution claim here.
