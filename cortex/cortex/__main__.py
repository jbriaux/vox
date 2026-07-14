"""Entry point: python -m cortex --config config.yaml"""

import argparse
import os
import sys
import time
from pathlib import Path

import uvicorn
import yaml


class _Tee:
    """Mirror a stream into the run's log file — the village chronicle
    (TECH EXCHANGED, RAID, COUNCIL PLAN...) survives the console window."""

    def __init__(self, stream, logfile):
        self._stream = stream
        self._log = logfile

    def write(self, text):
        self._stream.write(text)
        try:
            self._log.write(text)
            self._log.flush()
        except ValueError:
            pass  # log closed during shutdown

    def flush(self):
        self._stream.flush()

    def isatty(self):
        return getattr(self._stream, "isatty", lambda: False)()


def main():
    ap = argparse.ArgumentParser(description="VOX Cortex — NPC cognition service")
    ap.add_argument("--config", default="config.yaml", help="path to config.yaml")
    ap.add_argument("--no-log-file", action="store_true",
                    help="print to console only (default: also write "
                         "data/logs/cortex_<timestamp>.log)")
    args = ap.parse_args()
    os.environ["CORTEX_CONFIG"] = args.config
    with open(args.config, encoding="utf-8") as f:
        server = (yaml.safe_load(f) or {}).get("server", {})

    if not args.no_log_file:
        log_dir = Path("data") / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_path = log_dir / time.strftime("cortex_%Y%m%d_%H%M%S.log")
        log = open(log_path, "a", encoding="utf-8", buffering=1)
        sys.stdout = _Tee(sys.stdout, log)
        sys.stderr = _Tee(sys.stderr, log)
        print(f"[cortex] logging to {log_path}")

    uvicorn.run(
        "cortex.server:app",
        host=server.get("host", "127.0.0.1"),
        port=int(server.get("port", 8765)),
    )


if __name__ == "__main__":
    main()
