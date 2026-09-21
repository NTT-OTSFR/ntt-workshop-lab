# NTT Workshop Lab

This repository hosts two independent Network-as-Code (NAC) Terraform
solutions, each self-contained in its own subfolder with its own
`main.tf`, data model, tests, and GitHub Actions workflows.

| Solution | Folder | Workflows prefix |
|---|---|---|
| Meraki unified branch network | [`meraki/`](meraki/README.md) | `meraki-*.yml` |
| Catalyst Center fabric deployment | [`catalystcenter/`](catalystcenter/README.md) | `cc-*.yml` |

For a full workshop walkthrough of both solutions' workflows — data model, deploy/destroy
steps, verification, and a suggested end-to-end exercise — see [`LAB_GUIDE.md`](LAB_GUIDE.md).

## Repository layout

```
.
├── meraki/            # Meraki NAC solution (Terraform + data model + tests)
├── catalystcenter/     # Catalyst Center NAC solution (Terraform + data model + tests)
├── .github/workflows/  # CI/CD pipelines for both solutions, namespaced by prefix
└── LICENSE
```

Each solution manages its own Terraform state independently (via GitHub
Actions cache + artifacts, namespaced per solution) and can be planned,
deployed, tested, and destroyed without affecting the other.

See each subfolder's own README for solution-specific setup, required
secrets, and usage instructions.
