param location string
param tags object = {}
param logAnalyticsWorkspaceId string
@minValue(100)
@maxValue(10000)
@description('p95 quiz/API response-time threshold. Local healthy requests are below 400 ms; the workshop latency image adds 1,250 ms.')
param quizLatencyThresholdMs int = 900

resource portalFailures 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'Caldova-portal-requests-failing'
  location: location
  tags: tags
  properties: {
    description: 'Caldova users are receiving failed responses from the portal.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    criteria: {
      allOf: [
        {
          query: 'ContainerAppConsoleLogs_CL\n| where ContainerAppName_s startswith "ca-caldova-portal-"\n| where Log_s has_any ("request_failed", "502", "503")\n| summarize AggregatedValue = count() by bin(TimeGenerated, 5m)'
          metricMeasureColumn: 'AggregatedValue'
          timeAggregation: 'Total'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    skipQueryValidation: true
    autoMitigate: false
    actions: {}
  }
}

resource reportingFailures 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'Caldova-reporting-output-missing'
  location: location
  tags: tags
  properties: {
    description: 'Caldova reporting output is not being produced successfully.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    criteria: {
      allOf: [
        {
          query: 'let Recent = Syslog\n| where TimeGenerated > ago(5m)\n| where ProcessName == "caldova-reporting";\nrange check from 1 to 1 step 1\n| extend FailureCount = toscalar(Recent | where SyslogMessage has "FAILED" | count), LastSuccess = toscalar(Recent | where SyslogMessage has "category=CaldovaReportingHeartbeat" and SyslogMessage has "status=ok" | summarize max(TimeGenerated))\n| where FailureCount > 0 or isnull(LastSuccess)\n| project AggregatedValue = 1'
          metricMeasureColumn: 'AggregatedValue'
          timeAggregation: 'Total'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    skipQueryValidation: true
    autoMitigate: false
    actions: {}
  }
}

resource quizLatency 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'Caldova-quiz-response-time-elevated'
  location: location
  tags: tags
  properties: {
    description: 'Caldova learners are experiencing elevated response times when opening quizzes and assessments.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    criteria: {
      allOf: [
        {
          query: 'AppRequests\n| where AppRoleName == "caldova-api"\n| where Url has "/quiz/" or Url has "/assessments/"\n| summarize P95ResponseMs = percentile(DurationMs, 95), RequestCount = count()\n| where RequestCount >= 5'
          metricMeasureColumn: 'P95ResponseMs'
          timeAggregation: 'Maximum'
          operator: 'GreaterThan'
          threshold: quizLatencyThresholdMs
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    skipQueryValidation: true
    autoMitigate: true
    actions: {}
  }
}

output portalAlertName string = portalFailures.name
output reportingAlertName string = reportingFailures.name
output quizLatencyAlertName string = quizLatency.name

resource quizLaunchFailures 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'Caldova-quiz-launch-failing'
  location: location
  tags: tags
  properties: {
    description: 'Caldova learners cannot begin a quiz activity through the public site.'
    severity: 1
    enabled: true
    scopes: [
      logAnalyticsWorkspaceId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT1M'
    autoMitigate: false
    criteria: {
      allOf: [
        {
          query: 'AGWAccessLogs\n| where RequestUri startswith "/api/quiz/"\n| where toint(HttpStatus) between (500 .. 599)\n| summarize AggregatedValue = count() by bin(TimeGenerated, 1m)'
          metricMeasureColumn: 'AggregatedValue'
          timeAggregation: 'Total'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    skipQueryValidation: true
    actions: {}
  }
}

output quizLaunchAlertName string = quizLaunchFailures.name
