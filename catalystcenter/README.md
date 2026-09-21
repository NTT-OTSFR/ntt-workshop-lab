[![Terraform Version](https://img.shields.io/badge/terraform-%5E1.15-blue)](https://www.terraform.io)

# Network-as-Code Catalyst Center Terraform

Use Terraform to operate and manage a Cisco Catalyst Center instance using purpose built modules. Everything can also be executed locally (without CI/CD) following the instructions below.

## Setup

Install [Terraform](https://www.terraform.io/downloads) (> 1.15.0), and the following Python tools:

- [nac-validate](https://github.com/netascode/nac-validate)

```shell
pip install nac-validate
```

Set environment variables pointing to Catalyst Center instance:

```shell
export CC_USERNAME=admin
export CC_PASSWORD=Cisco123
export CC_URL=https://10.1.1.1
```

Device provisioning can take time, and resource operations might timeout. You can set up a timeout in seconds for asynchronous tasks using the CC_MAX_TIMEOUT environment variable, which defaults to 180 seconds

```shell
export CC_MAX_TIMEOUT=600
```

## Initialization

```shell
terraform init
```

This command will download all the required providers and modules from the public Terraform Registry ([https://registry.terraform.io](https://registry.terraform.io)).

## Pre-Change Validation

```shell
nac-validate data/
```

This command performs syntactic and semantic validation of YAML input files located in `data/`.

## Terraform Plan/Apply

```shell
terraform apply
```

This command will apply/deploy the desired configuration.

## Testing

```shell
nac-test --data ./data --data ./defaults.yaml --templates ./tests/templates --output ./tests/results
```

This command will render and execute a set of tests and provide the results in a report (`tests/results/log.html`).

## Terraform Destroy

```shell
terraform destroy
```

This command will delete all the previously created configuration.

## Documentation

Further documentation is available [here](https://netascode.cisco.com).
