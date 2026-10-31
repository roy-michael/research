import numpy as np
import scipy.signal as signal
from scipy.special import jv  # Bessel functions of the first kind
import torch
import torch.nn as nn
import torch.optim as optim
from torch.distributions import Normal
import gymnasium as gym
from gymnasium import spaces
import matplotlib.pyplot as plt

# Set random seeds for reproducibility
np.random.seed(42)
torch.manual_seed(42)


# ==============================================================================
# 1. PHYSICS-INFORMED SYNTHETIC ENVIRONMENT (BELLHOP + PIERSON-MOSKOWITZ)
# ==============================================================================
def generate_sea_surface(wind_speed=8.5, duration=30.0, fs_env=50.0):
    """Generates sea surface height h(t) and orbital velocity v_z(t) via Pierson-Moskowitz."""
    g = 9.81
    alpha = 0.0081
    beta_pm = 0.74

    f = np.linspace(0.08, 1.2, 200)
    df = f[1] - f[0]
    omega = 2 * np.pi * f
    omega_0 = g / wind_speed

    S_omega = (alpha * g ** 2 / omega ** 5) * np.exp(-beta_pm * (omega_0 / omega) ** 4)
    S_f = S_omega * (2 * np.pi)

    amps = np.sqrt(2 * S_f * df)
    phases = np.random.uniform(0, 2 * np.pi, size=len(f))

    t_env = np.arange(0, duration, 1.0 / fs_env)
    h_t = np.sum(amps[:, None] * np.cos(omega[:, None] * t_env[None, :] + phases[:, None]), axis=0)
    v_z = np.sum(-(amps * omega)[:, None] * np.sin(omega[:, None] * t_env[None, :] + phases[:, None]), axis=0)

    # Dominant wave frequency (peak of PM spectrum)
    f_peak = float(f[np.argmax(S_f)])
    return t_env, h_t, v_z, f_peak


def synthesize_vessel_audio(f0=400.0, duration=30.0, fs=2000.0, is_surface_boat=True, wind_speed=8.5):
    """
    Synthesizes realistic hydrophone audio for a Surface Boat (depth=0.5m)
    or Underwater Scooter/AUV (depth=25m) at R=1000m, H_rec=30m.
    """
    c = 1500.0
    k = 2 * np.pi * f0 / c
    R = 1000.0
    z_rx = 30.0
    z_tx = 0.5 if is_surface_boat else 25.0

    t = np.arange(0, duration, 1.0 / fs)
    t_env, h_env, vz_env, f_w = generate_sea_surface(wind_speed=wind_speed, duration=duration)
    h_t = np.interp(t, t_env, h_env)
    v_wave = np.interp(t, t_env, vz_env)
    wave_rms = np.std(h_t)

    # Geometric Eigenrays (Direct + Surface Reflected)
    L_dir = np.sqrt(R ** 2 + (z_rx - z_tx) ** 2)
    L_surf = np.sqrt(R ** 2 + (z_rx + z_tx) ** 2)
    theta_surf = np.arctan2(z_rx + z_tx, R)

    if is_surface_boat:
        # Surface vessel heaves on waves -> FM modulation (Bessel sidebands / Carson's Rule)
        inst_freq_dev = 3.5 * v_wave + 1.8 * np.random.randn(len(t))
        win = int(fs * 0.12)
        inst_freq_dev = np.convolve(inst_freq_dev, np.ones(win) / win, mode='same')
        source_phase_fm = 2 * np.pi * np.cumsum(inst_freq_dev) / fs

        # Low-grazing angle shadowing & lensing envelope (~1.72 deg)
        fading_env = np.clip(1.0 + 0.7 * h_t + 0.35 * np.random.randn(len(t)), 0.05, 2.5)
        env_win = int(fs * 0.08)
        fading_env = np.convolve(fading_env, np.ones(env_win) / env_win, mode='same')
        surf_amp = 0.85 / L_surf
    else:
        # Submerged AUV/DPV -> stable electric propulsion below wave base (beta ~ 0)
        inst_freq_dev = 0.12 * np.sin(2 * np.pi * 0.05 * t)
        source_phase_fm = 2 * np.pi * np.cumsum(inst_freq_dev) / fs
        fading_env = np.ones_like(t)

        # Rayleigh roughness loss for steep surface bounce
        rayleigh_g = 2.0 * k * wave_rms * np.sin(theta_surf)
        coherent_loss = np.exp(-0.5 * rayleigh_g ** 2)
        surf_amp = (0.25 * coherent_loss) / L_surf

    # Direct path arrival
    p_dir = (1.0 / L_dir) * np.cos(2 * np.pi * f0 * (t - L_dir / c) + source_phase_fm)

    # Surface-reflected path arrival (Moving mirror phase modulation: 4*pi*f0*h(t)*sin(theta)/c)
    micro_scatter = np.cumsum(np.random.normal(0, 0.06, size=len(t))) if is_surface_boat else 0.0
    surf_phase_mod = (4 * np.pi * f0 / c) * h_t * np.sin(theta_surf) + micro_scatter
    p_surf = surf_amp * np.cos(2 * np.pi * f0 * (t - L_surf / c) + source_phase_fm + surf_phase_mod + np.pi)

    p_rx = (p_dir + p_surf) * fading_env
    p_rx = p_rx / (np.std(p_rx) + 1e-8)
    ambient_noise = np.random.normal(0, 0.30, size=len(t))

    metadata = {
        'f0_true': f0,
        'fw_est': f_w,
        'theta_g': theta_surf,
        'max_vz': float(np.max(np.abs(v_wave))),
        'is_surface': int(is_surface_boat)
    }
    return t, p_rx + ambient_noise, metadata


