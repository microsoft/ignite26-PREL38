# Per-instance GitHub integration

Each Skillable instance uses one private repository generated from the Caldova template. The repository name contains only the non-PII instance token: `caldova-<instance-token>`.

## Platform prerequisite

Skillable/event operations must provide the isolated private repository, the provisioned lab GitHub account/license, write access, protected `main`, and any GitHub App or OAuth prerequisites. The repository should be generated from `microsoft/ignite26-PREL38` and named with a non-PII instance token, such as `caldova-<instance-token>`.

The lab package does not create GitHub accounts, licenses, repositories, or an independent provisioning service. No attendee PAT is created or stored. If the application workflow is enabled, event operations must also configure the non-secret repository variables it declares and an Azure OIDC federated identity restricted to that learner repository, with only ACR push and isolated-resource-group deployment permissions.

## Agent connections

Connect the Preconfigured Agent before the exercise with both:

1. **Code Access** for semantic/file/commit evidence and root-cause analysis.
2. **GitHub OAuth connector** for branches, pull requests, and workflow evidence.

For the Configure Agent, the attendee uses OAuth:

- **Builder → Knowledge base/Code Access → Add repository → GitHub → Auth/Sign in**
- **Builder → Connectors → Add connector → GitHub OAuth connector**

OAuth refreshes automatically. The local source, lockfile hashes, deployment evidence, and image digests remain a deterministic fallback, not a replacement for the writable learner repository.

## Regression and recovery

[`../scripts/github/prepare-api-latency-regression.ps1`](../scripts/github/prepare-api-latency-regression.ps1) creates and pushes a prepared `simulation/api-latency-*` branch. The repository workflow builds immutable portal, healthy API, and latency API artifacts and deploys the branch commit. The exercise then follows:

1. prepared bad commit and Actions deployment;
2. Azure symptom and symptom-only alert;
3. SRE Agent correlation to repository, commit, file, deployed digest, and telemetry;
4. SRE Agent-created fix or revert pull request;
5. protected-main merge and Actions redeployment;
6. HTTP, telemetry, and alert recovery verification.

## Cleanup

Skillable/event operations own repository retention and cleanup. The lab reset removes the Azure regression and restores the healthy digest, but never deletes accounts or repositories.
