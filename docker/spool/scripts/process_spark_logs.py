import re
import pandas as pd
from datetime import datetime
import sys
import os

# === Helpers ===
def parse_timestamp(line):
    match = re.match(r"(\d{2}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})", line)
    if match:
        return datetime.strptime(match.group(1), "%d/%m/%y %H:%M:%S")
    return None

# === Argument parsing ===
log_path = "output.err"
output_dir = "."
if "--file" in sys.argv:
    idx = sys.argv.index("--file")
    if idx + 1 < len(sys.argv):
        log_path = sys.argv[idx + 1]
        output_dir = os.path.dirname(os.path.abspath(log_path))

# === Load log file ===
with open(log_path, "r") as file:
    log = file.read()

# === Establish start time ===
all_timestamps = re.findall(r"(\d{2}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})", log)
start_time = datetime.strptime(all_timestamps[0], "%d/%m/%y %H:%M:%S") if all_timestamps else None

# === 1. Executor Registrations ===
executor_entries = []
pattern = re.compile(
    r"(?P<ts>\d{2}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*Registered executor NettyRpcEndpointRef.* with ID (?P<executor_id>\d+)"
)
for match in pattern.finditer(log):
    ts = datetime.strptime(match.group("ts"), "%d/%m/%y %H:%M:%S")
    executor_entries.append({
        "timestamp": ts,
        "elapsed_sec": (ts - start_time).total_seconds(),
        "executor_id": match.group("executor_id")
    })
df_executors = pd.DataFrame(executor_entries)

# === 2. Job Specs ===
job_entries = []
job_pattern = re.compile(
    r"(?P<ts>\d{2}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*DAGScheduler: Job (?P<id>\d+) finished: (?P<desc>.+) at (?P<location>[^\s,]+), took (?P<time>[0-9.]+) s"
)
for match in job_pattern.finditer(log):
    ts = datetime.strptime(match.group("ts"), "%d/%m/%y %H:%M:%S")
    job_entries.append({
        "timestamp": ts,
        "elapsed_sec": (ts - start_time).total_seconds(),
        "job_id": int(match.group("id")),
        "description": match.group("desc").strip(),
        "location": match.group("location"),
        "duration_sec": float(match.group("time"))
    })
df_jobs = pd.DataFrame(job_entries)

# === 3. Stage Info ===
stage_entries = []
stage_submit_pattern = re.compile(
    r"(?P<ts>\d{2}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*Submitting (ShuffleMapStage|ResultStage) (?P<id>\d+) \([^)]+\)"
)
for match in stage_submit_pattern.finditer(log):
    ts = datetime.strptime(match.group("ts"), "%d/%m/%y %H:%M:%S")
    stage_entries.append({
        "timestamp": ts,
        "elapsed_sec": (ts - start_time).total_seconds(),
        "stage_id": int(match.group("id")),
        "type": match.group(2)
    })
df_stages = pd.DataFrame(stage_entries)

# === 4. Task Specs ===
task_entries = []
task_start_pattern = re.compile(
    r"(?P<ts>\d{2}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}).*Starting task (?P<task_num>\d+\.\d+) in stage (?P<stage_id>\d+\.\d+) \(TID (?P<tid>\d+)\) \((?P<host>[^,]+), executor (?P<executor_id>\d+)"
)
for match in task_start_pattern.finditer(log):
    ts = datetime.strptime(match.group("ts"), "%d/%m/%y %H:%M:%S")
    task_entries.append({
        "timestamp": ts,
        "elapsed_sec": (ts - start_time).total_seconds(),
        "task_id": match.group("tid"),
        "stage_id": match.group("stage_id"),
        "task_number": match.group("task_num"),
        "executor_id": match.group("executor_id"),
        "host": match.group("host")
    })
df_tasks = pd.DataFrame(task_entries)

# === Save CSVs ===
df_executors.to_csv(os.path.join(output_dir, "executor_registrations.csv"), index=False)
df_jobs.to_csv(os.path.join(output_dir, "job_specs.csv"), index=False)
df_stages.to_csv(os.path.join(output_dir, "stage_info.csv"), index=False)
df_tasks.to_csv(os.path.join(output_dir, "task_specs.csv"), index=False)

print("✅ All CSVs generated!")

