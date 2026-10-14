# Caldova audit report

Create a branded, downloadable PowerPoint audit report only after the read-only investigation is complete. The presentation is an evidence artifact; it must not replace or weaken the in-thread findings.

## Supported artifact flow

1. Use the agent workspace and `RunInTerminal` to generate a real `.pptx` with Python and `python-pptx`.
2. Do not install packages. If `python-pptx` is unavailable, report the exact blocker and do not create, rename, or attach a fake presentation.
3. Use a filename that contains `Caldova`, the review type, and the UTC date, with no spaces or personal names.
4. Validate the output before publishing:
   - the file is non-empty;
   - it opens as an Office Open XML ZIP package;
   - `[Content_Types].xml` and `ppt/presentation.xml` exist;
   - the deck contains at least six slides.
5. Call `SaveFileToBlob` for the validated `.pptx`. Do not claim the report is attached until that tool confirms the file was persisted with the current thread.

## Brand and structure

Use a dark navy and Caldova teal visual theme with high-contrast white text, restrained accent colors, and readable tables. Include:

1. **Cover** — `Caldova`, review title, resource-group scope, and generated-at UTC.
2. **Executive summary** — overall posture, top findings, and explicit unknown or inconclusive areas.
3. **Scope and evidence** — reviewed resources, time range, sources, freshness, and missing evidence.
4. **Findings** — concise evidence-backed table with severity, confidence, affected resource, and recommendation.
5. **Prioritized actions** — preventive, detective, and process recommendations. Keep every action advisory and read-only.
6. **Quality and provenance** — commands or source classes used, captured-at UTC, assumptions, exclusions, no-write confirmation, and the statement `Unknown is never reported as zero, healthy, compliant, or clean.`

Add more slides when needed for readable cost trends, image/dependency correlation, or detailed findings. Do not include access tokens, credentials, secret values, personal data, tenant user identities, or browser/profile information.

## Review-specific requirements

For a cost review, clearly separate billed ActualCost, forecast, Retail Prices estimate, and potential savings. Label cached or last-known-good billed data with its original capture time and cache age.

For a CVE review, correlate source commit and dependency or SBOM evidence with each exact deployed image digest, Defender evidence when available, runtime reachability, network exposure, and business criticality. Missing scan or correlation evidence makes the conclusion `INCONCLUSIVE`, never clean.

## Completion gate

The task is complete only when the in-thread report is present, the validated `.pptx` is persisted as a downloadable thread file, and the final response names the exact attachment. If publication fails, preserve the findings, state the failure, and do not report successful attachment.
