#!/bin/bash
# VO QC Server Launcher for macOS/Linux

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Find venv in parent directories
if [ -f "../../.venv/bin/python" ]; then
    PYTHON="../../.venv/bin/python"
elif [ -f "../.venv/bin/python" ]; then
    PYTHON="../.venv/bin/python"
elif [ -f ".venv/bin/python" ]; then
    PYTHON=".venv/bin/python"
else
    PYTHON="python3"
fi

echo ""
echo "============================================"
echo "  VO QC Server v1.0"
echo "============================================"
echo ""
echo "Using Python: $PYTHON"
echo "Directory: $SCRIPT_DIR"
echo ""
echo "Starting server on http://localhost:5000"
echo "Press Ctrl+C to stop"
echo ""
echo "============================================"
echo ""

# Run the Flask server
"$PYTHON" vo_qc_server.py
