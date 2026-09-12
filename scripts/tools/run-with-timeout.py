#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")
    if not args.command:
        parser.error("a command is required")

    try:
        process = subprocess.Popen(
            args.command,
            start_new_session=(os.name == "posix"),
        )
    except FileNotFoundError:
        print(f"command not found: {args.command[0]}", file=sys.stderr)
        return 127
    try:
        return process.wait(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        try:
            if os.name == "posix":
                os.killpg(process.pid, signal.SIGTERM)
            else:
                process.terminate()
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                if os.name == "posix":
                    os.killpg(process.pid, signal.SIGKILL)
                else:
                    process.kill()
            except ProcessLookupError:
                pass
            process.wait()
        return 124


if __name__ == "__main__":
    sys.exit(main())
