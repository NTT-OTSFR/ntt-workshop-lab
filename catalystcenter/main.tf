terraform {
  required_providers {
    catalystcenter = {
      source  = "CiscoDevNet/catalystcenter"
      version = "0.5.4"
    }
  }
}

provider "catalystcenter" {
  username    = "admin"
  url         = "https://198.18.129.100"
  max_timeout = 600
}

variable "yaml_directories" {
  type    = list(string)
  default = ["data/"]
}

module "catalyst_center" {
  source  = "netascode/nac-catalystcenter/catalystcenter"
  version = "0.4.1"

  yaml_directories      = var.yaml_directories
  templates_directories = ["data/templates/"]
  use_bulk_api          = false

  write_default_values_file = "defaults.yaml"
}