import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'analysis')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'plotting')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'simulation')))

import os
import glob
import numpy as np
import matplotlib.pyplot as plt
import librosa
from scipy.io import wavfile

def compute_spectral_flatness_for_dir(directory, max_files=20, duration=30):
    flatness_values = []
    
    wav_files = glob.glob(os.path.join(directory, "*.wav"))
    
    for wav_file in wav_files[:max_files]:
        try:
            # Use librosa to load. This resamples if necessary and handles mono
            y, sr = librosa.load(wav_file, sr=None, duration=duration, mono=True)
            
            # Compute spectral flatness
            flatness = librosa.feature.spectral_flatness(y=y)
            
            # We can take the mean flatness of this file
            flatness_values.append(np.mean(flatness))
        except Exception as e:
            print(f"Error processing {wav_file}: {e}")
            
    return flatness_values

def main():
    petrol_deep_dir = r"C:\Users\Roy\Recordings\Garda_2_26\2_Deep Water\Petrol"
    petrol_shallow_dir = r"C:\Users\Roy\Recordings\Garda_2_26\1_Shallow Water\Petrol"
    dataset_2307_dir = r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2307_free"
    dataset_2407_2_dir = r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_2_snake"
    dataset_2407_1_dir = r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m"
    
    print("Computing spectral flatness for Petrol Deep dataset...")
    petrol_deep_flatness = compute_spectral_flatness_for_dir(petrol_deep_dir)

    print("Computing spectral flatness for Petrol Shallow dataset...")
    petrol_shallow_flatness = compute_spectral_flatness_for_dir(petrol_shallow_dir)
    
    print("Computing spectral flatness for 2307 dataset...")
    d2307_flatness = compute_spectral_flatness_for_dir(dataset_2307_dir)
    
    print("Computing spectral flatness for 2407_2 dataset...")
    d2407_2_flatness = compute_spectral_flatness_for_dir(dataset_2407_2_dir)

    print("Computing spectral flatness for 2407_1 dataset...")
    d2407_1_flatness = compute_spectral_flatness_for_dir(dataset_2407_1_dir)
    
    plt.figure(figsize=(10, 6))
    
    # Plot histogram
    plt.hist(petrol_deep_flatness, bins=20, alpha=0.5, label='Petrol Deep', density=True, color='red')
    plt.hist(petrol_shallow_flatness, bins=20, alpha=0.5, label='Petrol Shallow', density=True, color='orange')
    plt.hist(d2307_flatness, bins=20, alpha=0.5, label='2307 Dataset', density=True, color='blue')
    plt.hist(d2407_2_flatness, bins=20, alpha=0.5, label='2407_2 Dataset', density=True, color='green')
    plt.hist(d2407_1_flatness, bins=20, alpha=0.5, label='2407_1 Dataset', density=True, color='purple')
    
    plt.title('Spectral Flatness Distribution: Petrol Deep/Shallow vs 2307 vs 2407_2 vs 2407_1')
    plt.xlabel('Mean Spectral Flatness')
    plt.ylabel('Density')
    plt.legend()
    plt.grid(True, alpha=0.3)
    
    output_path = 'spectral_flatness_comparison.png'
    plt.savefig(output_path)
    print(f"Saved plot to {output_path}")

if __name__ == "__main__":
    main()
