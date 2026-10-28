using Microsoft.Data.SqlClient;

namespace CaldovaAuthGateway;

internal static class DbConfig
{
    public static string GetConnectionString()
    {
        var host = Environment.GetEnvironmentVariable("DB_HOST");
        var database = Environment.GetEnvironmentVariable("DB_NAME");
        if (string.IsNullOrWhiteSpace(host) || string.IsNullOrWhiteSpace(database))
            throw new InvalidOperationException("DB_HOST and DB_NAME must be configured.");

        return new SqlConnectionStringBuilder
        {
            DataSource = $"tcp:{host}",
            InitialCatalog = database,
            Authentication = SqlAuthenticationMethod.ActiveDirectoryDefault,
            Encrypt = SqlConnectionEncryptOption.Mandatory,
            TrustServerCertificate = false
        }.ConnectionString;
    }
}
