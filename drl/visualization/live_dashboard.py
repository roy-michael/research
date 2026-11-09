"""
Live interactive & streaming Matplotlib dashboard (`drl.visualization.live_dashboard`) for real-time
monitoring of the Physics-Informed DRL training and held-out verification process across all datasets
(`HaifaBay`, `Croatia`, and `AUV`).
"""

from typing import Dict, Any, List
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec

from config import REAL_DATASET_CONFIGS, OUTPUT_LIVE_DASHBOARD_PATH

THEME = {
    "bg_fig": "#0b0f17",
    "bg_panel": "#131b2e",
    "border": "#263554",
    "text_primary": "#e2e8f0",
    "text_muted": "#94a3b8",
    "ppo": "#38bdf8",
    "cpo": "#f59e0b",
    "limit": "#fb7185",
    "HaifaBay": "#00b4d8",
    "Croatia": "#f77f00",
    "AUV": "#a855f7",
    "target": "#38e08c",
}


class LiveTrainingDashboard:
    """
    Real-time 6-panel (2x3) Matplotlib dashboard that streams epoch-by-epoch training
    and held-out verification telemetry across `HaifaBay`, `Croatia`, and `AUV`:
      - Panel 1 (Top-Left):    Training Reward Trajectory R_t (PIML-PPO vs. PIML-CPO)
      - Panel 2 (Top-Mid):     Physical & TiB Scale-Fairness Constraint Violations C_t vs. Limit d
      - Panel 3 (Top-Right):   Per-Dataset Training Accuracy Curves (HaifaBay, Croatia, AUV)
      - Panel 4 (Bot-Left):    Per-Dataset Held-Out Verification Accuracy Trajectories (Unseen WAVs)
      - Panel 5 (Bot-Mid):     Per-Dataset Learned Bandwidth Gate vs. Fairness Target Bandwidth (Hz)
      - Panel 6 (Bot-Right):   Live Verification Summary Bar Chart (PPO vs. CPO Held-Out Test Acc + J_TiB)
    """

    def __init__(
        self,
        epochs: int = 45,
        cost_limit: float = 0.05,
        dataset_configs: List[Dict[str, Any]] = None,
        out_path: str = OUTPUT_LIVE_DASHBOARD_PATH,
        enable_gui: bool = True,
    ):
        self.epochs = epochs
        self.cost_limit = cost_limit
        self.dataset_configs = dataset_configs or REAL_DATASET_CONFIGS
        self.ds_names = [c["name"] for c in self.dataset_configs]
        self.out_path = out_path
        self.enable_gui = enable_gui

        self.ppo_hist: Dict[str, Any] = None
        self.cpo_hist: Dict[str, Any] = None

        if self.enable_gui:
            try:
                plt.ion()
            except Exception:
                self.enable_gui = False

        self.fig = plt.figure(
            "DRL Live Training & Held-Out Verification Dashboard (HaifaBay, Croatia, AUV)",
            figsize=(17.5, 9.8),
            facecolor=THEME["bg_fig"],
        )
        gs = GridSpec(
            2, 3, figure=self.fig,
            left=0.055, right=0.98, top=0.89, bottom=0.08,
            hspace=0.34, wspace=0.24,
        )

        self.title_text = self.fig.text(
            0.055, 0.955,
            "LIVE DRL TRAINING & HELD-OUT VERIFICATION DASHBOARD  •  MULTISCALE TiB & JAIN'S FAIRNESS REWARD",
            fontsize=12.5, fontweight="bold", color=THEME["text_primary"],
        )
        self.status_text = self.fig.text(
            0.055, 0.925,
            "Status: Initializing Disjoint Train (75%) & Held-Out Verification (25%) Datasets...",
            fontsize=10.0, fontweight="bold", color=THEME["ppo"],
        )

        self.ax_reward = self.fig.add_subplot(gs[0, 0])
        self.ax_cost = self.fig.add_subplot(gs[0, 1])
        self.ax_tr_ds = self.fig.add_subplot(gs[0, 2])
        self.ax_te_ds = self.fig.add_subplot(gs[1, 0])
        self.ax_bw_ds = self.fig.add_subplot(gs[1, 1])
        self.ax_bars = self.fig.add_subplot(gs[1, 2])

        self._init_axes()
        self._flush_canvas()

    def _style_ax(self, ax, title: str, xlabel: str, ylabel: str):
        ax.set_facecolor(THEME["bg_panel"])
        for spine in ax.spines.values():
            spine.set_color(THEME["border"])
        ax.set_title(title, fontsize=10.0, fontweight="bold", color=THEME["text_primary"], pad=8)
        ax.set_xlabel(xlabel, fontsize=9.0, color=THEME["text_muted"])
        ax.set_ylabel(ylabel, fontsize=9.0, color=THEME["text_muted"])
        ax.tick_params(colors=THEME["text_muted"], labelsize=8.5)
        ax.grid(True, color="#1e293b", linestyle="--", alpha=0.65)

    def _init_axes(self):
        self._style_ax(
            self.ax_reward,
            "1. Live Training Reward ($R_t = R_{\\mathrm{BW}} + R_{\\mathrm{Fair}} + R_{\\mathrm{Class}}$)",
            "Epoch",
            "Mean Step Reward",
        )
        self.ax_reward.set_xlim(1, self.epochs)
        self.ax_reward.set_ylim(-0.5, 4.5)
        (self.line_r_ppo,) = self.ax_reward.plot([], [], color=THEME["ppo"], lw=2.2, label="PIML-PPO (Soft)")
        (self.line_r_cpo,) = self.ax_reward.plot([], [], color=THEME["cpo"], lw=2.2, label="PIML-CPO (Hard)")
        self.ax_reward.legend(loc="lower right", facecolor=THEME["bg_fig"], edgecolor=THEME["border"], labelcolor=THEME["text_primary"], fontsize=8.2)

        self._style_ax(
            self.ax_cost,
            "2. Physical & Scale-Fairness Violations ($C_t \\leq d$)",
            "Epoch",
            "Violation Rate",
        )
        self.ax_cost.set_xlim(1, self.epochs)
        self.ax_cost.set_ylim(-0.02, 0.60)
        (self.line_c_ppo,) = self.ax_cost.plot([], [], color=THEME["ppo"], lw=2.2, label="PIML-PPO Cost")
        (self.line_c_cpo,) = self.ax_cost.plot([], [], color=THEME["cpo"], lw=2.2, label="PIML-CPO Cost")
        self.ax_cost.axhline(
            self.cost_limit, color=THEME["limit"], ls="--", lw=1.6, label=f"Hard Limit ($d={self.cost_limit}$)"
        )
        self.ax_cost.legend(loc="upper right", facecolor=THEME["bg_fig"], edgecolor=THEME["border"], labelcolor=THEME["text_primary"], fontsize=8.2)

        self._style_ax(
            self.ax_tr_ds,
            "3. Per-Dataset Training Accuracy (PPO dashed / CPO solid)",
            "Epoch",
            "Train Accuracy (%)",
        )
        self.ax_tr_ds.set_xlim(1, self.epochs)
        self.ax_tr_ds.set_ylim(25, 105)
        self.lines_tr_ppo = {}
        self.lines_tr_cpo = {}
        for ds in self.ds_names:
            c = THEME.get(ds, "#38bdf8")
            (l_ppo,) = self.ax_tr_ds.plot([], [], color=c, ls="--", lw=1.4, alpha=0.65, label=f"{ds} (PPO)")
            (l_cpo,) = self.ax_tr_ds.plot([], [], color=c, ls="-", lw=2.2, label=f"{ds} (CPO)")
            self.lines_tr_ppo[ds] = l_ppo
            self.lines_tr_cpo[ds] = l_cpo
        self.ax_tr_ds.legend(loc="lower right", ncol=2, facecolor=THEME["bg_fig"], edgecolor=THEME["border"], labelcolor=THEME["text_primary"], fontsize=7.6)

        self._style_ax(
            self.ax_te_ds,
            "4. Live Held-Out Verification Accuracy Over All Datasets",
            "Epoch",
            "Verification Accuracy (%)",
        )
        self.ax_te_ds.set_xlim(1, self.epochs)
        self.ax_te_ds.set_ylim(25, 105)
        self.lines_te_ppo = {}
        self.lines_te_cpo = {}
        for ds in self.ds_names:
            c = THEME.get(ds, "#38bdf8")
            (l_ppo,) = self.ax_te_ds.plot([], [], color=c, ls="--", lw=1.4, alpha=0.65, label=f"{ds} Test (PPO)")
            (l_cpo,) = self.ax_te_ds.plot([], [], color=c, ls="-", lw=2.3, label=f"{ds} Test (CPO)")
            self.lines_te_ppo[ds] = l_ppo
            self.lines_te_cpo[ds] = l_cpo
        self.ax_te_ds.legend(loc="lower right", ncol=2, facecolor=THEME["bg_fig"], edgecolor=THEME["border"], labelcolor=THEME["text_primary"], fontsize=7.6)

        self._style_ax(
            self.ax_bw_ds,
            "5. Verification Bandwidth Gate vs. Fairness Target (Hz)",
            "Epoch",
            "Bandwidth Gate (Hz)",
        )
        self.ax_bw_ds.set_xlim(1, self.epochs)
        self.ax_bw_ds.set_ylim(10, 105)
        self.lines_bw_ppo = {}
        self.lines_bw_cpo = {}
        self.lines_bw_tgt = {}
        for ds in self.ds_names:
            c = THEME.get(ds, "#38bdf8")
            (l_ppo,) = self.ax_bw_ds.plot([], [], color=c, ls=":", lw=1.3, alpha=0.55)
            (l_cpo,) = self.ax_bw_ds.plot([], [], color=c, ls="-", lw=2.2, label=f"{ds} Gate (CPO)")
            (l_tgt,) = self.ax_bw_ds.plot([], [], color=c, ls="--", lw=1.3, alpha=0.85, label=f"{ds} Target")
            self.lines_bw_ppo[ds] = l_ppo
            self.lines_bw_cpo[ds] = l_cpo
            self.lines_bw_tgt[ds] = l_tgt
        self.ax_bw_ds.legend(loc="upper right", ncol=2, facecolor=THEME["bg_fig"], edgecolor=THEME["border"], labelcolor=THEME["text_primary"], fontsize=7.5)

        self._style_ax(
            self.ax_bars,
            "6. Live Verification Summary (All Datasets)",
            "Dataset (Unseen WAV Split)",
            "Verification Accuracy (%)",
        )
        self.x_bars = np.arange(len(self.ds_names))
        self.bar_width = 0.34
        self.bars_ppo = self.ax_bars.bar(
            self.x_bars - self.bar_width / 2, [0.0] * len(self.ds_names),
            self.bar_width, label="PIML-PPO Test (%)", color=THEME["ppo"], alpha=0.85,
        )
        self.bars_cpo = self.ax_bars.bar(
            self.x_bars + self.bar_width / 2, [0.0] * len(self.ds_names),
            self.bar_width, label="PIML-CPO Test (%)", color=THEME["cpo"], alpha=0.85,
        )
        self.ax_bars.set_xticks(self.x_bars)
        self.ax_bars.set_xticklabels([
            f"{c['name']}\n({'Surface' if c['is_surface'] else 'Submerged'})"
            for c in self.dataset_configs
        ])
        self.ax_bars.set_ylim(0, 118)
        self.bar_texts_ppo = [
            self.ax_bars.text(
                b.get_x() + b.get_width() / 2, 2.0, "0.0%",
                ha="center", va="bottom", color=THEME["text_primary"], fontsize=8.5, fontweight="bold",
            )
            for b in self.bars_ppo
        ]
        self.bar_texts_cpo = [
            self.ax_bars.text(
                b.get_x() + b.get_width() / 2, 2.0, "0.0%",
                ha="center", va="bottom", color=THEME["text_primary"], fontsize=8.5, fontweight="bold",
            )
            for b in self.bars_cpo
        ]
        self.ax_bars.legend(loc="lower right", facecolor=THEME["bg_fig"], edgecolor=THEME["border"], labelcolor=THEME["text_primary"], fontsize=8.2)

    def _flush_canvas(self):
        try:
            self.fig.canvas.draw_idle()
            self.fig.canvas.flush_events()
            if self.enable_gui:
                plt.pause(0.01)
        except Exception:
            pass

    def on_epoch_end(self, epoch: int, mode: str, history: Dict[str, Any]):
        """Callback invoked at the end of every PPO or CPO training epoch."""
        if mode.upper() == "PPO":
            self.ppo_hist = history
        else:
            self.cpo_hist = history

        if self.ppo_hist is not None:
            ep_p = np.arange(1, len(self.ppo_hist["reward"]) + 1)
            self.line_r_ppo.set_data(ep_p, self.ppo_hist["reward"])
            self.line_c_ppo.set_data(ep_p, self.ppo_hist["cost"])
            for i, ds in enumerate(self.ds_names):
                tr_seq = self.ppo_hist["train_ds_acc"].get(ds, [])
                te_seq = self.ppo_hist["test_ds_acc"].get(ds, [])
                bw_seq = self.ppo_hist["test_ds_bw_gate"].get(ds, [])
                tgt_seq = self.ppo_hist["test_ds_target_bw"].get(ds, [])
                if tr_seq:
                    self.lines_tr_ppo[ds].set_data(np.arange(1, len(tr_seq) + 1), tr_seq)
                if te_seq:
                    self.lines_te_ppo[ds].set_data(np.arange(1, len(te_seq) + 1), te_seq)
                    val_p = te_seq[-1]
                    self.bars_ppo[i].set_height(val_p)
                    self.bar_texts_ppo[i].set_position((self.bars_ppo[i].get_x() + self.bars_ppo[i].get_width() / 2, val_p + 1.5))
                    self.bar_texts_ppo[i].set_text(f"{val_p:.1f}%")
                if bw_seq:
                    self.lines_bw_ppo[ds].set_data(np.arange(1, len(bw_seq) + 1), bw_seq)
                if tgt_seq and self.cpo_hist is None:
                    self.lines_bw_tgt[ds].set_data(np.arange(1, len(tgt_seq) + 1), tgt_seq)

        if self.cpo_hist is not None:
            ep_c = np.arange(1, len(self.cpo_hist["reward"]) + 1)
            self.line_r_cpo.set_data(ep_c, self.cpo_hist["reward"])
            self.line_c_cpo.set_data(ep_c, self.cpo_hist["cost"])
            for i, ds in enumerate(self.ds_names):
                tr_seq = self.cpo_hist["train_ds_acc"].get(ds, [])
                te_seq = self.cpo_hist["test_ds_acc"].get(ds, [])
                bw_seq = self.cpo_hist["test_ds_bw_gate"].get(ds, [])
                tgt_seq = self.cpo_hist["test_ds_target_bw"].get(ds, [])
                if tr_seq:
                    self.lines_tr_cpo[ds].set_data(np.arange(1, len(tr_seq) + 1), tr_seq)
                if te_seq:
                    self.lines_te_cpo[ds].set_data(np.arange(1, len(te_seq) + 1), te_seq)
                    val_c = te_seq[-1]
                    self.bars_cpo[i].set_height(val_c)
                    self.bar_texts_cpo[i].set_position((self.bars_cpo[i].get_x() + self.bars_cpo[i].get_width() / 2, val_c + 1.5))
                    self.bar_texts_cpo[i].set_text(f"{val_c:.1f}%")
                if bw_seq:
                    self.lines_bw_cpo[ds].set_data(np.arange(1, len(bw_seq) + 1), bw_seq)
                if tgt_seq:
                    self.lines_bw_tgt[ds].set_data(np.arange(1, len(tgt_seq) + 1), tgt_seq)

        ds_te_str = "  |  ".join([
            f"{ds} Test: {history['test_ds_acc'][ds][-1]:.1f}% (Gate {history['test_ds_bw_gate'][ds][-1]:.1f} Hz)"
            for ds in self.ds_names if history["test_ds_acc"].get(ds)
        ])
        self.status_text.set_color(THEME["ppo"] if mode.upper() == "PPO" else THEME["cpo"])
        self.status_text.set_text(
            f"[{mode.upper()} Epoch {epoch:02d}/{self.epochs:02d}]  "
            f"Train R={history['reward'][-1]:+.2f}  •  Cost C={history['cost'][-1]:.3f}  •  "
            f"Train Acc={history['accuracy'][-1]:.1f}%   ||   {ds_te_str}"
        )

        if epoch == 1 or epoch % 5 == 0 or epoch == self.epochs:
            print(
                f"    [{mode.upper()} Ep {epoch:02d}/{self.epochs:02d}] "
                f"R={history['reward'][-1]:+.3f} | Cost={history['cost'][-1]:.3f} | "
                f"TrainAcc={history['accuracy'][-1]:5.1f}% || {ds_te_str}"
            )

        self._flush_canvas()
        if epoch == 1 or epoch % 5 == 0 or epoch == self.epochs:
            self.fig.savefig(self.out_path, dpi=220, facecolor=THEME["bg_fig"])

    def finalize(self, block: bool = False):
        """Saves the final high-resolution dashboard figure and optionally blocks the GUI window."""
        self.status_text.set_color(THEME["target"])
        self.status_text.set_text(
            self.status_text.get_text() + "   [COMPLETED]"
        )
        self.fig.savefig(self.out_path, dpi=300, facecolor=THEME["bg_fig"])
        print(f"[Saved] Live Training & Verification Dashboard: {self.out_path}")
        if self.enable_gui and block:
            plt.ioff()
            plt.show()
        else:
            plt.close(self.fig)

