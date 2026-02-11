import shutil
import os
import sys

with open('move_log.txt', 'w') as log:
    sys.stdout = log
    sys.stderr = log

    src_base = os.path.abspath(r'data/Caravan/Caravan-nc/timeseries/netcdf')
    dst_base = os.path.abspath(r'data/Caravan/timeseries/netcdf')

    folders = ['camelsaus', 'camelsgb']

    for folder in folders:
        src = os.path.join(src_base, folder)
        dst = os.path.join(dst_base, folder)
        
        if os.path.exists(src):
            print(f"Found {src}")
            if os.path.exists(dst):
                print(f"Destination {dst} already exists.")
            else:
                print(f"Moving to {dst_base}")
                try:
                    shutil.move(src, dst_base)
                    print(f"Moved {folder}")
                except Exception as e:
                    print(f"Error moving {folder}: {e}")
        else:
            print(f"Source {src} not found")

    print("Cleanup...")
    cleanup_dir = os.path.abspath(r'data/Caravan/Caravan-nc')
    if os.path.exists(cleanup_dir):
        try:
            shutil.rmtree(cleanup_dir)
            print(f"Removed {cleanup_dir}")
        except Exception as e:
            print(f"Error removing {cleanup_dir}: {e}")
    else:
        print(f"{cleanup_dir} already gone")
