import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'analysis')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'plotting')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'simulation')))

import numpy as np
import matplotlib.pyplot as plt
from scipy import signal
from diagram import load_and_concatenate

class DynamicSpectrogram:
    def __init__(self, ax, t, f, Sxx_dB):
        self.ax = ax
        self.t = t
        self.f = f
        self.Sxx_dB = Sxx_dB
        
        # Target resolution for rendering (keeps plot fast)
        self.target_shape = (800, 1200)
        
        # Plot initial heavily downsampled version
        initial_data = self.downsample(self.Sxx_dB)
        self.im = ax.imshow(initial_data, aspect='auto', origin='lower',
                            extent=[t[0], t[-1], f[0], f[-1]], cmap='viridis')
                            
        self.ax.callbacks.connect('xlim_changed', self.on_lims_change)
        self.ax.callbacks.connect('ylim_changed', self.on_lims_change)

    def downsample(self, array):
        # Calculate steps to fit target shape
        step_y = max(1, array.shape[0] // self.target_shape[0])
        step_x = max(1, array.shape[1] // self.target_shape[1])
        return array[::step_y, ::step_x]

    def on_lims_change(self, event_ax):
        xlim = event_ax.get_xlim()
        ylim = event_ax.get_ylim()
        
        # Find indices for the current zoom level
        x_idx1 = np.searchsorted(self.t, xlim[0])
        x_idx2 = np.searchsorted(self.t, xlim[1])
        y_idx1 = np.searchsorted(self.f, ylim[0])
        y_idx2 = np.searchsorted(self.f, ylim[1])
        
        # Ensure indices are within bounds
        x_idx1, x_idx2 = max(0, x_idx1), min(len(self.t)-1, x_idx2)
        y_idx1, y_idx2 = max(0, y_idx1), min(len(self.f)-1, y_idx2)
        
        if x_idx1 >= x_idx2 or y_idx1 >= y_idx2:
            return
            
        # Slice data
        sliced_data = self.Sxx_dB[y_idx1:y_idx2, x_idx1:x_idx2]
        downsampled = self.downsample(sliced_data)
        
        # Update plot data and extent
        self.im.set_data(downsampled)
        self.im.set_extent([self.t[x_idx1], self.t[x_idx2], self.f[y_idx1], self.f[y_idx2]])
        # Request redraw
        self.ax.figure.canvas.draw_idle()

def plot_spectrogram(samplerate, data, nfft=524288, overlap_ratio=0.9):
    # 512k FFT = 512 * 1024
    noverlap = int(nfft * overlap_ratio)
    
    print(f"Computing spectrogram with nperseg={nfft}, noverlap={noverlap} ({(overlap_ratio*100):.1f}% overlap)...")
    f, t, Sxx = signal.spectrogram(
        data, 
        fs=samplerate, 
        window='hann', 
        nperseg=nfft, 
        nfft=nfft,
        noverlap=noverlap
    )
    
    print("Spectrogram computed. Setting up interactive plot...")
    fig, ax = plt.subplots(figsize=(15, 8))
    
    # Convert to dB, avoiding log of 0
    Sxx_dB = 10 * np.log10(Sxx + np.finfo(float).eps)
    
    # Setup the interactive dynamic spectrogram
    dyn_spec = DynamicSpectrogram(ax, t, f, Sxx_dB)
    
    ax.set_ylabel('Frequency [Hz]')
    ax.set_xlabel('Time [sec]')
    ax.set_title('Spectrogram of 2407_1 (Interactive Zoom)')
    fig.colorbar(dyn_spec.im, ax=ax, label='Power/Frequency (dB/Hz)')
    plt.tight_layout()
    
    out_file = "spectrogram_2407_1_initial.png"
    plt.savefig(out_file, dpi=300)
    print(f"Saved initial zoomed-out spectrogram plot to {out_file}")
    
    print("Plot is ready! Zoom in to dynamically load higher resolution details.")
    plt.show()

if __name__ == '__main__':
    DIR_PATH = r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m"
    try:
        sample_rate, continuous_data, start_time = load_and_concatenate(DIR_PATH)
        print(f"Successfully loaded data. Shape: {continuous_data.shape}, Sample Rate: {sample_rate} Hz")
        
        # Remove NaNs and Infs if any exist
        clean_data = continuous_data[np.isfinite(continuous_data)]
        
        plot_spectrogram(sample_rate, clean_data)
    except Exception as e:
        print(f"An error occurred: {e}")
        import traceback
        traceback.print_exc()
