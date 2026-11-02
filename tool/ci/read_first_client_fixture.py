"""Qualification-only client ordering; all seven upstream test bodies stay exact."""

import hashlib
import re


SCOPE = 'owned_read_first_test_client'
TEST_PATH = 'p2p/legacy/shutdown_test.go'
PATCH_SHA256 = '88360342c36f591dad99f2442c7c1a0cd6fe5ec6ea5b534db1ab9a7e70dc540c'
ORIGINAL_SHA256 = '532c7bd18d746bc1457d49b9b16420220d7a0f3a97462fc3101d96310516a8b5'
PATCHED_SHA256 = '7e92c04318641610ba5e288299846ee7f3a6988b1dfec3e92034ea2b832eb6ac'
TEST_BODIES_SHA256 = 'c4cb203af516459ab6e3224ef13ca23bbd1480a044e4f0ecf3dadb5279ee77b3'
OLD = b'\tif _, err := cli.doProtoHandshake(&protoHandshake{Version: baseProtocolVersion, Name: "probe", ID: discover.PubkeyID(&cliKey.PublicKey), Caps: caps}); err != nil {\n'
NEW = b'''\t// Read the early rejection before writing a protocol handshake. A concurrent
\t// write can turn the disconnect reason into a socket reset on Windows.
\tour := &protoHandshake{Version: baseProtocolVersion, Name: "probe", ID: discover.PubkeyID(&cliKey.PublicKey), Caps: caps}
\tif _, err := readProtocolHandshake(cli.rw, our); err != nil {
\t\tfd.Close()
\t\treturn nil, err
\t}
\tif err := p2p.Send(cli.rw, handshakeMsg, our); err != nil {
'''


class Refused(Exception):
    pass


def need(value):
    if not value:
        raise Refused('NODE_REGRESSIONS_REFUSED')


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def patched(original, patch):
    need(type(original) is bytes and type(patch) is bytes
         and sha(original) == ORIGINAL_SHA256 and sha(patch) == PATCH_SHA256
         and original.count(OLD) == 1)
    result = original.replace(OLD, NEW)
    before, after = re.search(rb'^func Test', original, re.M), re.search(rb'^func Test', result, re.M)
    need(before is not None and after is not None and sha(result) == PATCHED_SHA256
         and len(re.findall(rb'^func Test', original, re.M)) == 7
         and original[before.start():] == result[after.start():]
         and sha(original[before.start():]) == TEST_BODIES_SHA256)
    return result


def pending():
    return dict(scope=SCOPE, phase='prepared', patch_sha256=PATCH_SHA256,
        original_test_sha256=ORIGINAL_SHA256, patched_test_sha256=PATCHED_SHA256,
        test_bodies_sha256=TEST_BODIES_SHA256, all_seven_test_bodies_unchanged=False,
        original_restored=False, test_exit=None, test_output_complete=None, test_forced=None)


def validate(value, *, required):
    need(type(required) is bool)
    if value is None:
        need(not required)
        return None
    need(type(value) is dict and set(value) == set(pending())
         and value['scope'] == SCOPE and value['phase'] in ('prepared', 'applied', 'held', 'restored')
         and value['patch_sha256'] == PATCH_SHA256
         and value['original_test_sha256'] == ORIGINAL_SHA256
         and value['patched_test_sha256'] == PATCHED_SHA256
         and value['test_bodies_sha256'] == TEST_BODIES_SHA256
         and all(type(value[key]) is bool for key in ('all_seven_test_bodies_unchanged', 'original_restored'))
         and (value['test_exit'] is None or type(value['test_exit']) is int)
         and all(value[key] is None or type(value[key]) is bool
                 for key in ('test_output_complete', 'test_forced')))
    if value['phase'] == 'restored' or value['original_restored']:
        need(value['phase'] == 'restored' and value['original_restored']
             and value['all_seven_test_bodies_unchanged']
             and type(value['test_exit']) is int and value['test_output_complete'] is True
             and value['test_forced'] is False)
    if required:
        need(value['phase'] == 'restored' and value['test_exit'] == 0)
    return {key: value[key] for key in ('scope', 'phase', 'patch_sha256',
        'all_seven_test_bodies_unchanged', 'original_restored', 'test_exit',
        'test_output_complete', 'test_forced')}
