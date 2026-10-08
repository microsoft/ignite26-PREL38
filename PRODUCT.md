# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Microsoft Ignite learners working in an assigned Skillable workstation. They choose a prepared or learner-configured Azure SRE Agent, run one production-style incident exercise, investigate it, verify recovery, and restore the workstation.

## Product Purpose

Caldova makes the Azure SRE Agent incident loop concrete: validate ownership, introduce a symptom, wait for the real monitor, investigate with the selected agent, verify the learner-visible outcome, and reset safely.

## Operating Context

The simulator runs locally while the application and agents run in a per-learner Azure resource group. Workshop operations may take several minutes and must show honest progress and actionable failure recovery.

## Capabilities and Constraints

- Preconfigured and Configure learning paths share the same scenario.
- Learner-facing text describes symptoms without disclosing causes.
- Azure changes require an explicit Skillable safety gate.
- Images are built and published before the workshop.
- Per-learner state and locking prevent overlapping scenario actions.

## Product Principles

- Readiness before mutation.
- One visible owner for each live alert.
- Measured recovery, never assumed success.
- Familiar controls and accessible task flow over decorative dashboards.

## Accessibility & Inclusion

Keyboard operation, visible focus, semantic status updates, responsive layout, readable contrast, and reduced-motion support are required.
