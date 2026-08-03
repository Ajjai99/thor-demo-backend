1. Purpose

This document provides a detailed technical blueprint for implementing the DevOps architecture of the Thor platform solution. It includes exact tool configurations, automation logic, infrastructure definitions, pipeline scripts, and environment-specific deployment procedures. The objective is to enable engineers to consistently and securely deliver, monitor, and manage application services using codified, version-controlled, and auditable practices. 
2. Scope

This document outlines the detailed technical implementation of the DevOps architecture for Thor platform, covering: 

    Source Code Management: Repository structure, branching strategy, and pipeline triggers using GitHub.

    CI/CD Pipeline: Build-once/promote-everywhere pipeline definitions and stages using GitHub Actions.

    Infrastructure as Code: Infrastructure Provisioning, remote state, and environment isolation configuration via a mono-repo(backend + infra) with Terraform.

    Container Image Strategy: Image creation, tagging, and registry integration using ECR.

      Deployment & Orchestration: Deployment configurations and Rolling and blue-green rollout strategies on ECS Fargate.

      Secrets & Configuration: Injection, storage, and rotation via AWS Secrets Manager.

    Monitoring, Logging & Alerting: Using Amazon CloudWatch, CloudWatch Alarms, and AWS X-Ray.

     Security & Compliance: Security enforcement via IAM least-privilege access/ RBAC, image/secret scanning, and network isolation via security groups .

