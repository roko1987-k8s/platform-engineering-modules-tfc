terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "= 4.81.0" }
  }
  # Independent state: this Storage Account must not host its own bootstrap state.
  backend "local" {}
}
