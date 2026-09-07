import tkinter as tk
from tkinter import filedialog, messagebox
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2Tk
from scipy.io import wavfile
from scipy.signal import welch
import os

class AudioInspectorApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Audio Inspector - Interactive PSD & Envelope")
        self.root.geometry("1000x800")
        
        # --- Top Frame for Controls ---
        control_frame = tk.Frame(self.root, pady=10, padx=10)
        control_frame.pack(side=tk.TOP, fill=tk.X)
        
        self.load_btn = tk.Button(control_frame, text="Load WAV File", command=self.load_file, font=("Arial", 12, "bold"))
        self.load_btn.pack(side=tk.LEFT)
        
        self.file_label = tk.Label(control_frame, text="No file loaded", font=("Arial", 10), fg="gray")
        self.file_label.pack(side=tk.LEFT, padx=15)
        
        # --- Matplotlib Figure Setup ---
        self.fig, (self.ax_env, self.ax_psd) = plt.subplots(2, 1, figsize=(10, 8))
        self.fig.tight_layout(pad=4.0)
        
        self.canvas = FigureCanvasTkAgg(self.fig, master=self.root)
        self.canvas.draw()
        
        # Add navigation toolbar (zoom, pan, save)
        toolbar_frame = tk.Frame(self.root)
        toolbar_frame.pack(side=tk.TOP, fill=tk.X)
        self.toolbar = NavigationToolbar2Tk(self.canvas, toolbar_frame)
        self.toolbar.update()
        
        self.canvas.get_tk_widget().pack(side=tk.TOP, fill=tk.BOTH, expand=1)
        
    def load_file(self):
        filepath = filedialog.askopenfilename(
            title="Select WAV File",
            filetypes=(("WAV files", "*.wav"), ("All files", "*.*"))
        )
        if not filepath:
            return
            
        self.file_label.config(text=f"Loading: {os.path.basename(filepath)}...", fg="blue")
        self.root.update()
        
        try:
            self.process_and_plot(filepath)
            self.file_label.config(text=f"Loaded: {os.path.basename(filepath)}", fg="green")
        except Exception as e:
            messagebox.showerror("Error", f"Failed to load audio file:\n{str(e)}")
            self.file_label.config(text="Error loading file", fg="red")
            
    def process_and_plot(self, filepath):
        # 1. Load Audio
        sr, data = wavfile.read(filepath)
        
        # Convert to mono if stereo
        if len(data.shape) > 1:
            data = data.mean(axis=1)
            
        # 2. Calculate Fast Envelope (Downsampled Rolling Max)
        # To keep UI responsive, we calculate envelope by taking max over chunks
        chunk_size = sr // 100 # 100 envelope points per second
        num_chunks = len(data) // chunk_size
        
        if num_chunks > 0:
            truncated_data = data[:num_chunks * chunk_size]
            reshaped_data = truncated_data.reshape((num_chunks, chunk_size))
            envelope = np.max(np.abs(reshaped_data), axis=1)
            time_env = np.arange(num_chunks) * (chunk_size / sr)
        else:
            envelope = np.abs(data)
            time_env = np.arange(len(data)) / sr

        # 3. Calculate Welch PSD
        nperseg = min(4096, len(data))
        freqs, psd = welch(data, fs=sr, nperseg=nperseg)
        psd_db = 10 * np.log10(psd + 1e-12)
        
        # 4. Update Plots
        self.ax_env.clear()
        self.ax_env.plot(time_env, envelope, color='dodgerblue')
        self.ax_env.set_title("Time-Domain Envelope (Downsampled Absolute Max)", fontweight='bold')
        self.ax_env.set_xlabel("Time (s)")
        self.ax_env.set_ylabel("Amplitude")
        self.ax_env.grid(True, alpha=0.3)
        
        self.ax_psd.clear()
        self.ax_psd.semilogx(freqs, psd_db, color='crimson')
        self.ax_psd.set_title("Welch Power Spectral Density (PSD)", fontweight='bold')
        self.ax_psd.set_xlabel("Frequency (Hz)")
        self.ax_psd.set_ylabel("Power (dB/Hz)")
        self.ax_psd.grid(True, which='both', alpha=0.3)
        
        self.fig.tight_layout(pad=4.0)
        self.canvas.draw()

if __name__ == "__main__":
    root = tk.Tk()
    app = AudioInspectorApp(root)
    root.mainloop()
