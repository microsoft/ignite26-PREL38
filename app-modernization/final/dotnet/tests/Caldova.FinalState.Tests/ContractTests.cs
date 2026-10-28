using System.Net;
using CaldovaAuthGateway;
using CaldovaLoanPortal.Authentication;
using CaldovaLoanPortal.Controllers;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Caldova.FinalState.Tests;

public class ContractTests
{
    private static readonly IConfiguration Configuration = new ConfigurationBuilder()
        .AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["AUTH_ALLOWED_RETURN_ORIGINS"] = "https://portal.example.invalid;http://localhost:8082",
            ["PUBLIC_BASE_URL"] = "http://localhost:8082",
            ["AuthGatewayLoginUrl"] = "http://localhost:8081/Login.aspx"
        }).Build();

    [Theory]
    [InlineData("https://attacker.example/", "/")]
    [InlineData("//attacker.example/", "/")]
    [InlineData("/\\attacker.example/", "/")]
    [InlineData("javascript:alert(1)", "/")]
    [InlineData("https://portal.example.invalid.attacker.example/", "/")]
    [InlineData("https://name@portal.example.invalid/", "/")]
    [InlineData("/safe\nLocation: https://attacker.example", "/")]
    [InlineData("/Home", "/Home")]
    [InlineData("https://portal.example.invalid/Home", "https://portal.example.invalid/Home")]
    [InlineData("http://localhost:8082/Default.aspx", "http://localhost:8082/Default.aspx")]
    public void ReturnUrlIsConstrainedToLocalOrConfiguredOrigins(string input, string expected) =>
        Assert.Equal(expected, ReturnUrlPolicy.Resolve(input, Configuration));

    [Fact]
    public void PortalChallengeReturnsToThePortalRatherThanGatewayRoot()
    {
        var url = GatewayUrls.Login(Configuration, "/Default.aspx?tab=history");
        Assert.Equal(
            "http://localhost:8081/Login.aspx?ReturnUrl=http%3A%2F%2Flocalhost%3A8082%2FDefault.aspx%3Ftab%3Dhistory", url);
    }

    [Theory]
    [InlineData("/health", "OK")]
    [InlineData("/Health.ashx", "OK")]
    [InlineData("/WhoAmI.ashx", "{\"authenticated\":false}")]
    [InlineData("/auth/WhoAmI.ashx", "{\"authenticated\":false}")]
    public async Task GatewayPublicAliasesPreserveBodiesWithoutDatabaseAccess(string path, string expected)
    {
        await using var factory = new WebApplicationFactory<AuthRepository>();
        var client = factory.CreateClient();
        var response = await client.GetAsync(path);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(expected, await response.Content.ReadAsStringAsync());
        Assert.True(response.Headers.CacheControl?.NoStore);
    }

    [Fact]
    public async Task LoginPreservesTheReturnDestinationInItsForm()
    {
        await using var factory = new WebApplicationFactory<AuthRepository>();
        var body = await factory.CreateClient().GetStringAsync("/auth/Login.aspx?ReturnUrl=%2FHome");
        Assert.Contains("action=\"/auth/login\"", body);
        Assert.Contains("name=\"ReturnUrl\" value=\"/Home\"", body);
    }

    [Theory]
    [InlineData("/health")]
    [InlineData("/Health.ashx")]
    public async Task PortalHealthIsAnonymous(string path)
    {
        await using var factory = new WebApplicationFactory<HomeController>();
        var response = await factory.CreateClient().GetAsync(path);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("OK", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task GatewayReadinessFailsExplicitlyWhenConfigurationIsUnavailable()
    {
        await using var factory = new WebApplicationFactory<AuthRepository>().WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services => services.AddSingleton<Func<SqlConnection>>(
                () => throw new InvalidOperationException("not configured"))));
        var response = await factory.CreateClient().GetAsync("/health/ready");
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
    }

    [Fact]
    public async Task PortalDoesNotTurnMissingConfigurationIntoAnEmptySuccessfulPage()
    {
        await using var factory = new WebApplicationFactory<HomeController>();
        var response = await factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        }).GetAsync("/");
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
    }
}
