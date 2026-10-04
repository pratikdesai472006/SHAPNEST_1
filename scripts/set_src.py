Import("env")
import os

env_name = env["PIOENV"]
src_map = {
    "node_fan": os.path.join("firmware", "node_fan"),
    "node_iron": os.path.join("firmware", "node_iron"),
    "node_door": os.path.join("firmware", "node_door"),
    "wristband": os.path.join("firmware", "wristband"),
}

if env_name in src_map:
    target_dir = os.path.abspath(os.path.join(env["PROJECT_DIR"], src_map[env_name]))
    env["PROJECT_SRC_DIR"] = target_dir
    print(f"[set_src.py] Redirected PROJECT_SRC_DIR for {env_name} -> {target_dir}")
