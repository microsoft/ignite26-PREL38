#nullable enable
using System.Text.RegularExpressions;

namespace CaldovaAuthGateway
{
    /// <summary>
    /// PII masking helper for Caldova Bank policy ZB-MOD-001, section 6, item 1.
    /// Masks or omits personally identifiable information before it is written to
    /// any log, trace, metric dimension, audit record, console, or exception message.
    /// </summary>
    public static class PiiMask
    {
        // SSN: 123-45-6789 or 123456789
        private static readonly Regex SsnPattern =
            new(@"\b(\d{3})-?(\d{2})-?(\d{4})\b", RegexOptions.Compiled);

        // Account / card number: 12–19 consecutive digits
        private static readonly Regex AccountDigitPattern =
            new(@"\b\d{12,19}\b", RegexOptions.Compiled);

        /// <summary>
        /// Masks an SSN to the format <c>***-**-1234</c>.
        /// Returns <c>***-**-****</c> if the value is null or empty.
        /// </summary>
        public static string Ssn(string? ssn)
        {
            if (string.IsNullOrEmpty(ssn))
                return "***-**-****";

            var match = SsnPattern.Match(ssn);
            if (match.Success)
                return $"***-**-{match.Groups[3].Value}";

            // Fallback: show only last 4 characters
            return ssn.Length >= 4
                ? $"***-**-{ssn[^4..]}"
                : "***-**-****";
        }

        /// <summary>
        /// Masks an account or card number to the format <c>****1234</c>.
        /// Returns <c>****</c> if the value is null, empty, or has fewer than 4 digits.
        /// </summary>
        public static string Account(string? accountNumber)
        {
            if (string.IsNullOrEmpty(accountNumber))
                return "****";

            // Strip non-digit separators before examining the number
            var digits = Regex.Replace(accountNumber, @"\D", "");
            return digits.Length >= 4
                ? $"****{digits[^4..]}"
                : "****";
        }

        /// <summary>
        /// Masks an email address to the format <c>j***@example.com</c>.
        /// Returns <c>***</c> if the value is null, empty, or has no '@'.
        /// </summary>
        public static string Email(string? email)
        {
            if (string.IsNullOrEmpty(email))
                return "***";

            var at = email.IndexOf('@');
            if (at <= 0)
                return "***";

            var domain = email[at..];
            return $"{email[0]}***{domain}";
        }

        /// <summary>
        /// Masks a phone number to the format <c>***-***-1234</c>.
        /// Returns <c>***-***-****</c> if the value is null, empty, or has fewer than 4 digits.
        /// </summary>
        public static string Phone(string? phone)
        {
            if (string.IsNullOrEmpty(phone))
                return "***-***-****";

            var digits = Regex.Replace(phone, @"\D", "");
            return digits.Length >= 4
                ? $"***-***-{digits[^4..]}"
                : "***-***-****";
        }
    }
}
