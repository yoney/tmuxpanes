#!/bin/bash
# scripts/test.sh - Run isolated test

cd "$(dirname "$0")/../.."

# Check if in tmux
if [ -z "$TMUX" ]; then
    echo "ERROR: Not in a tmux session. Please run inside tmux first."
    exit 1
fi

echo "Starting isolated test environment..."
echo ""

nvim --clean -u test/minimal.lua "$@"
