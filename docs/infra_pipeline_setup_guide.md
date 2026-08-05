# Infra Pipeline Setup Guide

This document explains what needs to exist in AWS and GitHub before the
`infra.yml` GitHub Actions workflow can run — the pipeline that plans and
applies Terraform/Terragrunt changes under `infra/` for `dev`, `qa`, and
`prod`.

## Overview

`infra.yml` needs four things in place before it can do anything:

1. Each environment's real AWS account ID, filled into `infra/root.hcl`.
2. A GitHub OIDC identity provider registered in AWS, so AWS trusts tokens
   issued by GitHub Actions.
3. An IAM role GitHub Actions can assume via that provider.
4. Six GitHub Environments, each holding that role's ARN.

**File location:** `.github/workflows/infra.yml`

## GitHub Environments needed

Each of the three stages (`dev`, `qa`, `prod`) needs two environments — one
for the read-only preview commands, one for the actual apply:

| Environment | Purpose | Protected? |
|---|---|---|
| `dev-infra-plan` | Preview changes for dev | No |
| `dev-infra-apply` | Apply changes to dev | No |
| `qa-infra-plan` | Preview changes for qa | No |
| `qa-infra-apply` | Apply changes to qa | **Yes** |
| `prod-infra-plan` | Preview changes for prod | No |
| `prod-infra-apply` | Apply changes to prod | **Yes** |

Each one needs an `AWS_ROLE_ARN` variable. `AWS_REGION` is optional —
defaults to `us-east-1` if you don't set it.

> **If dev lives in a different AWS account than qa/prod**, repeat every
> step below separately for that account — an OIDC provider and an IAM
> role each live in exactly one AWS account, so dev's `-infra-plan`/
> `-infra-apply` environments need their own role/provider pointing at
> dev's account, distinct from whatever qa/prod use.

## Step 1: Configure AWS account IDs (`infra/root.hcl`)

Before touching AWS or GitHub at all, `infra/root.hcl`'s `account_map`
needs each environment's real AWS account ID:

```hcl
account_map = {
  dev = {
    account_name = "dev"
    account_id   = "<DEV_ACCOUNT_ID>"
    aws_region   = "us-east-1"
  }
  qa = {
    account_name = "qa"
    account_id   = "<QA_ACCOUNT_ID>"
    aws_region   = "us-east-1"
  }
  prod = {
    account_name = "prod"
    account_id   = "<PROD_ACCOUNT_ID>"
    aws_region   = "us-east-1"
  }
}
```

This isn't cosmetic — `account_id` is what builds the S3 state bucket's
name (`thor-terraform-state-<account_id>`), so a blank or wrong value
here means `init-terragrunt` can't find (or auto-create) the right
bucket at all. Today, `dev` and `qa` share one account and `prod`'s
`account_id` is still blank — fill in whichever ones are real before
setting up that environment's pipeline. If dev later moves to its own
account (see the note further down), update `dev`'s entry to match.

## Step 2: Create the OIDC identity provider (AWS Console)

This tells AWS to trust tokens issued by GitHub Actions. Do this once per
AWS account.

1. Go to **IAM → Identity providers → Add provider**
2. Provider type: **OpenID Connect**
3. Provider URL: `https://token.actions.githubusercontent.com`
4. Audience: `sts.amazonaws.com`
5. Click **Add provider**

## Step 3: Create the IAM role (AWS Console)

This is the role GitHub Actions assumes to run Terraform.

1. Go to **IAM → Roles → Create role**
2. Trusted entity type: **Web identity**
3. Identity provider: the one you just created
4. Audience: `sts.amazonaws.com`
5. Skip the console's built-in repo/branch fields — they only allow one
   combination, and this role needs six trusted at once. Click **Create
   role** anyway, then open its **Trust relationships** tab and replace
   the policy with:

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
            "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:environment:dev-infra-plan",
            "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:environment:dev-infra-apply",
            "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:environment:qa-infra-plan",
            "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:environment:qa-infra-apply",
            "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:environment:prod-infra-plan",
            "repo:<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>:environment:prod-infra-apply"
          ]
        }
      }
    }
  ]
}
```

Fill in:
- `<ACCOUNT_ID>` — the AWS account this role lives in
- `<GITHUB_ORG>@<GITHUB_ORG_ID>/<REPO>@<REPO_ID>` — GitHub's default
  subject-claim format for an environment-scoped job. Using the numeric
  org/repo IDs (not just the plain names) means the trust policy keeps
  working even if the org or repo is later renamed — names can be
  reclaimed by someone else after a rename or delete, the numeric IDs
  can't be reused.

6. Attach a permissions policy. This repo's convention is the AWS-managed
   **AdministratorAccess** policy — a deliberate tradeoff (broad CI
   permissions), not an oversight. If you want a narrowly scoped policy
   instead, that's a materially larger task (EC2/ECS/ECR/S3/IAM/RDS/ELB/
   API Gateway/service-discovery permissions, plus the S3 state bucket).
7. Name the role (e.g. `thor-shared-role`) and copy its **ARN** — you'll
   need it in Step 4.

## Step 4: Create the six GitHub Environments (GitHub UI)

Go to **Repo → Settings → Environments → New environment**, once for each
of the six names in the table above.

For each one:

1. **Name it exactly as listed** — it must match the trust policy's `sub`
   claims character-for-character, including the `-infra-plan`/
   `-infra-apply` suffix.
2. **Add a variable**: `AWS_ROLE_ARN` = the role ARN from Step 3.
3. **Set protection rules**:
   - `*-infra-plan` (all three): **leave unprotected**. Plan is read-only
     and has to actually run before anyone can review its output —
     protecting it would deadlock the pipeline.
   - `dev-infra-apply`: your call — auto-applying on push to `dev` is the
     pattern this repo already uses elsewhere, so unprotected is
     reasonable here too.
   - `qa-infra-apply`, `prod-infra-apply`: **add required reviewers** —
     this is the actual approval gate before real infrastructure changes
     apply.

GitHub auto-creates an environment the first time a workflow references
an unknown name, but bare — no reviewers, no variables. If any of these
six get auto-created by a run instead of being set up ahead of time, that
run sails through ungated on `qa`/`prod`.

## Verifying it works

Open a PR that touches something under `infra/**` targeting `dev`. You
should see `init-terragrunt` → `validate-terragrunt` → `lint-terragrunt`
→ `plan-terragrunt` run and post a plan as a PR comment, with no AWS
credential errors. Merging (or pushing directly to `dev`) should then run
`apply-terragrunt` — for `qa`/`prod`, that job pauses for a required
reviewer's approval before applying.
