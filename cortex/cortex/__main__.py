"""Entry point: python -m cortex --config config.yaml"""

import argparse
import os

import uvicorn
import yaml


def main():
    ap = argparse.ArgumentParser(description="VOX Cortex — NPC cognition service")
    ap.add_argument("--config", default="config.yaml", help="path to config.yaml")
    args = ap.parse_args()
    os.environ["CORTEX_CONFIG"] = args.config
    with open(args.config, encoding="utf-8") as f:
        server = (yaml.safe_load(f) or {}).get("server", {})
    uvicorn.run(
        "cortex.server:app",
        host=server.get("host", "127.0.0.1"),
        port=int(server.get("port", 8765)),
    )


if __name__ == "__main__":
    main()
