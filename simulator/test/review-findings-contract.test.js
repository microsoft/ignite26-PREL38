"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const repoRoot = path.resolve(__dirname, "..", "..");
const read = (relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), "utf8");

function runPowerShell(script, env = {}) {
  const result = spawnSync("pwsh", ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, ...env }
  });
  assert.equal(result.status, 0, `${result.stderr}\n${result.stdout}`);
  return result.stdout.trim();
}

test("protected deployment parameters keep secrets out of Azure CLI arguments and errors", () => {
  const secret = ["Literal", "Review", "Value", "9f7c!"].join("-");
  const modulePath = path.join(repoRoot, "scripts", "Caldova.Lifecycle.psm1");
  const output = runPowerShell(`
    Import-Module ${JSON.stringify(modulePath)} -Force
    $secret = $env:CALDOVA_REVIEW_SECRET
    $path = New-CaldovaProtectedParameterFile -Parameters @{ postgresAdminPassword = $secret; location = 'westus3' } -SensitiveParameterNames @('postgresAdminPassword')
    try {
      $arguments = @('deployment','sub','create','--parameters',"@$path")
      function global:az {
        $global:LASTEXITCODE = 7
        Write-Error "simulated failure containing $secret"
      }
      $errorText = ''
      try { Invoke-CaldovaAz -Arguments $arguments -SensitiveValues @($secret) | Out-Null } catch { $errorText = $_.Exception.Message }
      [pscustomobject]@{
        argumentsContainSecret = (($arguments -join ' ').Contains($secret))
        errorContainsSecret = $errorText.Contains($secret)
        errorWasRedacted = $errorText.Contains('[REDACTED]')
        parameterFileContainsSecret = (Get-Content -LiteralPath $path -Raw).Contains($secret)
      } | ConvertTo-Json -Compress
    } finally {
      Remove-CaldovaProtectedParameterFile -Path $path
    }
  `, { CALDOVA_REVIEW_SECRET: secret });
  const result = JSON.parse(output.split(/\r?\n/).at(-1));
  assert.equal(result.argumentsContainSecret, false);
  assert.equal(result.errorContainsSecret, false);
  assert.equal(result.errorWasRedacted, true);
  assert.equal(result.parameterFileContainsSecret, true);

  const provision = read("scripts/provision.ps1");
  assert.doesNotMatch(provision, /postgresAdminPassword=\$postgresPassword/);
  assert.match(provision, /New-CaldovaProtectedParameterFile/);
  assert.match(provision, /finally\s*\{[\s\S]*Remove-CaldovaProtectedParameterFile/);
});

test("SRE Agent role assignments support non-user deployers and grant no secret data-plane role", () => {
  const bicep = read("infra/modules/sre-agents.bicep");
  assert.doesNotMatch(bicep, /principalType:\s*'User'/);
  assert.doesNotMatch(bicep, /4633458b-17de-408a-b874-0445c86b69e6|keyVaultSecretsUser/i);
  assert.match(bicep, /principalId:\s*deployer\(\)\.objectId/);
  const architecture = read("docs/architecture.md");
  assert.match(architecture, /no Key Vault secret-value data-plane role/i);
});

test("snapshot-less scenario one deletion requires the complete planted fingerprint", () => {
  const modulePath = path.join(repoRoot, "scripts", "scenarios", "Caldova.QuizLaunch.psm1");
  const output = runPowerShell(`
    Import-Module ${JSON.stringify(modulePath)} -Force
    $exact = [pscustomobject]@{
      name = 'caldova-quiz-launch-scenario-1'; priority = 220; direction = 'Inbound'; access = 'Deny'; protocol = 'Tcp'
      sourceAddressPrefix = '10.20.0.0/24'; sourcePortRange = '*'; destinationAddressPrefix = '*'; destinationPortRange = '443'
      description = 'Caldova learner scenario 1'
    }
    $mismatch = $exact.PSObject.Copy()
    $mismatch.destinationPortRange = '80'
    [pscustomobject]@{
      exact = Test-CaldovaScenarioOneRuleFingerprint -Rule $exact -ExpectedSourcePrefix '10.20.0.0/24'
      mismatch = Test-CaldovaScenarioOneRuleFingerprint -Rule $mismatch -ExpectedSourcePrefix '10.20.0.0/24'
    } | ConvertTo-Json -Compress
  `);
  const result = JSON.parse(output.split(/\r?\n/).at(-1));
  assert.equal(result.exact, true);
  assert.equal(result.mismatch, false);
  const module = read("scripts/scenarios/Caldova.QuizLaunch.psm1");
  assert.match(module, /does not exactly match the planted scenario fingerprint\. Refusing to delete it/);
});

test("quiz launch alert uses supported five-minute path-specific gateway access evidence", () => {
  const alert = read("infra/modules/alerts.bicep");
  const gateway = read("infra/modules/application-gateway.bicep");
  const facilitator = read("docs/facilitator-scenarios.md");
  assert.match(gateway, /category:\s*'ApplicationGatewayAccessLog'/);
  assert.match(gateway, /logAnalyticsDestinationType:\s*'Dedicated'/);
  assert.match(alert, /resource quizLaunchFailures 'Microsoft\.Insights\/scheduledQueryRules/);
  assert.match(alert, /evaluationFrequency:\s*'PT5M'/);
  assert.match(alert, /RequestUri startswith "\/api\/quiz\/"/);
  assert.match(alert, /HttpStatus\) between \(500 \.\. 599\)/);
  assert.doesNotMatch(alert, /metricName:\s*'FailedRequests'/);
  assert.match(facilitator, /each path-isolation scenario produces the same quiz-specific signal/i);
  assert.match(facilitator, /excludes non-quiz routes and non-5xx responses/i);
});

test("simulator locks selectors for an active exercise and aggregate reset gates idle on readiness", () => {
  const app = read("simulator/public/app.js");
  const reset = read("scripts/reset.ps1");
  assert.match(app, /exerciseActive = busy \|\| state\.active/);
  assert.match(app, /elements\.learner\.disabled = exerciseActive/);
  assert.match(app, /elements\.scenario\.disabled = exerciseActive/);
  assert.match(app, /input\.disabled = exerciseActive/);
  const scenarioResetPosition = reset.indexOf("& $resetScript");
  const readinessPosition = reset.indexOf("readiness.ps1");
  assert.ok(scenarioResetPosition >= 0 && readinessPosition > scenarioResetPosition);
});
