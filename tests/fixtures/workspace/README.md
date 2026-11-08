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

These unchanged copies come from the same tag's [`examples` directory](https://github.com/tmux-python/tmuxp/tree/91ac8519ac7d54bf540e3488637b9d26a1ee80ef/examples):

| Copy | Upstream file | SHA-256 |
| --- | --- | --- |
| [`tmuxp-v1.74.0-skip-send.yaml`](tmuxp-v1.74.0-skip-send.yaml) | `skip-send.yaml` | `94f9966e4a8b7540d1fcf8297af3b86c239f6376019cd954174ddc8af4644529` |
| [`tmuxp-v1.74.0-skip-send.json`](tmuxp-v1.74.0-skip-send.json) | `skip-send.json` | `3615f4c75ff43fbed2ed71d4a9e5bdb2bc1688871b3d26634a7fa8f25a3b0d52` |
| [`tmuxp-v1.74.0-skip-send-pane-level.yaml`](tmuxp-v1.74.0-skip-send-pane-level.yaml) | `skip-send-pane-level.yaml` | `bbcfafd8a18df84e1d7ba82b317412234c943ef18404e16bd8a671a575a2a96f` |
| [`tmuxp-v1.74.0-skip-send-pane-level.json`](tmuxp-v1.74.0-skip-send-pane-level.json) | `skip-send-pane-level.json` | `53b7ef9cf0f96772988c36b807b1e1fc3cd9f82fa13c7c9ce71af670c616d6f8` |

The rest of that `examples` directory is copied unchanged too, with tmuxp's
license, so that every example tmuxp ships loads through `Import-TmuxWorkspace`
in `tests/WorkspaceFiles.Tests.ps1`. `skip-send.yaml` and
`skip-send-pane-level.yaml` are in the table above. The test names the
examples the loader refuses, with the error each raises.

