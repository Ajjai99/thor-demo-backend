# How the infra pipeline works

One workflow, six jobs, always run in the same order. What changes is which trigger fired — a PR preview, or a real push. Triggers only when a change touches the `infra/` folder — nothing else wakes this workflow up.

Source: [`.github/workflows/infra.yml`](../.github/workflows/infra.yml)

## Diagram 1 — Pull request workflow

Opening a PR, or pushing a new commit to it, runs four checks and stops — nothing gets applied yet.

```mermaid
flowchart LR
    p1["context"] --> p2["init-terragrunt"]
    p2 --> p3["validate-terragrunt"]
    p3 --> p4["lint-terragrunt"]
    p4 --> p5["plan-terragrunt"]
    p5 --> p6["plan posted as<br/>PR comment"]

    classDef preview fill:#f3e1d4,stroke:#c4622a,color:#1a1d24;
    class p1,p2,p3,p4,p5,p6 preview;
```

Preview only — never applies anything.

## Diagram 2 — Push workflow

A push to dev, qa, or main — which is what a merge actually produces — runs the identical five checks, then applies.

```mermaid
flowchart LR
    u1["context"] --> u2["init-terragrunt"]
    u2 --> u3["validate-terragrunt"]
    u3 --> u4["lint-terragrunt"]
    u4 --> u5["plan-terragrunt"]
    u5 --> u6["apply-terragrunt"]

    classDef preview fill:#f3e1d4,stroke:#c4622a,color:#1a1d24;
    classDef apply fill:#e2e9f3,stroke:#4c6fa6,color:#1a1d24;
    class u1,u2,u3,u4,u5 preview;
    class u6 apply;
```

Same five checks as the PR workflow, plus apply — which only ever happens here.

## Job by job

| # | Job | What it does |
|---|-----|---------------|
| 1 | `context` | Figures out the environment — dev, qa, or prod — from the branch name. |
| 2 | `init-terragrunt` | Connects to the S3 state backend, downloads providers. Fails fast if credentials or backend access are broken. |
| 3 | `validate-terragrunt` | Checks the Terraform code is syntactically valid — types, references, structure. |
| 4 | `lint-terragrunt` | Checks formatting (`hcl fmt`) and AWS best-practice rules (`tflint`). |
| 5 | `plan-terragrunt` | Previews exactly what would change. On a PR, posts that preview as a comment for review. |
| 6 | `apply-terragrunt` — *push only* | Actually makes the change. Automatic for dev; waits for a required reviewer on qa/prod, if configured. |

---

thor-backend · generated from [`.github/workflows/infra.yml`](../.github/workflows/infra.yml)
