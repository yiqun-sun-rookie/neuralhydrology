
import tarfile
import os
from pathlib import Path

def extract_missing_folders():
    tar_path = Path("data/Caravan/Caravan-nc.tar.gz")
    extract_path = Path("data/Caravan")
    
    folders_to_extract = [
        "Caravan-nc/timeseries/netcdf/camelsaus",
        "Caravan-nc/timeseries/netcdf/camelsgb"
    ]
    
    print(f"Opening {tar_path}...")
    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            print("Tar file opened successfully.")
            members = []
            count = 0
            for member in tar:
                count += 1
                if count % 1000 == 0:
                    print(f"Scanned {count} files...", end="\r")
                for folder in folders_to_extract:
                    if member.name.startswith(folder):
                        members.append(member)
                        break
            
            print(f"\nFound {len(members)} files to extract.")
            if members:
                tar.extractall(path=extract_path, members=members)
                print("Extraction complete.")
            else:
                print("No matching files found.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    extract_missing_folders()
