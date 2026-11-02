"""Exact isolated-lab correction; no node is patched by importing this file."""

import json
import re


BASE_SHA = "2d1b929cc3fa5269cf133757d4a6963821137984"
BASE_TREE = "4467fff960ea6a5409908d7c85497a68482e0edb"
COMPILED_TREE = "a9262cce18190bfc01e85ac903558500379d014f"
PATCH_SHA256 = "ce0d51dbd7791933a25864a9a03e897ac1120a0a8543150367e66bd31af8d764"
FIXTURE_SHA256 = "22ae33b7fb4f9809352bd634bae7799c245e68f02fadc9d8c0d7d4afbb660643"
ORIGINAL_MANAGER_SHA256 = "8f32ad6efc0f52aaadf3f6aa8d7138862758b83aab1eb16371dbfb8864483361"
PATCHED_MANAGER_SHA256 = "d727dbd3a4b3569417379d1b0668345552c7e88d2ade5645f98ee626c5b38376"
TEST_NAME = "TestClosedWorkerProducerEventStopsWithoutTask"
PACKAGE = "github.com/zenon-network/go-zenon/pillar"
TEST_PATH = "pillar/closed_producer_task_test.go"
PHASES = ("fixture", "unpatched_test", "apply", "patched_test", "verified")
MAX_BYTES = 1024**2


class Refused(Exception):
    def __init__(self):
        super().__init__("NODE_REGRESSIONS_REFUSED")


def need(value):
    if not value:
        raise Refused()


def result(raw, *, failing):
    """Require the actual named test and package, including the old panic."""
    need(type(failing) is bool and type(raw) is bytes and 0 < len(raw) <= MAX_BYTES)
    lines = raw.splitlines()
    need(len(lines) <= 10000)
    counts, output = {}, []
    for line in lines:
        try:
            event = json.loads(line)
        except (ValueError, UnicodeError):
            raise Refused() from None
        need(type(event) is dict and event.get("Package") == PACKAGE
             and event.get("Action") in ("start", "run", "pause", "cont", "output", "pass", "fail")
             and event.get("Test") in (None, TEST_NAME))
        action, test = event.get("Action"), event.get("Test")
        counts[(action, test)] = counts.get((action, test), 0) + 1
        if action == "output":
            need(type(event.get("Output")) is str)
            output.append(event["Output"])
    need(counts.get(("run", TEST_NAME)) == 1)
    text = "".join(output)
    if failing:
        need(counts.get(("fail", None)) == 1
             and counts.get(("fail", TEST_NAME), 0) <= 1
             and not any(action == "pass" for action, _ in counts)
             and "panic: runtime error: invalid memory address or nil pointer dereference" in text
             and PACKAGE + ".(*manager).processSupervised(" in text
             and re.search(r"[/\\]pillar[/\\]manager\.go:120(?:\s|$)", text))
    else:
        need(counts.get(("pass", None)) == counts.get(("pass", TEST_NAME)) == 1
             and not any(action == "fail" for action, _ in counts)
             and "panic:" not in text and "fatal error:" not in text)
    return True


def pending():
    return dict(phase="fixture", patch_sha256=PATCH_SHA256,
        fixture_sha256=FIXTURE_SHA256, compiled_tree=None,
        unpatched_exit=None, patched_exit=None,
        unpatched_expected_panic=False, patched_test_passed=False)


def validate(value, *, required):
    """Validate facts only; a retained report never creates a runtime owner."""
    need(type(required) is bool)
    if value is None:
        need(not required)
        return None
    need(type(value) is dict and set(value) == set(pending())
         and value["phase"] in PHASES
         and value["patch_sha256"] == PATCH_SHA256
         and value["fixture_sha256"] == FIXTURE_SHA256
         and value["compiled_tree"] in (None, COMPILED_TREE)
         and all(type(value[key]) is bool for key in
                 ("unpatched_expected_panic", "patched_test_passed"))
         and all(value[key] is None or type(value[key]) is int
                 for key in ("unpatched_exit", "patched_exit")))
    phase = PHASES.index(value["phase"])
    need(value["unpatched_exit"] in (None, 1) and value["patched_exit"] in (None, 0)
         and value["unpatched_expected_panic"] == (value["unpatched_exit"] == 1)
         and value["patched_test_passed"] == (value["patched_exit"] == 0))
    if phase >= 2:
        need(value["unpatched_expected_panic"])
    if phase >= 3:
        need(value["compiled_tree"] == COMPILED_TREE)
    if required or phase == 4:
        need(phase == 4 and value["unpatched_expected_panic"]
             and value["patched_test_passed"] and value["compiled_tree"] == COMPILED_TREE)
    return dict(phase=value["phase"], patch_sha256=PATCH_SHA256,
        compiled_tree=value["compiled_tree"], unpatched_exit=value["unpatched_exit"],
        patched_exit=value["patched_exit"])
