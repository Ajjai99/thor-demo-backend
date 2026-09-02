# CreateManifest

Lambda invoked directly and synchronously by the ingestion EventBridge Pipe
(`infra/src/modules/ingestion/pipe.tf`) whenever a message lands on the
ingestion SQS queue. Its own code decides success/failure and calls
`states:StartExecution` to hand that outcome to the ingestion Step Functions
state machine, which then either runs the ingestion ECS task
(`backend/workflows/Thor.Workflows.Ingestion`) or requeues/DLQs on failure.

Deployed by `infra/src/modules/ingestion/lambda.tf`, only active when
`enable_ingestion = true` for the environment.

## Structure

- `src/` — the function itself (`CreateManifest.csproj`, `Function.cs`)
- `test/` — unit tests (`CreateManifest.Tests.csproj`)

## Input

Invoked by EventBridge Pipes with no input transformer configured — the
event is a JSON *array* of raw SQS message objects, not the `{"Records":
[...]}` wrapper a classic SQS-triggered Lambda gets. Each message's own
`body` is the S3 bucket-notification JSON, as a string.

## Environment variables

Set by Terraform on the Lambda resource:

- `STATE_MACHINE_ARN`

## Status

Placeholder implementation — logs what it received and reports success to
Step Functions, no real manifest-building logic yet.
