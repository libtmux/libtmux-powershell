"""Prove build-tmux.sh resolves and builds a ref at the commit it names.

The tmux repository is a local stand-in whose build produces a script that
reports a version, so these tests need git, make and awk but no network and no
compiler.
"""

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "build-tmux.sh"

AUTOGEN = """\
echo AUTOGEN-RAN
cat > configure <<'CONFIGURE'
case "$1" in --prefix=*) prefix="${1#--prefix=}" ;; esac
printf 'PREFIX = %s\\n' "$prefix" > Makefile
cat >> Makefile <<'MAKEFILE'
all:
	:
install:
	mkdir -p $(PREFIX)/bin
	printf '#!/bin/sh\\necho "tmux %s"\\n' "$$(cat VERSION)" > $(PREFIX)/bin/tmux
	chmod +x $(PREFIX)/bin/tmux
MAKEFILE
CONFIGURE
chmod +x configure
"""

IDENTITY = {
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@example.invalid",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@example.invalid",
}


def git(repository, *arguments):
    done = subprocess.run(
        ["git", "-C", str(repository), *arguments],
        check=True,
        capture_output=True,
        text=True,
        env={**os.environ, **IDENTITY},
    )
    return done.stdout.strip()


@unittest.skipUnless(
    all(shutil.which(tool) for tool in ("bash", "git", "make", "awk", "sed")),
    "needs bash, git, make, awk and sed",
)
class BuildTmux(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = pathlib.Path(self.directory.name)
        self.repository = root / "tmux"
        self.build_root = root / "build"
        self.repository.mkdir()
        git(self.repository, "init", "--quiet", "-b", "master")
        self.release = self.commit("3.8")
        git(self.repository, "tag", "3.8")
        git(self.repository, "checkout", "--quiet", "-b", "topic")
        self.annotated = self.commit("9.1")
        git(self.repository, "tag", "-a", "-m", "annotated", "9.1")
        self.topic = self.commit("9.2")
        git(self.repository, "checkout", "--quiet", "master")

    def commit(self, version):
        (self.repository / "VERSION").write_text(version + "\n", encoding="utf-8")
        (self.repository / "autogen.sh").write_text(AUTOGEN, encoding="utf-8")
        git(self.repository, "add", "-A")
        git(self.repository, "commit", "--quiet", "-m", f"tmux {version}")
        return git(self.repository, "rev-parse", "HEAD")

    def build(self, *arguments):
        environment = {
            **os.environ,
            "LIBTMUX_TMUX_REPOSITORY": str(self.repository),
            "LIBTMUX_TMUX_BUILD_ROOT": str(self.build_root),
            "LIBTMUX_BUILD_JOBS": "1",
        }
        return subprocess.run(
            ["bash", str(SCRIPT), *arguments],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )

    @staticmethod
    def fields(result):
        return dict(line.split("=", 1) for line in result.stdout.splitlines())

    def test_a_tag_resolves_to_its_commit(self):
        result = self.build("--resolve", "3.8")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, f"commit={self.release}\n")

    def test_an_annotated_tag_resolves_to_the_commit_not_the_tag_object(self):
        result = self.build("--resolve", "9.1")
        self.assertEqual(result.stdout, f"commit={self.annotated}\n")
        self.assertNotEqual(git(self.repository, "rev-parse", "9.1"), self.annotated)

    def test_a_branch_resolves_to_its_tip(self):
        self.assertEqual(self.build("--resolve", "topic").stdout, f"commit={self.topic}\n")

    def test_a_full_commit_resolves_to_itself(self):
        self.assertEqual(
            self.build("--resolve", self.topic).stdout, f"commit={self.topic}\n"
        )

    def test_a_tag_wins_over_a_branch_of_the_same_name(self):
        git(self.repository, "branch", "3.8", self.topic)
        self.assertEqual(self.build("--resolve", "3.8").stdout, f"commit={self.release}\n")

    def test_an_unknown_ref_does_not_resolve(self):
        result = self.build("--resolve", "no-such-ref")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("is not a tag, a branch or a full commit", result.stderr)

    def test_a_malformed_ref_is_refused_before_git_sees_it(self):
        for ref in (
            "--upload-pack=touch-pwned", "-x", "a..b", "topic.lock", "topic/", "$(id)",
            "a b", "a;b", "a" * 65, "deadbeef", "",
        ):
            for flag in ("--resolve", "--ref"):
                with self.subTest(flag=flag, ref=ref):
                    result = self.build(flag, ref)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, "")
                    self.assertRegex(result.stderr, "usable tmux ref|abbreviated commit")
                    self.assertFalse((self.build_root / "sources").exists())

    def test_a_ref_builds_from_source_at_the_resolved_commit(self):
        result = self.build("--ref", "topic")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("AUTOGEN-RAN", result.stderr)
        printed = self.fields(result)
        self.assertEqual(printed["commit"], self.topic)
        self.assertEqual(printed["version"], "9.2")
        install = self.build_root / "installs" / f"ref-{self.topic}"
        self.assertEqual(printed["binary"], str(install / "bin" / "tmux"))

    def test_a_ref_given_as_a_commit_is_fetched_by_hash(self):
        result = self.build("--ref", self.annotated)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.fields(result)["commit"], self.annotated)
        self.assertEqual(self.fields(result)["version"], "9.1")

    def test_a_cached_ref_build_is_reused(self):
        first = self.build("--ref", "topic")
        second = self.build("--ref", "topic")
        self.assertIn("AUTOGEN-RAN", first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertNotIn("AUTOGEN-RAN", second.stderr)
        self.assertEqual(second.stdout, first.stdout)

    def test_a_moved_branch_is_built_afresh(self):
        first = self.build("--ref", "topic")
        git(self.repository, "checkout", "--quiet", "topic")
        moved = self.commit("9.3")
        git(self.repository, "checkout", "--quiet", "master")
        second = self.build("--ref", "topic")
        self.assertEqual(self.fields(first)["commit"], self.topic)
        self.assertEqual(self.fields(second)["commit"], moved)
        self.assertEqual(self.fields(second)["version"], "9.3")
        self.assertIn("AUTOGEN-RAN", second.stderr)

    def test_a_tampered_cache_is_rebuilt(self):
        first = self.build("--ref", "topic")
        pathlib.Path(self.fields(first)["binary"]).write_text(
            '#!/bin/sh\necho "tmux 0.0"\n', encoding="utf-8"
        )
        second = self.build("--ref", "topic")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn("cache validation failed", second.stderr)
        self.assertEqual(self.fields(second)["version"], "9.2")

    def test_a_cache_that_holds_another_commit_than_its_name_is_rebuilt(self):
        self.build("--ref", "topic")
        install = self.build_root / "installs" / f"ref-{self.topic}"
        (install / "source-commit").write_text(self.release + "\n", encoding="utf-8")
        second = self.build("--ref", "topic")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn("cache validation failed", second.stderr)
        self.assertEqual(self.fields(second)["commit"], self.topic)

    def test_the_flags_take_exactly_one_ref(self):
        for arguments in (("--ref",), ("--resolve",), ("--ref", "topic", "extra"), ("3.8",), ()):
            with self.subTest(arguments=arguments):
                result = self.build(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertIn("usage: build-tmux.sh", result.stderr)


if __name__ == "__main__":
    unittest.main()
