# Infra Pipeline Setup Guide

This document explains what needs to exist in AWS and GitHub before the
`infra.yml` GitHub Actions workflow can run — the pipeline that plans and
applies Terraform/Terragrunt changes under `infra/` for `dev`, `qa`, and
`prod`.

## Overview

`infra.yml` needs five things in place before it can do anything:

1. Each environment's real AWS account ID, filled into `infra/root.hcl`.
2. A GitHub OIDC identity provider registered in AWS.
3. Three IAM roles — `deploy-dev`, `deploy-qa`, `deploy-prod` — **shared
   with the backend deploy pipeline** (`_deploy-core.yml`), not infra-only
   roles. One role per environment covers both purposes.
4. Four repo-level variables (`DEV_AWS_ROLE_ARN`/`QA_AWS_ROLE_ARN`/
   `PROD_AWS_ROLE_ARN`/`AWS_REGION`) plus the `dev`/`qa`/`prod` GitHub
   Environments (already needed by backend deploy) — `qa`/`prod`
   configured with required reviewers, `dev` left unprotected.
5. JFrog repo-level secrets/variables — the Terraform state backend *and*
   the Lambda build cache both run through JFrog Artifactory now, not S3.

**File location:** `.github/workflows/infra.yml`

## How this differs from a per-job-environment setup

Only two of `infra.yml`'s five jobs (`apply-terragrunt`, `seed-ecr-placeholder`)
set a GitHub Environment at all — `validate-terragrunt` (which now runs
`terragrunt init` internally, rather than a separate `init-terragrunt` job)
and `plan-terragrunt` never do, for any branch, since they're read-only and
there's nothing to gate. `apply-terragrunt`/`seed-ecr-placeholder` run
under the environment `context` resolved (`dev`/`qa`/`prod`) — the same
three Environments the backend deploy pipeline already uses. `dev` has no
required-reviewer rule, so it still applies fully automatically; only
`qa`/`prod` actually pause for approval. AWS role resolution is
**repo-level** for every job (`vars.DEV_AWS_ROLE_ARN` etc., picked with a
chained `&&`/`||` expression on the resolved environment), not
GitHub-Environment-scoped like a typical per-environment setup — that
part stays true regardless of which Environment (if any) a job runs
under. This means there's no `dev-infra-plan`/`dev-infra-apply`/
`qa-infra-plan`/etc. — just the three roles and the three shared
Environments.

## Step 1: Configure AWS account IDs (`infra/root.hcl`)

Before touching AWS or GitHub, `infra/root.hcl`'s `account_map` needs each
environment's real AWS account ID:

```hcl
account_map = {
  dev  = { account_name = "dev",  account_id = "<DEV_ACCOUNT_ID>",  aws_region = "us-east-1" }
  qa   = { account_name = "qa",   account_id = "<QA_ACCOUNT_ID>",   aws_region = "us-east-1" }
  prod = { account_name = "prod", account_id = "<PROD_ACCOUNT_ID>", aws_region = "us-east-1" }
}
```

Note: Terraform state now lives in JFrog Artifactory, not S3 (configured
via Step 4's `JFROG_HOSTNAME`/`JFROG_STATE_BACKEND_REPOSITORY`) —
`account_id` itself isn't read anywhere in `root.hcl` (only `aws_region`
feeds the AWS provider).

## Step 2: Create the OIDC identity provider (AWS Console)

Once per AWS account:

1. **IAM → Identity providers → Add provider**
2. Provider type: **OpenID Connect**
3. Provider URL: `https://token.actions.githubusercontent.com`
4. Audience: `sts.amazonaws.com`
5. **Add provider**

## Step 3: Create the three deploy roles (AWS Console)

Repeat this for each of `dev`, `qa`, `prod` — three separate roles,
`deploy-dev`/`deploy-qa`/`deploy-prod`.

