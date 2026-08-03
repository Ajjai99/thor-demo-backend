include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../src"
}


dependency "dev" {
  config_path = "../dev"

  mock_outputs = {
    vpc_id             = "vpc-mock00000000"
    vpc_cidr           = "10.255.255.0/24"
    public_subnet_ids  = ["subnet-mockpub1", "subnet-mockpub2"]
    private_subnet_ids = ["subnet-mockpriv1", "subnet-mockpriv2"]
  }
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
}

inputs = {
  enable_network = false

  dev_vpc_id             = dependency.dev.outputs.vpc_id
  dev_vpc_cidr           = dependency.dev.outputs.vpc_cidr
  dev_public_subnet_ids  = dependency.dev.outputs.public_subnet_ids
  dev_private_subnet_ids = dependency.dev.outputs.private_subnet_ids

  # vpc_cidr / public_subnet_cidrs / private_subnet_cidrs are unused now that
  # enable_network is false — dev's values apply instead.

  enable_compute = false

  # container_image left unset falls back to that service's own ECR repo at the "latest" tag; set it explicitly once CI promotes a real image.
  # services = {
  #   thor                  = { cpu = 512; memory = 1024; desired_count = 2 }
  #   "task-api"            = { cpu = 512; memory = 1024; desired_count = 2 }
  #   "intelligence-engine" = { cpu = 512; memory = 1024; desired_count = 2 }
  # }
}
