using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using CaldovaAuthGateway;
using CaldovaLoanPortal.Controllers;
using CaldovaRiskEngine;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Caldova.FinalState.Tests;

[Collection("SQL")]
public sealed class ThreeAppSqlTests(SqlFixture sql)
{
    private WebApplicationFactory<T> Factory<T>(Dictionary<string, string?>? settings = null) where T : class =>
        new WebApplicationFactory<T>().WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Testing");
            builder.ConfigureAppConfiguration((_, config) =>
                config.AddInMemoryCollection(settings ?? new Dictionary<string, string?>()));
            builder.ConfigureTestServices(services =>
            {
                services.AddSingleton<Func<SqlConnection>>(() => new SqlConnection(sql.ConnectionString));
                services.AddDataProtection().UseEphemeralDataProtectionProvider();
            });
        });

    private static HttpClient Client<T>(WebApplicationFactory<T> factory, int port) where T : class =>
        factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            BaseAddress = new Uri($"http://localhost:{port}"), AllowAutoRedirect = false
        });

    private WebApplicationFactory<AuthRepository> Gateway() =>
        Factory<AuthRepository>(new() { ["AUTH_ALLOWED_RETURN_ORIGINS"] = "http://localhost:8082" });

    private async Task<string> SignIn(HttpClient gateway)
    {
        var response = await gateway.PostAsync("/Login.aspx", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["username"] = sql.Username, ["password"] = sql.Password,
            ["ReturnUrl"] = "http://localhost:8082/Default.aspx"
        }));
        Assert.Equal(HttpStatusCode.Redirect, response.StatusCode);
        Assert.Equal("http://localhost:8082/Default.aspx", response.Headers.Location?.AbsoluteUri);
        return response.Headers.GetValues("Set-Cookie")
            .Single(x => x.StartsWith(".CALDOVAAUTH=", StringComparison.Ordinal)).Split(';')[0];
    }

    private WebApplicationFactory<HomeController> Portal(WebApplicationFactory<AuthRepository> gateway) =>
        Factory<HomeController>(new()
        {
            ["AUTH_GATEWAY_WHOAMI_URL"] = "http://localhost:8081/WhoAmI.ashx",
            ["AuthGatewayLoginUrl"] = "http://localhost:8081/Login.aspx",
            ["AuthGatewayLogoutUrl"] = "http://localhost:8081/Logout.aspx",
            ["PUBLIC_BASE_URL"] = "http://localhost:8082",
            ["LoanOriginationApiUrl"] = ""
        }).WithWebHostBuilder(builder => builder.ConfigureTestServices(services =>
            services.AddHttpClient("CaldovaAuth").ConfigurePrimaryHttpMessageHandler(gateway.Server.CreateHandler)));

    [Fact]
    public async Task GatewayCookieAuthenticatesTheRealPortalAndLogoutRevokesTheSession()
    {
        await using var gatewayFactory = Gateway();
        using var gateway = Client(gatewayFactory, 8081);
        var cookie = await SignIn(gateway);
        using var identity = JsonDocument.Parse(await gateway.GetStringAsync("/WhoAmI.ashx"));
        Assert.True(identity.RootElement.GetProperty("authenticated").GetBoolean());
        Assert.Equal(sql.Username, identity.RootElement.GetProperty("username").GetString());
        Assert.Equal("LoanOfficer", identity.RootElement.GetProperty("roles")[0].GetString());
        var sessionToken = identity.RootElement.GetProperty("sessionToken").GetString();

        await using var portalFactory = Portal(gatewayFactory);
        using var portal = Client(portalFactory, 8082);
        portal.DefaultRequestHeaders.Add("Cookie", cookie);
        var page = await portal.GetAsync("/Default.aspx");
        Assert.Equal(HttpStatusCode.OK, page.StatusCode);
        var html = await page.Content.ReadAsStringAsync();
        Assert.Contains("id=\"gvLoanHistory\"", html);
        var token = Regex.Match(html, "name=\"__RequestVerificationToken\"[^>]*value=\"([^\"]+)\"").Groups[1].Value;
        Assert.False(string.IsNullOrEmpty(token));
        var wizard = await portal.PostAsync("/Home/Index", new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["__RequestVerificationToken"] = WebUtility.HtmlDecode(token),
            ["Step"] = "2", ["action"] = "Next", ["CustomerId"] = "1",
            ["FirstName"] = "Fixture", ["LastName"] = "Customer",
            ["Employer"] = "Fixture employer", ["JobTitle"] = "Fixture role"
        }));
        Assert.Equal(HttpStatusCode.OK, wizard.StatusCode);
        Assert.Contains("Fixture loan", await wizard.Content.ReadAsStringAsync());
        Assert.Equal(HttpStatusCode.OK, (await portal.GetAsync("/health/ready")).StatusCode);

        var logout = await portal.GetAsync("/Logout.aspx");
        Assert.Equal("http://localhost:8081/Logout.aspx", logout.Headers.Location?.AbsoluteUri);
        Assert.False(logout.Headers.Contains("Set-Cookie"));
        await gateway.GetAsync("/Logout.aspx");
        using var tokenRequest = new HttpRequestMessage(HttpMethod.Get, "/api/auth/validate");
        tokenRequest.Headers.Add("X-Session-Token", sessionToken);
        using var tokenResponse = await gateway.SendAsync(tokenRequest);
        using var tokenBody = JsonDocument.Parse(await tokenResponse.Content.ReadAsStringAsync());
        Assert.False(tokenBody.RootElement.GetProperty("valid").GetBoolean());
        Assert.Equal(HttpStatusCode.Redirect, (await portal.GetAsync("/Default.aspx")).StatusCode);
    }

    [Fact]
    public async Task RiskSoapScoresAndPersistsTheSameSharedDatabaseApplication()
    {
        await using var factory = Factory<CaldovaRiskEngineService>();
        using var risk = Client(factory, 8083);
        var request = new HttpRequestMessage(HttpMethod.Post, "/CaldovaRiskEngine.svc");
        request.Headers.Add("SOAPAction", "\"http://tempuri.org/IRiskEngineService/ScoreLoanApplication\"");
        request.Content = new StringContent(
            """<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><ScoreLoanApplication xmlns="http://tempuri.org/"><applicationId>1</applicationId></ScoreLoanApplication></s:Body></s:Envelope>""",
            Encoding.UTF8, "text/xml");
        using var response = await risk.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = XDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("76.47", body.Descendants().Single(x => x.Name.LocalName == "CalculatedScore").Value);
        Assert.Equal("B", body.Descendants().Single(x => x.Name.LocalName == "RiskRating").Value);
        await using var connection = new SqlConnection(sql.ConnectionString);
        await connection.OpenAsync();
        await using var command = new SqlCommand(
            "SELECT COUNT(*) FROM RiskAssessments WHERE ApplicationID = 1 AND OverallRiskScore = 76.47 AND RiskLevel = 'B';",
            connection);
        Assert.True((int)(await command.ExecuteScalarAsync())! > 0);
        Assert.Equal(HttpStatusCode.OK, (await risk.GetAsync("/health/ready")).StatusCode);
    }

    [Fact]
    public async Task RiskModelUpdateAndFactorReadExecuteAgainstSql()
    {
        await using var factory = Factory<CaldovaRiskEngineService>();
        using var risk = Client(factory, 8083);
        var update = await risk.PostAsJsonAsync("/api/risk/model", new RiskModelUpdateRequest
        {
            UpdatedBy = "fixture-operator",
            Parameters = new() { new RiskModelParameter { Name = "BaseScore", Value = 5m } }
        });
        Assert.Equal(HttpStatusCode.OK, update.StatusCode);
        var result = await update.Content.ReadFromJsonAsync<RiskModelUpdateResponse>();
        Assert.True(result?.Success);
        Assert.Equal(1, result?.UpdatedCount);
        var factors = await risk.GetFromJsonAsync<RiskFactorsResponse>("/api/risk/factors/1");
        Assert.Equal(1, factors?.CustomerId);
        Assert.Equal(4, factors?.Factors?.Count);
    }

    [Fact]
    public async Task PortalSubmissionCanBeScoredByTheModernizedRiskService()
    {
        await using var gatewayFactory = Gateway();
        using var gateway = Client(gatewayFactory, 8081);
        var cookie = await SignIn(gateway);
        await using var portalFactory = Portal(gatewayFactory);
        using var portal = Client(portalFactory, 8082);
        portal.DefaultRequestHeaders.Add("Cookie", cookie);
        var purpose = "validation-" + Guid.NewGuid().ToString("N");
        var response = await PostPortal(portal, new()
        {
            ["Step"] = "5", ["action"] = "Finish", ["CustomerId"] = "1",
            ["LoanProductId"] = "1", ["RequestedAmount"] = "12000",
            ["TermMonths"] = "60", ["Purpose"] = purpose
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("Application saved. External forwarding is not configured; do not resubmit.",
            await response.Content.ReadAsStringAsync());

        await using var connection = new SqlConnection(sql.ConnectionString);
        await connection.OpenAsync();
        await using var query = new SqlCommand(
            "SELECT ApplicationID FROM LoanApplications WHERE Purpose = @purpose;", connection);
        query.Parameters.AddWithValue("@purpose", purpose);
        var applicationId = (int)(await query.ExecuteScalarAsync())!;
        await using var riskFactory = Factory<CaldovaRiskEngineService>();
        using var risk = Client(riskFactory, 8083);
        var score = await risk.PostAsync($"/api/risk/score/{applicationId}", null);
        Assert.Equal(HttpStatusCode.OK, score.StatusCode);
        var result = await score.Content.ReadFromJsonAsync<RiskScoreResponse>();
        Assert.Equal(applicationId, result?.ApplicationId);
        Assert.Equal(66.37m, result?.CalculatedScore);
        Assert.Equal("C", result?.RiskRating);
        Assert.Equal(10800m, result?.MaxApprovedAmount);
    }

    [Fact]
    public async Task InvalidSubmissionIsNotReportedAsSaved()
    {
        await using var gatewayFactory = Gateway();
        using var gateway = Client(gatewayFactory, 8081);
        var cookie = await SignIn(gateway);
        await using var portalFactory = Portal(gatewayFactory);
        using var portal = Client(portalFactory, 8082);
        portal.DefaultRequestHeaders.Add("Cookie", cookie);
        var response = await PostPortal(portal, new()
        {
            ["Step"] = "5", ["action"] = "Finish", ["CustomerId"] = "1",
            ["LoanProductId"] = "1", ["RequestedAmount"] = "-1", ["TermMonths"] = "60"
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var html = await response.Content.ReadAsStringAsync();
        Assert.Contains("Enter a valid customer, product, positive amount and term.", html);
        Assert.DoesNotContain("Application saved", html);
    }

    [Fact]
    public async Task GoingBackRebuildsTheReviewInsteadOfRenderingPostedHtml()
    {
        await using var gatewayFactory = Gateway();
        using var gateway = Client(gatewayFactory, 8081);
        var cookie = await SignIn(gateway);
        await using var portalFactory = Portal(gatewayFactory);
        using var portal = Client(portalFactory, 8082);
        portal.DefaultRequestHeaders.Add("Cookie", cookie);
        var response = await PostPortal(portal, new()
        {
            ["Step"] = "5", ["action"] = "Previous", ["FirstName"] = "Fixture",
            ["LastName"] = "Customer", ["RequestedAmount"] = "12000", ["TermMonths"] = "60",
            ["ReviewSummary"] = "<script>untrusted()</script>"
        });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var html = await response.Content.ReadAsStringAsync();
        Assert.DoesNotContain("<script>untrusted()", html);
        Assert.Contains("<b>Customer:</b> Fixture Customer", html);
    }

    private static async Task<HttpResponseMessage> PostPortal(HttpClient portal, Dictionary<string, string> form)
    {
        var page = await portal.GetStringAsync("/Default.aspx");
        var token = Regex.Match(page, "name=\"__RequestVerificationToken\"[^>]*value=\"([^\"]+)\"").Groups[1].Value;
        Assert.False(string.IsNullOrEmpty(token));
        form["__RequestVerificationToken"] = WebUtility.HtmlDecode(token);
        return await portal.PostAsync("/Home/Index", new FormUrlEncodedContent(form));
    }
}