1. **IAM → Roles → Create role**
2. Trusted entity type: **Web identity**
3. Identity provider: the one from Step 2
4. Audience: `sts.amazonaws.com`
5. Skip the console's repo/branch fields (only support one combo — each of
   these roles needs several trusted at once). Create the role, then edit
   its **Trust relationships** tab and replace the policy with the one
   below for that role (fill in `<ACCOUNT_ID>` and `<GITHUB_ORG>@
   <GITHUB_ORG_ID>/<REPO>@<REPO_ID>`, same subject-claim format used
   elsewhere in this repo's IAM setup):

   **`deploy-dev`:**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
           "StringLike": {
             "token.actions.githubusercontent.com:sub": [
               "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:environment:dev",
               "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:ref:refs/heads/dev",
               "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:pull_request"
             ]
           }
         }
       }
     ]
   }
   ```

   **`deploy-qa`:**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
           "StringLike": {
             "token.actions.githubusercontent.com:sub": [
               "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:environment:qa-candidate",
               "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:environment:qa",
               "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:ref:refs/heads/qa",
               "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:pull_request"
             ]
           }
         }
       }
     ]
   }
   ```

   **`deploy-prod`** (branch is `main`, not `prod` — that's the actual branch name this environment deploys from):
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
           "StringLike": {
             "token.actions.githubusercontent.com:sub": [
               "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:environment:prod",
               "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:ref:refs/heads/main",
               "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:pull_request"
             ]
           }
         }
       }
     ]
   }
   ```

   The `ref:refs/heads/<branch>` entries exist because `infra.yml`'s
   `init`/`validate`/`plan` never set a GitHub Environment, for any
   branch — a push presents a `ref:`-based subject there instead of an
   `environment:`-based one. (`apply-terragrunt`/`seed-ecr-placeholder`
   run under a real Environment for all three environments now, so those
   two jobs authenticate via the `environment:<name>` subjects instead.)

   **Real GitHub OIDC limitation worth knowing**: the `pull_request`
   subject is identical regardless of which branch the PR targets —
   there's no way to scope "only PRs into dev" via the `sub` claim alone.
   All three roles need to trust it. Low risk in practice, since
   PR-triggered jobs are read-only (nothing applies from a PR).

6. Attach an inline permissions policy (**Add permissions → Create inline
   policy → JSON**) — the same shape for all three roles, just with
   `<environment>` swapped for `dev`/`qa`/`prod`. Resources are scoped to
   the `thor-<environment>-*` naming convention already used throughout
   the Terraform modules **wherever that's actually possible** — some
   services don't support it (see the notes after the policy) and stay
   `Resource: "*"` on purpose, not by oversight:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "Ec2NetworkingDescribe",
         "Effect": "Allow",
         "Action": ["ec2:Describe*"],
         "Resource": "*"
       },
       {
         "Sid": "Ec2NetworkingCreate",
         "Effect": "Allow",
         "Action": [
           "ec2:CreateVpc", "ec2:CreateSubnet", "ec2:CreateSecurityGroup",
           "ec2:CreateRouteTable", "ec2:CreateInternetGateway", "ec2:CreateVpcEndpoint",
           "ec2:CreateTags"
         ],
         "Resource": "*",
         "Condition": {
           "StringEquals": { "aws:RequestTag/Environment": "<environment>" }
         }
       },
       {
         "Sid": "Ec2NetworkingManageOwn",
         "Effect": "Allow",
         "Action": [
           "ec2:ModifyVpcAttribute", "ec2:DeleteVpc",
           "ec2:ModifySubnetAttribute", "ec2:DeleteSubnet",
           "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
           "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress", "ec2:DeleteSecurityGroup",
           "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:ReplaceRoute",
           "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:ReplaceRouteTableAssociation",
           "ec2:DeleteRouteTable",
           "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:DeleteInternetGateway",
           "ec2:ModifyVpcEndpoint", "ec2:DeleteVpcEndpoints",
           "ec2:DeleteTags"
         ],
         "Resource": [
           "arn:aws:ec2:*:*:vpc/*",
           "arn:aws:ec2:*:*:subnet/*",
           "arn:aws:ec2:*:*:security-group/*",
           "arn:aws:ec2:*:*:route-table/*",
           "arn:aws:ec2:*:*:internet-gateway/*",
           "arn:aws:ec2:*:*:vpc-endpoint/*"
         ],
         "Condition": {
           "StringEquals": { "aws:ResourceTag/Environment": "<environment>" }
         }
       },
       {
         "Sid": "EcrPushPull",
         "Effect": "Allow",
         "Action": ["ecr:*"],
         "Resource": "arn:aws:ecr:*:*:repository/*-<environment>"
       },
       {
         "Sid": "EcrAuth",
         "Effect": "Allow",
         "Action": ["ecr:GetAuthorizationToken"],
         "Resource": "*"
       },
       {
         "Sid": "EcrPullThroughCache",
         "Effect": "Allow",
         "Action": [
           "ecr:CreatePullThroughCacheRule", "ecr:DescribePullThroughCacheRules", "ecr:DeletePullThroughCacheRule"
         ],
         "Resource": "*"
       },
       {
         "Sid": "EcsTaskDefinition",
         "Effect": "Allow",
         "Action": ["ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition"],
         "Resource": "*"
       },
       {
         "Sid": "EcsDeploy",
         "Effect": "Allow",
         "Action": ["ecs:*"],
         "Resource": [
           "arn:aws:ecs:*:*:cluster/thor-<environment>",
           "arn:aws:ecs:*:*:service/thor-<environment>/*",
           "arn:aws:ecs:*:*:task-definition/thor-<environment>-*:*",
           "arn:aws:ecs:*:*:task/thor-<environment>/*"
         ]
       },
       {
         "Sid": "ElbDescribe",
         "Effect": "Allow",
         "Action": [
           "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeListeners",
           "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetHealth",
           "elasticloadbalancing:DescribeRules", "elasticloadbalancing:DescribeTags"
         ],
         "Resource": "*"
       },
       {
         "Sid": "LoadBalancing",
         "Effect": "Allow",
         "Action": ["elasticloadbalancing:*"],
         "Resource": [
           "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/thor-nlb-<environment>*/*",
           "arn:aws:elasticloadbalancing:*:*:targetgroup/thor-<environment>-*/*",
           "arn:aws:elasticloadbalancing:*:*:listener/net/thor-nlb-<environment>*/*/*"
         ]
       },
       {
         "Sid": "ApiGatewayHttpApi",
         "Effect": "Allow",
         "Action": ["apigateway:GET", "apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE"],
         "Resource": [
           "arn:aws:apigateway:*::/apis",
           "arn:aws:apigateway:*::/apis/*",
           "arn:aws:apigateway:*::/vpclinks",
           "arn:aws:apigateway:*::/vpclinks/*",
           "arn:aws:apigateway:*::/domainnames",
           "arn:aws:apigateway:*::/domainnames/*",
           "arn:aws:apigateway:*::/tags/*"
         ]
       },
       {
         "Sid": "CloudFrontOriginAccessControl",
         "Effect": "Allow",
         "Action": ["cloudfront:*OriginAccessControl*"],
         "Resource": "*"
       },
       {
         "Sid": "CloudFrontManageOwn",
         "Effect": "Allow",
         "Action": [
           "cloudfront:GetDistribution", "cloudfront:GetDistributionConfig", "cloudfront:UpdateDistribution",
           "cloudfront:DeleteDistribution", "cloudfront:CreateInvalidation", "cloudfront:ListInvalidations",
           "cloudfront:GetInvalidation", "cloudfront:TagResource", "cloudfront:UntagResource",
           "cloudfront:ListTagsForResource"
         ],
         "Resource": "*",
         "Condition": {
           "StringEquals": { "aws:ResourceTag/Environment": "<environment>" }
         }
       },
       {
         "Sid": "CloudFrontCreate",
         "Effect": "Allow",
         "Action": ["cloudfront:CreateDistribution", "cloudfront:TagResource"],
         "Resource": "*",
         "Condition": {
           "StringEquals": { "aws:RequestTag/Environment": "<environment>" }
         }
       },
       {
         "Sid": "Waf",
         "Effect": "Allow",
         "Action": ["wafv2:*"],
         "Resource": "arn:aws:wafv2:*:*:global/webacl/thor-<environment>-frontend-waf/*"
       },
       { "Sid": "Route53Dns", "Effect": "Allow", "Action": ["route53:*"], "Resource": "*" },
       { "Sid": "ServiceDiscovery", "Effect": "Allow", "Action": ["servicediscovery:*"], "Resource": "*" },
       {
         "Sid": "S3FrontendBucket",
         "Effect": "Allow",
         "Action": ["s3:*"],
         "Resource": "arn:aws:s3:::thor-frontend-<environment>-*"
       },
       {
         "Sid": "TerraformStateBucket",
         "Effect": "Allow",
         "Action": ["s3:ListBucket"],
         "Resource": "arn:aws:s3:::thor-terraform-state-<account-id>"
       },
       {
         "Sid": "TerraformStateObjects",
         "Effect": "Allow",
         "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
         "Resource": "arn:aws:s3:::thor-terraform-state-<account-id>/thor-<environment>/*"
       },
       {
         "Sid": "KmsForManagedSecrets",
         "Effect": "Allow",
         "Action": ["kms:DescribeKey"],
         "Resource": "*"
       },
       {
         "Sid": "Rds",
         "Effect": "Allow",
         "Action": ["rds:*"],
         "Resource": [
           "arn:aws:rds:*:*:cluster:thor-<environment>-aurora",
           "arn:aws:rds:*:*:db:thor-<environment>-aurora-*",
           "arn:aws:rds:*:*:subgrp:thor-<environment>-aurora"
         ]
       },
       {
         "Sid": "RdsData",
         "Effect": "Allow",
         "Action": ["rds-data:*"],
         "Resource": "arn:aws:rds:*:*:cluster:thor-<environment>-aurora"
       },
       {
         "Sid": "RdsProxy",
         "Effect": "Allow",
         "Action": ["rds:CreateDBProxy", "rds:ModifyDBProxy", "rds:DeleteDBProxy", "rds:DescribeDBProxies"],
         "Resource": "arn:aws:rds:*:*:db-proxy:thor-<environment>-rds-proxy"
       },
       {
         "Sid": "RdsProxyTargets",
         "Effect": "Allow",
         "Action": [
           "rds:RegisterDBProxyTargets", "rds:DeregisterDBProxyTargets",
           "rds:DescribeDBProxyTargets", "rds:DescribeDBProxyTargetGroups", "rds:ModifyDBProxyTargetGroup"
         ],
         "Resource": "*"
       },
       { "Sid": "SecretsManager", "Effect": "Allow", "Action": ["secretsmanager:*"], "Resource": "*" },
       {
         "Sid": "Lambda",
         "Effect": "Allow",
         "Action": ["lambda:*"],
         "Resource": "arn:aws:lambda:*:*:function:thor-<environment>-*"
       },
       {
         "Sid": "Logs",
         "Effect": "Allow",
         "Action": ["logs:*"],
         "Resource": [
           "arn:aws:logs:*:*:log-group:/ecs/<environment>/*",
           "arn:aws:logs:*:*:log-group:/aws/lambda/thor-<environment>-*"
         ]
       },
       {
         "Sid": "ManageThorIamRoles",
         "Effect": "Allow",
         "Action": [
           "iam:CreateRole", "iam:DeleteRole", "iam:GetRole",
           "iam:UpdateAssumeRolePolicy",
           "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
           "iam:AttachRolePolicy", "iam:DetachRolePolicy",
           "iam:TagRole", "iam:UntagRole",
           "iam:ListRolePolicies", "iam:ListAttachedRolePolicies"
         ],
         "Resource": "arn:aws:iam::*:role/thor-<environment>-*"
       },
       { "Sid": "PassExecutionAndTaskRoles", "Effect": "Allow", "Action": ["iam:PassRole"], "Resource": "arn:aws:iam::*:role/thor-<environment>-*" }
     ]
   }
   ```

   **Scoped to `thor-<environment>-*`** (or a close variant): ECR, ECS,
   load balancing, the S3 frontend bucket, RDS/RDS Data API, RDS Proxy,
   Lambda, CloudWatch Logs, WAF, and IAM role management/`PassRole`. No S3
   statement for Terraform state — that lives in JFrog Artifactory
   (Step 4), not an S3 bucket this role needs access to.

   **`RdsProxy`'s ARN is unverified, same caveat as the ELB listener ARN
   below**: written as `db-proxy:thor-<environment>-rds-proxy` (the
   `db_proxy_name`), matching how its `Rds` sibling statement scopes
   `cluster`/`db`/`subgrp` by name rather than an AWS-generated ID — but
   unlike those, this hasn't been confirmed against AWS's own IAM
   resource-type reference for the `rds:` (not `rds-db:`) namespace
   specifically. If `CreateDBProxy`/etc. get denied unexpectedly, check
   the ARN in the error message; it may need to be the `prx-<random-id>`
   AWS assigns instead, same as the `rds-db:connect` runtime-auth ARN
   uses (a different, already-confirmed case, not this one).

   **Left as `Resource: "*"` on purpose, not by oversight:**
   - **EC2** — VPC/subnet/security-group IDs (`vpc-xxxxx`) are AWS-random,
     not name-derived. Scoping by name would mean scoping by the `Name`
     *tag* instead of the ARN, and many EC2 create actions don't support
     resource-level permissions or tag-on-create conditions consistently
     — getting this wrong is the likeliest way to break `terraform apply`
     outright (e.g. "create a new VPC" evaluated before the resource, and
     its tag, exist).
   - **API Gateway**, **CloudFront**, **Service Discovery** — all use
     AWS-random IDs in their ARNs (REST API ID, distribution ID,
     namespace/service ID), never the `thor-<environment>-*` name itself.
   - **Route53** — the hosted zone (`aws_route53_zone`, for the TLS
     sidecar's Let's Encrypt DNS-01 challenge) gets an AWS-random zone ID
     (`Z0953...`), not a name-derived one; the domain name itself
     (`cndemo.com`) isn't part of the zone's ARN at all. Also covers the
     ACME provider's own DNS-01 record management (`ChangeResourceRecordSets`
     etc.), which targets that same unscoped zone ARN.
   - **ECR pull-through cache rule management** (`CreatePullThroughCacheRule`/
     `DescribePullThroughCacheRules`/`DeletePullThroughCacheRule`, used to
     mirror the TLS sidecar's `nginx` base image from `public.ecr.aws`
     since this VPC has no NAT Gateway route to reach it directly) — these
     specific actions don't support resource-level permissions in IAM at
     all, unlike ordinary repository push/pull. The repositories the cache
     rule actually populates *are* ARN-scoped, but that's a separate
     concern from managing the rule resource itself — see
     `modules/ecs/tls_sidecar.tf`'s own IAM policy for the ECS execution
     role's `ecr:CreateRepository`/`BatchImportUpstreamImage` grant, scoped
     to `repository/ecr-public/*`, which is a different role than this one.
   - **Secrets Manager** — the Aurora master secret's ID is auto-generated
     by AWS (`rds!cluster-<random-uuid>`) when using
     `manage_master_user_password`, never derived from the naming
     convention at all.

   **Not fully verified — treat as best-effort, not guaranteed-exact**:
   the ARN formats above follow AWS's documented patterns, but a couple
   (the ELB listener ARN's segment count in particular) haven't been
   confirmed against a real apply in this account. If something gets
   denied unexpectedly, check the exact ARN in the CloudTrail/IAM error
   message against the pattern above before assuming the permission is
   simply missing.

7. Name the role (`deploy-dev`/`deploy-qa`/`deploy-prod`) and copy its
   **ARN** — needed in Step 4.

## Step 4: Set the repo-level variables and secrets

Variables (**Repo → Settings → Secrets and variables → Actions →
Variables**):

- `DEV_AWS_ROLE_ARN`, `QA_AWS_ROLE_ARN`, `PROD_AWS_ROLE_ARN` — the three
  role ARNs
- `AWS_REGION` (optional, defaults to `us-east-1`)
- `JFROG_HOSTNAME` — Terraform remote backend hostname
- `JFROG_STATE_BACKEND_REPOSITORY` — backend organization; state lives in
  `thor-<environment>` workspaces
- `jf_usr_thor` — JFrog username (→ `JFROG_USERNAME`)
- `JFROG_LAMBDA_ARTIFACTS_REPOSITORY` — Lambda build cache repo
- `JFROG_DOCKER_REPOSITORY` — not read by `infra.yml`; it's the backend
  deploy pipeline's (`_deploy-core.yml`, on `feature/thor-73-backend-pipeline`,
  not yet merged) Docker repo — its `dev` job builds/pushes
  `<JFROG_HOSTNAME>/<JFROG_DOCKER_REPOSITORY>/<service>:<sha>`. Listed
  here since it's configured in the same place.

