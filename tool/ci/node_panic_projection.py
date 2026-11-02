"""Bounded panic facts without log text, addresses or source paths."""

import hashlib
import re


MAX_BYTES = 2 * 1024**2
STATUSES = frozenset(("CAPTURED", "AMBIGUOUS", "REFUSED"))
KINDS = frozenset(("NIL_POINTER", "BOUNDS", "CLOSED_CHANNEL", "CONCURRENT_MAP",
                   "WAIT_GROUP", "DEADLOCK", "OTHER"))
PACKAGES = frozenset(("app", "chain", "cmd", "common", "consensus", "embedded",
                      "node", "p2p", "pillar", "protocol", "rpc", "verifier",
                      "wallet", "zenon"))
HEADER = re.compile(rb"^(?:panic:|fatal error:) ([^\r\n]{1,4096})$", re.MULTILINE)
FRAME = re.compile(
    rb"^\tgithub\.com/zenon-network/go-zenon/([A-Za-z0-9_./-]{1,160}\.go):"
    rb"([1-9][0-9]{0,5})(?: \+0x[0-9a-f]+)?$", re.MULTILINE)


def project(raw):
    """Observe the first crashing goroutine; this cannot qualify an exit."""
    refused = dict(status="REFUSED", kind="OTHER", bytes=None, sha256=None, frames=[])
    if type(raw) is not bytes or len(raw) > MAX_BYTES:
        return refused
    headers = list(HEADER.finditer(raw))
    if not headers:
        return None
    result = dict(status="AMBIGUOUS", kind="OTHER", bytes=len(raw),
                  sha256=hashlib.sha256(raw).hexdigest(), frames=[])
    if len(headers) != 1:
        return result
    message = headers[0].group(1)
    for kind, pattern in (
        ("NIL_POINTER", rb"runtime error: invalid memory address or nil pointer dereference"),
        ("BOUNDS", rb"runtime error: (?:index|slice bounds) out of range"),
        ("CLOSED_CHANNEL", rb"(?:send on|close of) closed channel"),
        ("CONCURRENT_MAP", rb"concurrent map (?:writes|iteration and map write|read and map write)"),
        ("WAIT_GROUP", rb"sync: (?:negative WaitGroup counter|WaitGroup misuse|WaitGroup is reused)"),
        ("DEADLOCK", rb"all goroutines are asleep - deadlock!"),
    ):
        if re.match(pattern, message):
            result["kind"] = kind
            break
    stack = re.search(rb"(?:^|\n)goroutine [0-9]{1,20} \[running\]:\n",
                      raw[headers[0].end():])
    if stack is None:
        result["status"] = "REFUSED"
        return result
    start = headers[0].end() + stack.end()
    block = raw[start:].split(b"\n\n", 1)[0]
    for frame in FRAME.finditer(block):
        path = frame.group(1)
        parts = path.decode("ascii").split("/")
        if parts[0] not in PACKAGES or any(part in (".", "..", "") for part in parts):
            continue
        fact = dict(package=parts[0], source_path_sha256=hashlib.sha256(path).hexdigest(),
                    line=int(frame.group(2)))
        if fact not in result["frames"]:
            result["frames"].append(fact)
        if len(result["frames"]) == 3:
            break
    result["status"] = "CAPTURED"
    return result
