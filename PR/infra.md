Infra Modules

network — VPC, subnets, routing, VPC endpoints. The foundation everything else sits on.
ecs — Fargate cluster, ECR repos, task definitions, IAM roles, and the thor/task-api/intelligence-engine services (rolling or blue/green). Includes the NLB + blue/green target groups for thor.
api_gateway — public entry point; routes external traffic through a VPC Link into thor's NLB.
aurora — Aurora PostgreSQL Serverless v2, task-api's database, with RDS Data API enabled for CI access.
frontend — private S3 bucket + CloudFront for the static SPA.


infra.yml

The CI/CD pipeline for everything under infra/ — plans and applies Terraform/Terragrunt changes for dev, qa, and prod.

On a PR: runs init → validate → lint → plan, posts the plan as a PR comment. Nothing gets applied.
On a push (i.e. after merge): runs the same checks, then apply — automatic for dev, gated behind required reviewers for qa/prod — then seeds any empty ECR repo with a placeholder image so ECS always has something to pull.