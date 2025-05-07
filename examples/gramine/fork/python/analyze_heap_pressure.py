#!/usr/bin/env python3

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import os

# === CONFIGURATION ===
BASELINE_FILE = "../output-data/full-gc-benchmark/baseline_metrics_20250427_090126.csv"
SUMMARY_FILE = "../output-data/full-gc-benchmark/full_gc_benchmark_summary_20250427_090126.csv"
PLOT_DIR = "../output-data/heap-pressure-benchmark/plots"

os.makedirs(PLOT_DIR, exist_ok=True)

# === Load Data ===
print("📥 Loading CSV files...")
baseline = pd.read_csv(BASELINE_FILE)
summ = pd.read_csv(SUMMARY_FILE)

# === Preprocess ===
print("🔎 Preprocessing...")
# Keep only successful runs
summ = summ[(summ['exit_code_native'] == 0) & (summ['exit_code_gramine'] == 0)]

# Fix columns if needed
for col in [
    'native_user_time_sec', 'native_system_time_sec', 'native_cpu_percent',
    'native_elapsed_time_sec', 'native_max_mem_kb',
    'gramine_user_time_sec', 'gramine_system_time_sec', 'gramine_cpu_percent',
    'gramine_elapsed_time_sec', 'gramine_adj_elapsed_sec', 'gramine_max_mem_kb'
]:
    summ[col] = pd.to_numeric(summ[col], errors='coerce')

# Merge baseline mean elapsed time to adjust gramine elapsed
baseline_elapsed = baseline[baseline['metric'] == 'elapsed_time_sec']['mean'].values[0]

if 'gramine_adj_elapsed_sec' not in summ.columns or summ['gramine_adj_elapsed_sec'].isnull().all():
    summ['gramine_adj_elapsed_sec'] = summ['gramine_elapsed_time_sec'] - baseline_elapsed
    summ['gramine_adj_elapsed_sec'] = summ['gramine_adj_elapsed_sec'].clip(lower=0)

# Compute heap per thread if missing
if 'heap_per_thread_mb' not in summ.columns:
    summ['heap_per_thread_mb'] = summ['heap_size_mb'] / summ['num_threads']

# === Plotting Helpers ===
sns.set(style="whitegrid")

# Save a plot easily
def save_plot(fig, name):
    fig.savefig(os.path.join(PLOT_DIR, f"{name}.png"), bbox_inches='tight')
    fig.savefig(os.path.join(PLOT_DIR, f"{name}.pdf"), bbox_inches='tight')
    plt.close(fig)

# === Plot: Elapsed Time vs Heap Per Thread ===
def plot_elapsed_time():
    for mode in ['native', 'gramine']:
        fig, ax = plt.subplots(figsize=(10,6))
        for gc, group in summ.groupby('gc_type'):
            if mode == 'native':
                y = group['native_elapsed_time_sec']
            else:
                y = group['gramine_adj_elapsed_sec']
            ax.plot(group['heap_per_thread_mb'], y, label=gc)
        ax.set_xscale('log')
        ax.set_xlabel('Heap per Thread (MB)')
        ax.set_ylabel('Elapsed Time (s)')
        ax.set_title(f'Elapsed Time vs Heap/Thread ({mode.capitalize()})')
        ax.legend()
        save_plot(fig, f"elapsed_vs_heap_{mode}")

# === Plot: CPU % vs Heap Per Thread ===
def plot_cpu_usage():
    for mode in ['native', 'gramine']:
        fig, ax = plt.subplots(figsize=(10,6))
        for gc, group in summ.groupby('gc_type'):
            if mode == 'native':
                y = group['native_cpu_percent']
            else:
                y = group['gramine_cpu_percent']
            ax.plot(group['heap_per_thread_mb'], y, label=gc)
        ax.set_xscale('log')
        ax.set_xlabel('Heap per Thread (MB)')
        ax.set_ylabel('CPU Usage (%)')
        ax.set_title(f'CPU Usage vs Heap/Thread ({mode.capitalize()})')
        ax.legend()
        save_plot(fig, f"cpu_vs_heap_{mode}")

# === Plot: Max Memory Usage ===
def plot_memory_usage():
    for mode in ['native', 'gramine']:
        fig, ax = plt.subplots(figsize=(10,6))
        for gc, group in summ.groupby('gc_type'):
            if mode == 'native':
                y = group['native_max_mem_kb'] / 1024  # MB
            else:
                y = group['gramine_max_mem_kb'] / 1024  # MB
            ax.plot(group['heap_per_thread_mb'], y, label=gc)
        ax.set_xscale('log')
        ax.set_xlabel('Heap per Thread (MB)')
        ax.set_ylabel('Max Memory Usage (MB)')
        ax.set_title(f'Max Memory Usage vs Heap/Thread ({mode.capitalize()})')
        ax.legend()
        save_plot(fig, f"memory_vs_heap_{mode}")

# === Run All Plots ===
plot_elapsed_time()
plot_cpu_usage()
plot_memory_usage()

print("\n✅ Benchmark analysis complete!")
print(f"Plots saved under {PLOT_DIR}/")

