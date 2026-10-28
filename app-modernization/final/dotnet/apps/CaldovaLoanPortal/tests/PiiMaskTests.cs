using Xunit;
using CaldovaLoanPortal.Helpers;

namespace CaldovaLoanPortal.Tests;

/// <summary>
/// Tests verifying that PiiMask correctly masks sensitive personal data
/// before it is written to logs, traces, or telemetry.
/// Per Caldova Bank policy ZB-MOD-001, section 6, item 1.
/// </summary>
public class PiiMaskTests
{
    // ── SSN masking ────────────────────────────────────────────────────────────

    [Theory]
    [InlineData("123-45-6789", "***-**-6789")]
    [InlineData("123456789",   "***-**-6789")]
    public void Ssn_ReturnsExpectedMaskedFormat(string input, string expected)
    {
        Assert.Equal(expected, PiiMask.Ssn(input));
    }

    [Fact]
    public void Ssn_NullOrEmpty_ReturnsFullMask()
    {
        Assert.Equal("***-**-****", PiiMask.Ssn(null));
        Assert.Equal("***-**-****", PiiMask.Ssn(""));
    }

    [Fact]
    public void Ssn_LogMessage_DoesNotContainRawSsn()
    {
        // Simulates: _logger.LogInformation("Application for SSN {Ssn}", PiiMask.Ssn(rawSsn))
        const string rawSsn = "123-45-6789";
        var logMessage = string.Format("Application for SSN {0}", PiiMask.Ssn(rawSsn));

        Assert.DoesNotContain(rawSsn, logMessage);
        Assert.DoesNotContain("123", logMessage);
        Assert.DoesNotContain("45", logMessage);
        Assert.Contains("6789", logMessage);       // last 4 digits are visible
    }

    // ── Account / card number masking ─────────────────────────────────────────

    [Theory]
    [InlineData("1234567890",     "****7890")]
    [InlineData("9876543210123456", "****3456")]
    public void Account_ReturnsExpectedMaskedFormat(string input, string expected)
    {
        Assert.Equal(expected, PiiMask.Account(input));
    }

    [Fact]
    public void Account_NullOrEmpty_ReturnsFullMask()
    {
        Assert.Equal("****", PiiMask.Account(null));
        Assert.Equal("****", PiiMask.Account(""));
    }

    [Fact]
    public void Account_LogMessage_DoesNotContainRawAccountNumber()
    {
        // Simulates: _logger.LogInformation("Payment for account {Account}", PiiMask.Account(rawAccount))
        const string rawAccount = "9876543210123456";
        var logMessage = string.Format("Payment for account {0}", PiiMask.Account(rawAccount));

        Assert.DoesNotContain(rawAccount, logMessage);
        Assert.DoesNotContain("987654321012", logMessage); // leading digits must not appear
        Assert.Contains("3456", logMessage);                // last 4 digits are visible
    }

    // ── Email masking ──────────────────────────────────────────────────────────

    [Theory]
    [InlineData("john.doe@example.com", "j***@example.com")]
    [InlineData("a@test.org",           "***@test.org")]
    public void Email_ReturnsExpectedMaskedFormat(string input, string expected)
    {
        Assert.Equal(expected, PiiMask.Email(input));
    }

    [Fact]
    public void Email_NullOrEmpty_ReturnsFullMask()
    {
        Assert.Equal("***@***", PiiMask.Email(null));
        Assert.Equal("***@***", PiiMask.Email(""));
    }

    [Fact]
    public void Email_LogMessage_DoesNotContainRawLocalPart()
    {
        const string rawEmail = "john.doe@example.com";
        var logMessage = string.Format("Contact email {0}", PiiMask.Email(rawEmail));

        Assert.DoesNotContain("john.doe", logMessage);
        Assert.Contains("@example.com", logMessage); // domain is preserved
    }

    // ── Phone masking ──────────────────────────────────────────────────────────

    [Theory]
    [InlineData("555-867-5309", "***-***-5309")]
    [InlineData("5558675309",   "***-***-5309")]
    public void Phone_ReturnsExpectedMaskedFormat(string input, string expected)
    {
        Assert.Equal(expected, PiiMask.Phone(input));
    }

    [Fact]
    public void Phone_NullOrEmpty_ReturnsFullMask()
    {
        Assert.Equal("***-***-****", PiiMask.Phone(null));
        Assert.Equal("***-***-****", PiiMask.Phone(""));
    }

    // ── Combined: SSN and account in same log message ─────────────────────────

    [Fact]
    public void CombinedLogMessage_WithSsnAndAccount_ContainsNeitherRawValue()
    {
        const string rawSsn     = "987-65-4321";
        const string rawAccount = "1234567890123456";

        var logMessage = string.Format(
            "Loan submitted — SSN {0}, account {1}",
            PiiMask.Ssn(rawSsn),
            PiiMask.Account(rawAccount));

        // Raw SSN digits must not appear
        Assert.DoesNotContain("987", logMessage);
        Assert.DoesNotContain("65", logMessage);

        // Raw account prefix must not appear
        Assert.DoesNotContain("123456789012", logMessage);

        // Only last-4 fragments are acceptable
        Assert.Contains("4321", logMessage);
        Assert.Contains("3456", logMessage);
    }
}