Secrets:

- `jf_api_thor` — JFrog access token, used as both
  `TF_TOKEN_sphereco_jfrog_io` and `JFROG_ACCESS_TOKEN`

`root.hcl`'s `jfrog_hostname`/`repo_name` locals read `JFROG_HOSTNAME`/
`JFROG_STATE_BACKEND_REPOSITORY` via `get_env()` with **no fallback
default** — both are required, or every `terragrunt` command (plan,
apply, init, validate, destroy) fails immediately at the locals-eval step
with `EnvVarNotFoundError`. For **local** runs, export them yourself
first:
```
export JFROG_HOSTNAME=sphereco.jfrog.io
export JFROG_STATE_BACKEND_REPOSITORY=terraform-state-local
```

## Step 5: Configure the `dev`/`qa`/`prod` GitHub Environments

These are the **same** Environments the backend deploy pipeline already
needs — no infra-specific Environments to create.

1. **Repo → Settings → Environments**
2. Create all three (`dev`, `qa`, `prod`) if they don't already exist.
3. `qa` and `prod`: add required reviewers. `dev`: leave unprotected —
   `apply-terragrunt`/`seed-ecr-placeholder` still run fully
   automatically there, it just runs under a real Environment now
   instead of none at all.
4. No `AWS_ROLE_ARN` variable needed on any of the three Environments for
   infra's sake — `infra.yml` reads the repo-level variables from Step 4
   regardless of which Environment a job is running under.

## Verifying it works

Open a PR touching `infra/**` or `backend/functions/**` targeting `dev`.
You should see `validate-terragrunt` (runs `terragrunt init` internally,
then `hcl fmt` + `tflint`) → `plan-terragrunt` post a plan comment with no
AWS credential errors. Merging should then run `apply-terragrunt`
automatically for `dev` — `qa`/`prod` pause for reviewer approval.
