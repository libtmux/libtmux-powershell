# Upstream tmuxp fixtures

These files are unchanged copies of [tmuxp v1.74.0 builder fixtures](https://github.com/tmux-python/tmuxp/tree/91ac8519ac7d54bf540e3488637b9d26a1ee80ef/tests/fixtures/workspace/builder):

| Copy | Upstream file | SHA-256 |
| --- | --- | --- |
| [`tmuxp-v1.74.0-two_windows.yaml`](tmuxp-v1.74.0-two_windows.yaml) | `two_windows.yaml` | `d96733a6709f2bb3c295f6d4abae73ac3f5697009a6da86123c0dba1992282e9` |
| [`tmuxp-v1.74.0-three_windows.yaml`](tmuxp-v1.74.0-three_windows.yaml) | `three_windows.yaml` | `e7c9d625d3d976859839174631db35eacf7b797943465ab15e2b8521f1b86e2e` |
| [`tmuxp-v1.74.0-first_pane_start_directory.yaml`](tmuxp-v1.74.0-first_pane_start_directory.yaml) | `first_pane_start_directory.yaml` | `f68399d1cb2a7c55c0a704287d97f02cfb185e4392f0e4702366286fb02cfa2f` |
| [`tmuxp-v1.74.0-environment_vars.yaml`](tmuxp-v1.74.0-environment_vars.yaml) | `environment_vars.yaml` | `fd1526dbe34c0b8695818103b25ab950208915ee25775682078fb213d955b4a7` |
| [`tmuxp-v1.74.0-window_options.yaml`](tmuxp-v1.74.0-window_options.yaml) | `window_options.yaml` | `09b7ba17cc1436bd3c2b36c7546db1c05de78c2391eee271cb07426c37d12cb4` |
| [`tmuxp-v1.74.0-window_index.yaml`](tmuxp-v1.74.0-window_index.yaml) | `window_index.yaml` | `07504a692b8ae31192772e3fcea01906d85b6949555e62bc6191d116b807bdc2` |

The corpus checks command-object order, live window and pane creation,
first-pane directories, environment overrides, a standard window option,
and session-relative window indices against an owned tmux server.
[`corpus.yaml`](corpus.yaml) and
[`corpus.json`](corpus.json) are locally authored declarations.
