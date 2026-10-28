using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace CaldovaAuthGateway
{
    public static class LogoutEndpoint
    {
        public static async Task<IResult> HandleAsync(
            HttpContext context,
            ILoggerFactory loggerFactory,
            AuthRepository repository)
        {
            var logger = loggerFactory.CreateLogger(typeof(LogoutEndpoint));

            // Resolve the surrogate UserId from the NameIdentifier claim — never log session token (secret)
            var userIdClaim = context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? "unknown";

            var sessionToken = context.User.FindFirst("sessionToken")?.Value;
            if (!string.IsNullOrWhiteSpace(sessionToken))
            {
                await repository.DeactivateSessionToken(sessionToken);
                // Log only UserId (surrogate) — do NOT log sessionToken (it is a secret)
                logger.LogInformation("Session deactivated for user {UserId}", userIdClaim);
            }

            await context.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
            logger.LogInformation("Logout completed for user {UserId}", userIdClaim);
            return Results.Redirect($"{context.Request.PathBase}/login?loggedOut=1");
        }
    }
}
