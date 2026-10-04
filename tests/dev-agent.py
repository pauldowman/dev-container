#!/usr/bin/env python3
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class DevAgentTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="dev-agent-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "scripts").mkdir()
        (self.root / "bin").mkdir()
        shutil.copy2(ROOT / "dev", self.root / "dev")
        shutil.copy2(ROOT / "scripts/env.sh", self.root / "scripts/env.sh")
        (self.root / ".env").write_text(f"CODE_DIR={self.root}\nUSERNAME=tester\n")
        self.env = os.environ.copy()
        self.env.update({"PATH": str(self.root / "bin") + ":" + self.env["PATH"], "TEST_AGENT_ROOT": str(self.root), "SSH_AUTH_SOCK": str(self.root / "existing.sock")})
        self.stub("docker", "printf '127.0.0.1:2222\\n'\n")
        self.stub("ssh", 'printf "connect %s\\n" "$SSH_AUTH_SOCK" >> "$TEST_AGENT_ROOT/events"\n')
        self.stub("ssh-agent", 'printf "create\\n" >> "$TEST_AGENT_ROOT/events"\nprintf "SSH_AUTH_SOCK=%s/new.sock; export SSH_AUTH_SOCK;\\n" "$TEST_AGENT_ROOT"\n')
        self.stub("ssh-add", '''if [ "${1:-}" = "-l" ]; then
  [ -f "$TEST_AGENT_ROOT/loaded" ] && exit 0
  exit "$TEST_AGENT_STATUS"
fi
printf "load %s\\n" "$SSH_AUTH_SOCK" >> "$TEST_AGENT_ROOT/events"
[ "${TEST_AGENT_LOAD_FAIL:-0}" = "0" ] || exit 1
[ "${TEST_AGENT_STAYS_EMPTY:-0}" = "0" ] || exit 0
touch "$TEST_AGENT_ROOT/loaded"
''')

    def stub(self, name, body):
        path = self.root / "bin" / name
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    def run_dev(self, status, expected_status=0):
        self.env["TEST_AGENT_STATUS"] = str(status)
        result = subprocess.run([str(self.root / "dev"), "list"], env=self.env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, expected_status, result.stderr)
        events = self.root / "events"
        return events.read_text().splitlines() if events.exists() else []

    def test_loaded_agent_is_preserved(self):
        self.assertEqual(self.run_dev(0), [f"connect {self.root}/existing.sock"])

    def test_empty_agent_loads_keys_without_creating_another_agent(self):
        self.assertEqual(self.run_dev(1), [f"load {self.root}/existing.sock", f"connect {self.root}/existing.sock"])

    def test_unreachable_agent_is_replaced_before_loading_keys(self):
        self.assertEqual(self.run_dev(2), ["create", f"load {self.root}/new.sock", f"connect {self.root}/new.sock"])

    def test_unset_socket_starts_an_agent_and_loads_keys(self):
        del self.env["SSH_AUTH_SOCK"]
        self.assertEqual(self.run_dev(2), ["create", f"load {self.root}/new.sock", f"connect {self.root}/new.sock"])

    def test_key_loading_failure_prevents_connection(self):
        self.env["TEST_AGENT_LOAD_FAIL"] = "1"
        self.assertEqual(self.run_dev(1, expected_status=1), [f"load {self.root}/existing.sock"])

    def test_agent_still_empty_after_loading_prevents_connection(self):
        self.env["TEST_AGENT_STAYS_EMPTY"] = "1"
        self.assertEqual(self.run_dev(1, expected_status=1), [f"load {self.root}/existing.sock"])


if __name__ == "__main__":
    unittest.main()
