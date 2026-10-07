"""Own Windows descendants before execution, using documented Kernel32 APIs.

This is lifecycle ownership, not a replacement for the container sandbox.
"""
import ctypes as C
import os
import threading
import time

DWORD = C.c_uint32
HANDLE = C.c_void_p


class BasicLimits(C.Structure):
    _fields_ = [("process_time", C.c_int64), ("job_time", C.c_int64),
                ("flags", DWORD), ("working_min", C.c_size_t), ("working_max", C.c_size_t),
                ("process_count", DWORD), ("affinity", C.c_size_t),
                ("priority", DWORD), ("scheduling", DWORD)]


class ExtendedLimits(C.Structure):
    _fields_ = [("basic", BasicLimits), ("io", C.c_uint64 * 6),
                ("process_memory", C.c_size_t), ("job_memory", C.c_size_t),
                ("peak_process_memory", C.c_size_t), ("peak_job_memory", C.c_size_t)]


class Accounting(C.Structure):
    _fields_ = [("times", C.c_int64 * 4), ("page_faults", DWORD),
                ("total_processes", DWORD), ("active_processes", DWORD), ("terminated_processes", DWORD)]


class ThreadEntry(C.Structure):
    _fields_ = [("size", DWORD), ("usage", DWORD), ("thread_id", DWORD),
                ("process_id", DWORD), ("base_priority", C.c_int32),
                ("delta_priority", C.c_int32), ("flags", DWORD)]


class WindowsJob:
    def __init__(self):
        if os.name != "nt":
            raise OSError("Windows Job Objects require Windows")
        self._lock = threading.RLock()
        self._handle = None
        self._api = C.WinDLL("kernel32", use_last_error=True)
        signatures = {
            "CreateJobObjectW": ([C.c_void_p, C.c_wchar_p], HANDLE),
            "SetInformationJobObject": ([HANDLE, C.c_int, C.c_void_p, DWORD], C.c_int),
            "AssignProcessToJobObject": ([HANDLE, HANDLE], C.c_int),
            "QueryInformationJobObject": ([HANDLE, C.c_int, C.c_void_p, DWORD, C.c_void_p], C.c_int),
            "TerminateJobObject": ([HANDLE, C.c_uint], C.c_int),
            "OpenProcess": ([DWORD, C.c_int, DWORD], HANDLE),
            "OpenThread": ([DWORD, C.c_int, DWORD], HANDLE),
            "ResumeThread": ([HANDLE], DWORD),
            "CreateToolhelp32Snapshot": ([DWORD, DWORD], HANDLE),
            "Thread32First": ([HANDLE, C.POINTER(ThreadEntry)], C.c_int),
            "Thread32Next": ([HANDLE, C.POINTER(ThreadEntry)], C.c_int),
            "CloseHandle": ([HANDLE], C.c_int),
        }
        for name, (arguments, result) in signatures.items():
            function = getattr(self._api, name)
            function.argtypes, function.restype = arguments, result
        self._handle = self._api.CreateJobObjectW(None, None)
        if not self._handle:
            raise C.WinError(C.get_last_error())
        limits = ExtendedLimits()
        limits.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE; no breakaway.
        if not self._api.SetInformationJobObject(self._handle, 9, C.byref(limits), C.sizeof(limits)):
            error = C.WinError(C.get_last_error())
            self.close()
            raise error

    def assign_and_resume(self, pid):
        """Assign an already CREATE_SUSPENDED process, then resume its sole thread."""
        with self._lock:
            process = self._api.OpenProcess(0x0101, False, pid)  # SET_QUOTA | TERMINATE
            if not process:
                raise C.WinError(C.get_last_error())
            try:
                if not self._api.AssignProcessToJobObject(self._handle, process):
                    raise C.WinError(C.get_last_error())
            finally:
                self._api.CloseHandle(process)
            snapshot = self._api.CreateToolhelp32Snapshot(0x4, 0)  # SNAPTHREAD
            if snapshot == HANDLE(-1).value or not snapshot:
                raise C.WinError(C.get_last_error())
            try:
                entry = ThreadEntry()
                entry.size = C.sizeof(entry)
                found = self._api.Thread32First(snapshot, C.byref(entry))
                while found:
                    if entry.process_id == pid:
                        thread = self._api.OpenThread(0x2, False, entry.thread_id)  # SUSPEND_RESUME
                        if not thread:
                            raise C.WinError(C.get_last_error())
                        try:
                            previous = self._api.ResumeThread(thread)
                            if previous != 1:
                                raise OSError("Owned primary thread did not have the expected suspend count")
                            return
                        finally:
                            self._api.CloseHandle(thread)
                    entry.size = C.sizeof(entry)
                    found = self._api.Thread32Next(snapshot, C.byref(entry))
                raise OSError("Owned suspended process primary thread was not found")
            finally:
                self._api.CloseHandle(snapshot)

    def active_count(self):
        with self._lock:
            if self._handle is None:
                return 0
            information = Accounting()
            if not self._api.QueryInformationJobObject(self._handle, 1, C.byref(information), C.sizeof(information), None):
                raise C.WinError(C.get_last_error())
            return information.active_processes

    def terminate(self, seconds=2.0):
        with self._lock:
            if self._handle is None:
                return True
            if not self._api.TerminateJobObject(self._handle, 1):
                return False
            deadline = time.monotonic() + seconds
            while self.active_count():
                if time.monotonic() >= deadline:
                    return False
                time.sleep(0.01)
            return True

    def close(self):
        with self._lock:
            if self._handle is not None:
                if not self._api.CloseHandle(self._handle):
                    raise C.WinError(C.get_last_error())
                self._handle = None
