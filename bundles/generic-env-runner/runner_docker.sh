#!/usr/bin/env bash
#
# Usage: runner_docker.sh <docker_image> <task_code>
#
# Runs <task_code> with bash inside <docker_image>.
#
# - Variables listed in $task_params are passed to the container with -e.
# - Variables named docker_mount_<name> defined in docker.env are mounted with
#   -v <absolute_path>:<absolute_path>. Relative paths are resolved against
#   the directory containing runners.xml.
# - The image is pulled only once, under a per-image lock, when it is not
#   available locally.

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <docker_image> <task_code>" >&2
    exit 2
fi

docker_image="$1"
task_code="$2"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "${COMPI_RUNNERS_FILE:-}" ]; then
    runners_dir="$(cd -- "$(dirname -- "${COMPI_RUNNERS_FILE}")" && pwd)"
else
    runners_dir="${script_dir}"
fi

docker_env_file="${script_dir}/docker.env"
if [ -f "${docker_env_file}" ]; then
    . "${docker_env_file}"
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "[runner_docker] ERROR: 'docker' not found. Add it to PATH." >&2
    exit 1
fi

image_exists() {
    docker image inspect "${docker_image}" >/dev/null 2>&1
}

pull_image() {
    echo "[runner_docker] Pulling image '${docker_image}'..." >&2
    docker pull "${docker_image}"
}

# Pull the image only once, even if several tasks start in parallel with the
# same image.
if ! image_exists; then
    if command -v flock >/dev/null 2>&1; then
        # Lock per image and user. cksum avoids problematic characters
        # (/, :) and keeps the file name short.
        lock_id="$(printf '%s' "${docker_image}" | cksum | awk '{print $1}')"
        lock_file="${TMPDIR:-/tmp}/compi-docker-image-${UID}-${lock_id}.lock"

        (
            flock 9
            # Another task may have pulled the image while we were waiting
            if ! image_exists; then
                pull_image
            fi
        ) 9>"${lock_file}"
    else
        # Fallback without flock: keep the previous behaviour
        pull_image
    fi
fi

# Task parameter variables
env_args=()
for param in ${task_params:-}; do
    env_args+=(-e "${param}")
done

# Mount paths
mount_args=()
for var in ${!docker_mount_@}; do
    path="${!var}"
    [ -n "${path}" ] || continue

    case "${path}" in
        /*) ;;
        *) path="${runners_dir}/${path}" ;;
    esac

    if [ ! -e "${path}" ]; then
        echo "[runner_docker] ERROR: mount path does not exist: ${path}" >&2
        exit 1
    fi

    abs_path="$(realpath -- "${path}")"
    mount_args+=(-v "${abs_path}:${abs_path}")
done

exec docker run --rm --pull=never "${env_args[@]}" "${mount_args[@]}" \
    --entrypoint /bin/bash "${docker_image}" -c "${task_code}"
