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
          query: 'ContainerAppConsoleLogs_CL\n| where ContainerAppName_s startswith "ca-caldova-portal-"\n| where Log_s !has "path=/api/recommendations/health"\n| where Log_s has_any ("request_failed", "502", "503")\n| summarize AggregatedValue = count() by bin(TimeGenerated, 5m)'
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
    autoMitigate: true
    actions: {}
  }
}

module reportingFailures './reporting-alert.bicep' = {
  name: 'reporting-alert'
  params: {
    location: location
    tags: tags
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
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
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    criteria: {
      allOf: [
        {
          query: 'AppTraces\n| where Message startswith "caldova_request service=caldova-api"\n| where Message has " path=/quiz/" or Message has " path=/assessments/"\n| parse Message with * " ms=" ResponseMs:long\n| summarize P95ResponseMs = percentile(ResponseMs, 95), RequestCount = count()\n| where RequestCount >= 5'
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
output reportingAlertName string = reportingFailures.outputs.alertName
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
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    autoMitigate: true
    criteria: {
      allOf: [
        {
          query: 'AGWAccessLogs\n| where RequestUri startswith "/api/quiz/"\n| where toint(HttpStatus) between (500 .. 599)\n| summarize AggregatedValue = count() by bin(TimeGenerated, 5m)'
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
