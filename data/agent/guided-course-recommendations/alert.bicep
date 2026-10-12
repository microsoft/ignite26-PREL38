param location string
param appInsightsId string
param tags object = {}
param enabled bool = false

resource recommendationsUnavailable 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'Course-recommendations-unavailable'
  location: location
  tags: tags
  properties: {
    description: 'The optional course recommendations experience is unavailable while core learning remains healthy.'
    severity: 3
    enabled: enabled
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      appInsightsId
    ]
    criteria: {
      allOf: [
        {
          query: 'customEvents\n| where timestamp > ago(5m)\n| where name == "CaldovaRecommendationsHealth"\n| where tostring(customDimensions.featureStatus) == "degraded"\n| where tostring(customDimensions.route) == "/recommendations/health"\n| summarize AggregatedValue = count()'
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

output alertName string = recommendationsUnavailable.name
output alertEnabled bool = enabled
