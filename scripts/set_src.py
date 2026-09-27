Import("env")
import os

env_name = env["PIOENV"]
src_map = {
    "node_fan": os.path.join("firmware", "node_fan"),
    "node_iron": os.path.join("firmware", "node_iron"),
    "node_door": os.path.join("firmware", "node_door"),
    "node_4": os.path.join("firmware", "node_4"),
    "node_5": os.path.join("firmware", "node_5"),
    "wristband": os.path.join("firmware", "wristband"),
    "central_hub": os.path.join("firmware", "central_hub"),
    # Compatibility aliases
    "node_esp32c3": os.path.join("firmware", "node_fan"),
    "wristband_esp32c3": os.path.join("firmware", "wristband"),
    "central_hub_esp32wroom": os.path.join("firmware", "central_hub")
}

if env_name in src_map:
    target_dir = os.path.abspath(os.path.join(env["PROJECT_DIR"], src_map[env_name]))
    env["PROJECT_SRC_DIR"] = target_dir
    print(f"[set_src.py] Redirected PROJECT_SRC_DIR for {env_name} -> {target_dir}")
