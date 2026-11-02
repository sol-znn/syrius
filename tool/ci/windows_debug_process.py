"""An owned Windows process tree for the manual debug-loop qualification.

A new Python child waits for START before it launches the Flutter tool. Assigning
that gated child to a private job prevents an application launch before ownership
is established. Closing the job is forced cleanup, never a successful app exit.
"""

import ctypes
from ctypes import wintypes
import hashlib
import os
from pathlib import Path, PureWindowsPath
import re
import stat
import time


class ProcessRefused(Exception):
    pass


HELPER_EXIT_MARKER = 0xE000D007
HELPER_SCOPE = 'owned_helpers_after_completed_debug_actors'


def compiler_helper_path(text):
    """Bind telemetry to the compiler recorded by this fresh CMake build."""
    values = re.findall(r'^set\(CMAKE_CXX_COMPILER "([^"\r\n]+)"\)', text, re.M)
    if len(values) != 1:
        raise ProcessRefused('HELPER_IMAGE_REFUSED')
    if len(values[0]) > 4096 or any(ord(char) < 32 for char in values[0]):
        raise ProcessRefused('HELPER_IMAGE_REFUSED')
    path = PureWindowsPath(values[0])
    if (not re.fullmatch(r'[A-Za-z]:', path.drive) or not path.is_absolute()
            or path.name.lower() != 'cl.exe' or '..' in path.parts):
        raise ProcessRefused('HELPER_IMAGE_REFUSED')
    return path.parent / 'vctip.exe'


