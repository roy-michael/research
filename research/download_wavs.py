import os
import urllib.request
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
import ssl
import argparse
# File containing URLs
URL_FILE = r"C:\Users\Roy\Downloads\bc4abdddec4344fe913558479d5f8a7b.txt"

# Output base directory - You can change this if you want it downloaded elsewhere
OUTPUT_DIR = r"C:\Users\Roy\Downloads\wav_downloads"

def download_file(url):
    try:
        # Parse the URL to get the 'path' parameter
        parsed_url = urllib.parse.urlparse(url)
        query_params = urllib.parse.parse_qs(parsed_url.query)
        
        if 'path' not in query_params:
            return f"Skipped (No path param): {url}"
            
        file_path = query_params['path'][0]
        
        # Remove leading slash so os.path.join doesn't treat it as absolute
        file_path = file_path.lstrip('/')
        
        # Create full local path
        local_path = os.path.join(OUTPUT_DIR, os.path.normpath(file_path))
        
        # Ensure the directory exists
        os.makedirs(os.path.dirname(local_path), exist_ok=True)
        
        # Only download if it doesn't already exist
        if not os.path.exists(local_path):
            # Context for avoiding SSL errors
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            
            # Encode URL to handle spaces and other control characters
            safe_url = urllib.parse.quote(url, safe=":/&?=")
            
            req = urllib.request.Request(safe_url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, context=ctx) as response, open(local_path, 'wb') as out_file:
                # Read in chunks for large files
                while True:
                    chunk = response.read(8192 * 4) # 32KB chunks
                    if not chunk:
                        break
                    out_file.write(chunk)
            return f"Downloaded: {local_path}"
        else:
            return f"Already exists: {local_path}"
    except Exception as e:
        return f"Error downloading {url}: {e}"

def main():
    parser = argparse.ArgumentParser(description="Download WAV files from SciDB URLs")
    parser.add_argument('--parent-folder', type=str, help="Filter downloads by a specific parent folder name (e.g. 'Motor Boats')")
    parser.add_argument('--workers', type=int, default=10, help="Number of parallel workers")
    args = parser.parse_args()

    if not os.path.exists(URL_FILE):
        print(f"Error: URL file not found at {URL_FILE}")
        return

    # Read URLs from the file
    with open(URL_FILE, 'r', encoding='utf-8') as f:
        urls = [line.strip() for line in f if line.strip()]
        
    # Filter only .wav files
    wav_urls = [url for url in urls if '.wav' in url.lower()]
    
    # Filter by parent folder if specified
    if args.parent_folder:
        # Check if the folder name is in the url string (URL encoded or not)
        wav_urls = [url for url in wav_urls if args.parent_folder in urllib.parse.unquote(url)]
        print(f"Filtering by parent folder: '{args.parent_folder}'")
    
    print(f"Found {len(wav_urls)} WAV URLs out of {len(urls)} total URLs.")
    
    if not wav_urls:
        print("No WAV files to download.")
        return
        
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Download in parallel
    max_workers = args.workers
    print(f"Starting downloads with {max_workers} parallel workers...")
    
    success_count = 0
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_url = {executor.submit(download_file, url): url for url in wav_urls}
        for future in as_completed(future_to_url):
            url = future_to_url[future]
            try:
                result = future.result()
                print(result)
                if result.startswith("Downloaded"):
                    success_count += 1
            except Exception as exc:
                print(f"{url} generated an exception: {exc}")
                
    print(f"\nFinished. Successfully downloaded {success_count} new files.")

if __name__ == '__main__':
    main()
