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

The catalog in `scenarios.json` is the single source of truth for learner-facing scenario text, timing, thresholds, alerts, and script entry points. Runtime state, exact baseline snapshots, response-plan ownership snapshots, and per-learner locks are stored under the gitignored `.caldova/` directory.

Every exercise preserves the same simulator flow: Check validates the selected agent and a healthy baseline, Start captures only the values it will change and waits for a fresh learner-scoped alert, Check recovery measures the learner symptom, Fix restores the captured live state, and Reset restores state plus the original response-plan owner.

The catalog includes independent exercises for response-time degradation, intermittent quiz failures, consistent quiz failures, and missing grade reports. They use the same lock, ownership, progress, mock-driver, Azure-driver, and reset architecture as the original quiz-launch scenarios.

Once an exercise starts, the learner, target-agent, and scenario selectors remain locked until Reset completes. Verify, Fix, and Reset requests must match the stored active selection. Reset always runs through `scripts/reset.ps1`, which performs the scenario-specific restore once and then requires aggregate workstation readiness before the simulator clears active state and reports **Baseline restored**.
