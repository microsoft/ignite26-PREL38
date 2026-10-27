using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace CaldovaLoanPortal;

public sealed class DatabaseReadiness(Func<SqlConnection> connections, ILogger<DatabaseReadiness> logger) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        try
        {
            await using var connection = connections();
            await connection.OpenAsync(cancellationToken);
            await using var command = new SqlCommand("SELECT 1;", connection);
            await command.ExecuteScalarAsync(cancellationToken);
            return HealthCheckResult.Healthy();
        }
        catch (SqlException exception)
        {
            logger.LogWarning("Database readiness failed (SQL error {ErrorNumber}).", exception.Number);
            return HealthCheckResult.Unhealthy("Database connection is unavailable.");
        }
        catch (InvalidOperationException)
        {
            logger.LogWarning("Database readiness failed: configuration is missing or invalid.");
            return HealthCheckResult.Unhealthy("Database configuration is unavailable.");
        }
    }
}