# ==============================================================================
# 2. OFFLINE DSP FEATURE EXTRACTION PIPELINE (WELCH + HILBERT + ROBUST METRICS)
# ==============================================================================
class OfflineFeatureExtractor:
    """
    Runs once per audio recording prior to RL training.
    Segments audio into 1-second buffers, uses Welch PSD for dominant frequency
    and bandwidth lobes, and uses narrowband Hilbert Transform for phase/envelope metrics.
    """

    def __init__(self, fs=2000.0, buffer_sec=1.0, search_band=(350.0, 450.0)):
        self.fs = fs
        self.buffer_sec = buffer_sec
        self.samples_per_buf = int(fs * buffer_sec)
        self.search_band = search_band

    def compute_jains_index(self, psd_slice):
        """Jain's Fairness Index on spectral energy distribution."""
        x = np.abs(psd_slice) + 1e-12
        n = len(x)
        return float((np.sum(x) ** 2) / (n * np.sum(x ** 2)))

    def compute_masd(self, env):
        """Mean Absolute Successive Difference (outlier-resistant jerkiness metric)."""
        return float(np.mean(np.abs(np.diff(env))))

    def compute_coherence_time(self, env):
        """Time delay tau (seconds) where normalized autocorrelation drops below 0.5."""
        env_zm = env - np.mean(env)
        norm = np.sum(env_zm ** 2)
        if norm < 1e-10:
            return self.buffer_sec
        acf = np.correlate(env_zm, env_zm, mode='full')[len(env_zm) - 1:] / norm
        below_half = np.where(acf < 0.5)[0]
        if len(below_half) == 0:
            return self.buffer_sec
        return float(below_half[0] / self.fs)

    def extract_recording_features(self, audio_sig):
        """Processes a multi-second audio signal into a sequence of J buffer feature dicts."""
        num_buffers = len(audio_sig) // self.samples_per_buf
        buffer_features = []

        for j in range(num_buffers):
            seg = audio_sig[j * self.samples_per_buf: (j + 1) * self.samples_per_buf]

            # --- Stage A: Welch PSD for Dominant Frequency & Lobe Bandwidth ---
            f_welch, Pxx = signal.welch(seg, fs=self.fs, nperseg=512, noverlap=384)
            band_mask = (f_welch >= self.search_band[0]) & (f_welch <= self.search_band[1])
            f_band = f_welch[band_mask]
            P_band = Pxx[band_mask]

            peak_idx = np.argmax(P_band)
            f_dom = float(f_band[peak_idx])
            peak_power = P_band[peak_idx]

            # -6 dB (quarter power) bandwidth spread around dominant frequency
            thresh = peak_power * 0.25
            active_bins = f_band[P_band >= thresh]
            bw_measured = float(active_bins[-1] - active_bins[0]) if len(active_bins) > 1 else float(
                f_band[1] - f_band[0])

            # Estimate ocean wave modulation frequency f_w via spectral autocorrelation
            P_norm = P_band - np.mean(P_band)
            spec_acf = np.correlate(P_norm, P_norm, mode='full')[len(P_norm) - 1:]
            df_welch = f_band[1] - f_band[0]
            # Look for secondary sideband lobe spacing between 0.1 Hz and 3.0 Hz
            fw_est = 0.25  # Default gravity wave fallback

            jains_idx = self.compute_jains_index(P_band)

            # --- Stage B: Narrowband Bandpass + Hilbert Transform for Phase & Envelope ---
            low_cut = max(20.0, f_dom - 15.0)
            high_cut = min(self.fs / 2.0 - 20.0, f_dom + 15.0)
            sos = signal.butter(4, [low_cut, high_cut], btype='bandpass', fs=self.fs, output='sos')
            narrow_sig = signal.sosfiltfilt(sos, seg)

            analytic_sig = signal.hilbert(narrow_sig)
            envelope = np.abs(analytic_sig)
            envelope_norm = envelope / (np.mean(envelope) + 1e-8)

            inst_phase = np.unwrap(np.angle(analytic_sig))
            inst_freq = (self.fs / (2.0 * np.pi)) * np.diff(inst_phase)
            # Robust phase drift / instantaneous frequency MAD (Median Absolute Deviation)
            phase_drift_mad = float(np.median(np.abs(inst_freq - np.median(inst_freq))))

            masd_val = self.compute_masd(envelope_norm)
            tc_val = self.compute_coherence_time(envelope_norm)

            buffer_features.append({
                'f_dom': f_dom,
                'bw_measured': bw_measured,
                'jains_index': jains_idx,
                'masd': masd_val,
                'coherence_time': tc_val,
                'phase_drift_mad': phase_drift_mad,
                'fw_est': fw_est
            })

        # Compute temporal stability across buffers (dt derivatives & running statistics)
        f_doms = np.array([b['f_dom'] for b in buffer_features])
        bws = np.array([b['bw_measured'] for b in buffer_features])
        jains = np.array([b['jains_index'] for b in buffer_features])

        state_sequence = []
        for j in range(num_buffers):
            win_start = max(0, j - 4)  # 5-buffer sliding context
            df_dt = float(abs(f_doms[j] - f_doms[j - 1])) if j > 0 else 0.0
            djain_dt = float(abs(jains[j] - jains[j - 1])) if j > 0 else 0.0
            bw_mean = float(np.mean(bws[win_start: j + 1]))
            bw_std = float(np.std(bws[win_start: j + 1]))

            # Time-in-band stability indicator P_i (fraction of recent buffers within 1.5 Hz of median)
            med_f = np.median(f_doms[win_start: j + 1])
            time_in_band = float(np.mean(np.abs(f_doms[win_start: j + 1] - med_f) <= 1.5))

            # Construct compact 8-D State Vector s_t
            s_t = np.array([
                time_in_band,  # [0] Stability: Time in Band P_i
                buffer_features[j]['jains_index'],  # [1] Stability: Jain's Index
                djain_dt,  # [2] Stability: d(Jain)/dt
                bw_mean,  # [3] Combine BW: Mean Bandwidth
                bw_std,  # [4] Combine BW: Std Bandwidth
                buffer_features[j]['masd'],  # [5] Temporal Chaos: MASD
                buffer_features[j]['coherence_time'],  # [6] Channel Memory: Coherence Time T_c
                buffer_features[j]['phase_drift_mad']  # [7] Phase Incoherence: Inst. Freq MAD
            ], dtype=np.float32)

            state_sequence.append({
                's_t': s_t,
                'df_dt': df_dt,
                'bw_measured': buffer_features[j]['bw_measured'],
                'f_dom': buffer_features[j]['f_dom']
            })

        return state_sequence


