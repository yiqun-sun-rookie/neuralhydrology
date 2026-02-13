import os
import sys
import traceback


def main() -> int:
    save_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "data", "CAMELS_US"))
    os.makedirs(save_dir, exist_ok=True)
    print(f"Start downloading CAMELS-US to: {save_dir}")
    try:
        from hydrodataset import CAMELS
    except Exception as exc:
        print("hydrodataset is not installed or failed to import:", exc)
        return 2

    try:
        camels = CAMELS(save_dir=save_dir)
        camels.download_data()
        print("Download finished.")
        return 0
    except Exception as exc:
        print("Download failed:", exc)
        traceback.print_exc()
        return 3


if __name__ == "__main__":
    sys.exit(main())



