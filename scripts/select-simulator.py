"""Select an available iPhone on iOS 26+ without relying on a device name."""
import json
import re
import subprocess

inventory = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
candidates = []
for runtime, devices in inventory["devices"].items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match or int(match.group(1)) < 26:
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append(((int(match.group(1)), int(match.group(2))), device["udid"]))
if not candidates:
    raise SystemExit("An installed iOS 26+ iPhone simulator runtime is required.")
print(sorted(candidates, reverse=True)[0][1])

