"""Read-only process admission for one bounded, isolated Python helper.

Only exit status leaves this helper: zero means the complete snapshot contains
its own process and no Syrius process, 23 means Syrius exists, and one means
the observation or snapshot closure is uncertain. No process is opened or killed.
"""

import ctypes
from ctypes import wintypes
import os
from pathlib import PureWindowsPath
import sys


MAX_ENTRIES = 65536
NO_MORE_FILES = 18


class Refused(Exception):
    pass


class Toolhelp:
    """Keep the original read-only snapshot handle until its checked closure."""

    def __init__(self):
        if os.name != 'nt':
            raise Refused()

        class ProcessEntry(ctypes.Structure):
            _fields_ = [
                ('dwSize', wintypes.DWORD), ('cntUsage', wintypes.DWORD),
                ('th32ProcessID', wintypes.DWORD), ('th32DefaultHeapID', ctypes.c_size_t),
                ('th32ModuleID', wintypes.DWORD), ('cntThreads', wintypes.DWORD),
                ('th32ParentProcessID', wintypes.DWORD), ('pcPriClassBase', wintypes.LONG),
                ('dwFlags', wintypes.DWORD), ('szExeFile', wintypes.WCHAR * 260),
            ]

        self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        self.kernel.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
        self.kernel.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
        for name in ('Process32FirstW', 'Process32NextW'):
            function = getattr(self.kernel, name)
            function.argtypes = [wintypes.HANDLE, ctypes.POINTER(ProcessEntry)]
            function.restype = wintypes.BOOL
        self.kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        self.kernel.CloseHandle.restype = wintypes.BOOL
        self.entry = ProcessEntry()
        self.entry.dwSize = ctypes.sizeof(ProcessEntry)

    def snapshot(self):
        # TH32CS_SNAPPROCESS only: no heaps, modules, threads or inheritance.
        handle = self.kernel.CreateToolhelp32Snapshot(2, 0)
        if handle in (None, 0, ctypes.c_void_p(-1).value):
            raise Refused()
        return handle

    def _read(self, function, handle):
        ctypes.set_last_error(0)
        if function(handle, ctypes.byref(self.entry)):
            return int(self.entry.th32ProcessID), self.entry.szExeFile
        if ctypes.get_last_error() != NO_MORE_FILES:
            raise Refused()
        return None

    def first(self, handle):
        return self._read(self.kernel.Process32FirstW, handle)

    def next(self, handle):
        return self._read(self.kernel.Process32NextW, handle)

    def close(self, handle):
        if not self.kernel.CloseHandle(handle):
            raise Refused()


def observe(api, own_pid):
    """Require a complete snapshot and exact original closure, including refusal."""
    if type(own_pid) is not int or own_pid <= 0:
        raise Refused()
    handle = api.snapshot()
    try:
        row = api.first(handle)
        seen, existing = set(), False
        while row is not None:
            if type(row) is not tuple or len(row) != 2:
                raise Refused()
            pid, image = row
            if (type(pid) is not int or not 0 <= pid <= 0xffffffff or pid in seen
                    or type(image) is not str or not 0 < len(image) < 260
                    or any(character in image for character in ('\0', '/', '\\'))
                    or len(seen) >= MAX_ENTRIES):
                raise Refused()
            seen.add(pid)
            # Keep the original exact process-name rule, ignoring its extension.
            existing |= PureWindowsPath(image).stem.casefold() == 'syrius'
            row = api.next(handle)
        # Empty/partial snapshots must never be accepted as an empty machine.
        if own_pid not in seen:
            raise Refused()
        return 23 if existing else 0
    finally:
        api.close(handle)


def main(arguments=None):
    arguments = sys.argv[1:] if arguments is None else arguments
    if arguments or os.name != 'nt':
        return 1
    try:
        return observe(Toolhelp(), os.getpid())
    except (Exception, KeyboardInterrupt):
        # No names, PIDs, paths, raw OS errors or exceptions reach stdout/stderr.
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
