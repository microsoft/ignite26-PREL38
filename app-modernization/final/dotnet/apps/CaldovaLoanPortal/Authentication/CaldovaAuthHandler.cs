using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace CaldovaLoanPortal.Authentication;

/// <summary>
/// Scheme name constant for the CaldovaAuthGateway authentication scheme.
/// </summary>
public static class CaldovaAuthDefaults
{
    public const string AuthenticationScheme = "CaldovaAuth";
}

/// <summary>
/// Custom ASP.NET Core authentication handler that validates the .CALDOVAAUTH cookie
/// by calling the CaldovaAuthGateway /WhoAmI.ashx endpoint.
/// </summary>
public class CaldovaAuthHandler : AuthenticationHandler<CaldovaAuthOptions>
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IConfiguration _configuration;

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public CaldovaAuthHandler(
        IOptionsMonitor<CaldovaAuthOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder,
        IHttpClientFactory httpClientFactory,
        IConfiguration configuration)
        : base(options, logger, encoder)
    {
        _httpClientFactory = httpClientFactory;
        _configuration = configuration;
    }

    /// <summary>
    /// Reads the .CALDOVAAUTH cookie and validates it against the WhoAmI endpoint.
    /// Returns a successful ticket if authenticated, or NoResult/Failure otherwise.
    /// </summary>
    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var cookieValue = Request.Cookies[".CALDOVAAUTH"];
        if (string.IsNullOrEmpty(cookieValue))
        {
            // No cookie — anonymous request; not an error
            Logger.LogDebug("Authentication skipped: .CALDOVAAUTH cookie absent.");
            return AuthenticateResult.NoResult();
        }

        var whoAmIUrl = _configuration["AUTH_GATEWAY_WHOAMI_URL"];
        if (string.IsNullOrEmpty(whoAmIUrl))
        {
            Logger.LogWarning("Authentication failed: AUTH_GATEWAY_WHOAMI_URL is not configured.");
            return AuthenticateResult.Fail("AUTH_GATEWAY_WHOAMI_URL is not configured.");
        }

        try
        {
            var client = _httpClientFactory.CreateClient("CaldovaAuth");
            // Pass the cookie value as a Cookie header so the gateway can validate it
            using var requestMessage = new HttpRequestMessage(HttpMethod.Get, whoAmIUrl);
            requestMessage.Headers.Add("Cookie", $".CALDOVAAUTH={cookieValue}");

            using var response = await client.SendAsync(requestMessage, Context.RequestAborted);
            if (!response.IsSuccessStatusCode)
            {
                Logger.LogWarning("Authentication failed: WhoAmI endpoint returned status {StatusCode}.", response.StatusCode);
                return AuthenticateResult.Fail($"WhoAmI endpoint returned {response.StatusCode}.");
            }

            var json = await response.Content.ReadAsStringAsync();
            var whoAmI = JsonSerializer.Deserialize<WhoAmIResponse>(json, JsonOptions);

            if (whoAmI is null || !whoAmI.Authenticated ||
                string.IsNullOrWhiteSpace(whoAmI.Username) ||
                string.IsNullOrWhiteSpace(whoAmI.SessionToken) || whoAmI.Roles is null)
            {
                Logger.LogInformation("Authentication failed: WhoAmI response indicates unauthenticated session.");
                return AuthenticateResult.Fail("Not authenticated.");
            }

            var claims = new List<Claim>
            {
                new(ClaimTypes.Name, whoAmI.Username ?? string.Empty),
                new("displayName", whoAmI.DisplayName ?? string.Empty),
                new("sessionToken", whoAmI.SessionToken ?? string.Empty),
            };

            foreach (var role in whoAmI.Roles)
            {
                claims.Add(new Claim(ClaimTypes.Role, role));
            }

            var identity = new ClaimsIdentity(claims, Scheme.Name);
            var principal = new ClaimsPrincipal(identity);
            var ticket = new AuthenticationTicket(principal, Scheme.Name);

            // Log authentication success without username or any personal data
            Logger.LogInformation(
                "Authentication successful via CaldovaAuthGateway. Role count: {RoleCount}.",
                whoAmI.Roles.Length);

            return AuthenticateResult.Success(ticket);
        }
        catch (HttpRequestException)
        {
            Logger.LogWarning("Authentication failed: WhoAmI request could not be completed.");
            return AuthenticateResult.Fail("Failed to contact authentication gateway.");
        }
        catch (JsonException)
        {
            Logger.LogWarning("Authentication failed: invalid WhoAmI response.");
            return AuthenticateResult.Fail("Invalid authentication response.");
        }
        catch (OperationCanceledException) when (!Context.RequestAborted.IsCancellationRequested)
        {
            Logger.LogWarning("Authentication failed: WhoAmI request timed out.");
            return AuthenticateResult.Fail("Authentication gateway timed out.");
        }
    }

    /// <summary>
    /// Redirects unauthenticated users to the CaldovaAuthGateway sign-in page with a ReturnUrl.
    /// </summary>
    protected override Task HandleChallengeAsync(AuthenticationProperties properties)
    {
        var returnUrl = properties.RedirectUri
                        ?? (Request.PathBase + Request.Path + Request.QueryString);
        Response.Redirect(GatewayUrls.Login(_configuration, returnUrl));
        return Task.CompletedTask;
    }
}
