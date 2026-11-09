"""
Visualization & reporting package (`drl.visualization`):
  - `live_dashboard`: Real-time 6-panel Matplotlib dashboard (`LiveTrainingDashboard`) streaming
    epoch-by-epoch training and held-out verification across `HaifaBay`, `Croatia`, and `AUV`.
  - `reporting`: Console statistical tables and publication-grade figures (`print_feature_summary`,
    `print_evaluation_summary`, `plot_training_and_eval_results`, `plot_minute_tib_fairness_diagnostics`).
"""

from visualization.live_dashboard import LiveTrainingDashboard
from visualization.reporting import (
    print_feature_summary,
    print_evaluation_summary,
    plot_training_and_eval_results,
    plot_minute_tib_fairness_diagnostics,
)

__all__ = [
    "LiveTrainingDashboard",
    "print_feature_summary",
    "print_evaluation_summary",
    "plot_training_and_eval_results",
    "plot_minute_tib_fairness_diagnostics",
]

