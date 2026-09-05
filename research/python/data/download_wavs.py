import os
import sys
import urllib.parse
import urllib.request
import urllib.error
import concurrent.futures
import threading

# Configuration
URL_FILE = r"C:\Users\gorke\Downloads\bc4abdddec4344fe913558479d5f8a7b.txt"
DEST_DIR = r"D:\RoyStudies\Recordings\hear-my-ship"
MAX_WORKERS = 1
MAX_RETRIES = 5
TIMEOUT_SECONDS = 30

def get_wav_urls_and_paths(file_path):
    """
    Reads the file, filters for WAV files, and extracts their destination paths.
    """
    downloads = []
    if not os.path.exists(file_path):
        print(f"Error: The input file '{file_path}' does not exist.")
        sys.exit(1)
        
    with open(file_path, "r", encoding="utf-8") as f:
        for line in f:
            url = line.strip()
            if not url:
                continue
            
            # Parse URL and check query parameters
            parsed_url = urllib.parse.urlparse(url)
            query_params = urllib.parse.parse_qsl(parsed_url.query)
            query_dict = dict(query_params)
            
            # Extract 'path' or 'fileName' to check if it's a WAV file
            path_param = query_dict.get("path", "")
            file_name_param = query_dict.get("fileName", "")
            
            # We filter for .wav files
            is_wav = (
                path_param.lower().endswith(".wav") or 
                file_name_param.lower().endswith(".wav") or
                url.lower().split('?')[0].endswith(".wav")
            )
            
            if is_wav:
                # Determine relative file hierarchy from the 'path' parameter
                # Strip leading slash to make it relative for joining
                rel_path = path_param.lstrip("/")
                if not rel_path:
                    # Fallback to fileName parameter or actual url path
                    rel_path = file_name_param or os.path.basename(parsed_url.path)
                
                # Properly URL-encode the query parameters to handle spaces and special chars
                encoded_query = urllib.parse.urlencode(query_params)
                clean_url = urllib.parse.urlunparse((
                    parsed_url.scheme,
                    parsed_url.netloc,
                    parsed_url.path,
                    parsed_url.params,
                    encoded_query,
                    parsed_url.fragment
                ))
                
                downloads.append((clean_url, rel_path))
                
    return downloads


def download_file(url, rel_path, dest_dir, progress_lock, progress_state):
    """
    Downloads a single file, handles retries, and maintains progress.
    """
    dest_path = os.path.join(dest_dir, rel_path)
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    
    # Skip if file already exists and is non-empty
    if os.path.exists(dest_path) and os.path.getsize(dest_path) > 0:
        with progress_lock:
            progress_state["skipped"] += 1
            progress_state["completed"] += 1
            total = progress_state["total"]
            current = progress_state["completed"]
            pct = (current / total) * 100
            print(f"[{current}/{total}] ({pct:.1f}%) Skipped (already exists): {rel_path}")
        return True

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            req = urllib.request.Request(
                url, 
                headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
            )
            with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as response, open(dest_path, "wb") as out_file:
                out_file.write(response.read())
            
            with progress_lock:
                progress_state["downloaded"] += 1
                progress_state["completed"] += 1
                total = progress_state["total"]
                current = progress_state["completed"]
                pct = (current / total) * 100
                print(f"[{current}/{total}] ({pct:.1f}%) Downloaded: {rel_path}")
            
            # Short sleep to prevent rate limiting
            import time
            time.sleep(1.0)
            return True
            
        except urllib.error.HTTPError as e:
            if e.code == 429:
                retry_after = e.headers.get("Retry-After")
                sleep_time = 5 * attempt
                if retry_after:
                    try:
                        sleep_time = int(retry_after)
                    except ValueError:
                        pass
                import time
                print(f"Rate limited (429) for {rel_path}. Retrying in {sleep_time}s (attempt {attempt}/{MAX_RETRIES})...")
                time.sleep(sleep_time)
                continue
            
            error_msg = f"HTTP Error {e.code}: {e.reason}"
            if attempt == MAX_RETRIES:
                with progress_lock:
                    progress_state["failed"] += 1
                    progress_state["completed"] += 1
                    total = progress_state["total"]
                    current = progress_state["completed"]
                    pct = (current / total) * 100
                    print(f"[{current}/{total}] ({pct:.1f}%) Failed downloading {rel_path} after {MAX_RETRIES} attempts. Error: {error_msg}")
                if os.path.exists(dest_path):
                    try:
                        os.remove(dest_path)
                    except:
                        pass
                return False
                
        except Exception as e:
            error_msg = str(e)
            if attempt == MAX_RETRIES:
                with progress_lock:
                    progress_state["failed"] += 1
                    progress_state["completed"] += 1
                    total = progress_state["total"]
                    current = progress_state["completed"]
                    pct = (current / total) * 100
                    print(f"[{current}/{total}] ({pct:.1f}%) Failed downloading {rel_path} after {MAX_RETRIES} attempts. Error: {error_msg}")
                if os.path.exists(dest_path):
                    try:
                        os.remove(dest_path)
                    except:
                        pass
                return False
            import time
            time.sleep(2 * attempt)

def main():
    print(f"Reading URL list from: {URL_FILE}")
    wav_downloads = get_wav_urls_and_paths(URL_FILE)
    total_files = len(wav_downloads)
    print(f"Found {total_files} WAV files to download.")
    
    if total_files == 0:
        print("No WAV files found. Exiting.")
        return

    print(f"Downloading to: {DEST_DIR}")
    print(f"Using {MAX_WORKERS} parallel threads.")
    
    progress_state = {
        "total": total_files,
        "completed": 0,
        "downloaded": 0,
        "skipped": 0,
        "failed": 0
    }
    progress_lock = threading.Lock()
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = []
        for url, rel_path in wav_downloads:
            futures.append(
                executor.submit(
                    download_file, 
                    url, 
                    rel_path, 
                    DEST_DIR, 
                    progress_lock, 
                    progress_state
                )
            )
        
        # Wait for all to complete
        concurrent.futures.wait(futures)
        
    print("\nDownload process complete!")
    print(f"Total files: {progress_state['total']}")
    print(f"Downloaded:  {progress_state['downloaded']}")
    print(f"Skipped:     {progress_state['skipped']}")
    print(f"Failed:      {progress_state['failed']}")

if __name__ == "__main__":
    main()
