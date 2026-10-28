namespace CaldovaLoanPortal.Authentication;

/// <summary>
/// Represents the JSON response from the CaldovaAuthGateway /WhoAmI.ashx endpoint.
/// </summary>
public class WhoAmIResponse
{
    public bool Authenticated { get; set; }
    public string? Username { get; set; }
    public string? DisplayName { get; set; }
    public string? SessionToken { get; set; }
    public string[] Roles { get; set; } = Array.Empty<string>();
}
