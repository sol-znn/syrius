"""Optional loopback-only observations; never runtime or shutdown authority."""

import hashlib
import http.client
import re
import time


PORT = 45999
PORTS = {"rpc": PORT, "pillar": 46000, "pillar2": 46001, "pillar3": 46002, "observer": 46003}
MAX_BYTES = 1024**2
STATUSES = frozenset(("CAPTURED", "UNAVAILABLE", "REFUSED", "NO_SHUTDOWN_STACK", "AMBIGUOUS"))
FUNCTIONS = {
    "github.com/zenon-network/go-zenon/node.(*Node).Stop": "NODE_STOP",
    "github.com/zenon-network/go-zenon/node.(*httpServer).stop": "NODE_HTTP_STOP",
    "github.com/zenon-network/go-zenon/node.(*httpServer).doStop": "NODE_HTTP_DO_STOP",
    "net/http.(*Server).Shutdown": "HTTP_SERVER_SHUTDOWN",
    "github.com/zenon-network/go-zenon/p2p/switcher.(*Server).Stop": "P2P_SWITCHER_STOP",
    "github.com/zenon-network/go-zenon/p2p/legacy.(*Server).Stop": "P2P_LEGACY_STOP",
    "github.com/zenon-network/go-zenon/protocol.(*ProtocolManager).Stop": "PROTOCOL_STOP",
    "github.com/zenon-network/go-zenon/zenon.(*zenon).Stop": "ZENON_STOP",
    "github.com/zenon-network/go-zenon/pillar.(*manager).Stop": "PILLAR_MANAGER_STOP",
    "github.com/zenon-network/go-zenon/pillar.(*worker).Stop": "PILLAR_WORKER_STOP",
    "github.com/zenon-network/go-zenon/rpc/api/subscribe.(*Server).Stop": "SUBSCRIBE_STOP",
    "sync.(*WaitGroup).Wait": "WAIT_GROUP",
    "sync.runtime_SemacquireWaitGroup": "WAIT_GROUP_SEMAPHORE",
    "sync.(*Mutex).Lock": "MUTEX_LOCK",
    "sync.(*RWMutex).Lock": "RW_MUTEX_LOCK",
    "sync.runtime_SemacquireMutex": "MUTEX_SEMAPHORE",
}
CODES = frozenset(FUNCTIONS.values())
OWNER = b"github.com/zenon-network/go-zenon/node.(*Node).Stop("
WORKER_KINDS = frozenset(("SYNCER", "MESSAGE_HANDLER"))
WORKER_PACKAGES = frozenset(("protocol", "protocol/downloader", "protocol/fetcher"))
WORKER_STATES = frozenset(("SELECT", "CHAN_RECEIVE", "CHAN_SEND", "SEMAPHORE", "IO_WAIT", "RUNNING", "OTHER"))


def protocol_workers(raw):
    """Locate the two public worker paths counted by the protocol stop wait."""
    refused = dict(status="REFUSED", count=None, items=[])
    if type(raw) is not bytes or not 0 < len(raw) <= MAX_BYTES:
        return refused
    blocks = raw.split(b"\n\n")
    if len(blocks) > 4096:
        return refused
    count, items = 0, []
    markers = ((b"github.com/zenon-network/go-zenon/protocol.(*ProtocolManager).Start.func1(", "SYNCER"),
               (b"github.com/zenon-network/go-zenon/protocol.(*ProtocolManager).handleMsg(", "MESSAGE_HANDLER"))
    states = {b"select": "SELECT", b"chan receive": "CHAN_RECEIVE", b"chan send": "CHAN_SEND",
              b"semacquire": "SEMAPHORE", b"IO wait": "IO_WAIT", b"running": "RUNNING", b"runnable": "RUNNING"}
    for block in blocks:
        lines = block.splitlines()
        kind = next((kind for marker, kind in markers if any(line.startswith(marker) for line in lines)), None)
        if kind is None:
            continue
        header = re.fullmatch(rb"goroutine [0-9]+ \[([^\r\n\]]{1,128})\]:", lines[0])
        if header is None:
            return refused
        site = None
        for index, line in enumerate(lines[:-1]):
            function = re.match(rb"github.com/zenon-network/go-zenon/(protocol(?:/(?:downloader|fetcher))?)\.", line)
            if function is None:
                continue
            package = function[1]
            location = re.search(rb"(?:^|/)(" + re.escape(package)
                + rb"/[A-Za-z0-9_]+\.go):([1-9][0-9]{0,5})(?:\s|$)", lines[index + 1].replace(b"\\", b"/"))
            if location is None:
                return refused
            site = dict(kind=kind, state=states.get(header[1].split(b",", 1)[0], "OTHER"),
                package=package.decode("ascii"), source_path_sha256=hashlib.sha256(location[1]).hexdigest(),
                line=int(location[2]))
            break
        if site is None:
            return refused
        count += 1
        if site not in items:
            items.append(site)
    items.sort(key=lambda item: (item["kind"] != "SYNCER", item["state"] == "IO_WAIT"))
    return dict(status="CAPTURED" if count else "EMPTY", count=count, items=items[:4])


