import os
import wave

directory = r"D:\RoyStudies\Recordings\Croatia\data"
start_file = "record_20250722_183004"
end_file = "record_20250722_192013"

all_files = [f for f in os.listdir(directory) if f.endswith('.wav')]
all_files.sort()

files_to_merge = []
in_range = False
for f in all_files:
    if f.startswith(start_file):
        in_range = True
    if in_range:
        files_to_merge.append(os.path.join(directory, f))
    if f.startswith(end_file):
        break

if not files_to_merge:
    print("No files found in range.")
else:
    print(f"Merging {len(files_to_merge)} files...")
    
    data = []
    with wave.open(files_to_merge[0], 'rb') as w:
        params = w.getparams()
        data.append(w.readframes(w.getnframes()))
        
    for f in files_to_merge[1:]:
        with wave.open(f, 'rb') as w:
            data.append(w.readframes(w.getnframes()))
            
    out_path = os.path.join(directory, f"merged_{start_file}_to_{end_file}.wav")
    with wave.open(out_path, 'wb') as w_out:
        w_out.setparams(params)
        for d in data:
            w_out.writeframes(d)
    
    print(f"Saved merged file to {out_path}")
