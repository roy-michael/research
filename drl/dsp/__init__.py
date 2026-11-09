"""
DSP package (`drl.dsp`):
  - `watershed_tracker`: High-resolution Welch PSD, macro-lobe segmentation, and 0.5s watershed bandwidth tracking.
  - `feature_extractor`: Offline feature extractor combining Watershed Bandwidth, Multiscale TiB Scale-Uniformity Fairness,
    Hilbert envelope coherence, and 2nd-order Digital PLL phase-lock tracking.
"""

from dsp.watershed_tracker import (
    DEFAULT_BW_CONFIG,
    compute_welch_psd,
    segment_macro_lobes,
    compute_single_slice_watershed_bandwidth,
)
from dsp.feature_extractor import OfflineFeatureExtractor

__all__ = [
    "DEFAULT_BW_CONFIG",
    "compute_welch_psd",
    "segment_macro_lobes",
    "compute_single_slice_watershed_bandwidth",
    "OfflineFeatureExtractor",
]

