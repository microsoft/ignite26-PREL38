using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.SqlClient;
using Xunit;

namespace Caldova.FinalState.Tests;

public sealed class SqlFixture : IAsyncLifetime
{
    private string? _container;
    public string ConnectionString { get; private set; } = "";
    public string Username { get; } = "fixture-user@example.invalid";
    public string Password { get; } = Convert.ToHexString(RandomNumberGenerator.GetBytes(24));

    public async Task InitializeAsync()
    {
        var sqlPassword = Convert.ToHexString(RandomNumberGenerator.GetBytes(24)) + "a!";
        try
        {
            _container = (await Docker(new[]
            {
                "run", "--detach", "--platform", "linux/amd64", "--memory", "3g", "--cpus", "2",
                "--label", "copilot.validation=prel38-final-dotnet",
                "--env", "ACCEPT_EULA=Y", "--env", "MSSQL_PID=Developer",
                "--env", "MSSQL_SA_PASSWORD", "--publish", "127.0.0.1::1433",
                "mcr.microsoft.com/mssql/server:2022-latest"
            }, sqlPassword)).Trim();
            var address = (await Docker(new[] { "port", _container, "1433/tcp" })).Trim();
            var port = address[(address.LastIndexOf(':') + 1)..];
            var connection = new SqlConnectionStringBuilder
            {
                DataSource = $"127.0.0.1,{port}", UserID = "sa", Password = sqlPassword,
                Encrypt = SqlConnectionEncryptOption.Optional, ConnectTimeout = 3
            };
            var ready = false;
            for (var attempt = 0; attempt < 60; attempt++)
            {
                try
                {
                    await using var probe = new SqlConnection(connection.ConnectionString);
                    await probe.OpenAsync();
                    ready = true;
                    break;
                }
                catch (SqlException)
                {
                    await Task.Delay(1000);
                }
            }
            if (!ready)
                throw new InvalidOperationException("The isolated SQL fixture did not become ready.");
            await using (var master = new SqlConnection(connection.ConnectionString))
            {
                await master.OpenAsync();
                await using var create = new SqlCommand("CREATE DATABASE CaldovaFinalValidation;", master);
                await create.ExecuteNonQueryAsync();
            }
            connection.InitialCatalog = "CaldovaFinalValidation";
            ConnectionString = connection.ConnectionString;
            await using var database = new SqlConnection(ConnectionString);
            await database.OpenAsync();
            await using (var schema = new SqlCommand(
                await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "schema.sql")), database))
                await schema.ExecuteNonQueryAsync();
            var salt = Convert.ToHexString(RandomNumberGenerator.GetBytes(16));
            var hash = Convert.ToHexString(SHA1.HashData(Encoding.UTF8.GetBytes(salt + Password)));
            await using var user = new SqlCommand(
                "INSERT INTO Users (UserID, Username, PasswordHash, Salt, IsActive, IsLockedOut, FirstName, LastName) " +
                "VALUES (1, @username, @hash, @salt, 1, 0, 'Fixture', 'Customer');", database);
            user.Parameters.AddWithValue("@username", Username);
            user.Parameters.AddWithValue("@hash", hash);
            user.Parameters.AddWithValue("@salt", salt);
            await user.ExecuteNonQueryAsync();
        }
        catch
        {
            await DisposeAsync();
            throw;
        }
    }

    public async Task DisposeAsync()
    {
        SqlConnection.ClearAllPools();
        if (_container is not null)
        {
            await Docker(new[] { "rm", "--force", _container });
            _container = null;
        }
    }

    private static async Task<string> Docker(string[] arguments, string? password = null)
    {
        var start = new ProcessStartInfo("docker")
        {
            RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false
        };
        foreach (var argument in arguments)
            start.ArgumentList.Add(argument);
        if (password is not null)
            start.Environment["MSSQL_SA_PASSWORD"] = password;
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Docker could not start.");
        var output = process.StandardOutput.ReadToEndAsync();
        var error = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        if (process.ExitCode != 0)
            throw new InvalidOperationException($"Docker command failed ({process.ExitCode}): {await error}");
        return await output;
    }
}

[CollectionDefinition("SQL", DisableParallelization = true)]
public sealed class SqlCollection : ICollectionFixture<SqlFixture>;
