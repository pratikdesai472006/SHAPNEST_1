Import("env")

# Remove -Wl,--cref from LINKFLAGS if present to prevent 32-bit ld.exe memory exhaustion
if "-Wl,--cref" in env.get("LINKFLAGS", []):
    env["LINKFLAGS"].remove("-Wl,--cref")
    print("[fix_link.py] Successfully removed -Wl,--cref from LINKFLAGS")
