#!/usr/bin/env bash
# Creates (or updates) the Terraform/Terragrunt CI role for one environment —
# broader than create-deploy-role.sh's app-deploy role, since this one has to
# create/modify the VPC, security groups, the ECS cluster/services/NLB, API
# Gateway, and IAM roles/policies themselves. Scoped broadly per AWS service
# (Terraform needs full lifecycle CRUD across resource types it doesn't know
# about in advance — unlike the app-deploy role, which only ever touches
# resources that already exist), but IAM actions are restricted to role/policy
# names matching this project's thor-<environment>-* naming convention, since
# unrestricted iam:* is the actual privilege-escalation risk here.
#
# One role, trusted by two GitHub Environments: <environment>-infra-plan
# (ungated — terragrunt plan is read-only and has to run before anyone can
# review it, so it can't itself wait on approval) and <environment>-infra
# (gated by that environment's required reviewers, if configured — this is
# the one terragrunt apply actually runs under). Both store this role's ARN
# under the same AWS_ROLE_ARN variable name used by the app-deploy pipeline —
# deliberately consistent naming, not a separate TF_ROLE_ARN_* scheme.
#
# Usage: ./create-terraform-role.sh <environment> <github_org> [aws_profile]

set -euo pipefail

ENVIRONMENT="${1:?Usage: create-terraform-role.sh <environment> <github_org> [aws_profile]}"
GITHUB_ORG="${2:?GitHub org/user is required}"
GITHUB_REPO="${GITHUB_REPO:-thor-demo-backend}"
export AWS_PROFILE="${3:-${AWS_PROFILE:-default}}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ROLE_NAME="terraform-${ENVIRONMENT}"
OIDC_PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
STATE_BUCKET="thor-terraform-state-${ACCOUNT_ID}"

echo "Using AWS profile '${AWS_PROFILE}' -> account ${ACCOUNT_ID}, environment '${ENVIRONMENT}'."

if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${OIDC_PROVIDER_ARN}" >/dev/null 2>&1; then
  echo "No GitHub OIDC provider found in this account (${OIDC_PROVIDER_ARN}). Run create-github-oidc-provider.sh first."
  exit 1
fi

TRUST_POLICY="$(jq -n \
  --arg oidc_arn "${OIDC_PROVIDER_ARN}" \
  --arg apply_sub "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:${ENVIRONMENT}-infra" \
  --arg plan_sub "repo:${GITHUB_ORG}/${GITHUB_REPO}:environment:${ENVIRONMENT}-infra-plan" \
  '{
    Version: "2012-10-17",
    Statement: [{
      Effect: "Allow",
      Principal: { Federated: $oidc_arn },
      Action: "sts:AssumeRoleWithWebIdentity",
      Condition: {
        StringEquals: { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
        StringLike:   { "token.actions.githubusercontent.com:sub": [$apply_sub, $plan_sub] }
      }
    }]
  }'
)"

PERMISSIONS_POLICY="$(jq -n \
  --arg state_bucket_arn "arn:aws:s3:::${STATE_BUCKET}" \
  --arg role_arn_pattern "arn:aws:iam::${ACCOUNT_ID}:role/thor-${ENVIRONMENT}-*" \
  --arg policy_arn_pattern "arn:aws:iam::${ACCOUNT_ID}:policy/thor-${ENVIRONMENT}-*" \
  '{
    Version: "2012-10-17",
    Statement: [
      { Sid: "TerraformState", Effect: "Allow", Action: ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"], Resource: [$state_bucket_arn, "\($state_bucket_arn)/*"] },
      { Sid: "Ec2Networking", Effect: "Allow", Action: ["ec2:*"], Resource: "*" },
      { Sid: "Ecs", Effect: "Allow", Action: ["ecs:*"], Resource: "*" },
      { Sid: "Ecr", Effect: "Allow", Action: ["ecr:*"], Resource: "*" },
      { Sid: "Elb", Effect: "Allow", Action: ["elasticloadbalancing:*"], Resource: "*" },
      { Sid: "ServiceDiscovery", Effect: "Allow", Action: ["servicediscovery:*"], Resource: "*" },
      { Sid: "ApiGateway", Effect: "Allow", Action: ["apigateway:*"], Resource: "arn:aws:apigateway:*::/*" },
      { Sid: "Logs", Effect: "Allow", Action: ["logs:*"], Resource: "*" },
      { Sid: "IamScoped", Effect: "Allow",
        Action: ["iam:CreateRole","iam:DeleteRole","iam:GetRole","iam:UpdateRole","iam:UpdateAssumeRolePolicy","iam:PutRolePolicy","iam:DeleteRolePolicy","iam:GetRolePolicy","iam:ListRolePolicies","iam:AttachRolePolicy","iam:DetachRolePolicy","iam:ListAttachedRolePolicies","iam:TagRole","iam:UntagRole","iam:PassRole"],
        Resource: [$role_arn_pattern] },
      { Sid: "IamPolicyScoped", Effect: "Allow",
        Action: ["iam:CreatePolicy","iam:DeletePolicy","iam:GetPolicy","iam:GetPolicyVersion","iam:CreatePolicyVersion","iam:DeletePolicyVersion","iam:ListPolicyVersions","iam:TagPolicy","iam:UntagPolicy"],
        Resource: [$policy_arn_pattern] },
      { Sid: "IamRead", Effect: "Allow", Action: ["iam:GetOpenIDConnectProvider"], Resource: "*" }
    ]
  }'
)"

if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "Role ${ROLE_NAME} already exists — updating trust policy and permissions."
  aws iam update-assume-role-policy --role-name "${ROLE_NAME}" --policy-document "${TRUST_POLICY}"
else
  read -rp "Create IAM role ${ROLE_NAME} in account ${ACCOUNT_ID}? [y/N] " CONFIRM
  [[ "${CONFIRM}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
  aws iam create-role --role-name "${ROLE_NAME}" --assume-role-policy-document "${TRUST_POLICY}"
fi

aws iam put-role-policy --role-name "${ROLE_NAME}" --policy-name "terraform-permissions" --policy-document "${PERMISSIONS_POLICY}"

ROLE_ARN="$(aws iam get-role --role-name "${ROLE_NAME}" --query 'Role.Arn' --output text)"
echo "Role ready: ${ROLE_ARN}"
echo "Set AWS_ROLE_ARN to this value on BOTH the '${ENVIRONMENT}-infra-plan' and '${ENVIRONMENT}-infra' GitHub Environments."
echo "Only configure required reviewers on '${ENVIRONMENT}-infra' — leave '${ENVIRONMENT}-infra-plan' unprotected, or plan can never run to let anyone review it."
