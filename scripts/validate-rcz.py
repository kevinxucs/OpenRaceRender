#!/usr/bin/env python3
"""Compare native RCZ import with a matching RaceChrono CSV v3 export.

Usage: python3 scripts/validate-rcz.py SESSION.rcz SESSION_v3.csv [--samples 20]
Private recordings and generated reports belong under ignored build/validation.
"""
import argparse
import csv
import json
import math
import re
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("rcz", type=Path)
parser.add_argument("csv", type=Path)
parser.add_argument("--samples", type=int, default=20)
parser.add_argument("--exe", type=Path, default=Path(__file__).resolve().parent.parent / ".build/release/OpenRaceRender")
parser.add_argument("--out", type=Path)
args = parser.parse_args()
assert 1 <= args.samples <= 100

def inspect(at=None):
    command = [str(args.exe), "inspect-data", str(args.rcz)]
    if at is not None:
        command += ["--time", str(at)]
    result = subprocess.run(command, check=True, capture_output=True)
    return json.loads(result.stdout)

start = time.monotonic()
metadata = inspect()
elapsed = time.monotonic() - start
epoch_ms = round(metadata["firstSampleUnixTime"] * 1000)
targets = [(i + 1) * metadata["duration"] / (args.samples + 1) for i in range(args.samples)]
selected = []
with args.csv.open(encoding="utf-8-sig", newline="") as file:
    reader = csv.reader(file)
    for row in reader:
        if row and row[0].lower() == "timestamp":
            names, units, sources = row, next(reader), next(reader)
            break
    else:
        raise AssertionError("Expected a RaceChrono CSV v3 header")
    for row in reader:
        if not row or len(selected) == len(targets):
            continue
        relative = (round(float(row[0]) * 1000) - epoch_ms) / 1000
        if relative >= targets[len(selected)] and relative <= metadata["duration"]:
            selected.append((relative, row))

labels = {
    "Speed": "speed", "Latitude": "latitude", "Longitude": "longitude", "Heading": "bearing",
    "Altitude": "altitude", "GPS accuracy": "accuracy", "Device battery level": "device_battery_level",
    "Coordinate precision": "coordinate_precision", "Altitude precision": "altitude_precision",
    "RPM": "rpm", "Throttle position": "throttle_pos", "Accelerator position": "accelerator_pos",
    "Brake position": "brake_pos", "Clutch position": "clutch_pos", "Steering angle": "steering_angle",
    "Coolant temperature": "coolant_temp", "Engine oil temperature": "engine_oil_temp",
    "Intake temperature": "intake_temp", "Air temperature": "air_temp", "Fuel level": "fuel_level",
    "Tyre pressure": "tyre_pressure", "Tyre temperature": "tyre_temp", "Wheel speed": "speed",
    "Longitudinal acceleration": "longitudinal_acc", "Lateral acceleration": "lateral_acc",
    "X acceleration": "x_acc", "Y acceleration": "y_acc", "Z acceleration": "z_acc",
    "X rotation rate": "x_rate_of_rotation", "Y rotation rate": "y_rate_of_rotation",
    "Z rotation rate": "z_rate_of_rotation", "Yaw rate": "yaw_rate", "Pitch rate": "pitch_rate", "Roll rate": "roll_rate",
    "X magnetic field": "x_magnetic_field", "Y magnetic field": "y_magnetic_field", "Z magnetic field": "z_magnetic_field",
}
mapping = []
for header in metadata["channels"]:
    if header == "Distance (m)" and "distance_traveled" in names:
        mapping.append((header, names.index("distance_traveled"), 0.01))
        continue
    match = re.fullmatch(r"(.+?)(?: \(([^)]+)\))? \*([A-Z0-9]+) (\d+)", header)
    if not match:
        continue
    label, unit, _, device = match.groups()
    suffix = ""
    position = re.search(r" (Front|Rear|RR|RL|FR|FL)(?: (\d+))?$", label)
    if position:
        suffix = "_" + position[1].lower() + ("_" + position[2] if position[2] else "")
        label = label[:position.start()]
    name = labels.get(label)
    if not name:
        continue  # Discrete enums and derived-only channels have separate regression tests.
    expected = [i for i, (n, source) in enumerate(zip(names, sources))
                if n == name + suffix and source.startswith(device + ":")]
    if len(expected) == 1:
        tolerance = 2e-7 if name in ("latitude", "longitude") else (0.05 if name == "rpm" else 0.001)
        mapping.append((header, expected[0], tolerance))

errors, compared, failures = {}, 0, []
for at, row in selected:
    actual = inspect(at)["values"]
    for header, index, tolerance in mapping:
        if index >= len(row) or not row[index]:
            continue
        expected = float(row[index])
        if not math.isfinite(expected):
            continue
        if actual.get(header) is None:
            failures.append({"time": at, "channel": header, "error": "Missing native value for a recorded CSV sample"})
            continue
        error = abs(actual[header] - expected)
        errors[header] = max(errors.get(header, 0), error)
        compared += 1
        if error > tolerance:
            failures.append({"time": at, "channel": header, "error": error, "tolerance": tolerance})
assert compared > 0, "No matching recorded channels were compared"
report = {"title": metadata["title"], "duration": metadata["duration"], "samples": metadata["samples"],
          "channels": len(metadata["channels"]), "laps": metadata["laps"], "importSeconds": elapsed,
          "comparedValues": compared, "maximumErrors": errors, "failures": failures}
if args.out:
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2))
print(json.dumps({k: report[k] for k in ("duration", "samples", "channels", "laps", "importSeconds", "comparedValues")}, indent=2))
assert not failures, json.dumps(failures[:10], indent=2)
print("PASS recorded RCZ channel values agree with RaceChrono CSV v3")
