#!/usr/bin/env bash
# Version management script for TwinTub
# Gets version from git tags or falls back to a default

set -euo pipefail

# Default version if no git tags exist
DEFAULT_VERSION="1.0.0"

# Try to get version from git tag
get_version() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "$DEFAULT_VERSION"
        return
    fi

    # Try to get the latest tag
    local tag
    tag=$(git describe --tags --abbrev=0 2>/dev/null || true)

    if [ -n "$tag" ]; then
        # Remove 'v' prefix if present
        echo "${tag#v}"
    else
        # Count commits for dev version
        local commits
        commits=$(git rev-list --count HEAD 2>/dev/null || echo "0")
        echo "${DEFAULT_VERSION}-dev.${commits}"
    fi
}

# Get build number (commit count)
get_build_number() {
    if git rev-parse --git-dir >/dev/null 2>&1; then
        git rev-list --count HEAD 2>/dev/null || echo "1"
    else
        echo "1"
    fi
}

# Main
case "${1:-}" in
    --version)
        get_version
        ;;
    --build)
        get_build_number
        ;;
    --full)
        echo "Version: $(get_version)"
        echo "Build: $(get_build_number)"
        echo "Commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
        ;;
    *)
        get_version
        ;;
esac
