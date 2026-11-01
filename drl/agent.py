"""
Neural network architecture (`PIMLActorCritic`), PPO / primal-dual Lagrangian CPO
training loop (`train_piml_agent`), and deterministic dataset evaluator (`evaluate_agent_by_dataset`).
"""

from typing import Dict, Any, Tuple
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.distributions import Normal

from config import TrainConfig
from env import AcousticPIMLEnv


class PIMLActorCritic(nn.Module):
    """
    Actor-Critic network with Dual Critics:
    - Actor outputs mean action mu(s_t) and log_std
    - Reward Critic estimates V_R(s_t)
    - Cost Critic estimates V_C(s_t) for CPO constraint enforcement
    """

    def __init__(self, state_dim: int = 8, action_dim: int = 3, hidden_dim: int = 64):
        super().__init__()
        self.shared = nn.Sequential(
            nn.Linear(state_dim, hidden_dim),
            nn.Tanh(),
            nn.Linear(hidden_dim, hidden_dim),
            nn.Tanh(),
        )
        self.actor_mu = nn.Linear(hidden_dim, action_dim)
        nn.init.zeros_(self.actor_mu.bias)
        self.actor_log_std = nn.Parameter(torch.zeros(1, action_dim) - 0.35)

        self.reward_critic = nn.Sequential(
            nn.Linear(state_dim, hidden_dim),
            nn.Tanh(),
            nn.Linear(hidden_dim, 1),
        )
        self.cost_critic = nn.Sequential(
            nn.Linear(state_dim, hidden_dim),
            nn.Tanh(),
            nn.Linear(hidden_dim, 1),
        )

    def get_action_and_values(self, state: torch.Tensor, action: torch.Tensor = None,
                              deterministic: bool = False):
        features = self.shared(state)
        mu = self.actor_mu(features)
        std = torch.exp(self.actor_log_std)
        dist = Normal(mu, std)

        if action is None:
            action = mu if deterministic else dist.sample()

        log_prob = dist.log_prob(action).sum(dim=-1)
        entropy = dist.entropy().sum(dim=-1)
        v_r = self.reward_critic(state).squeeze(-1)
        v_c = self.cost_critic(state).squeeze(-1)
        return action, log_prob, entropy, v_r, v_c


