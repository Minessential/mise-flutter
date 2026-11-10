#!/usr/bin/env bash
# Pick a Python 3 executable that exists on this host. Windows GitHub runners
# provide `python`, not necessarily `python3`; Unix runners usually provide
# `python3`. Callers use "$PYTHON" after sourcing this file.
if [[ -n "${PYTHON:-}" ]]; then
  :
elif command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo 'python 3.11+ is required for the test suite' >&2
  exit 127
fi
export PYTHON
