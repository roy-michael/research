"""
Reinforcement Learning package (`drl.rl`):
  - `env`:   Gymnasium RL environment (`AcousticPIMLEnv`) with Multiscale TiB & Jain's Fairness rewards
    and CPO physical/coherence constraints.
  - `agent`: Dual-critic Actor-Critic network (`PIMLActorCritic`), PPO/CPO trainer (`train_piml_agent`),
    and deterministic per-dataset evaluator (`evaluate_agent_by_dataset`).
"""

from rl.env import AcousticPIMLEnv
from rl.agent import PIMLActorCritic, train_piml_agent, evaluate_agent_by_dataset

__all__ = [
    "AcousticPIMLEnv",
    "PIMLActorCritic",
    "train_piml_agent",
    "evaluate_agent_by_dataset",
]