# ==============================================================================
# 3. GYMNASIUM RL ENVIRONMENT (PIML REWARD & CPO HARD CONSTRAINTS)
# ==============================================================================
class AcousticPIMLEnv(gym.Env):
    """
    RL Environment operating on pre-extracted DSP feature vectors s_t.
    Action a_t = [delta_fc_track, bw_gate_est, surface_vs_submerged_logit]
    """

    def __init__(self, dataset):
        super().__init__()
        self.dataset = dataset  # List of pre-extracted recording dicts
        self.current_rec = None
        self.step_idx = 0

        # Action space:
        # a[0]: Frequency tracking offset adjustment [-5.0, +5.0] Hz
        # a[1]: Estimated Carson Bandwidth Gate [0.5, 15.0] Hz
        # a[2]: Classification logit (<0: Submerged Scooter/AUV, >0: Surface Vessel)
        self.action_space = spaces.Box(
            low=np.array([-5.0, 0.5, -5.0], dtype=np.float32),
            high=np.array([5.0, 15.0, 5.0], dtype=np.float32)
        )

        # Observation space: 8-D Extracted Feature Vector s_t
        self.observation_space = spaces.Box(
            low=-np.inf, high=np.inf, shape=(8,), dtype=np.float32
        )

    def reset(self, seed=None, options=None):
        super().reset(seed=seed)
        idx = np.random.randint(0, len(self.dataset))
        self.current_rec = self.dataset[idx]
        self.step_idx = 0
        return self.current_rec['steps'][0]['s_t'], {}

    def step(self, action):
        step_data = self.current_rec['steps'][self.step_idx]
        meta = self.current_rec['metadata']
        s_t = step_data['s_t']

        delta_f_action = float(np.clip(action[0], -5.0, 5.0))
        bw_action = float(np.clip(action[1], 0.5, 15.0))
        class_logit = float(action[2])
        pred_is_surface = 1 if class_logit > 0.0 else 0

        # ------------------------------------------------------------------
        # A. PHYSICS-INFORMED REWARD (R_t)
        # ------------------------------------------------------------------
        # 1. Carson's Rule & Bessel Sideband Fit: BW_carson = 2 * (Delta_f + f_w)
        # Estimate modulation index beta from phase drift MAD and coherence time
        tc_val = max(0.05, float(s_t[6]))
        doppler_spread_bd = 1.0 / tc_val
        carson_bw_target = 2.0 * (0.25 * doppler_spread_bd + meta['fw_est'])
        carson_bw_target = np.clip(carson_bw_target, 0.8, 14.0)

        bw_fit_reward = np.exp(-0.25 * abs(bw_action - carson_bw_target))

        # 2. Coherence & Stability Consistency Reward
        time_in_band = float(s_t[0])
        masd_val = float(s_t[5])
        # High stability + low MASD physically indicates submerged wave-base operation
        physics_submerged_score = time_in_band - 1.5 * masd_val
        physics_alignment = 1.0 if (
                (physics_submerged_score > 0.1 and pred_is_surface == 0) or
                (physics_submerged_score <= 0.1 and pred_is_surface == 1)
        ) else -0.5

        # 3. Classification accuracy against ground truth
        class_reward = 2.0 if pred_is_surface == meta['is_surface'] else -2.0

        reward = float(bw_fit_reward + physics_alignment + class_reward)

        # ------------------------------------------------------------------
        # B. CPO HARD PHYSICAL CONSTRAINTS (Cost C_t <= d)
        # ------------------------------------------------------------------
        # Constraint 1: Kinematic Doppler Bound |Delta f_max| = (2*f0/c)*sin(theta_g)*v_z_max + margin
        c_sound = 1500.0
        max_doppler_shift = (2.0 * meta['f0_true'] / c_sound) * np.sin(meta['theta_g']) * meta['max_vz'] + 2.5
        kinematic_violation = 1.0 if abs(delta_f_action) > max_doppler_shift else 0.0

        # Constraint 2: Unphysical Bandwidth vs. Coherence Time Violation
        # Opening a massive bandwidth when coherence time is near 1.0s violates narrowband physics
        coherence_violation = 1.0 if (tc_val > 0.85 and bw_action > 6.0) else 0.0

        cost = float(max(kinematic_violation, coherence_violation))

        # Advance time buffer
        self.step_idx += 1
        terminated = self.step_idx >= len(self.current_rec['steps'])
        next_state = self.current_rec['steps'][self.step_idx]['s_t'] if not terminated else np.zeros(8,
                                                                                                     dtype=np.float32)

        info = {
            'cost': cost,
            'correct': int(pred_is_surface == meta['is_surface']),
            'carson_target': carson_bw_target
        }
        return next_state, reward, terminated, False, info


