terraform {
  cloud {

    organization = "pramod-organization"

    workspaces {
      name = "CLI-DRIVEN-WORKFLOW"
    }
  }
  required_providers {
    time = {
      source  = "hashicorp/time"
      version = "0.13.1"
    }
  }
}

resource "time_sleep" "wait_10_seconds" {
  create_duration = "10s"
}