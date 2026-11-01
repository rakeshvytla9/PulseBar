"""Verify CPU units using a short one-core worker. Standard library only."""
from pathlib import Path
import json
import subprocess
import sys

worker = subprocess.Popen([sys.executable, "-c", "import time\nend=time.monotonic()+3\nwhile time.monotonic()<end: pass"])
try:
    result = subprocess.run([sys.executable, str(Path(__file__).with_name("profile.py")), str(worker.pid), "--seconds", "2", "--interval", "0.1"], capture_output=True, text=True, check=True)
    reading = json.loads(result.stdout)
    cpu = reading["average_cpu_percent_of_one_core"]
    assert 50 <= cpu <= 120, f"One-core worker reported {cpu}% CPU; check clock units or host saturation"
    print(f"PASS: one-core worker measured {cpu:.1f}% CPU with Mach timebase conversion")
finally:
    worker.wait()
