using System.Reflection;
using System.Runtime.Serialization;
using System.Xml.Linq;
using CaldovaRiskEngine;
using Xunit;

namespace CaldovaRiskEngine.Tests;

public class RiskBehaviorTests
{
    private static T Invoke<T>(string method, params object[] args) =>
        (T)typeof(CaldovaRiskEngineService)
            .GetMethod(method, BindingFlags.NonPublic | BindingFlags.Static)!
            .Invoke(null, args)!;

    [Theory]
    [InlineData(0, "0")]
    [InlineData(300, "0")]
    [InlineData(575, "0.5")]
    [InlineData(850, "1")]
    [InlineData(1200, "1")]
    public void CreditScoreNormalizationIsPreserved(int score, string expected) =>
        Assert.Equal(decimal.Parse(expected, System.Globalization.CultureInfo.InvariantCulture),
            Invoke<decimal>("NormalizeCreditScore", score));

    [Theory]
    [InlineData("0", "0", "0.5")]
    [InlineData("5000", "10000", "0.5")]
    [InlineData("-10", "100", "0")]
    [InlineData("200", "100", "1")]
    public void BalanceNormalizationIsPreserved(string balance, string requested, string expected)
    {
        var culture = System.Globalization.CultureInfo.InvariantCulture;
        Assert.Equal(decimal.Parse(expected, culture),
            Invoke<decimal>("NormalizeBalance", decimal.Parse(balance, culture), decimal.Parse(requested, culture)));
    }

    [Theory]
    [InlineData(0, "1")]
    [InlineData(180, "0.5")]
    [InlineData(360, "0")]
    [InlineData(720, "0")]
    public void TermNormalizationIsPreserved(int months, string expected) =>
        Assert.Equal(decimal.Parse(expected, System.Globalization.CultureInfo.InvariantCulture),
            Invoke<decimal>("NormalizeTerm", months));

    [Theory]
    [InlineData("85", "A")]
    [InlineData("84.99", "B")]
    [InlineData("75", "B")]
    [InlineData("65", "C")]
    [InlineData("55", "D")]
    [InlineData("45", "E")]
    [InlineData("44.99", "F")]
    public void RatingBoundariesArePreserved(string score, string expected) =>
        Assert.Equal(expected, Invoke<string>("GetRating",
            decimal.Parse(score, System.Globalization.CultureInfo.InvariantCulture)));

    [Theory]
    [InlineData("A", "1.25")]
    [InlineData("B", "1.10")]
    [InlineData("C", "0.90")]
    [InlineData("D", "0.70")]
    [InlineData("E", "0.50")]
    [InlineData("F", "0")]
    public void ApprovalMultipliersArePreserved(string rating, string expected) =>
        Assert.Equal(decimal.Parse(expected, System.Globalization.CultureInfo.InvariantCulture),
            Invoke<decimal>("GetApprovalMultiplier", rating));

    [Fact]
    public void ScoreDataContractRetainsItsNamespaceAndMembers()
    {
        var serializer = new DataContractSerializer(typeof(RiskScoreResponse));
        using var stream = new MemoryStream();
        serializer.WriteObject(stream, new RiskScoreResponse { RiskRating = "A" });
        stream.Position = 0;
        var element = XElement.Load(stream);
        Assert.Equal("RiskScoreResponse", element.Name.LocalName);
        Assert.Equal("http://schemas.datacontract.org/2004/07/CaldovaRiskEngine", element.Name.NamespaceName);
        Assert.Equal(new[]
        {
            "ApplicationId", "CalculatedScore", "CustomerId", "EvaluatedAtUtc",
            "MaxApprovedAmount", "RequestedAmount", "RiskRating"
        }, element.Elements().Select(x => x.Name.LocalName));
    }
}
