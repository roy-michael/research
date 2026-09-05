import os
from pathlib import Path

# Base directory for the repository
BASE_DIR = Path(__file__).resolve().parent.parent.parent

# Centralized output directory for all plots and generated reports
REPORTS_DIR = BASE_DIR / "research" / "reports"
IMAGES_DIR = REPORTS_DIR / "images"

def get_output_dir(dataset_name: str) -> Path:
    """Returns a centralized output directory for a given dataset."""
    out_dir = IMAGES_DIR / dataset_name
    out_dir.mkdir(parents=True, exist_ok=True)
    return out_dir
