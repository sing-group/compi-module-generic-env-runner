# Conda environments

Place one environment file per conda environment in this directory, named:

```
<environment_name>_environment.yml
```

The environment name is the value configured in `conda-envs.env`. Do not set
`name:` in the YAML file: the name is provided with `conda env create -n`.
