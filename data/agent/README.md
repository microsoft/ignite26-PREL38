# Azure SRE Agent configuration bundle

`configuration.json` is consumed by the repository-owned `scripts/configure-agent.mjs` adapter.

| Artifact | Purpose | Applied to |
|---|---|---|
| `connectors.json` | Identity-first Azure MCP and Microsoft Learn connector definitions | Both agents |
| `source-context.md` | Caldova architecture and evidence context uploaded as agent knowledge | Both agents |
| `cve-evidence-contract.md` | Fail-closed source, SBOM, image, Defender, and exposure correlation contract | Both agents |
| `live-report-prompts.md` | Exact supported portal prompts for FinOps and Operations Command Center reports | Both agents |
| `skills/*/SKILL.md` | Native structured `srectl` skill | Preconfigured agent only |
| `agents/*/*.yaml` | Native `ExtendedAgent` definition | Preconfigured agent only |
| `incident-filters/*.yaml` | Native Azure Monitor incident response filter | Preconfigured agent only |
| `incident-triage-skill.md` and `response-plan.md` | Human-readable author and learner references | Repository only |
| `investigation-example.md` | Root-cause-neutral example of a completed evidence/action/verification report | Repository only |

The configurator also uploads a generated `caldova-deployment-evidence` document containing the canonical source commit, dependency lockfile hashes, direct dependencies, and deployed revision/image identities. The preconfigured agent receives exactly five weekly read-only tasks: NSG, RBAC, cost, capacity, and CVE.

The Configure-path agent receives the secure connectors and source context needed for the exercise, but not the finished skill, custom agent, or response plan.
