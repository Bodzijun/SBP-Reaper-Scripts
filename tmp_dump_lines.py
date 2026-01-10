from pathlib import Path

path = Path(r"e:/GitHUB/SBP-Reaper-Scripts/VO/VO tool.lua")
lines = path.read_text().splitlines()
for idx in range(929, 1220):
    print(f"{idx+1}: {lines[idx]}")
