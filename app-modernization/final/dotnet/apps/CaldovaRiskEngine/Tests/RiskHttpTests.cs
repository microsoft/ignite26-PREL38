using System.Net;
using System.Text;
using System.Xml.Linq;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace CaldovaRiskEngine.Tests;

public class RiskHttpTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public RiskHttpTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment("Testing");
            builder.ConfigureTestServices(services =>
                services.AddSingleton<Func<SqlConnection>>(() =>
                    throw new InvalidOperationException("private-database-detail")));
        }).CreateClient();
    }

    [Theory]
    [InlineData("/health")]
    [InlineData("/Health.ashx")]
    public async Task LegacyAndModernHealthReturnExactBody(string path)
    {
        var response = await _client.GetAsync(path);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("OK", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task ReadinessIsNotLiveness()
    {
        var response = await _client.GetAsync("/health/ready");
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.DoesNotContain("private-database-detail", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task SoapContractStillExposesAllThreeOperations()
    {
        var response = await _client.GetAsync("/CaldovaRiskEngine.svc?wsdl");
        response.EnsureSuccessStatusCode();
        var document = XDocument.Parse(await response.Content.ReadAsStringAsync());
        XNamespace wsdl = "http://schemas.xmlsoap.org/wsdl/";
        var operations = document.Descendants(wsdl + "portType")
            .Descendants(wsdl + "operation").Select(x => (string?)x.Attribute("name"));
        Assert.Equal(new[] { "GetRiskFactors", "ScoreLoanApplication", "UpdateRiskModel" },
            operations.OrderBy(x => x));
    }

    [Fact]
    public async Task InvalidSoapInputRetainsFaultContract()
    {
        using var request = SoapScore(0);
        var response = await _client.SendAsync(request);
        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
        Assert.Contains("applicationId must be greater than 0.", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task SoapDatabaseFailureDoesNotExposeExceptionDetails()
    {
        using var request = SoapScore(1);
        var response = await _client.SendAsync(request);
        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
        var body = await response.Content.ReadAsStringAsync();
        Assert.Contains("The risk operation could not be completed.", body);
        Assert.DoesNotContain("private-database-detail", body);
    }

    private static HttpRequestMessage SoapScore(int applicationId)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "/CaldovaRiskEngine.svc");
        request.Headers.Add("SOAPAction", "\"http://tempuri.org/IRiskEngineService/ScoreLoanApplication\"");
        request.Content = new StringContent(
            $"""<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><ScoreLoanApplication xmlns="http://tempuri.org/"><applicationId>{applicationId}</applicationId></ScoreLoanApplication></s:Body></s:Envelope>""",
            Encoding.UTF8, "text/xml");
        return request;
    }
}
