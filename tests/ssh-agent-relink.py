#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


class AgentRelinkTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="ssh-dev-container-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.link = self.root / "stable.sock"
        self.key = self.make_key("signing-key")
        self.other_key = self.make_key("other-key")

    def make_key(self, name):
        key = self.root / name
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)], check=True)
        return key

    def agent(self, name, key=None):
        socket = self.root / f"agent.{name}"
        process = subprocess.Popen(["ssh-agent", "-D", "-a", str(socket)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        def stop():
            process.terminate()
            process.wait(timeout=5)

        self.addCleanup(stop)
        deadline = time.monotonic() + 5
        while not socket.exists():
            if process.poll() is not None or time.monotonic() > deadline:
                self.fail("Test agent did not start")
            time.sleep(0.01)
        if key:
            env = os.environ.copy()
            env["SSH_AUTH_SOCK"] = str(socket)
            subprocess.run(["ssh-add", str(key)], env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return socket

    def run_relink(self, expected_status=0):
        result = subprocess.run([str(ROOT / "scripts/ssh-agent-relink"), str(self.link), str(self.key) + ".pub"], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, expected_status, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(result.stderr, "")

    def test_empty_agent_yields_to_agent_with_signing_key(self):
        self.link.symlink_to(self.agent("empty"))
        usable = self.agent("usable", self.key)
        self.run_relink()
        self.assertEqual(self.link.readlink(), usable)

    def test_wrong_key_yields_to_agent_with_signing_key(self):
        self.link.symlink_to(self.agent("wrong", self.other_key))
        usable = self.agent("usable", self.key)
        self.run_relink()
        self.assertEqual(self.link.readlink(), usable)

    def test_dead_socket_is_replaced(self):
        self.link.symlink_to(self.root / "agent.dead")
        usable = self.agent("usable", self.key)
        self.run_relink()
        self.assertEqual(self.link.readlink(), usable)

    def test_healthy_current_agent_is_preserved(self):
        current = self.agent("current", self.key)
        self.link.symlink_to(current)
        self.agent("alternative", self.key)
        self.run_relink()
        self.assertEqual(self.link.readlink(), current)

    def test_missing_link_is_created(self):
        usable = self.agent("usable", self.key)
        self.run_relink()
        self.assertEqual(self.link.readlink(), usable)

    def test_no_matching_key_preserves_link_and_reports_failure(self):
        current = self.agent("empty")
        self.link.symlink_to(current)
        self.agent("wrong", self.other_key)
        self.run_relink(expected_status=1)
        self.assertEqual(self.link.readlink(), current)

    def test_missing_public_key_preserves_link_and_reports_failure(self):
        current = self.agent("current", self.key)
        self.link.symlink_to(current)
        self.key.with_suffix(".pub").unlink()
        self.run_relink(expected_status=1)
        self.assertEqual(self.link.readlink(), current)

    def test_failed_link_write_is_silent_and_reports_failure(self):
        self.link = self.root / "missing-directory" / "stable.sock"
        self.agent("usable", self.key)
        self.run_relink(expected_status=1)
        self.assertFalse(self.link.exists())

    def test_relinked_agent_can_sign_with_the_expected_key(self):
        self.link.symlink_to(self.agent("empty"))
        self.agent("usable", self.key)
        self.run_relink()
        payload = self.root / "payload"
        payload.write_text("Commit signing regression probe\n")
        env = os.environ.copy()
        env["SSH_AUTH_SOCK"] = str(self.link)
        subprocess.run(["ssh-keygen", "-Y", "sign", "-n", "git", "-f", str(self.key) + ".pub", str(payload)], env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    unittest.main()