def train_piml_agent(
    env: AcousticPIMLEnv,
    mode: str = "CPO",
    train_cfg: TrainConfig = None,
) -> Tuple[PIMLActorCritic, Dict[str, list]]:
    """
    Trains the agent using either:
    - 'PPO': Fixed soft penalty weight on physical constraint violations.
    - 'CPO': Constrained Policy Optimization via primal-dual Lagrangian multiplier optimization.
    """
    if train_cfg is None:
        train_cfg = TrainConfig()

    np.random.seed(train_cfg.seed)
    torch.manual_seed(train_cfg.seed)

    model = PIMLActorCritic(
        state_dim=train_cfg.state_dim,
        action_dim=train_cfg.action_dim,
        hidden_dim=train_cfg.hidden_dim,
    )
    optimizer = optim.Adam(model.parameters(), lr=train_cfg.lr_actor_critic)

    log_lambda = torch.tensor(-0.5, requires_grad=True)
    lambda_optimizer = optim.Adam([log_lambda], lr=train_cfg.lr_lambda)

    history = {"reward": [], "cost": [], "accuracy": []}

    for _ in range(train_cfg.epochs):
        states, actions, log_probs, rewards, costs, dones, accs = [], [], [], [], [], [], []
        state, _ = env.reset()

        for _ in range(train_cfg.steps_per_epoch):
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
            costs.append(info["cost"])
            dones.append(done)
            accs.append(info["correct"])

            state = next_state if not done else env.reset()[0]

        returns_r, returns_c = [], []
        r_acc, c_acc = 0.0, 0.0
        for r, c, d in zip(reversed(rewards), reversed(costs), reversed(dones)):
            if d:
                r_acc, c_acc = 0.0, 0.0
            r_acc = r + train_cfg.gamma * r_acc
            c_acc = c + train_cfg.gamma * c_acc
            returns_r.insert(0, r_acc)
            returns_c.insert(0, c_acc)

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

        if mode.upper() == "CPO":
            lambda_loss = -log_lambda.exp() * (avg_ep_cost - train_cfg.cost_limit)
            lambda_optimizer.zero_grad()
            lambda_loss.backward()
            lambda_optimizer.step()
            with torch.no_grad():
                log_lambda.clamp_(-4.0, 3.0)
            lam = float(log_lambda.exp().item())
        else:
            lam = train_cfg.ppo_soft_lambda

        for _ in range(train_cfg.update_iters):
            _, new_log_probs, entropy, v_r_pred, v_c_pred = model.get_action_and_values(states_t, actions_t)
            ratio = torch.exp(new_log_probs - old_log_probs_t)

            surr1_r = ratio * adv_r
            surr2_r = torch.clamp(ratio, 1.0 - train_cfg.clip_eps, 1.0 + train_cfg.clip_eps) * adv_r
            policy_reward_loss = -torch.min(surr1_r, surr2_r).mean()

            policy_cost_loss = (ratio * adv_c).mean()

            actor_loss = (policy_reward_loss + lam * policy_cost_loss) / (1.0 + lam)
            critic_loss = 0.5 * ((v_r_pred - returns_r_t) ** 2).mean() + 0.5 * ((v_c_pred - returns_c_t) ** 2).mean()
            total_loss = actor_loss + critic_loss - train_cfg.entropy_coef * entropy.mean()

            optimizer.zero_grad()
            total_loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), train_cfg.max_grad_norm)
            optimizer.step()

        history["reward"].append(float(np.mean(rewards)))
        history["cost"].append(avg_ep_cost)
        history["accuracy"].append(float(np.mean(accs) * 100.0))

    return model, history


def evaluate_agent_by_dataset(env: AcousticPIMLEnv, model: PIMLActorCritic) -> Dict[str, Dict[str, float]]:
    """Evaluates a trained policy deterministically across every recording in `env`."""
    per_ds: Dict[str, Dict[str, list]] = {}
    for rec_idx, rec in enumerate(env.dataset):
        ds_name = rec["metadata"]["dataset_name"]
        if ds_name not in per_ds:
            per_ds[ds_name] = {
                "correct": [],
                "cost": [],
                "reward": [],
                "bw_gate_hz": [],
                "target_bw_hz": [],
            }

        state, _ = env.reset(options={"rec_idx": rec_idx})
        done = False
        while not done:
            s_tensor = torch.FloatTensor(state).unsqueeze(0)
            with torch.no_grad():
                action, _, _, _, _ = model.get_action_and_values(s_tensor, deterministic=True)
            act_np = action.squeeze(0).numpy()
            state, reward, terminated, truncated, info = env.step(act_np)
            done = terminated or truncated

            per_ds[ds_name]["correct"].append(info["correct"])
            per_ds[ds_name]["cost"].append(info["cost"])
            per_ds[ds_name]["reward"].append(reward)
            per_ds[ds_name]["bw_gate_hz"].append(info["bw_action_hz"])
            per_ds[ds_name]["target_bw_hz"].append(info["target_bw_hz"])

    summary: Dict[str, Dict[str, float]] = {}
    for ds_name, vals in per_ds.items():
        summary[ds_name] = {
            "accuracy": float(np.mean(vals["correct"]) * 100.0),
            "cost": float(np.mean(vals["cost"])),
            "reward": float(np.mean(vals["reward"])),
            "bw_gate_hz": float(np.mean(vals["bw_gate_hz"])),
            "target_bw_hz": float(np.mean(vals["target_bw_hz"])),
        }
    return summary

