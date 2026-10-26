#!/usr/bin/env python3
"""Exercise the launcher's exact embedded selector against filesystem fixtures."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

WRAPPER = Path(os.environ.get("WRAPPER", Path(__file__).resolve().parents[1] / "bin/agent"))
SOURCE = WRAPPER.read_text().split('"$RETIRED_FILE" <<\'PY\'\n', 1)[1].split("\nPY\n", 1)[0]
A = "11111111-1111-1111-1111-111111111111"
B = "22222222-2222-2222-2222-222222222222"


class SessionCacheTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "sessions"
        self.root.mkdir()
        self.workspace = str(self.base / "workspace")
        self.retired = self.base / "retired"
        self.cache_home = self.base / "cache"
        self.cache = self.cache_home / "remote-agent-stack/copilot-sessions-v1.json"
        self.env = dict(os.environ, HOME=str(self.base), XDG_CACHE_HOME=str(self.cache_home))

    def write(self, name, session_id=A, updated="2026-08-01", cwd=None, summary="1"):
        path = self.root / name / "workspace.yaml"
        path.parent.mkdir(exist_ok=True)
        path.write_text(
            f"id: {session_id}\ncwd: {cwd or self.workspace}\n"
            f"updated_at: {updated}\nsummary_count: {summary}\n"
        )
        return path

    def command(self, workspace=None):
        return [sys.executable, "-", str(self.root), workspace or self.workspace, str(self.retired)]

    def run_selector(self, expected=A, preamble="", workspace=None):
        result = subprocess.run(self.command(workspace), input=preamble + SOURCE, text=True,
                                capture_output=True, env=self.env, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, expected + "\n", result.stderr)
        return result

    def test_incremental_updates_retirement_and_deletion(self):
        self.write("a")
        self.run_selector()
        before = self.cache.stat().st_mtime_ns
        self.assertIn("1 reused, 0 read", self.run_selector().stderr)
        self.assertEqual(self.cache.stat().st_mtime_ns, before)
        self.write("b", B, "2026-08-02", summary="0")
        self.run_selector(A)
        self.write("b", B, "2026-08-02")
        self.run_selector(B)
        self.retired.write_text(B + "\n")
        self.assertIn("2 reused, 0 read", self.run_selector(A).stderr)
        self.retired.unlink()
        self.write("b", B, "2026-08-02", cwd=self.workspace + "-other")
        self.run_selector(A)
        self.run_selector(B, workspace=self.workspace + "-other")
        (self.root / "a/workspace.yaml").unlink()
        self.run_selector("")
        self.assertNotIn("a", json.loads(self.cache.read_text())["entries"])
        self.write("a")
        self.run_selector(A)

    def test_same_size_restored_mtime_and_replacement(self):
        path = self.write("a")
        self.run_selector()
        before = path.stat()
        self.write("a", B)
        os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))
        self.assertEqual(path.stat().st_size, before.st_size)
        self.run_selector(B)
        replacement = path.with_suffix(".new")
        replacement.write_text(path.read_text().replace(B, A))
        os.utime(replacement, ns=(before.st_atime_ns, before.st_mtime_ns))
        os.replace(replacement, path)
        self.run_selector(A)

    def test_corrupt_incompatible_and_unwritable_cache(self):
        self.write("a")
        self.run_selector()
        valid = json.loads(self.cache.read_text())
        invalid = [
            "{", "null", "[]",
            json.dumps(dict(valid, version=2)),
            json.dumps(dict(valid, root="/another/root")),
            json.dumps(dict(valid, entries={"a": {"signature": [True] * 5, "fields": {}}})),
        ]
        for content in invalid:
            with self.subTest(content=content):
                self.cache.write_text(content)
                self.assertIn("1 read", self.run_selector().stderr)
        self.cache.unlink()
        self.run_selector()
        blocker = self.base / "not-a-directory"
        blocker.write_text("block")
        self.env["XDG_CACHE_HOME"] = str(blocker)
        self.assertIn("could not be saved", self.run_selector().stderr)

    def test_missing_metadata_hidden_directories_and_ties(self):
        self.write("a", A)
        self.write("z", B)
        self.write(".hidden", B, "2026-09-01")
        (self.root / "missing").mkdir()
        (self.root / "directory").mkdir()
        (self.root / "directory/workspace.yaml").mkdir()
        self.run_selector(A)
        self.assertIn("2 reused, 0 read, 2 skipped", self.run_selector(A).stderr)

    def test_unstable_read_retries_then_uses_uncached_fallback(self):
        path = self.write("a")
        replacement = path.read_text().replace(A, B)
        preamble = f"""
import os
_stat = os.stat
_calls = 0
def changing_stat(path, *args, **kwargs):
    global _calls
    if str(path) == {str(path)!r}:
        _calls += 1
        if _calls == 2:
            with open(path, "w") as stream:
                stream.write({replacement!r})
    return _stat(path, *args, **kwargs)
os.stat = changing_stat
"""
        self.run_selector(B, preamble=preamble)
        self.assertEqual(json.loads(self.cache.read_text())["entries"]["a"]["fields"]["id"], B)
        other = self.write("other", A, cwd=self.workspace + "-other")
        self.run_selector(B)
        before = self.cache.read_bytes()
        preamble = f"""
import os
_stat = os.stat
def changing_stat(path, *args, **kwargs):
    if str(path) == {str(other)!r}:
        with open(path, "a") as stream:
            stream.write("\\n")
    return _stat(path, *args, **kwargs)
os.stat = changing_stat
"""
        result = self.run_selector(B, preamble=preamble)
        self.assertIn("using an uncached scan", result.stderr)
        self.assertIn("0 reused, 2 read", result.stderr)
        self.assertEqual(self.cache.read_bytes(), before)

    def test_concurrent_older_publisher_finishes_last(self):
        self.write("a")
        ready = self.base / "ready"
        release = self.base / "release"
        preamble = f"""
import os
import time
_replace = os.replace
def paused_replace(source, destination):
    with open({str(ready)!r}, "w") as stream:
        stream.write("ready")
    deadline = time.monotonic() + 20
    while not os.path.exists({str(release)!r}):
        if time.monotonic() > deadline:
            raise RuntimeError("publication fixture timeout")
        time.sleep(0.01)
    return _replace(source, destination)
os.replace = paused_replace
"""
        old = subprocess.Popen(self.command(), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, env=self.env)
        try:
            old.stdin.write(preamble + SOURCE)
            old.stdin.close()
            old.stdin = None
            deadline = time.monotonic() + 20
            while not ready.exists() and old.poll() is None and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists(), "old publisher did not reach atomic replacement")
            self.write("a", B)
            self.run_selector(B)
            release.touch()
            stdout, stderr = old.communicate(timeout=30)
            self.assertEqual(old.returncode, 0, stderr)
            self.assertEqual(stdout, A + "\n")
            self.assertEqual(json.loads(self.cache.read_text())["entries"]["a"]["fields"]["id"], A)
            self.run_selector(B)
            self.assertEqual(self.cache.stat().st_mode & 0o777, 0o600)
            self.assertEqual(list(self.cache.parent.glob("*.tmp")), [])
        finally:
            if old.poll() is None:
                old.kill()
                old.communicate()


if __name__ == "__main__":
    unittest.main()
