"""
Gymnasium Reinforcement Learning environment (`AcousticPIMLEnv`) with
physics-informed rewards and Constrained Policy Optimization (CPO) costs.
"""

from typing import List, Dict, Any
import numpy as np
import gymnasium as gym
from gymnasium import spaces


class AcousticPIMLEnv(gym.Env):
    """
    RL Environment operating on pre-extracted DSP + 0.5s Digital PLL feature vectors s_t
    from HaifaBay (Surface), Croatia (Submerged DPV), and AUV (Submerged AUV).
    Action a_t = [delta_fc_track, bw_gate_norm, surface_vs_submerged_logit]
    """

    def __init__(self, dataset: List[Dict[str, Any]], balanced_sampling: bool = True):
        super().__init__()
        self.dataset = dataset
        self.balanced_sampling = balanced_sampling
        self.surface_indices = [i for i, d in enumerate(dataset) if d["metadata"]["is_surface"] == 1]
        self.submerged_indices = [i for i, d in enumerate(dataset) if d["metadata"]["is_surface"] == 0]

        self.current_rec = None
        self.step_idx = 0

        # Action space (centered around 0):
        # a[0]: PLL / NCO Frequency tracking step adjustment [-5.0, +5.0] Hz
        # a[1]: Bandwidth Gate Action in [-5.0, +5.0] -> maps linearly to [10.0, 130.0] Hz
        # a[2]: Classification logit (<0: Submerged Croatia/AUV, >0: Surface HaifaBay)
        self.action_space = spaces.Box(
            low=np.array([-5.0, -5.0, -5.0], dtype=np.float32),
            high=np.array([5.0, 5.0, 5.0], dtype=np.float32),
        )

        # Observation space: 8-D Extracted Feature Vector s_t
        self.observation_space = spaces.Box(
            low=-np.inf, high=np.inf, shape=(8,), dtype=np.float32
        )

    def reset(self, seed=None, options=None):
        super().reset(seed=seed)
        if options and "rec_idx" in options:
            idx = options["rec_idx"]
        elif self.balanced_sampling and self.surface_indices and self.submerged_indices:
            if np.random.rand() < 0.5:
                idx = int(np.random.choice(self.surface_indices))
            else:
                idx = int(np.random.choice(self.submerged_indices))
        else:
            idx = np.random.randint(0, len(self.dataset))

        self.current_rec = self.dataset[idx]
        self.step_idx = 0
        return self.current_rec["steps"][0]["s_t"], {}

    def step(self, action):
        step_data = self.current_rec["steps"][self.step_idx]
        meta = self.current_rec["metadata"]
        s_t = step_data["s_t"]

        delta_f_action = float(np.clip(action[0], -5.0, 5.0))
        bw_act_norm = float(np.clip(action[1], -5.0, 5.0))
        bw_action_hz = 70.0 + 12.0 * bw_act_norm
        class_logit = float(np.clip(action[2], -5.0, 5.0))
        pred_is_surface = 1 if class_logit > 0.0 else 0

        # ------------------------------------------------------------------
        # A. PHYSICS-INFORMED REWARD (R_t) USING REAL WATERSHED + PLL METRICS
        # ------------------------------------------------------------------
        plv_r = float(step_data["plv_r"])
        sigma_f_hz = float(step_data["inst_freq_std"])
        bw_sliding_hz = float(step_data["bw_mean"])
        tib_val = float(step_data["tib"])

        carson_pll_hz = 2.0 * (sigma_f_hz / max(0.20, plv_r) + meta["fw_est"])
        target_bw_hz = float(np.clip(0.75 * bw_sliding_hz + 0.25 * carson_pll_hz, 12.0, 125.0))
        bw_fit_reward = float(np.exp(-0.04 * abs(bw_action_hz - target_bw_hz)))

        phys_surface_score = float(s_t[3]) - 0.35 * float(s_t[6]) - 0.25 * float(s_t[0])
        physics_alignment = 1.0 if (
            (phys_surface_score >= 0.0 and pred_is_surface == 1)
            or (phys_surface_score < 0.0 and pred_is_surface == 0)
        ) else -0.5

        y_sign = 1.0 if meta["is_surface"] == 1 else -1.0
        margin_reward = 0.5 * float(np.tanh(y_sign * class_logit))
        class_reward = (2.0 if pred_is_surface == meta["is_surface"] else -2.0) + margin_reward

        reward = float(bw_fit_reward + physics_alignment + class_reward)

        # ------------------------------------------------------------------
        # B. CPO HARD PHYSICAL CONSTRAINTS (Cost C_t <= d)
        # ------------------------------------------------------------------
        c_sound = 1500.0
        max_doppler_shift = (2.0 * max(150.0, meta["f0_true"]) / c_sound) * np.sin(meta["theta_g"]) * meta["max_vz"] + 2.2
        kinematic_violation = 1.0 if abs(delta_f_action) > max_doppler_shift else 0.0

        coherence_violation = 1.0 if (
            (bw_sliding_hz < 45.0 and bw_action_hz > 68.0)
            or (bw_sliding_hz > 75.0 and bw_action_hz < 35.0)
        ) else 0.0

        cost = float(max(kinematic_violation, coherence_violation))

        self.step_idx += 1
        terminated = self.step_idx >= len(self.current_rec["steps"])
        next_state = (
            self.current_rec["steps"][self.step_idx]["s_t"]
            if not terminated else np.zeros(8, dtype=np.float32)
        )

        info = {
            "cost": cost,
            "correct": int(pred_is_surface == meta["is_surface"]),
            "dataset_name": meta["dataset_name"],
            "bw_action_hz": bw_action_hz,
            "target_bw_hz": target_bw_hz,
            "plv_r": plv_r,
            "tib": tib_val,
            "freq_verif_err": float(step_data["freq_verif_err"]),
        }
        return next_state, reward, terminated, False, info

