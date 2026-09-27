Import("env")
import os

env_name = env["PIOENV"]
src_map = {
    "node_esp32c3": os.path.join("firmware", "node_esp32c3"),
    "wristband_esp32c3": os.path.join("firmware", "wristband_esp32c3"),
    "central_hub_esp32wroom": os.path.join("firmware", "central_hub_esp32wroom"),
}

if env_name in src_map:
    target_dir = os.path.abspath(os.path.join(env["PROJECT_DIR"], src_map[env_name]))
    env["PROJECT_SRC_DIR"] = target_dir
    print(f"[set_src.py] Redirected PROJECT_SRC_DIR for {env_name} -> {target_dir}")