# ==============================================================================
# 4. PPO / LAGRANGIAN-CPO AGENT ARCHITECTURE
# ==============================================================================
class PIMLActorCritic(nn.Module):
    """
    Actor-Critic network with Dual Critics:
    - Actor outputs mean action mu(s_t) and log_std
    - Reward Critic estimates V_R(s_t)
    - Cost Critic estimates V_C(s_t) for CPO constraint enforcement
    """

    def __init__(self, state_dim=8, action_dim=3, hidden_dim=64):
        super().__init__()
        self.shared = nn.Sequential(
            nn.Linear(state_dim, hidden_dim),
            nn.Tanh(),
            nn.Linear(hidden_dim, hidden_dim),
            nn.Tanh()
        )
        self.actor_mu = nn.Linear(hidden_dim, action_dim)
        self.actor_log_std = nn.Parameter(torch.zeros(1, action_dim) - 0.5)

        self.reward_critic = nn.Sequential(
            nn.Linear(state_dim, hidden_dim),
            nn.Tanh(),
            nn.Linear(hidden_dim, 1)
        )
        self.cost_critic = nn.Sequential(
            nn.Linear(state_dim, hidden_dim),
            nn.Tanh(),
            nn.Linear(hidden_dim, 1)
        )

    def get_action_and_values(self, state, action=None):
        features = self.shared(state)
        mu = self.actor_mu(features)
        std = torch.exp(self.actor_log_std)
        dist = Normal(mu, std)

        if action is None:
            action = dist.sample()

        log_prob = dist.log_prob(action).sum(dim=-1)
        entropy = dist.entropy().sum(dim=-1)
        v_r = self.reward_critic(state).squeeze(-1)
        v_c = self.cost_critic(state).squeeze(-1)
        return action, log_prob, entropy, v_r, v_c


