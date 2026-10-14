"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..", "..");
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");

test("guided scenario is isolated, default, and initially unowned", () => {
  const catalog = JSON.parse(read("simulator/scenarios.json"));
  const scenario = catalog.scenarios.find((entry) => entry.id === catalog.defaultScenarioId);
  const configuration = read("data/agent/configuration.json");
  const alerts = read("infra/modules/alerts.bicep");
  const responsePlan = read("data/agent/incident-filters/caldova-azure-monitor-response.yaml");

  assert.equal(scenario.id, "course-recommendations-unavailable");
  assert.equal(scenario.incident.expectedInitially, false);
  assert.equal("alert" in scenario, false);
  assert.doesNotMatch(configuration, /course-recommendations-recovery|caldova-guided-feature-responder|course-recommendations-learning-response/);
  assert.match(alerts, /where Log_s !has "path=\/api\/recommendations\/health"/);
  assert.doesNotMatch(alerts, /Course-recommendations-unavailable/);
  assert.match(responsePlan, /titleContains: Caldova/);
  assert.doesNotMatch("Course-recommendations-unavailable", /Caldova/);
});

test("guided scenario mutates only one non-secret setting and supports dynamic alert behavior", () => {
  const source = read("scripts/scenarios/Caldova.CourseRecommendations.psm1");
  assert.match(source, /\$script:SettingName = 'CALDOVA_RECOMMENDATIONS_MODE'/);
  assert.match(source, /containerapp', 'update'/);
  assert.match(source, /Test-CaldovaRecommendationsAlertConfigured/);
  assert.match(source, /Wait-CaldovaRecommendationsAlert/);
  assert.match(source, /alertExpected = \$alertConfigured/);
  assert.match(source, /\/health', '\/ready', '\/api\/courses', '\/api\/quiz\/OPS-201-M1', '\/api\/exports\/recent'/);
  assert.doesNotMatch(source, /secret\s+(?:show|set)|role\s+assignment|network\s+nsg|postgres/i);
});

test("fresh Skillable prepare establishes only the recommendations symptom", () => {
  const template = read("infra/skillable.bicep");
  const prepare = read("scripts/prepare.ps1");
  const scenario = read("scripts/scenarios/Caldova.CourseRecommendations.psm1");

  assert.match(template, /param recommendationsMode string = 'unavailable'/);
  assert.match(prepare, /\$guidedFeature = Initialize-CaldovaRecommendationsPreparedState/);
  assert.ok(
    prepare.indexOf("Initialize-CaldovaRecommendationsPreparedState") >
      prepare.indexOf("No successful Caldova reporting heartbeat"),
    "Prepare must prove the healthy data and reporting baseline before creating the isolated symptom",
  );
  assert.match(scenario, /Assert-CaldovaRecommendationsCoreHealthy -Context \$context/);
  assert.match(scenario, /Set-CaldovaRecommendationsMode -Context \$context -Mode \$script:UnavailableValue/);
  assert.match(scenario, /Wait-CaldovaRecommendationsState -Context \$context -State degraded/);
  assert.match(scenario, /Send-CaldovaRecommendationsTraffic -Context \$context -ExpectedState degraded -Requests 6/);
  assert.match(scenario, /alertExpected = \$false/);
  assert.match(scenario, /\$paths = @\('\/health', '\/ready', '\/api\/courses', '\/api\/quiz\/OPS-201-M1', '\/api\/exports\/recent'\)/);
  assert.match(scenario, /Where-Object \{ \$_ -ne 'Healthy' \}/);
});

test("guided reference artifacts are uniquely named and remain outside the applied bundle", () => {
  const bundle = read("data/agent/configuration.json");
  const skill = read("data/agent/guided-course-recommendations/skill/SKILL.md");
  const agent = read("data/agent/guided-course-recommendations/agent/caldova-guided-feature-responder.yaml");
  const filter = read("data/agent/guided-course-recommendations/incident-filter/course-recommendations-learning-response.yaml");
  const alert = read("data/agent/guided-course-recommendations/alert.bicep");

  assert.match(skill, /name: course-recommendations-recovery/);
  assert.match(agent, /name: caldova-guided-feature-responder/);
  assert.match(filter, /name: course-recommendations-learning-response/);
  assert.match(filter, /titleContains: Course-recommendations-unavailable/);
  assert.match(alert, /name: 'Course-recommendations-unavailable'/);
  for (const name of [
    "course-recommendations-recovery",
    "caldova-guided-feature-responder",
    "course-recommendations-learning-response"
  ]) {
    assert.equal(bundle.includes(name), false);
  }
});
