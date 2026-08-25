# This script profiles football data from local CSV files and generates HTML reports using ydata-profiling.

import pandas as pd  # Import for data manipulation
from ydata_profiling import ProfileReport  # Import for generating data report
import os  # Import for file handling
from pathlib import Path  # A modern way to handle file paths

# --- Configuration ---
# Assuming this script is located in: {project_root}/scripts/
current_script_path = Path(__file__).resolve()
project_root_dir = current_script_path.parent.parent

# Define the data and reports directories relative to the project root
# Input CSVs should be in: {project_root}/data/
data_directory = Path(project_root_dir / "data")
# Output reports will be saved in: {project_root}/reports/
reports_directory = Path(project_root_dir / "reports")

print(f"Project root directory: {project_root_dir.resolve()}")
print(f"Data directory being scanned: {data_directory.resolve()}")

# Ensure the reports directory exists
reports_directory.mkdir(parents=True, exist_ok=True)

# Store paths of CSV files
csv_files = []

# Find all CSV files in the data directory
for file_path in data_directory.glob("*.csv"):
    csv_files.append(file_path)

# Check if any CSV files were found
if not csv_files:
    print("-" * 50)
    print(f"ERROR: No CSV files found in '{data_directory}'.")
    print("Please ensure your raw data files are in the 'data/' folder.")
    print("-" * 50)
else:
    print(f"Found {len(csv_files)} CSV files to profile.")

# --- Loop through each CSV file and generate a report ---
for csv_file_path in csv_files:
    file_name = csv_file_path.name  # e.g., 'team_stats_2023.csv'
    report_name = f"profile_report_{csv_file_path.stem}.html"  # e.g., 'profile_report_team_stats_2023.html'
    report_output_path = reports_directory / report_name

    print(f"\n--- Profiling '{file_name}' ---")
    try:
        # Load the dataset
        df = pd.read_csv(csv_file_path)
        print(f"Loaded '{file_name}' successfully. Shape: {df.shape}")

        # Generate the ydata-profiling report
        profile = ProfileReport(df, title=f"Profile Report for {file_name}", sort=None)

        # Save the report to an HTML file
        profile.to_file(report_output_path)
        print(f"Report saved to: {report_output_path.resolve()}")

    except pd.errors.EmptyDataError:
        print(f"Warning: '{file_name}' is empty. Skipping profiling for this file.")
    except FileNotFoundError:
        print(
            f"Error: File '{csv_file_path}' not found. Please check your data directory."
        )
    except Exception as e:
        print(f"An error occurred while processing '{file_name}': {e}")

print("\n--- Profiling complete! ---")
print(f"You can find your reports in the '{reports_directory.resolve()}' folder.")
