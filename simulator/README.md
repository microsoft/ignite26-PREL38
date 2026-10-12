# Caldova learner simulator

The simulator is a local, dependency-free Node.js workstation UI for independently selectable Caldova incident scenarios.

The learner-facing entry point is the attached startup wrapper:

```powershell
$env:CALDOVA_AZURE_MUTATION_ENABLED = 'YES'
$env:CALDOVA_AZURE_TARGET = 'skillable'
pwsh -NoProfile -File scripts/start-simulator.ps1 -LearnerNumber 1
```

It verifies and opens `http://127.0.0.1:7070/?learnerNumber=1`. Press Ctrl+C in the same terminal to stop it cleanly.

The two environment variables are an explicit safety gate. Without both exact values, configuration checks can run, but Start and Reset fail before any Azure resource change.

For local UI and endpoint testing without Azure:

```powershell
pwsh -NoProfile -File scripts/start-simulator.ps1 -LearnerNumber 1 -Mock -NoBrowser
```

The catalog in `scenarios.json` is the single source of truth for the default scenario, learner-facing text, timing, thresholds, incident expectations, and script entry points. Runtime state, exact baseline snapshots, response-plan ownership snapshots, and per-learner locks are stored under the gitignored `.caldova/` directory.

The default `course-recommendations-unavailable` exercise is intentionally different: Check proves all core paths are healthy, Start captures the one non-secret Container Apps setting and immediately generates App Insights evidence, and no alert is expected on the initial run. If the learner later creates the exact guided alert, the same Start action detects it and uses a bounded alert wait. Fix and Reset restore the feature to healthy; Reset runs strict guided-feature readiness.

The catalog also includes independent exercises for response-time degradation, intermittent quiz failures, consistent quiz failures, and missing grade reports. They retain the existing alert ownership and wait behavior.

Once an exercise starts, the learner, target-agent, and scenario selectors remain locked until Reset completes. Verify, Fix, and Reset requests must match the stored active selection. Reset always runs through `scripts/reset.ps1`, which performs the scenario-specific restore once and then requires aggregate workstation readiness before the simulator clears active state and reports **Baseline restored**.
