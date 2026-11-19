#!/usr/bin/env bash
#
# Usage: runner_conda.sh <conda_env> <task_code>
#
# Runs <task_code> with bash inside the conda environment <conda_env>.
# If the environment does not exist, it is created from:
#   <script_directory>/conda-envs/<conda_env>_environment.yml
# If the environment already exists, it is not modified.

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <conda_env> <task_code>" >&2
    exit 2
fi

conda_env="$1"
task_code="$2"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
envs_dir="${script_dir}/conda-envs"
env_file="${envs_dir}/${conda_env}_environment.yml"

find_conda() {
    if [ -n "${CONDA_EXE:-}" ] && [ -x "${CONDA_EXE}" ]; then
        printf '%s\n' "${CONDA_EXE}"
        return 0
    fi
    if command -v conda >/dev/null 2>&1; then
        command -v conda
        return 0
    fi
    local candidate
    for candidate in \
        "${HOME}/miniconda3/bin/conda" \
        "${HOME}/anaconda3/bin/conda" \
        "${HOME}/miniforge3/bin/conda" \
        "${HOME}/mambaforge/bin/conda" \
        "/opt/conda/bin/conda"; do
        if [ -x "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

if ! conda_bin="$(find_conda)"; then
    echo "[runner_conda] ERROR: 'conda' not found. Add it to PATH or set CONDA_EXE." >&2
    exit 1
fi

env_exists() {
    "${conda_bin}" env list \
        | awk -v env="${conda_env}" '$1 == env { found = 1 } END { exit !found }'
}

create_env() {
    if [ ! -f "${env_file}" ]; then
        echo "[runner_conda] ERROR: environment '${conda_env}' does not exist and '${env_file}' was not found." >&2
        exit 1
    fi
    echo "[runner_conda] Creating conda environment '${conda_env}' from '${env_file}'..." >&2
    "${conda_bin}" env create -f "${env_file}" -n "${conda_env}"
}

if ! env_exists; then
    if command -v flock >/dev/null 2>&1; then
        mkdir -p "${envs_dir}"
        lock_file="${envs_dir}/.${conda_env//\//_}.lock"
        (
            flock 9
            if ! env_exists; then
                create_env
            fi
        ) 9>"${lock_file}"
    else
        create_env
    fi
fi

exec "${conda_bin}" run --no-capture-output -n "${conda_env}" \
    /bin/bash -c "${task_code}"
