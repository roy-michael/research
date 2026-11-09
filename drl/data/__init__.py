"""
Data loading & splitting package (`drl.data`):
  - `loader`: Memory-mapped WAV segment loading (`load_real_wav_segment`) and disjoint
    file-level Train/Held-Out Test dataset builder (`build_train_test_real_datasets`).
"""

from data.loader import (
    load_real_wav_segment,
    synthesize_vessel_audio,
    build_train_test_real_datasets,
)

__all__ = [
    "load_real_wav_segment",
    "synthesize_vessel_audio",
    "build_train_test_real_datasets",
]