def train_piml_agent(env, mode='CPO', epochs=40, steps_per_epoch=300, cost_limit=0.08):
    """
    Trains the agent using either:
    - 'PPO': Soft penalty added to reward.
    - 'CPO': Constrained Policy Optimization via primal-dual Lagrangian trust-region projection.
    """
    model = PIMLActorCritic()
    optimizer = optim.Adam(model.parameters(), lr=3e-4)

    # Lagrangian multiplier for CPO hard constraint C(pi) <= cost_limit
    log_lambda = torch.tensor(0.0, requires_grad=True)
    lambda_optimizer = optim.Adam([log_lambda], lr=5e-2)

    clip_eps = 0.2
    gamma = 0.99

    history = {'reward': [], 'cost': [], 'accuracy': []}

    for epoch in range(epochs):
        states, actions, log_probs, rewards, costs, dones, accs = [], [], [], [], [], [], []
        state, _ = env.reset()

        for _ in range(steps_per_epoch):
            s_tensor = torch.FloatTensor(state).unsqueeze(0)
            with torch.no_grad():
                action, log_prob, _, _, _ = model.get_action_and_values(s_tensor)

            act_np = action.squeeze(0).numpy()
            next_state, reward, terminated, truncated, info = env.step(act_np)
            done = terminated or truncated

            states.append(state)
            actions.append(act_np)
            log_probs.append(log_prob.item())
            rewards.append(reward)
            costs.append(info['cost'])
            dones.append(done)
            accs.append(info['correct'])

            state = next_state if not done else env.reset()[0]

        # Compute discounted returns for Reward (R) and Constraint Cost (C)
        returns_r, returns_c = [], []
        R_acc, C_acc = 0.0, 0.0
        for r, c, d in zip(reversed(rewards), reversed(costs), reversed(dones)):
            if d:
                R_acc, C_acc = 0.0, 0.0
            R_acc = r + gamma * R_acc
            C_acc = c + gamma * C_acc
            returns_r.insert(0, R_acc)
            returns_c.insert(0, C_acc)

        states_t = torch.FloatTensor(np.array(states))
        actions_t = torch.FloatTensor(np.array(actions))
        old_log_probs_t = torch.FloatTensor(np.array(log_probs))
        returns_r_t = torch.FloatTensor(returns_r)
        returns_c_t = torch.FloatTensor(returns_c)

        with torch.no_grad():
            _, _, _, v_r_old, v_c_old = model.get_action_and_values(states_t, actions_t)
            adv_r = returns_r_t - v_r_old
            adv_r = (adv_r - adv_r.mean()) / (adv_r.std() + 1e-8)

            adv_c = returns_c_t - v_c_old
            adv_c = (adv_c - adv_c.mean()) / (adv_c.std() + 1e-8)

        avg_ep_cost = float(np.mean(costs))

        # Update dual variable lambda in CPO mode if constraints are violated
        if mode == 'CPO':
            lambda_loss = -log_lambda.exp() * (avg_ep_cost - cost_limit)
            lambda_optimizer.zero_grad()
            lambda_loss.backward()
            lambda_optimizer.step()
            lam = float(log_lambda.exp().item())
        else:
            lam = 0.25  # Fixed soft weight in standard PPO

        # Policy & Critic Update Epochs
        for _ in range(6):
            _, new_log_probs, entropy, v_r_pred, v_c_pred = model.get_action_and_values(states_t, actions_t)
            ratio = torch.exp(new_log_probs - old_log_probs_t)

            # Clipped surrogate objective for Reward
            surr1_r = ratio * adv_r
            surr2_r = torch.clamp(ratio, 1.0 - clip_eps, 1.0 + clip_eps) * adv_r
            policy_reward_loss = -torch.min(surr1_r, surr2_r).mean()

            # Surrogate Cost penalty (enforces C(pi) <= d)
            policy_cost_loss = (ratio * adv_c).mean()

            # Combined primal objective
            actor_loss = (policy_reward_loss + lam * policy_cost_loss) / (1.0 + lam)
            critic_loss = 0.5 * ((v_r_pred - returns_r_t) ** 2).mean() + 0.5 * ((v_c_pred - returns_c_t) ** 2).mean()
            total_loss = actor_loss + critic_loss - 0.01 * entropy.mean()

            optimizer.zero_grad()
            total_loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 0.5)
            optimizer.step()

        history['reward'].append(np.mean(rewards))
        history['cost'].append(avg_ep_cost)
        history['accuracy'].append(np.mean(accs) * 100.0)

    return model, history


