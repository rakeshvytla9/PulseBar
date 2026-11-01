"""Exercise the production reader with a local transfer; no internet or packages."""
import json
import selectors
import socket
import subprocess
import sys
import threading

binary = sys.argv[1]
server = socket.socket()
server.bind(("127.0.0.1", 0))
server.listen(1)
payload = b"p" * (2 * 1024 * 1024)

def receive():
    connection, _ = server.accept()
    with connection:
        while connection.recv(65536):
            pass

receiver = threading.Thread(target=receive)
receiver.start()
process = subprocess.Popen([binary, "--diagnose", "--interface", "lo0", "--signal-ready"],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
# Wait for the actual production counter baseline, rather than guessing how long
# a cold macOS/font startup takes under load.
with selectors.DefaultSelector() as ready:
    ready.register(process.stderr, selectors.EVENT_READ)
    assert ready.select(timeout=10), "diagnostic process did not establish its baseline"
    assert process.stderr.readline().strip() == "READY", "unexpected diagnostic startup output"
with socket.create_connection(server.getsockname()) as client:
    client.sendall(payload)
receiver.join(timeout=3)
server.close()
output, errors = process.communicate(timeout=5)
assert process.returncode == 0, output
reading = json.loads(output)
assert reading["counter_available"], reading
assert reading["download_Bps"] > len(payload) * 0.8, reading
assert reading["upload_Bps"] > len(payload) * 0.8, reading
print("PASS: real 2 MiB loopback transfer detected in both 64-bit counters")
print(json.dumps(reading, indent=2))
