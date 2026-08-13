# Shared

Code shared across `thor`, `task-api`, and `intelligence-engine`. A change
anywhere under this folder triggers a rebuild of all three services in
`deploy.yml`, not just the one whose own source changed.

Not yet wired into any service's Docker build context — each service's
`docker build` currently runs from its own `backend/services/<service>/`
directory, which can't `COPY` files from here. Consuming anything placed
in this folder requires updating each service's build context first.
