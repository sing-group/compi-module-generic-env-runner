# Compi Generic Environment Runner

Compi module that installs a generic default runner capable of executing each
pipeline task in a conda environment, inside a Docker image, or directly with
bash.

The runner reads its configuration from `.env` files, so the `pipeline.xml` does
not need to contain any conda or Docker details. For each task, the runner:

- runs it in a conda environment if `<normalized_task_id>_conda_env` is set;
- runs it inside a Docker image if `<normalized_task_id>_image` is set;
- otherwise, runs it with `/bin/bash -c`.

## Repository layout

```
.
├── metadata.json
├── LICENSE
├── README.md
├── runners.xml
├── bundles/
│   └── generic-env-runner/
│       ├── runner_conda.sh
│       ├── runner_docker.sh
│       ├── conda-envs.env
│       ├── docker.env
│       └── conda-envs/
│           └── README.md
└── example/
    ├── compi.project
    ├── pipeline.xml
    └── runners.xml
```

## Requirements

- Compi.
- `compi-dk` 1.7.0 or newer, with `add-module` support.
- `bash`, `flock` and `realpath`.
- `conda` for tasks configured with a conda environment.
- `docker` for tasks configured with a Docker image.
- The target project must have a runners file (`runners.xml` by default).
  `compi-dk new-project` does not create one, so create a minimal file before
  adding the module:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<runners xmlns="http://sing-group.org/compi/runners-1.0"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
</runners>
```

## Installation

Module repository:
[https://github.com/sing-group/compi-module-generic-env-runner](https://github.com/sing-group/compi-module-generic-env-runner)

`compi-dk` expects a ZIP URL. For GitHub, use the archive URL:

```bash
compi-dk add-module --url \
  https://github.com/sing-group/compi-module-generic-env-runner/archive/refs/heads/main.zip
```

For a fixed version, use a tag instead:

```bash
compi-dk add-module --url \
  https://github.com/sing-group/compi-module-generic-env-runner/archive/refs/tags/1.1.0.zip
```

The module appends its runner to the project runners file and installs:

```
<project>/
├── runners.xml
├── generic-env-runner/
│   ├── runner_conda.sh
│   ├── runner_docker.sh
│   ├── conda-envs.env
│   ├── docker.env
│   └── conda-envs/
│       └── README.md
└── LICENSE_generic-env-runner
```

`compi-dk` installs the module license as `LICENSE_generic-env-runner`.

## Configuration

Task ids are normalized before being used as part of a variable name: any
character that is not valid in a bash variable name is replaced by `_`. For
example, `task-conda` becomes `task_conda`.

### Conda environments

Edit `generic-env-runner/conda-envs.env`:

```bash
<normalized_task_id>_conda_env=<environment_name>
```

Example:

```bash
task_align_conda_env=align-env
```

The environment file is looked up at:

```
generic-env-runner/conda-envs/<environment_name>_environment.yml
```

Do not set `name:` in the YAML file: the environment name is provided with
`conda env create -n`.

If the environment does not exist, `runner_conda.sh` creates it from the YAML
file before running the task. Environment creation is protected with a
per-environment `flock`, so parallel tasks do not create the same environment
twice. Existing environments are not updated automatically.

### Docker images

Edit `generic-env-runner/docker.env`:

```bash
<normalized_task_id>_image=<docker_image>
```

Example:

```bash
task_align_image=pegi3s/clustalomega:latest
```

The shell used inside the container defaults to `/bin/bash`. It can be changed
per task:

```bash
<normalized_task_id>_shell=<shell>
```

Example:

```bash
task_align_shell=/bin/sh
```

Mount paths are declared with variables named `docker_mount_<name>`:

```bash
docker_mount_<name>=<path>
```

Example:

```bash
docker_mount_data=./data
```

Every `docker_mount_*` variable is passed to `docker run` as:

```
-v <absolute_path>:<absolute_path>
```

Paths can be absolute or relative to the directory containing `runners.xml`.
Since `docker.env` is sourced as a shell file, pipeline parameters can be used
in the values:

```bash
docker_mount_work="${workingDir:-}"
```

The variables listed in `$task_params` are passed to the container with `-e`,
so the task code can use pipeline parameters inside the container.

If the image is not available locally, `runner_docker.sh` pulls it only once,
using a per-image `flock`. Parallel tasks using the same image wait for that
single pull instead of starting concurrent downloads. `docker run` is executed
with `--pull=never` to prevent Docker from pulling the image again on its own.

Mount paths must exist. If a path does not exist, the runner fails with a clear
error instead of letting Docker create a root-owned directory.

### Runner selection

- If `<normalized_task_id>_conda_env` is set, the task runs in conda.
- Else, if `<normalized_task_id>_image` is set, the task runs in Docker.
- Else, the task runs directly with bash.
- If both conda and Docker are configured for the same task, the runner fails.

## Example project

The `example/` directory is a minimal `compi-dk` project that uses the same
pipeline as the `compi-env-runner` example:

```
example/
├── compi.project
├── pipeline.xml
└── runners.xml
```

It contains three tasks:

- `task-conda`: runs in a conda environment with Python 3.11.
- `task-docker`: runs inside `debian:13-slim` and writes a file in the mounted
  working directory.
- `task-bash`: runs with the host bash and reads the outputs of the other two
  tasks.

### Add the real module and test it

```bash
cd example

compi-dk add-module --url \
  https://github.com/sing-group/compi-module-generic-env-runner/archive/refs/heads/main.zip
```

Configure the installed module:

```bash
cat > generic-env-runner/conda-envs.env <<'EOF'
task_conda_conda_env=task-conda
EOF

mkdir -p generic-env-runner/conda-envs
cat > generic-env-runner/conda-envs/task-conda_environment.yml <<'EOF'
channels:
  - conda-forge
dependencies:
  - python=3.11
EOF

cat > generic-env-runner/docker.env <<'EOF'
task_docker_image=debian:13-slim
docker_mount_work="${workingDir:-}"
EOF
```

Run the pipeline:

```bash
compi run -o -r runners.xml -- -w $(pwd)
```

Expected behaviour:

- `task-conda` creates (if needed) and uses the `task-conda` conda environment.
- `task-docker` runs Debian inside Docker and writes `docker-output.txt` in the
  working directory.
- `task-bash` runs on the host and prints the outputs generated by the conda
  and Docker tasks.

## Running inside a compi-dk Docker image

This module is intended for local execution and does not include Dockerfile
instructions. If you want to use it inside a `compi-dk` image, add the module
files to the project `Dockerfile` manually:

```dockerfile
ADD runners.xml /runners.xml
ADD generic-env-runner /generic-env-runner
```

Then make sure Compi receives `-r /runners.xml` inside the image, either in the
`entrypoint.sh` or in the `docker run` command.

Remember that conda tasks require `conda` to be available in the execution
environment, and Docker tasks require a Docker client and access to the Docker
daemon (usually through `/var/run/docker.sock`).

## Notes

- The module installs a **default runner**. If the project already has another
  default runner, only one should remain.
- Conda environments are created but not updated when their YAML file changes.
  To recreate one, remove it with `conda env remove -n <environment_name>` and
  run the pipeline again.
- `conda run --no-capture-output` requires a reasonably recent conda version.
- Files created by Docker tasks may be owned by root because the runner does not
  pass `--user`.
- The `flock` files in `runner_conda.sh` are stored in the installed
  `conda-envs/` directory. The per-image pull locks are stored in
  `${TMPDIR:-/tmp}`.

## License

MIT. See `LICENSE`. When the module is added to a project, `compi-dk` installs
it as `LICENSE_generic-env-runner`.
