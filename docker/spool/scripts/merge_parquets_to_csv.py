#!/usr/bin/env python3

import argparse
import os
import glob
import pandas as pd

def merge_parquets(path_prefix: str, dest_dir: str):
    parquet_files = glob.glob(f"{path_prefix}*.parquet")
    if not parquet_files:
        print(f"❌ No Parquet files found matching: {path_prefix}*.parquet")
        return

    print(f"📁 Found {len(parquet_files)} files. Merging...")

    dfs = [pd.read_parquet(pq) for pq in parquet_files]
    combined_df = pd.concat(dfs, ignore_index=True)

    os.makedirs(dest_dir, exist_ok=True)
    prefix_name = os.path.basename(path_prefix.rstrip("/").rstrip("-"))
    output_path = os.path.join(dest_dir, f"{prefix_name}.csv")

    combined_df.to_csv(output_path, index=False)
    print(f"✅ CSV saved to: {output_path}")

def main():
    parser = argparse.ArgumentParser(description="Merge all Parquet files with a given prefix into a single CSV.")
    parser.add_argument("--path-prefix", required=True, help="Path prefix for Parquet files, e.g. /path/to/output/index/part-")
    parser.add_argument("--dest", required=True, help="Destination directory for the merged CSV")

    args = parser.parse_args()
    merge_parquets(args.path_prefix, args.dest)

if __name__ == "__main__":
    main()
