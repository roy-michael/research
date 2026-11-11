"""
Gymnasium Reinforcement Learning environment (`drl.rl.env.AcousticPIMLEnv`) with
physics-informed Multiscale TiB & Jain's Fairness rewards and Constrained Policy Optimization (CPO) costs.
"""

from typing import List, Dict, Any
import numpy as np
import gymnasium as gym
from gymnasium import spaces

from config import (
    CLASS_AMBIENT,
    CLASS_UNDERWATER,
    CLASS_SURFACE,
    CLASS_NAMES,
    NUM_CLASSES,
)


class AcousticPIMLEnv(gym.Env):
    r"""
    Gymnasium RL Environment operating on pre-extracted DSP, Multiscale TiB Scale-Uniformity Fairness,
    Digital PLL, and Net SNR feature vectors s_t for 3-Class acoustic classification:
      - Class 0: Ocean Ambient Noise (no boat, or target swallowed at low SNR)
      - Class 1: Underwater Scooter / DPV (narrow motor harmonic, phase locked, scale invariant TiB)
      - Class 2: Surface Vessel (cavitation, multipath spreading, negative TiB drift)

    Observation Space (9-D):
      [mu_tib, jain_tib, delta_tib, std_tib, bw_norm, masd_norm, plv_norm, fstd_norm, snr_norm]

    Action Space (5-D):
      [delta_f, bw_action_norm, logit_ambient, logit_underwater, logit_surface]
    """

    def __init__(
        self,
        dataset: List[Dict[str, Any]],
        balanced_sampling: bool = True,
        reward_mode: str = "tib_fairness",
    ):
        super().__init__()
        self.dataset = dataset
        self.balanced_sampling = balanced_sampling
        self.reward_mode = reward_mode

        self.class_indices = {
            c: [i for i, d in enumerate(dataset) if d["metadata"]["target_class"] == c]
            for c in range(NUM_CLASSES)
        }
        self.available_classes = [c for c, idxs in self.class_indices.items() if len(idxs) > 0]

        self.current_rec = None
        self.step_idx = 0

        # Action: [delta_f, bw_action_norm, logit_ambient, logit_underwater, logit_surface]
        self.action_space = spaces.Box(
            low=np.array([-5.0, -5.0, -5.0, -5.0, -5.0], dtype=np.float32),
            high=np.array([5.0, 5.0, 5.0, 5.0, 5.0], dtype=np.float32),
        )

        # Observation: 9 continuous physical features
        self.observation_space = spaces.Box(
            low=-np.inf, high=np.inf, shape=(9,), dtype=np.float32
        )

    def reset(self, seed=None, options=None):
        super().reset(seed=seed)
        if options and "rec_idx" in options:
            idx = options["rec_idx"]
        elif self.balanced_sampling and len(self.available_classes) > 1:
            chosen_cls = int(np.random.choice(self.available_classes))
            idx = int(np.random.choice(self.class_indices[chosen_cls]))
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

        class_logits = np.clip(np.array(action[2:5], dtype=np.float32), -5.0, 5.0)
        pred_class = int(np.argmax(class_logits))
        target_class = int(meta["target_class"])
        is_correct = int(pred_class == target_class)

        # Softmax probabilities over the 3 classes
        shift_logits = class_logits - np.max(class_logits)
        exp_l = np.exp(shift_logits)
        probs = exp_l / (np.sum(exp_l) + 1e-8)
        p_target = float(probs[target_class])

        plv_r = float(step_data["plv_r"])
        sigma_f_hz = float(step_data["inst_freq_std"])
        bw_sliding_hz = float(step_data["bw_mean"])
        tib_val = float(step_data["tib"])

        mu_tib = float(step_data["minute_mean_tib"])
        sigma_tib = float(step_data["minute_std_tib"])
        jain_tib = float(step_data["minute_fair_tib"])
        delta_tib = float(step_data["minute_delta_tib"])
        snr_peak_db = float(step_data.get("snr_peak", 10.0))

        # Bandwidth fit target depending on physical acoustic class
        if target_class == CLASS_AMBIENT:
            target_bw_hz = float(np.clip(bw_sliding_hz, 15.0, 35.0))
        elif target_class == CLASS_UNDERWATER:
            target_bw_hz = float(np.clip(bw_sliding_hz, 15.0, 42.0))
        else:  # CLASS_SURFACE
            scale_instability_hz = 65.0 * (
                (1.0 - jain_tib) * 4.5 + sigma_tib * 2.5 + max(0.0, -delta_tib) * 0.85
            )
            target_bw_hz = float(
                np.clip(
                    jain_tib * mu_tib * bw_sliding_hz + (1.0 - jain_tib * mu_tib) * (bw_sliding_hz + scale_instability_hz),
                    25.0,
                    125.0,
                )
            )

        bw_fit_reward = float(np.exp(-0.04 * abs(bw_action_hz - target_bw_hz)))

        # 3-Class Logit Margin Reward: z_target - max_{j != target} z_j
        other_logits = [float(class_logits[j]) for j in range(NUM_CLASSES) if j != target_class]
        margin = float(class_logits[target_class] - max(other_logits))
        margin_reward = 0.65 * float(np.tanh(margin))

        fairness_weight = float(np.clip(0.85 + 0.30 * jain_tib, 0.85, 1.15))
        class_reward = fairness_weight * (2.0 if is_correct else -2.0) + margin_reward

        # Physics-informed regime reward matching acoustic regime
        # Ambient: low SNR or broad low-coherence noise floor
        if pred_class == CLASS_AMBIENT:
            phys_ok = 1.0 if (snr_peak_db < 12.0 or (bw_sliding_hz < 45.0 and delta_tib > -0.15)) else -0.5
        elif pred_class == CLASS_UNDERWATER:
            # Underwater: narrow bandwidth, high Jain fairness, near-zero drift
            phys_ok = 1.0 if (bw_sliding_hz < 55.0 and delta_tib > -0.15 and jain_tib >= 0.90) else -0.5
        else:  # CLASS_SURFACE
            # Surface: high SNR (>=14 dB) with broad bandwidth cavitation (>=48 Hz) OR strong negative scale drift (<-0.18)
            phys_ok = 1.0 if (snr_peak_db >= 14.0 and (bw_sliding_hz >= 48.0 or delta_tib < -0.18)) else -0.5

        fairness_regime_reward = 1.0 * phys_ok
        reward = float(bw_fit_reward + fairness_regime_reward + class_reward)

        # Physical constraint costs
        c_sound = 1500.0
        max_doppler_shift = (2.0 * max(150.0, meta["f0_true"]) / c_sound) * np.sin(meta["theta_g"]) * meta["max_vz"] + 2.2
        kinematic_violation = 1.0 if abs(delta_f_action) > max_doppler_shift else 0.0

        coherence_violation = 1.0 if (
            ((jain_tib >= 0.98 and mu_tib >= 0.88 and bw_sliding_hz < 35.0) and bw_action_hz > 68.0)
            or (((jain_tib < 0.94 or delta_tib < -0.25) and bw_sliding_hz > 65.0) and bw_action_hz < 35.0)
            or (pred_class == CLASS_SURFACE and (bw_sliding_hz < 25.0 or snr_peak_db < 10.0) and delta_tib > -0.05 and jain_tib >= 0.98)
            or (pred_class == CLASS_UNDERWATER and bw_sliding_hz > 80.0 and delta_tib < -0.30)
        ) else 0.0

        cost = float(max(kinematic_violation, coherence_violation))

        self.step_idx += 1
        terminated = self.step_idx >= len(self.current_rec["steps"])
        next_state = (
            self.current_rec["steps"][self.step_idx]["s_t"]
            if not terminated else np.zeros(9, dtype=np.float32)
        )

        info = {
            "cost": cost,
            "correct": is_correct,
            "pred_class": pred_class,
            "target_class": target_class,
            "pred_class_name": CLASS_NAMES[pred_class],
            "target_class_name": meta["target_class_name"],
            "p_target": p_target,
            "probs": probs,
            "dataset_name": meta["dataset_name"],
            "bw_action_hz": bw_action_hz,
            "target_bw_hz": target_bw_hz,
            "bw_fit_reward": bw_fit_reward,
            "fairness_regime_reward": fairness_regime_reward,
            "plv_r": plv_r,
            "tib": tib_val,
            "minute_mean_tib": mu_tib,
            "minute_std_tib": sigma_tib,
            "minute_fair_tib": jain_tib,
            "minute_delta_tib": delta_tib,
            "snr_peak": snr_peak_db,
            "freq_verif_err": float(step_data["freq_verif_err"]),
        }
        return next_state, reward, terminated, False, info

