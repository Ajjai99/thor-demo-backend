include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../modules/infrastructure"
}

inputs = {
  vpc_cidr             = "10.2.0.0/16"
  public_subnet_cidrs  = ["10.2.0.0/24", "10.2.1.0/24"]
  private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24"]

  # container_image left unset falls back to that service's own ECR repo at the "latest" tag; set it explicitly once CI promotes a real image.
  services = {
    thor = {
      cpu                 = 1024
      memory              = 2048
      desired_count       = 4
      min_healthy_percent = 100
      max_percent         = 200
    }
    "task-api" = {
      cpu                 = 1024
      memory              = 2048
      desired_count       = 4
      min_healthy_percent = 100
      max_percent         = 200
    }
    "intelligence-engine" = {
      cpu                 = 1024
      memory              = 2048
      desired_count       = 4
      min_healthy_percent = 100
      max_percent         = 200
    }
  }
}