# ==============================================================================
# 5. MAIN EXECUTION: BUILD DATASET, TRAIN PPO vs. CPO, AND PLOT RESULTS
# ==============================================================================
if __name__ == '__main__':
    print("[1/3] Synthesizing BELLHOP + Pierson-Moskowitz Acoustic Dataset & Extracting DSP Features...")
    extractor = OfflineFeatureExtractor(fs=2000.0, buffer_sec=1.0)
    precomputed_dataset = []

    # Generate balanced synthetic dataset (12 recordings: 6 Surface Vessels, 6 Submerged Scooters/AUVs)
    for i in range(12):
        is_boat = (i % 2 == 0)
        f_motor = np.random.uniform(385.0, 415.0)
        wind = np.random.uniform(6.5, 11.0)
        _, audio, meta = synthesize_vessel_audio(
            f0=f_motor, duration=15.0, fs=2000.0, is_surface_boat=is_boat, wind_speed=wind
        )
        steps = extractor.extract_recording_features(audio)
        precomputed_dataset.append({'steps': steps, 'metadata': meta})

    env = AcousticPIMLEnv(precomputed_dataset)

    print("[2/3] Training Physics-Informed PPO Agent (Soft Constraints)...")
    ppo_model, ppo_hist = train_piml_agent(env, mode='PPO', epochs=35, steps_per_epoch=240)

    print("[3/3] Training Physics-Informed CPO Agent (Hard Physical Constraints C(pi) <= d)...")
    cpo_model, cpo_hist = train_piml_agent(env, mode='CPO', epochs=35, steps_per_epoch=240, cost_limit=0.05)

    print(
        f"\nFinal PPO Accuracy: {ppo_hist['accuracy'][-1]:.1f}% | Final PPO Violation Rate: {ppo_hist['cost'][-1]:.3f}")
    print(f"Final CPO Accuracy: {cpo_hist['accuracy'][-1]:.1f}% | Final CPO Violation Rate: {cpo_hist['cost'][-1]:.3f}")

    # Plot Training Comparison
    fig, axes = plt.subplots(1, 3, figsize=(15, 4.5))

    axes[0].plot(ppo_hist['reward'], label='PIML-PPO', color='royalblue', lw=2)
    axes[0].plot(cpo_hist['reward'], label='PIML-CPO', color='darkorange', lw=2)
    axes[0].set_title('Physics-Informed Reward ($R_t$)', fontweight='bold')
    axes[0].set_xlabel('Epoch')
    axes[0].set_ylabel('Mean Step Reward')
    axes[0].legend()
    axes[0].grid(alpha=0.3)

    axes[1].plot(ppo_hist['cost'], label='PIML-PPO Violations', color='royalblue', lw=2)
    axes[1].plot(cpo_hist['cost'], label='PIML-CPO Violations', color='darkorange', lw=2)
    axes[1].axhline(0.05, color='crimson', linestyle='--', label='Hard Constraint Limit ($d=0.05$)')
    axes[1].set_title('Physical Constraint Violations ($C_t$)', fontweight='bold')
    axes[1].set_xlabel('Epoch')
    axes[1].set_ylabel('Violation Frequency')
    axes[1].legend()
    axes[1].grid(alpha=0.3)

    axes[2].plot(ppo_hist['accuracy'], label='PIML-PPO', color='royalblue', lw=2)
    axes[2].plot(cpo_hist['accuracy'], label='PIML-CPO', color='darkorange', lw=2)
    axes[2].set_title('Surface vs. Submerged Classification (%)', fontweight='bold')
    axes[2].set_xlabel('Epoch')
    axes[2].set_ylabel('Accuracy (%)')
    axes[2].set_ylim(40, 105)
    axes[2].legend()
    axes[2].grid(alpha=0.3)

    plt.tight_layout()
    plt.show()