"""Injected crash facts; no native process, network or scratch is used."""

import hashlib
import json
import unittest

from tool.ci import node_panic_projection as panic


def crashed(message=b"runtime error: invalid memory address or nil pointer dereference"):
    return (b"private log and address\npanic: " + message + b"\n\n"
            b"goroutine 18 [running]:\nprivate.function(0xprivate)\n"
            b"\tgithub.com/zenon-network/go-zenon/wallet/manager.go:257 +0x123\n"
            b"\t/fixture/private/file.go:23 +0x123\n\n"
            b"goroutine 19 [select]:\n"
            b"\tgithub.com/zenon-network/go-zenon/node/node.go:99 +0x123\n")


class PanicProjectionTests(unittest.TestCase):
    def test_actual_crashing_block_is_hashed_without_echoing_text_or_paths(self):
        raw = crashed()
        value = panic.project(raw)
        self.assertEqual(value["status"], "CAPTURED")
        self.assertEqual(value["kind"], "NIL_POINTER")
        self.assertEqual(value["bytes"], len(raw))
        self.assertEqual(value["sha256"], hashlib.sha256(raw).hexdigest())
        self.assertEqual(value["frames"], [dict(package="wallet", line=257,
            source_path_sha256=hashlib.sha256(b"wallet/manager.go").hexdigest())])
        for private in ("private", "manager.go", "node.go", "0x123", "panic:"):
            self.assertNotIn(private, json.dumps(value))

    def test_unrecognized_message_never_becomes_public_text(self):
        value = panic.project(crashed(b"private failure, address and payload"))
        self.assertEqual(value["kind"], "OTHER")
        self.assertNotIn("private", json.dumps(value))

    def test_ambiguous_missing_and_oversized_stacks_keep_honest_status(self):
        self.assertEqual(panic.project(crashed() + crashed())["status"], "AMBIGUOUS")
        self.assertEqual(panic.project(b"panic: private\n")["status"], "REFUSED")
        self.assertEqual(panic.project(b"x" * (panic.MAX_BYTES + 1))["status"], "REFUSED")
        self.assertIsNone(panic.project(b"healthy private log\n"))

    def test_traversal_unknown_packages_and_other_goroutines_are_not_frames(self):
        raw = crashed().replace(b"wallet/manager.go", b"wallet/../private.go")
        self.assertEqual(panic.project(raw)["frames"], [])
        raw = crashed().replace(b"wallet/manager.go", b"private/package.go")
        self.assertEqual(panic.project(raw)["frames"], [])

    def test_source_location_facts_are_capped_even_in_one_panic_block(self):
        raw = crashed().split(b"\n\ngoroutine 19", 1)[0]
        raw += b"".join(b"\n\tgithub.com/zenon-network/go-zenon/pillar/worker.go:"
                        + str(line).encode() + b" +0x123" for line in range(1, 20)) + b"\n"
        self.assertEqual(len(panic.project(raw)["frames"]), 3)


if __name__ == "__main__":
    unittest.main()
