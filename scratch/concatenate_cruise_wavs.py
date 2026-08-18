import os
import wave

input_dir = r"D:\RoyStudies\Recordings\DepartmentalCruise-2025-06-12\icListen\wav"
output_file = r"D:\RoyStudies\Recordings\DepartmentalCruise-2025-06-12\icListen\DepartmentalCruise_combined.wav"

wav_files = []
for root, dirs, files in os.walk(input_dir):
    if "out" in dirs:
        dirs.remove("out")  # Do not traverse the 'out' directory
    for f in files:
        if f.endswith(".wav"):
            wav_files.append(os.path.join(root, f))

# Sort the files alphabetically (which aligns chronologically)
wav_files.sort()

print(f"Found {len(wav_files)} files. Concatenating...")

if wav_files:
    # Open the first file to read the parameters
    with wave.open(wav_files[0], 'rb') as w_in:
        params = w_in.getparams()
        
    print(f"Wav params: {params}")
    
    with wave.open(output_file, 'wb') as w_out:
        w_out.setparams(params)
        for i, f in enumerate(wav_files):
            print(f"Processing {i+1}/{len(wav_files)}: {os.path.basename(f)}")
            try:
                with wave.open(f, 'rb') as w_in:
                    w_out.writeframes(w_in.readframes(w_in.getnframes()))
            except wave.Error as e:
                print(f"Skipping {os.path.basename(f)} due to error: {e}")

print(f"Combined file saved to {output_file}")
