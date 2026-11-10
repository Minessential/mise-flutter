#!/usr/bin/env bash
# Source with an absolute test directory under the repository's .tmp/.
# Clear inherited mise settings without inspecting or logging their values.
for name in ${!MISE_@}; do unset "$name"; done
unset FLUTTER_STORAGE_BASE_URL FLUTTER_ROOT DART_SDK
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_COUNT
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_SYSTEM
export MISE_CONFIG_DIR="$1/config"
export MISE_SYSTEM_CONFIG_DIR="$1/system"
export MISE_GLOBAL_CONFIG_FILE="$1/global.toml"
export MISE_DATA_DIR="$1/data"
export MISE_CACHE_DIR="$1/cache"
export MISE_STATE_DIR="$1/state"
export MISE_ENV_CACHE=0 MISE_YES=1 MISE_USE_VERSIONS_HOST=0
export MISE_HTTP_RETRIES=0 MISE_NO_UPDATE_CHECK=1 MISE_LOCKFILE=1
export MISE_MINIMUM_RELEASE_AGE=0
export MISE_IGNORED_CONFIG_PATHS="$REPO/mise.toml"
export MISE_TRUSTED_CONFIG_PATHS="$REPO/.tmp"
mkdir -p "$MISE_CONFIG_DIR" "$MISE_SYSTEM_CONFIG_DIR" "$MISE_DATA_DIR" \
  "$MISE_CACHE_DIR" "$MISE_STATE_DIR"
# Do not let Git read a developer's credentials or rewrite the fixture remote.
export GIT_CONFIG_GLOBAL="$1/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
