#!/usr/bin/env python3

import re
import sys
import csv
from pathlib import Path

if len(sys.argv) != 3:
    print("Usage: parse_times.py <log_file> <script_file>")
    sys.exit(1)

log_file_path = sys.argv[1]
script_file_path = sys.argv[2]

# === 🧪 Step 1: Parse test case names from script ===
with open(script_file_path, "r") as f:
    script_lines = f.readlines()

test_names = []
for line in script_lines:
    if "time spark-submit" in line:
        after_jar = re.search(r'\.jar\s+(.+)', line)
        if after_jar:
            test_names.append(after_jar.group(1).strip())
        else:
            test_names.append("UNKNOWN")

# === ⏱ Step 2: Parse time blocks from log ===
time_block_pattern = re.compile(
    r"real\s+(\dm[\d.]+)s\s+user\s+(\dm[\d.]+)s\s+sys\s+(\dm[\d.]+)s", re.MULTILINE
)

def parse_time(tstr):
    m, s = tstr.strip().split("m")
    return float(m) * 60 + float(s[:-1])  # strip trailing 's'

with open(log_file_path, "r") as f:
    content = f.read()

matches = time_block_pattern.findall(content)
parsed_times = [(parse_time(r), parse_time(u), parse_time(s)) for r, u, s in matches]

# === 📊 Step 3: Write CSV ===
csv_path = Path(log_file_path).with_suffix(".csv")

with open(csv_path, "w", newline="") as csvfile:
    writer = csv.writer(csvfile)
    writer.writerow([
        "Test Case", "Real (s)", "User (s)", "Sys (s)",
        "Real Overhead", "User Overhead", "Sys Overhead",
        "Real Δ", "User Δ", "Sys Δ"
    ])

    baseline = parsed_times[0] if parsed_times else (1, 1, 1)
    prev = None

    for idx, (real, user, sys) in enumerate(parsed_times):
        label = test_names[idx] if idx < len(test_names) else f"Run {idx+1}"
        r_base_ov = real / baseline[0] if baseline[0] else 0
        u_base_ov = user / baseline[1] if baseline[1] else 0
        s_base_ov = sys / baseline[2] if baseline[2] else 0

        if prev:
            r_rel = real / prev[0] if prev[0] else 0
            u_rel = user / prev[1] if prev[1] else 0
            s_rel = sys / prev[2] if prev[2] else 0
        else:
            r_rel = u_rel = s_rel = 1.0

        writer.writerow([
            label,
            f"{real:.3f}", f"{user:.3f}", f"{sys:.3f}",
            f"{r_base_ov:.2f}x", f"{u_base_ov:.2f}x", f"{s_base_ov:.2f}x",
            f"{r_rel:.2f}x", f"{u_rel:.2f}x", f"{s_rel:.2f}x"
        ])
        prev = (real, user, sys)

print(f"✅ Done. Output written to: {csv_path}")
