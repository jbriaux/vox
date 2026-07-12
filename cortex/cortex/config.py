"""Config loading. Paths inside the config are resolved relative to the config file."""

from pathlib import Path

import yaml


def load_config(path: str) -> dict:
    p = Path(path).resolve()
    cfg = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    base = p.parent
    cfg["_base_dir"] = str(base)
    if cfg.get("data_dir"):
        cfg["data_dir"] = str(base / cfg["data_dir"])
    for name, ncfg in cfg.get("npcs", {}).items():
        persona_path = base / ncfg["persona"]
        ncfg["persona_data"] = yaml.safe_load(persona_path.read_text(encoding="utf-8")) or {}
        mem = ncfg.get("memory_db", f"data/memory/{name}.sqlite")
        ncfg["memory_db"] = str(base / mem)
    return cfg
