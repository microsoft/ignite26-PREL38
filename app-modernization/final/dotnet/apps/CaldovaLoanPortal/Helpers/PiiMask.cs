using System.Text.RegularExpressions;

namespace CaldovaLoanPortal.Helpers;

/// <summary>
/// PII masking utilities per Caldova Bank policy ZB-MOD-001, section 6, item 1.
/// Masks sensitive personal data before it is written to logs, traces,
/// metrics dimensions, or exception messages.
/// </summary>
/// <remarks>
/// Usage:
///   _logger.LogInformation("Payment for account {Account}", PiiMask.Account(accountNumber));
///   _logger.LogInformation("Application for SSN {Ssn}", PiiMask.Ssn(ssn));
/// </remarks>
public static class PiiMask
{
    private static readonly Regex NonDigits = new(@"\D", RegexOptions.Compiled);

    /// <summary>
    /// Masks a Social Security Number, exposing only the last 4 digits.
    /// Output format: ***-**-1234
    /// </summary>
    public static string Ssn(string? value)
    {
        if (string.IsNullOrEmpty(value)) return "***-**-****";
        var digits = NonDigits.Replace(value, "");
        return digits.Length >= 4
            ? $"***-**-{digits[^4..]}"
            : "***-**-****";
    }

    /// <summary>
    /// Masks an account or card number, exposing only the last 4 digits.
    /// Output format: ****1234
    /// </summary>
    public static string Account(string? value)
    {
        if (string.IsNullOrEmpty(value)) return "****";
        var stripped = value.Trim();
        return stripped.Length >= 4
            ? $"****{stripped[^4..]}"
            : "****";
    }

    /// <summary>
    /// Masks an email address, exposing only the first character of the local part and the domain.
    /// Output format: j***@example.com
    /// </summary>
    public static string Email(string? value)
    {
        if (string.IsNullOrEmpty(value)) return "***@***";
        var atIdx = value.IndexOf('@');
        if (atIdx <= 0) return "***@***";
        var local = value[..atIdx];
        var domain = value[(atIdx + 1)..];
        var maskedLocal = local.Length > 1 ? $"{local[0]}***" : "***";
        return $"{maskedLocal}@{domain}";
    }

    /// <summary>
    /// Masks a phone number, exposing only the last 4 digits.
    /// Output format: ***-***-1234
    /// </summary>
    public static string Phone(string? value)
    {
        if (string.IsNullOrEmpty(value)) return "***-***-****";
        var digits = NonDigits.Replace(value, "");
        return digits.Length >= 4
            ? $"***-***-{digits[^4..]}"
            : "***-***-****";
    }
}
