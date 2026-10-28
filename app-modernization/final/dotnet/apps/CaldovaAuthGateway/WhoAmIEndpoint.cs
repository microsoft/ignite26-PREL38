using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace CaldovaAuthGateway
{
    public static class WhoAmIEndpoint
    {
        public static async Task<IResult> Handle(
            HttpContext context,
            ILoggerFactory loggerFactory,
            AuthRepository repo)
        {
            var logger = loggerFactory.CreateLogger(typeof(WhoAmIEndpoint));

            if (context.User.Identity?.IsAuthenticated != true)
            {
                logger.LogDebug("WhoAmI: unauthenticated request");
                return Results.Json(new { authenticated = false });
            }

            var username = context.User.Identity.Name ?? string.Empty;
            var sessionToken = context.User.FindFirst("sessionToken")?.Value ?? string.Empty;
            var userIdClaim = context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? "unknown";

            var session = string.IsNullOrEmpty(sessionToken) ? null : await repo.ValidateSessionToken(sessionToken);
            var user = session == null ? null : await repo.GetUserByUsername(username);
            if (user == null || !user.IsActive || user.IsLockedOut || session?.UserId != user.UserId)
            {
                // Log only the surrogate UserId — never Username, FirstName, or LastName
                logger.LogWarning("WhoAmI: user {UserId} not found, inactive, or locked out", userIdClaim);
                return Results.Json(new { authenticated = false });
            }

            // Log only the surrogate identifier — do NOT log sessionToken (secret), FirstName, or LastName
            logger.LogInformation("WhoAmI: user {UserId} authenticated", user.UserId);

            var roles = await repo.GetUserRoles(user.UserId);
            var displayName = ((user.FirstName ?? string.Empty) + " " + (user.LastName ?? string.Empty)).Trim();
            if (string.IsNullOrEmpty(displayName))
            {
                displayName = user.Username;
            }

            return Results.Json(new
            {
                authenticated = true,
                username = user.Username,
                displayName,
                sessionToken,
                roles
            });
        }
    }
}