3. Architecture Diagram
Thor - Architecture - RDS Proxy.png
Application Architecture
4. Key Components
4.1 Source Code Management

     Repository Tool: GitHub.

     Repo Structure: A mono-repo containing both the backend and infra code (thor-platform) 

        src/ – Contains the Thor API implementation along with implementation for ingestion, PAI, ATRE and Control engine.

        infra/ – Terraform/IaC (bootstrap/, modules/, live/)

        .github/workflows/ – CI/CD YAMLs, shared across all services

    Branching Strategy: GitHub Flow.

        Feature branches → PR → develop/main.

        Release tags mark the commit promoted through dev, staging, prod

    PR Workflow: 

        Required reviewers, status checks, secret scan

        CODEOWNERS scopes reviewers by folder (e.g. src/** → Thor team only)

    Automation Hooks: 

        Path-aware triggers — only the changed service(s) get built and promoted

        infra/** and src/** changes trigger separate, independent pipelines

4.2 CI/CD Pipeline

    Tool: GitHub Actions.

    Pipeline Files: Defined in YAML (.github/workflows/*.yml, pipelines.yml, etc.) 

     Pipeline Stages: 

        Build: Install dependencies, lint, compile, run static code analysis 

        Test: Run unit/integration tests locally, before publish.

        Package: Build a single container image, tagged immutably with git SHA+ semantic version

        Publish: Push the versioned image to Artifactory — the canonical, cross-environment store. Never pushed directly to an environment's ECR.

        Promote: Pull that corret versioned image from Artifactory and push it into the target environment's ECR — no rebuild at any stage

        Deploy: ECS rolling update/blue-green(as needed) to the target environment; deployed smoke/integration tests run post-deploy

    Infra: Terraform apply executed via IaC pipeline job, workspace-selected per environment

    Triggers:

        Commit push, PR merge, tag creation (marks a release candidate),

        & manual triggers enabled workflow dispatch (used to gate dev → staging and staging → prod promotion; dev is the only fully automatic stage).

4.3 Infrastructure as Code

    Tool: Terraform

    Modules: Organized by service (e.g., network, compute, storage, db) — same modules, unchanged, reused across every environment.

    Environments: 

        To manage different environment, Environment Specific Directory method is followed. Each environment will have its own tf.vars files. Modules are imported in each environment’s directory so that code duplication is prevented. Below is the sample folder structure.
        modules/
          storage/
          compute/
          event-driven/
          ...
        environments/
          dev/
            main.tf        (calls modules/*, passes dev-specific vars)
            dev.tfvars
            backend.tf      (separate state)
          qa/
            main.tf
            qa.tfvars
            backend.tf
          prod/
            main.tf
            prod.tfvars
            backend.tf

        Note: Developers should be mindful of leveraging modules for preventing code duplication. Modules can implement feature flags to perform environment specific actions. 

    Remote State:

        Each environment will have a separate state file. Separate backends can be used if needed.

    Execution: 

        To deploy in a specific environment, navigate to respective environment and run the plan and apply commands
        # To deploy to dev environment

        cd environments/dev
        terraform init
        terraform plan  -var-file=dev.tfvars
        terraform apply -var-file=dev.tfvars

        plan output posted to the PR for review before apply runs

    Change Process: 

        PR-based changes with peer review and validation, same as before

        The CI process should be aware of which environment the changes are to be deployed. The plan and apply command should be run inside respective environment folders

4.4 Configuration & Secret Management

    Configuration Tool: Non-sensitive configuration is passed via ECS task definition environment variables and SSM Parameter Store. 

    Secrets Store: AWS Secrets Manager, with secrets path-separated by component and by environment, consistent with the platform's existing IAM strategy. 

    Injection Mechanism: ECS task definitions reference secret ARNs directly; secrets are never baked into the container image. Because the same promoted image is used in every environment, it only ever picks up environment-specific values through its task definition — reinforcing the build-once/promote-everywhere model. 

    Rotation Policy: Automated rotation via Secrets Manager rotation Lambdas, with KMS access scoped using kms:ViaService conditions. 

4.5 Containerization & Orchestration

    Container Tool: Docker.

    Dockerfiles: 

        Multi-stage builds with .dockerignore 

     Image Registry: 

        Artifactory — canonical, immutable store; every image is built once and published here

        ECR (per environment) — populated by the promotion job, not built to directly; retention policy configured per environment

    Orchestrator: ECS Fargate, with Service Connect for service-to-service discovery

    Deployment Strategy:

        Rolling updates for standard, backward-compatible releases.

        Blue-green for database changes only — used when a schema change can't be made backward-compatible not for the application containers themselves

    Ingress/Networking: 

        AWS WAF and an Application Load Balancer at the edge, with Service Connect for internal routing, consistent with the platform's VPC-endpoint-only network design

4.6 Monitoring, Logging & Alerts

    Monitoring Tool: Amazon CloudWatch, including Container Insights for ECS Fargate task-level metrics 

    Logging: CloudWatch Logs, aggregated per service/task with structured log filtering 

    Alerting: CloudWatch Alarms routed via SNS for threshold breaches (CPU, memory, HTTP 5xx rate) 

    Tracing: AWS X-Ray for distributed tracing across the ECS service mesh .

4.7 Security & Compliance

    Access Control:

        IAM roles scoped to principle of least privilege 

        GitHub OIDC-based CI/CD roles, ECS task execution and task roles, and tiered human access roles, consistent with the platform's existing IAM strategy 

    Image Scanning: 

        Artifactory Xray (and/or ECR image scanning) integrated into the CI pipeline, gating promotion on a clean scan result.

    Secret Scanning: 

        PR check integrations for tools like Gitleaks.

    Network Policies: 

        Security-group chaining between ECS services and Aurora/Graph DB, in line with the platform's VPC-endpoint-only design (no NAT Gateway egress).

    Audit Logging: 

        AWS CloudTrail captures all infrastructure changes and API access, centralized into CloudWatch.

5. DevOps Workflow
1. Local development and feature branch

Developer works on a feature branch, tested locally. Pre-commit hooks (linters, formatters, git hygiene checks) run before commits are accepted. A PR is opened against dev.
2. Merge to dev — build, unit test, store image
local_to_dev_workflow.drawio.png
Local to Dev Workflow

On merge to dev, a pipeline triggers automatically:

    Build the container image once from the merged commit.

    Run unit tests (not integration tests — Dev is a fast-feedback loop, not a promotion gate).

    Check for vulnerabilities in container using Snyk. Proceed to next steps only after container passes safety check

    Tag with the commit SHA (e.g. thor-api-dev:<commit-hash>) and push to Dev ECR.

    Deploy to ECS Dev.

This image is never rebuilt again — it's the same artifact that gets promoted through QA and Prod.
3. Promotion to QA — deploy candidate, test, then promote
dev_to_qa_workflow.drawio.png
Dev to QA Workflow

A developer manually opens a PR from dev to qa (not auto-created). It requires at least one reviewer approval to merge.

On merge, the pipeline:

    Pulls the existing image from Dev ECR by commit hash — no rebuild.

    Deploys it as a candidate to ECS QA (not yet tagged as QA-verified).

    Runs integration tests against the running candidate.

    Fail → QA service rolls back to its last stable revision; nothing is pushed to QA ECR.

    Pass → a manual approval gate (GitHub Environment reviewer) authorizes promotion.

    Once approved, the tested image is retagged and pushed to QA ECR (e.g. thor-api-qa:<commit-hash>).

The PR review gates the code change; the manual approval gates promoting the tested artifact — two distinct checkpoints.
4. Promotion to Prod — blue/green deployment
qa_to_prod_workflow.drawio.png
QA to Prod Workflow

A developer manually opens a PR from qa to main, requiring reviewer approval. On merge, the pipeline pulls the QA-verified image (no rebuild) and runs an ECS-native blue/green deployment:

    Green provisioning: new tasks launch on a separate target group; blue keeps serving 100% of traffic.

    Health checks must pass before proceeding.

    Test traffic / integration tests run against green (via a test listener rule or an ECS lifecycle hook).

    Fail → green is discarded, blue is untouched, no prod-verified tag is written.

    Pass → traffic shifts from blue to green (all-at-once or gradually, depending on strategy).

    Stabilization period: blue stays warm for a configured period after the shift; CloudWatch alarms on real error/latency metrics can still trigger rollback to blue during this window.

    Once the stabilization time is completed cleanly, blue is terminated.

Tag pattern per environment: thor-api-dev:<hash> → thor-api-qa:<hash> → thor-api-prod:<hash> — same artifact, retagged at each verified stage, never rebuilt.
6. Pipeline Setup and Build flow

The below details explains how the pipeline is configured and how container images are managed and deployed.

For authentication Github actions in AWS, OIDC and IAM is used to create short lived tokens
6.1 AWS Setup

    Create ECR repositories thor-dev, thor-qa and thor-prod for dev, qa and prod respectively. Dev and Qa resources will be in a single AWS account, prod is in separate account.

    Add Github OIDC provider in both AWS accounts. Github actions will be authenticated using short-lived OIDC tokens

    Create the following IAM roles and use assume-sts role function with following access in respective account. These roles will be assumed by the Github action workflows.

        deploy-dev: Write access to dev resources

        deploy-qa: Write access to qa resources and read access to dev’s ECR

        deploy-prod: Write access to prod resources and read access to qa’s ECR

The qa and prod workflows need access to dev and qa ECR to pull images.
6.2 Github Setup

    Create 3 environments dev, qa and prod

    Add a environment variable AWS_ROLE_ARN which maps a environment name to the IAM Role ARN in the respective AWS environment

    Add required reviewers and branch protection on qa and main branches

    In the codebase add deploy/dev-image.json, deploy/qa-image.json and deploy/prod-image.json.  These files be written by respective pipeline with the image digest, commitId and timestamp once the image is successfully deployed. The qa build will read the deploy/dev-image.json file to know which image to pull and promote. The changes made to these manifest files will be part of a separate PR. Its responsibility of the code maintainers to merge these PRs.

    CODEOWNERS entry for deploy/*.json

6.3 Github Actions Workflow

There are two Github action workflows

    Auto deploy workflow → Triggered when a PR is merged

    Manual deploy workflow → Manually triggered by an user, can be used for rolling back changes or deploy a older container image.

2 files. Conditionally handle manual and trigger in single workflow file. Keep the deploy-core.yml as a separate workflow or reusable action, this should have the core logics. Auto and mannual should just trigger the deploy-core.yml.

The workflows are implemented in the following way:
.github/workflows/
  _deploy-core.yml       <- reusable workflow, does the actual work
  deploy.yml             <- the core workflow, gets triggered by both mannual or PR merge trigger

The _deploy-core.yml is a reusable workflow that handles the actual auth, build & promote steps, and manifest write steps. The deploy.yml only decides the environment and which mode the pipeline was triggered and then calls _deploy-core.yml
image-20260720-110005.png
7. Handling Database Schema Changes

Blue and green share a single database instance during the stabilization period, so every schema change must work correctly against both app versions simultaneously. The default assumption is additive-heavy, so the process favors that case while still supporting deletions safely
Ordering

Schema migrations run before the dependent code is deployed — as an explicit pipeline step (or lifecycle hook) prior to registering the new task definition. Use a version-tracked, idempotent migration tool (Alembic + SQLAlchemy) with a short lock timeout so a stuck migration fails fast.
Additive changes (default case)

Additive changes are backward compatible by default: old code simply ignores what it doesn't know about.

    New tables — always safe.

    New columns — must be nullable or have a default, so existing inserts don't break.

    New indexes — created online/concurrently to avoid locking live traffic.

    New enum values / foreign keys — added without an immediate full-table validation lock.

Both blue and green are supported by the database with no further coordination required.
Destructive changes (renames, drops, type changes)

Not safe in a single step — blue may still depend on the old shape. Use expand → migrate → contract across separate releases:

    Expand: add the new column/table alongside the old one.

    Migrate: backfill data; green starts using the new column while the old one stays untouched (so blue keeps working if rolled back). Let this run for at least one full deploy cycle, ideally longer, before proceeding.

    Contract: in a later, separate release, drop the old column/table once no running version depends on it.

Never combine expand and contract for the same field in one release — that removes the safety margin the pattern exists to provide.
Tracking deprecated columns

Maintain an external document listing deprecated-but-not-yet-dropped columns/tables with a target removal date, so contract-phase cleanup doesn't get forgotten.
8. Testing Strategy

The objective of this deployment validation strategy is to ensure that every deployment is validated through automated API testing before progressing to the next environment or being released to production.

API Test Suite: The framework created to validate the API contains collections with all the scripts and test cases. It validates the function of each APIs, response body, schema details, boundary values, negative flows and other required checks. The Environment related variables (secretes are masked), test data files are stored separately and called for reusables.

Tools: Postman + Newman

Initial Stage: The APIs deployed to the QA environment(shared in swagger document) are tested functionally and the automation suites are generated. Next Stage: The created smoke & regressions suites are integrated in the pipeline for each environments based on the needs, then on each deployment the scripts will be executed automatically. The both smoke & regressions suite can be triggered in CI/CD and also from the local machine for the validation.
1. Functional Validation: 

The APIs validated manually on creation/changes for each time, apart from that after every deployment edge cases and core business scenarios will be validated.
2. Smoke Validation (Automation / Manual Trigger): 

    All critical APIs are reachable.

    Authentication succeeds.

    Critical business APIs return expected responses.

    No critical or blocker defects are identified.

3. Regression Validation (Automation / Manual Trigger): 

    All critical regression tests pass.

    No Critical or High severity defects remain open.

    Expected API response times are within agreed thresholds.

    Complete API coverage, end to end.

Recommended CI/CD Flow:
ci_cd_pipeline_flowchart.png
Environment Strategy:

Environment
	

Validations

Development
	

Smoke Suite

QA / Stage
	

Smoke Suite + Regression Suite

PROD
	

Smoke Suite + Health Checks

Health Checks: Contains script with minimum validations without affecting the DB to perform only in the production environment based on the requirements.
Reporting:

Each deployment execution will generate the Newman HTML Report it contains all the details of overall run summary, response time summary, request & response body, number of scripts & assertions pass/fail status, the failed test details with error messages. 

The reports will be stored in S3 bucket or shared in mail, after Ten days of reports generation it will be deleted from the bucket.
Deployment Success Criteria:

A deployment will be considered successful when:

    Smoke suite passes with 100% success.

    Functional and regression suites meet the agreed pass threshold (e.g., ≥95%, excluding approved known issues).

    No Critical or High severity defects are introduced.

    Authentication, file upload/download, and core business APIs operate as expected.

    Test reports are generated and reviewed.

UI Validations:

The UI validation strategy focuses on ensuring that the application's critical user interface and business workflows function correctly. QA performs manual Smoke and Regression testing using predefined test cases. Smoke testing verifies that the application is accessible and that critical user journeys, such as login, navigation, and core business functions, are working as expected. Regression testing validates that existing functionality has not been impacted by recent changes by executing the identified business-critical test scenarios. 

Any defects identified during manual validation are logged and reviewed. In case of critical defect, it will be resolved before the deployment is approved to the next environment.
Summary Of Test Strategy:

During development, developers perform local API validation before creating a Pull Request. After the code is merged, the CI/CD pipeline deploys the application to the Development environment and automatically executes the Newman Smoke Suite. Once the Smoke Suite passes and the deployment moves to the QA/Stage environment, both the Smoke and Regression Suites are executed. Before Production deployment, QA reviews the execution reports and confirms that all critical scenarios have passed. Following Production deployment, Health Checks are executed to verify deployment success without affecting production data. 

UI validations are performed manually after each deployment in every environment using the defined Smoke and Regression test cases to ensure the application's end-to-end functionality and user experience are not impacted by the deployment.
9. Backup, Rollback and Recovery Plans
9.1 Application Backup and Rollback

    Container images are pushed once to JFrog Artifactory as the immutable source of truth, then copied into the environment-specific ECR registries (dev, QA, prod) as they're promoted — the image is never rebuilt between stages. Older images therefore remain available in both JFrog Artifactory and each ECR registry, and every deployment corresponds to a distinct, versioned ECS task definition revision.

    Rolling back the application is a matter of pointing the ECS service back at the previous task definition revision, without rebuilding or re-pushing any image. Deployments use ECS-native rolling updates, with the built-in deployment circuit breaker enabled on all services — if new tasks fail health checks past a configured threshold, ECS automatically halts the rollout and rolls the service back to the last known-good task definition revision, without manual intervention.

    The pace and blast radius of each rollout are controlled via minimumHealthyPercent and maximumPercent on the ECS service, which determine how many old vs. new tasks run simultaneously as new tasks are gradually swapped in. Because this is a rolling swap rather than a full parallel standby environment, a small window exists where old and new tasks serve traffic together — this should be accounted for by ensuring both versions are compatible with the current API/schema contract during that window.

9.2 Database Backup and Rollback

    Schema changes follow the expand/contract pattern: each release only adds new tables/columns and backfills data, while the corresponding drop of the old schema is deferred to a later, separate release. This means the old schema shape remains available for the full duration a rollback might be needed, so rolling back the application to a previous version never requires a corresponding schema rollback — the previous code path still has what it needs.

    For disaster recovery and point-in-time needs, Aurora backup clusters are provisioned with storage capacity matching the primary database. Automated backups with point-in-time recovery (PITR) are enabled, with a retention window configurable from 1 to 35 days; backups needed beyond that window are archived to S3 for longer-term retention.

 

 

 

 