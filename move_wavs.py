import os
import shutil

ROOT_DIR = r"D:\RoyStudies\Recordings\hear-my-ship"

def move_wavs_up_and_clean(root_dir):
    if not os.path.exists(root_dir):
        print(f"Error: Directory '{root_dir}' does not exist.")
        return

    moved_count = 0
    deleted_dirs_count = 0
    dirs_to_check = set()

    # Step 1: Scan for all .wav files recursively
    for dirpath, _, filenames in os.walk(root_dir):
        for filename in filenames:
            if filename.lower().endswith(".wav"):
                src_path = os.path.join(dirpath, filename)
                parent_dir = dirpath
                grandparent_dir = os.path.dirname(parent_dir)

                # Ensure we are not going above the root directory
                if len(os.path.abspath(parent_dir)) <= len(os.path.abspath(root_dir)):
                    print(f"Skipping {filename}: already at or above root directory level.")
                    continue

                dest_path = os.path.join(grandparent_dir, filename)

                # Avoid overwriting a file if it already exists in the destination
                if os.path.exists(dest_path):
                    print(f"Warning: Destination file already exists, skipping: {dest_path}")
                    continue

                try:
                    # Move the file one level up
                    shutil.move(src_path, dest_path)
                    moved_count += 1
                    dirs_to_check.add(parent_dir)
                except Exception as e:
                    print(f"Error moving {src_path} to {dest_path}: {e}")

    # Step 2: Clean up empty directories
    # Sort paths by depth (deepest first) to delete subdirectories before parent directories
    sorted_dirs = sorted(list(dirs_to_check), key=len, reverse=True)
    for d in sorted_dirs:
        if os.path.exists(d) and not os.listdir(d):
            try:
                os.rmdir(d)
                deleted_dirs_count += 1
            except Exception as e:
                print(f"Error deleting empty directory {d}: {e}")

    print("\nProcess Completed!")
    print(f"Moved {moved_count} WAV files one folder up.")
    print(f"Deleted {deleted_dirs_count} empty directories.")

if __name__ == "__main__":
    move_wavs_up_and_clean(ROOT_DIR)