def image_pin(path):
    before = path.lstat()
    if (not stat.S_ISREG(before.st_mode) or getattr(before, 'st_file_attributes', 0) & 0x400
            or not 0 < before.st_size <= 64 * 1024**2):
        raise ProcessRefused('HELPER_IMAGE_REFUSED')
    identity = lambda info: (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        if identity(os.fstat(stream.fileno())) != identity(before):
            raise ProcessRefused('HELPER_IMAGE_REFUSED')
        total = 0
        for chunk in iter(lambda: stream.read(1024**2), b''):
            total += len(chunk)
            if total > before.st_size:
                raise ProcessRefused('HELPER_IMAGE_REFUSED')
            digest.update(chunk)
        if total != before.st_size or identity(os.fstat(stream.fileno())) != identity(before):
            raise ProcessRefused('HELPER_IMAGE_REFUSED')
    if identity(path.lstat()) != identity(before):
        raise ProcessRefused('HELPER_IMAGE_REFUSED')
    return digest.hexdigest(), identity(before)


class _Basic(ctypes.Structure):
    _fields_ = [("process_time", ctypes.c_longlong), ("job_time", ctypes.c_longlong),
                ("flags", wintypes.DWORD), ("min_working", ctypes.c_size_t),
                ("max_working", ctypes.c_size_t), ("active_limit", wintypes.DWORD),
                ("affinity", ctypes.c_size_t), ("priority", wintypes.DWORD),
                ("scheduling", wintypes.DWORD)]


class _Io(ctypes.Structure):
    _fields_ = [(name, ctypes.c_ulonglong) for name in
                ("read_ops", "write_ops", "other_ops", "read_bytes", "write_bytes", "other_bytes")]


class _Extended(ctypes.Structure):
    _fields_ = [("basic", _Basic), ("io", _Io), ("process_memory", ctypes.c_size_t),
                ("job_memory", ctypes.c_size_t), ("peak_process", ctypes.c_size_t),
                ("peak_job", ctypes.c_size_t)]


class _Accounting(ctypes.Structure):
    _fields_ = [(name, ctypes.c_longlong) for name in
                ("user", "kernel", "period_user", "period_kernel")] + [
                (name, wintypes.DWORD) for name in
                ("faults", "total", "active", "terminated")]


class _Members(ctypes.Structure):
    _fields_ = [("assigned", wintypes.DWORD), ("listed", wintypes.DWORD),
                ("identifiers", ctypes.c_size_t * 64)]


IMAGE_NAMES = {
    'dart.exe': 'DART', 'chrome.exe': 'CHROME', 'msedge.exe': 'EDGE',
    'msbuild.exe': 'MSBUILD', 'vctip.exe': 'VCTIP', 'csc.exe': 'COMPILER',
    'vbc.exe': 'COMPILER', 'cmake.exe': 'CMAKE', 'ninja.exe': 'NINJA',
    'conhost.exe': 'CONHOST', 'node.exe': 'NODE', 'python.exe': 'PYTHON',
    'syrius.exe': 'APPLICATION', 'crashpad_handler.exe': 'CRASHPAD',
}


class WindowsJob:
    def __init__(self):
        if os.name != "nt":
            raise ProcessRefused("PLATFORM_REFUSED")
        if (ctypes.sizeof(ctypes.c_void_p) != 8 or ctypes.sizeof(_Extended) != 144
                or ctypes.sizeof(_Accounting) != 48):
            raise ProcessRefused("PLATFORM_REFUSED")
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        declarations = {
            "CreateJobObjectW": ([ctypes.c_void_p, wintypes.LPCWSTR], wintypes.HANDLE),
            "SetInformationJobObject": ([wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p,
                                           wintypes.DWORD], wintypes.BOOL),
            "AssignProcessToJobObject": ([wintypes.HANDLE, wintypes.HANDLE], wintypes.BOOL),
            "QueryInformationJobObject": ([wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p,
                                             wintypes.DWORD, ctypes.c_void_p], wintypes.BOOL),
            "IsProcessInJob": ([wintypes.HANDLE, wintypes.HANDLE,
                                 ctypes.POINTER(wintypes.BOOL)], wintypes.BOOL),
            "OpenProcess": ([wintypes.DWORD, wintypes.BOOL, wintypes.DWORD], wintypes.HANDLE),
            "QueryFullProcessImageNameW": ([wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR,
                                              ctypes.POINTER(wintypes.DWORD)], wintypes.BOOL),
            "GetExitCodeProcess": ([wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)], wintypes.BOOL),
            "WaitForSingleObject": ([wintypes.HANDLE, wintypes.DWORD], wintypes.DWORD),
            "TerminateProcess": ([wintypes.HANDLE, wintypes.DWORD], wintypes.BOOL),
            "CloseHandle": ([wintypes.HANDLE], wintypes.BOOL),
        }
        for name, (arguments, result) in declarations.items():
            function = getattr(kernel, name)
            function.argtypes, function.restype = arguments, result
        self.kernel, self.handle, self.application = kernel, None, None
        self.forced = False
        self.active_at_close = None
        self.handle = kernel.CreateJobObjectW(None, None)
        if not self.handle:
            raise ProcessRefused("JOB_REFUSED")
        limits = _Extended()
        limits.basic.flags = 0x00002000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if not kernel.SetInformationJobObject(self.handle, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
            kernel.CloseHandle(self.handle)
            self.handle = None
            raise ProcessRefused("JOB_REFUSED")

    def assign(self, original):
        if self.handle is None or original.poll() is not None:
            raise ProcessRefused("JOB_REFUSED")
        if not self.kernel.AssignProcessToJobObject(self.handle, wintypes.HANDLE(int(original._handle))):
            raise ProcessRefused("JOB_REFUSED")

    def bind_application(self, pid, expected):
        if self.application is not None or type(pid) is not int or not 0 < pid < 0x100000000:
            raise ProcessRefused("PROCESS_REFUSED")
        handle = self.kernel.OpenProcess(0x1000 | 0x100000, False, pid)
        if not handle:
            raise ProcessRefused("PROCESS_REFUSED")
        try:
            member = wintypes.BOOL()
            if not self.kernel.IsProcessInJob(handle, self.handle, ctypes.byref(member)) or not member.value:
                raise ProcessRefused("PROCESS_REFUSED")
            size = wintypes.DWORD(32768)
            image = ctypes.create_unicode_buffer(size.value)
            if not self.kernel.QueryFullProcessImageNameW(handle, 0, image, ctypes.byref(size)):
                raise ProcessRefused("PROCESS_REFUSED")
            if os.path.normcase(str(Path(image.value).resolve())) != os.path.normcase(str(expected.resolve())):
                raise ProcessRefused("PROCESS_REFUSED")
            if self.kernel.WaitForSingleObject(handle, 0) != 0x102:
                raise ProcessRefused("PROCESS_REFUSED")
            self.application = handle
        finally:
            if self.application != handle:
                self.kernel.CloseHandle(handle)

    def application_exit(self, milliseconds=10000):
        if self.application is None or self.kernel.WaitForSingleObject(self.application, milliseconds) != 0:
            raise ProcessRefused("APPLICATION_EXIT_UNCONFIRMED")
        code = wintypes.DWORD()
        if not self.kernel.GetExitCodeProcess(self.application, ctypes.byref(code)):
            raise ProcessRefused("APPLICATION_EXIT_UNCONFIRMED")
        return code.value

    def active(self):
        if self.handle is None:
            raise ProcessRefused("JOB_REFUSED")
        value = _Accounting()
        if not self.kernel.QueryInformationJobObject(self.handle, 1, ctypes.byref(value), ctypes.sizeof(value), None):
            raise ProcessRefused("JOB_REFUSED")
        return value.active

    def remaining_images(self):
        """Read only this job's current members; expose fixed image classes."""
        result = dict(status='UNKNOWN', listed=0, observed=0, counts={})
        values = _Members()
        if (self.handle is None or not self.kernel.QueryInformationJobObject(
                self.handle, 3, ctypes.byref(values), ctypes.sizeof(values), None)
                or values.assigned != values.listed or values.listed > 64):
            return result
        result['listed'] = int(values.listed)
        for identifier in values.identifiers[:values.listed]:
            handle = self.kernel.OpenProcess(0x1000 | 0x100000, False, identifier)
            if not handle:
                return result
            try:
                member = wintypes.BOOL()
                if (not self.kernel.IsProcessInJob(handle, self.handle, ctypes.byref(member))
                        or not member.value):
                    return result
                size = wintypes.DWORD(32768)
                image = ctypes.create_unicode_buffer(size.value)
                if not self.kernel.QueryFullProcessImageNameW(handle, 0, image, ctypes.byref(size)):
                    return result
                label = IMAGE_NAMES.get(Path(image.value).name.lower(), 'OTHER')
                result['counts'][label] = result['counts'].get(label, 0) + 1
                result['observed'] += 1
            finally:
                self.kernel.CloseHandle(handle)
        result['status'] = 'OBSERVED'
        return result

    def finish_known_helpers(self, dart, compiler_resolver):
        """Stop at most one exact SDK and compiler helper after actor success.

        All members are bound before any signal. Handles, membership, image path
        and immutable image bytes are retained and rechecked. Interrupted helper
        exits keep their explicit marker; they are never normal application exits.
        """
        result = dict(scope=HELPER_SCOPE, status='FAILED', code=None,
                      forced=False, remaining=None, receipts=[],
                      observation=dict(stage='members', image_class=None,
                                       image_bytes=None, path_match=None))
        observation = result['observation']
        retained = []
        try:
            values = _Members()
            if (self.handle is None or not self.kernel.QueryInformationJobObject(
                    self.handle, 3, ctypes.byref(values), ctypes.sizeof(values), None)
                    or values.assigned != values.listed or values.listed > 2):
                raise ProcessRefused('HELPER_IDENTITY_REFUSED')
            roles = set()
            for identifier in values.identifiers[:values.listed]:
                observation.update(stage='member', image_class=None,
                                   image_bytes=None, path_match=None)
                if not 0 < identifier < 0x100000000:
                    raise ProcessRefused('HELPER_IDENTITY_REFUSED')
                handle = self.kernel.OpenProcess(0x1000 | 0x100000 | 1, False, identifier)
                if not handle:
                    raise ProcessRefused('HELPER_IDENTITY_REFUSED')
                item = dict(handle=handle)
                retained.append(item)
                member = wintypes.BOOL()
                size = wintypes.DWORD(32768)
                image = ctypes.create_unicode_buffer(size.value)
                if (not self.kernel.IsProcessInJob(handle, self.handle, ctypes.byref(member))
                        or not member.value or not self.kernel.QueryFullProcessImageNameW(
                            handle, 0, image, ctypes.byref(size))):
                    raise ProcessRefused('HELPER_IDENTITY_REFUSED')
                actual = Path(image.value).resolve()
                observation['image_class'] = IMAGE_NAMES.get(actual.name.lower(), 'OTHER')
                if os.path.normcase(str(actual)) == os.path.normcase(str(dart.resolve())):
                    role, expected = 'sdk_dart', dart.resolve()
                    observation.update(stage='sdk_image', path_match=True)
                elif actual.name.lower() == 'vctip.exe':
                    observation['stage'] = 'compiler_metadata'
                    role, expected = 'msvc_telemetry', compiler_resolver().resolve()
                    observation['stage'] = 'compiler_image'
                    observation['path_match'] = os.path.normcase(str(actual)) == os.path.normcase(str(expected))
                    if not observation['path_match']:
                        raise ProcessRefused('HELPER_IMAGE_REFUSED')
                else:
                    raise ProcessRefused('HELPER_IMAGE_REFUSED')
                if role in roles:
                    raise ProcessRefused('HELPER_IDENTITY_REFUSED')
                roles.add(role)
                observation['stage'] = 'image_pin'
                observation['image_bytes'] = expected.lstat().st_size
                pin = image_pin(expected)
                receipt = dict(role=role, image_sha256=pin[0], forced=False,
                    termination_requested=False, termination_succeeded=False,
                    actual_exit=None, exit_observed=False, stdio_captured=False)
                item.update(expected=expected, pin=pin, receipt=receipt)
                result['receipts'].append(receipt)
            # The complete observed member set must still be the same size.
            observation['stage'] = 'membership_recheck'
            if self.active() != len(retained):
                raise ProcessRefused('HELPER_IDENTITY_REFUSED')
            for item in retained:
                observation['stage'] = 'image_recheck'
                handle, receipt = item['handle'], item['receipt']
                member = wintypes.BOOL()
                if (not self.kernel.IsProcessInJob(handle, self.handle, ctypes.byref(member))
                        or not member.value or image_pin(item['expected']) != item['pin']):
                    raise ProcessRefused('HELPER_IDENTITY_REFUSED')
                state = self.kernel.WaitForSingleObject(handle, 0)
                if state == 0x102:
                    observation['stage'] = 'termination'
                    receipt['termination_requested'] = receipt['forced'] = True
                    result['forced'] = True
                    if not self.kernel.TerminateProcess(handle, HELPER_EXIT_MARKER):
                        raise ProcessRefused('HELPER_CLOSE_UNCONFIRMED')
                    receipt['termination_succeeded'] = True
                    if self.kernel.WaitForSingleObject(handle, 10000) != 0:
                        raise ProcessRefused('HELPER_CLOSE_UNCONFIRMED')
                elif state != 0:
                    raise ProcessRefused('HELPER_CLOSE_UNCONFIRMED')
                code = wintypes.DWORD()
                observation['stage'] = 'exit_observation'
                if not self.kernel.GetExitCodeProcess(handle, ctypes.byref(code)):
                    raise ProcessRefused('HELPER_CLOSE_UNCONFIRMED')
                receipt.update(actual_exit=code.value, exit_observed=True)
                expected_exit = HELPER_EXIT_MARKER if receipt['forced'] else 0
                if code.value != expected_exit or image_pin(item['expected']) != item['pin']:
                    raise ProcessRefused('HELPER_CLOSE_UNCONFIRMED')
            deadline = time.monotonic() + 1
            observation['stage'] = 'empty_job'
            while self.active() and time.monotonic() < deadline:
                time.sleep(.05)
            result['remaining'] = self.active()
            if result['remaining'] != 0:
                raise ProcessRefused('HELPER_CLOSE_UNCONFIRMED')
            result['status'] = 'PASSED'
            observation['stage'] = 'complete'
        except ProcessRefused as error:
            result['code'] = str(error)
        except Exception:
            result['code'] = 'HELPER_CLOSE_UNCONFIRMED'
        finally:
            for item in retained:
                self.kernel.CloseHandle(item['handle'])
        return result

    def close(self):
        """Close the owned handles and return the retained forced-cleanup flag."""
        if self.handle is not None:
            try:
                self.active_at_close = self.active()
                self.forced = self.forced or self.active_at_close != 0
            except ProcessRefused:
                self.forced = True
            if not self.kernel.CloseHandle(self.handle):
                self.forced = True
                raise ProcessRefused("CLOSE_UNCONFIRMED")
            self.handle = None
        if self.application is not None:
            if not self.kernel.CloseHandle(self.application):
                self.forced = True
                raise ProcessRefused("CLOSE_UNCONFIRMED")
            self.application = None
        return self.forced
