"""Read macOS process CPU, footprint and one-second CPU windows. No packages."""
import argparse
import ctypes
import json
import time

parser = argparse.ArgumentParser()
parser.add_argument("pid", type=int)
parser.add_argument("--seconds", type=float, default=30)
parser.add_argument("--interval", type=float, default=1)
args = parser.parse_args()

class Usage(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(name, ctypes.c_uint64) for name in (
        "user", "system", "idle_wakeups", "interrupt_wakeups", "pageins", "wired",
        "resident", "footprint", "start", "exit", "child_user", "child_system",
        "child_idle", "child_interrupt", "child_pageins", "child_elapsed", "read", "written")]

library = ctypes.CDLL("/usr/lib/libproc.dylib")
library.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]
timebase = Timebase()
if ctypes.CDLL("/usr/lib/libSystem.B.dylib").mach_timebase_info(ctypes.byref(timebase)) != 0 or not timebase.denom:
    raise SystemExit("Cannot obtain Mach clock conversion")
seconds_per_tick = timebase.numer / timebase.denom / 1e9

def read():
    value = Usage()
    if library.proc_pid_rusage(args.pid, 2, ctypes.byref(value)) != 0:
        raise SystemExit("Cannot read process counters. Check the PID is still running.")
    return value

start = read()
begin = time.monotonic()
previous = start
previous_time = begin
windows = []
short_windows = []
history = [(begin, start.user + start.system)]
deadline = begin + max(1, args.seconds)
while time.monotonic() < deadline:
    time.sleep(min(max(0.05, args.interval), max(0, deadline - time.monotonic())))
    current = read()
    now = time.monotonic()
    duration = now - previous_time
    if duration > 0:
        short_windows.append((current.user + current.system - previous.user - previous.system) * seconds_per_tick / duration * 100)
    total = current.user + current.system
    history.append((now, total))
    while len(history) > 1 and now - history[1][0] >= 1:
        history.pop(0)
    if now - history[0][0] >= 0.9:
        windows.append((total - history[0][1]) * seconds_per_tick / (now - history[0][0]) * 100)
    previous = current
    previous_time = now
end = previous
elapsed = previous_time - begin
print(json.dumps({
    "cpu_time_unit": "Mach ticks converted with mach_timebase_info",
    "mach_timebase_numer": timebase.numer,
    "mach_timebase_denom": timebase.denom,
    "duration_seconds": round(elapsed, 3),
    "average_cpu_percent_of_one_core": round((end.user + end.system - start.user - start.system) * seconds_per_tick / elapsed * 100, 3),
    "sampling_interval_seconds": max(0.05, args.interval),
    "highest_sampled_cpu_percent": round(max(short_windows, default=0), 3),
    "highest_one_second_cpu_percent": round(max(windows, default=0), 3),
    "resident_MiB": round(end.resident / 1024 / 1024, 2),
    "physical_footprint_MiB": round(end.footprint / 1024 / 1024, 2),
    "idle_wakeups_per_second": round((end.idle_wakeups - start.idle_wakeups) / elapsed, 2)
}, indent=2))
