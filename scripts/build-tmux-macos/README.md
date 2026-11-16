# build-tmux-macos

Builds one pinned tmux release from source on a macOS runner, for the
[macOS trial](../../.github/workflows/macos-trial.yml). The shared
`libtmux/.github` `build-tmux` action installs its dependencies with apt, so it
does not run on macOS; this script is the macOS build until that action
supports Homebrew.

`BuildTmuxMacos.ps1`:

1. installs the build dependencies with Homebrew and points `PATH`,
   `PKG_CONFIG_PATH`, `CPPFLAGS` and `LDFLAGS` at them, utf8proc included
   because tmux 3.3a rejects a bare `configure` and Homebrew on Apple silicon
   keeps utf8proc outside the default search paths;
2. clones the tag with `--depth 1` and exits 1 unless `HEAD` is the pinned
   commit and exactly that tag;
3. runs `autogen.sh`, `configure --enable-utf8proc`, `make` and `make install`
   under `<Root>/installs/<version>`;
4. exits 1 unless the install records the pinned commit, `tmux -V` reports the
   version and `lipo -archs` reports the architecture asked for;
5. writes the Homebrew versions to `-DependenciesFile`, appends the `bin`
   directory to the `GITHUB_PATH` file, and appends `TMUX_BINARY` to the
   `GITHUB_ENV` file.

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/build-tmux-macos/BuildTmuxMacos.ps1 \
    -Version 3.3a \
    -SourceCommit 0b355ae8114511e1ff6359272b164f1cdf718e80 \
    -Architecture arm64 \
    -Root core/artifacts/tmux \
    -DependenciesFile build/tmux-build-dependencies.txt \
    -GithubPath "$(mktemp)" \
    -GithubEnv "$(mktemp)"
```

## Tests

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/build-tmux-macos/tests/BuildTmuxMacos.Tests.ps1
```

The test checks the build environment against a table of fake Homebrew prefixes
and plants each fault in the clone and the build, a wrong commit, a missing tag,
a missing executable, a recorded commit, a reported version and an architecture
that differ, and expects it reported. The build itself needs macOS and Homebrew,
so it runs in the trial.