| Copy | Upstream file | SHA-256 |
| --- | --- | --- |
| [`tmuxp-v1.74.0-2-pane-synchronized.yaml`](tmuxp-v1.74.0-2-pane-synchronized.yaml) | `2-pane-synchronized.yaml` | `36c22bd8ec76aabad4e323aeec5583cdc432b259a20859a83b5a38cfa6f3b4fd` |
| [`tmuxp-v1.74.0-2-pane-vertical.yaml`](tmuxp-v1.74.0-2-pane-vertical.yaml) | `2-pane-vertical.yaml` | `aff75645be09a402cd55d41a2306742edd7642e851ec34542b2e21d836f3eabb` |
| [`tmuxp-v1.74.0-3-pane.yaml`](tmuxp-v1.74.0-3-pane.yaml) | `3-pane.yaml` | `05e2681908ac4eb713c84e7716529822f397a7584ff2f2f4f3dd744a7939da7f` |
| [`tmuxp-v1.74.0-4-pane.yaml`](tmuxp-v1.74.0-4-pane.yaml) | `4-pane.yaml` | `b7f46971537be3282e1a2d94b76cd4314eb31751ec1af04ba10b243bfd46c989` |
| [`tmuxp-v1.74.0-blank-panes.yaml`](tmuxp-v1.74.0-blank-panes.yaml) | `blank-panes.yaml` | `937847d1dc3cd286296c518579bd0a943910e3da4cb776cffb3852fbf3e19bd7` |
| [`tmuxp-v1.74.0-env-variables.yaml`](tmuxp-v1.74.0-env-variables.yaml) | `env-variables.yaml` | `ca94ad2c6791db1e21349c67f4d531d0d945cacd08bb887e2de56dc76c9462c3` |
| [`tmuxp-v1.74.0-focus-window-and-panes.yaml`](tmuxp-v1.74.0-focus-window-and-panes.yaml) | `focus-window-and-panes.yaml` | `262eb3a0922219d287d3823245290890581f36e4874c00c2aae564066617e006` |
| [`tmuxp-v1.74.0-main-pane-height-percentage.yaml`](tmuxp-v1.74.0-main-pane-height-percentage.yaml) | `main-pane-height-percentage.yaml` | `07a33fe4d81546bd0e6112a7ee58df1c44dafd3f5625dd341e699f66b3570646` |
| [`tmuxp-v1.74.0-main-pane-height.yaml`](tmuxp-v1.74.0-main-pane-height.yaml) | `main-pane-height.yaml` | `57a90c109014dbadc2b07d01ef0db765390205f4eb735d99215bdb4d07353154` |
| [`tmuxp-v1.74.0-minimal.yaml`](tmuxp-v1.74.0-minimal.yaml) | `minimal.yaml` | `24216b1e17789460daa0004ed7290c8354fc1278f2003ae2720e6fb8a1c151cd` |
| [`tmuxp-v1.74.0-options.yaml`](tmuxp-v1.74.0-options.yaml) | `options.yaml` | `9624202c8da8e68103c5c01b7b35c93466d2356c8147cff9b37e5c41da5bc496` |
| [`tmuxp-v1.74.0-pane-shell.yaml`](tmuxp-v1.74.0-pane-shell.yaml) | `pane-shell.yaml` | `293f2f047893ac50dd1b3fd6f76ebdb98947374db26d49c346b27e1135fe716f` |
| [`tmuxp-v1.74.0-plugin-system.yaml`](tmuxp-v1.74.0-plugin-system.yaml) | `plugin-system.yaml` | `a6fc2ea11d6dc0ea153997af64ca7e8564d5c2441258a8720c6a8698c070f4b1` |
| [`tmuxp-v1.74.0-session-environment.yaml`](tmuxp-v1.74.0-session-environment.yaml) | `session-environment.yaml` | `d6ea81bff48eaf23f286835f167f6fb2ab082d440b47bb5f1d21d5b1d731f596` |
| [`tmuxp-v1.74.0-shorthands.yaml`](tmuxp-v1.74.0-shorthands.yaml) | `shorthands.yaml` | `dba31248ac82e10bf1e026c4100ff22a51a9acedf1f365e8699c30bd67925278` |
| [`tmuxp-v1.74.0-sleep-pane-level.yaml`](tmuxp-v1.74.0-sleep-pane-level.yaml) | `sleep-pane-level.yaml` | `427905baf7bf54042b660d8f4e76498a53dfc01e4cfd98fc6801698382509811` |
| [`tmuxp-v1.74.0-sleep-virtualenv.yaml`](tmuxp-v1.74.0-sleep-virtualenv.yaml) | `sleep-virtualenv.yaml` | `dc8bf3821d7345b0107824e59788d79121daf611daa3565990a7afab1f35eb06` |
| [`tmuxp-v1.74.0-sleep.yaml`](tmuxp-v1.74.0-sleep.yaml) | `sleep.yaml` | `38c674a40f0a39f8a586e2d305dafdaf1bf3176160022b0c01d1f1cdf427c2a7` |
| [`tmuxp-v1.74.0-start-directory.yaml`](tmuxp-v1.74.0-start-directory.yaml) | `start-directory.yaml` | `7938f93e24e86f4f6ba9c6b06034cfb5b2b520d92556e0d02bae470ebff71f07` |
| [`tmuxp-v1.74.0-suppress-history.yaml`](tmuxp-v1.74.0-suppress-history.yaml) | `suppress-history.yaml` | `715f2a247e5c21e7f0ebf9fb21a18472a48edb6a968fbfb8a8aac0f1739a92c6` |
| [`tmuxp-v1.74.0-window-index.yaml`](tmuxp-v1.74.0-window-index.yaml) | `window-index.yaml` | `66075a8280639e3f3408019007075e2de871da18328790bdd9c5cec0ed81b985` |
| [`tmuxp-v1.74.0-LICENSE`](tmuxp-v1.74.0-LICENSE) | `LICENSE` | `14291e4446ae3d2aaafc0f3d19561714099ae58bdc394febdc61851c49fd19f3` |

The corpus checks command-object order, live window and pane creation,
first-pane directories, environment overrides, a standard window option,
session-relative window indices, and command Enter behavior against an owned
tmux server.
[`corpus.yaml`](corpus.yaml) and
[`corpus.json`](corpus.json) are locally authored declarations.
