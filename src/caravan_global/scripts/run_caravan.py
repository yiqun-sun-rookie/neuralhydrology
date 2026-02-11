import sys
from pathlib import Path
import os

# Add the project root to the python path
project_root = Path(__file__).resolve().parent.parent
sys.path.append(str(project_root))

from neuralhydrology.nh_run import start_run

if __name__ == "__main__":
    config_file = project_root / "configs" / "caravan" / "caravan_daily_basemodel.yml"
    print(f"Starting training with config: {config_file}")
    
    # Check if config file exists
    if not config_file.exists():
        print(f"Error: Config file not found at {config_file}")
        sys.exit(1)
        
    # Start the run (equivalent to 'nh-run train --config-file ...')
    start_run(config_file=config_file)
