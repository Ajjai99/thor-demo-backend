# Thor.Authorizer

API Gateway REQUEST-type Lambda authorizer. Validates the `x-api-key` header on
incoming connector requests against hashed keys stored in Aurora (via RDS Data
API) and returns an Allow/Deny IAM policy.

Deployed by `infra/src/modules/lambda`, wired into API Gateway by
`infra/src/modules/api_gateway/authorizer.tf`, only active when
`enable_authorizer = true` for the environment.

## Structure

- `src/` — the function itself (`Thor.Authorizer.csproj`, `Function.cs`)
- `test/` — unit tests (`Thor.Authorizer.Tests.csproj`)

## Environment variables

Set by Terraform on the Lambda resource:

- `AURORA_CLUSTER_ARN`
- `AURORA_SECRET_ARN`
- `AURORA_DATABASE_NAME`

## Status

Placeholder implementation — not yet wired to a real deploy pipeline. See
`infra/src/modules/lambda/main.tf`'s bootstrap placeholder for why the
Terraform-managed Lambda doesn't yet run this code.
