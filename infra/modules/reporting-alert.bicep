param location string
param tags object = {}
param logAnalyticsWorkspaceId string

resource reportingFailures 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'Caldova-reporting-output-missing'
  location: location
  tags: tags
  properties: {
    description: 'Caldova reporting output is not being produced successfully.'
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
          query: 'let Recent = Syslog\n| where TimeGenerated > ago(5m)\n| where ProcessName == "caldova-reporting";\nlet LastFailure = toscalar(Recent | where SyslogMessage has "status=FAILED" | summarize max(TimeGenerated));\nlet LastSuccess = toscalar(Recent | where SyslogMessage has "category=CaldovaReportingHeartbeat" and SyslogMessage has "status=ok" | summarize max(TimeGenerated));\nrange check from 1 to 1 step 1\n| where isnotnull(LastFailure) and (isnull(LastSuccess) or LastFailure > LastSuccess)\n| project AggregatedValue = 1'
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

output alertName string = reportingFailures.name