def project(raw):
    """Project one actual shutdown goroutine without echoing frames or paths."""
    if type(raw) is not bytes or not 0 < len(raw) <= MAX_BYTES:
        return dict(status="REFUSED", bytes=None, sha256=None, frames=[])
    result = dict(status="NO_SHUTDOWN_STACK", bytes=len(raw),
                  sha256=hashlib.sha256(raw).hexdigest(), frames=[])
    blocks = raw.split(b"\n\n")
    if len(blocks) > 4096:
        result["status"] = "REFUSED"
        return result
    selected = [block for block in blocks if OWNER in block]
    if not selected:
        return result
    if len(selected) != 1:
        result["status"] = "AMBIGUOUS"
        return result
    lines = selected[0].splitlines()
    if not lines or re.fullmatch(rb"goroutine [0-9]+ \[[^\r\n\]]{1,128}\]:", lines[0]) is None:
        result["status"] = "REFUSED"
        return result
    for line in lines[1:]:
        for name, code in FUNCTIONS.items():
            if line.startswith(name.encode("ascii") + b"(") and code not in result["frames"]:
                result["frames"].append(code)
    result["status"] = "CAPTURED" if "NODE_STOP" in result["frames"] else "REFUSED"
    if result["status"] == "CAPTURED":
        result["protocol_workers"] = protocol_workers(raw)
    return result


def capture(original):
    """One bounded read before forced cleanup, after an actual stop timeout."""
    result = dict(status="UNAVAILABLE", bytes=None, sha256=None, frames=[])
    if not getattr(original, "stack_debug", False) or original.process.poll() is not None:
        return result
    role, port = getattr(original, "stack_role", None), getattr(original, "stack_port", None)
    if type(role) is not str or role not in PORTS or type(port) is not int or port != PORTS[role]:
        result["status"] = "REFUSED"
        return result
    end = time.monotonic() + 3
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=1)
    try:
        # http.client uses no proxy, credentials, DNS alias or redirect handler.
        connection.request("GET", "/debug/pprof/goroutine?debug=2",
                           headers={"Connection": "close", "Accept-Encoding": "identity"})
        response = connection.getresponse()
        if response.status != 200 or response.getheader("Content-Encoding", "identity") != "identity":
            result["status"] = "REFUSED"
            return result
        raw = bytearray()
        while time.monotonic() < end:
            chunk = response.read1(min(65536, MAX_BYTES + 1 - len(raw)))
            if time.monotonic() >= end:
                return result
            if not chunk:
                if original.process.poll() is None:
                    result.update(project(bytes(raw)))
                return result
            raw.extend(chunk)
            if len(raw) > MAX_BYTES:
                result["status"] = "REFUSED"
                return result
    except Exception:
        return result
    finally:
        try:
            connection.close()
        except Exception:
            result.update(status="REFUSED", frames=[])
    return result
