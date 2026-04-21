import torch
import sys
from pathlib import Path
from neuralhydrology.utils.config import Config
from neuralhydrology.modelzoo import get_model

def transfer_weights(camels_model_path, caravan_config_path, output_path):
    print(f"Loading CAMELS-US weights from {camels_model_path}")
    camels_state_dict = torch.load(camels_model_path, map_location='cpu')

    print(f"Initializing Caravan model from {caravan_config_path}")
    cfg = Config(Path(caravan_config_path))
    # We need to set device to cpu for this operation
    cfg.device = 'cpu'
    
    # Initialize the model
    # Note: get_model might require the dataset to be initialized to know input dimensions if not explicit?
    # In NH, input dimensions are usually inferred from config (dynamic_inputs + static_attributes).
    # Let's hope it doesn't try to load data.
    # Actually, get_model calls InputLayer which calculates input size from cfg.
    # We need to make sure cfg has all necessary info.
    # The config we wrote has dynamic_inputs and static_attributes lists, so it should be fine.
    
    caravan_model = get_model(cfg)
    
    print("Transferring weights...")
    caravan_state_dict = caravan_model.state_dict()
    
    transferred_layers = []
    skipped_layers = []
    
    for key, value in camels_state_dict.items():
        if key in caravan_state_dict:
            if value.shape == caravan_state_dict[key].shape:
                caravan_state_dict[key] = value
                transferred_layers.append(key)
            else:
                skipped_layers.append(f"{key} (shape mismatch: {value.shape} vs {caravan_state_dict[key].shape})")
        else:
            skipped_layers.append(f"{key} (not in new model)")
            
    print(f"Transferred {len(transferred_layers)} layers.")
    print(f"Skipped {len(skipped_layers)} layers.")
    for s in skipped_layers:
        print(f"  - {s}")
        
    # Load the new state dict into the model to verify
    caravan_model.load_state_dict(caravan_state_dict)
    
    print(f"Saving new checkpoint to {output_path}")
    torch.save(caravan_state_dict, output_path)
    print("Done.")

if __name__ == "__main__":
    camels_path = r"runs/reproduce_531_nse074_2025_1129_2145_ep30/model_epoch030.pt"
    config_path = r"src/caravan_global/configs/caravan_daily_basemodel.yml"
    output_path = r"runs/reproduce_531_nse074_2025_1129_2145_ep30/caravan_pretrained_weights.pt"
    
    transfer_weights(camels_path, config_path, output_path)
