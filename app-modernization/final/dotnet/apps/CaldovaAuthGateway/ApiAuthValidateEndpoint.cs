using System.Globalization;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace CaldovaAuthGateway
{
    public static class ApiAuthValidateEndpoint
    {
        public static async Task<IResult> Handle(
            HttpContext context,
            ILoggerFactory loggerFactory,
            AuthRepository repository)
        {
            var logger = loggerFactory.CreateLogger(typeof(ApiAuthValidateEndpoint));

            var token = (context.Request.Query["token"].ToString() ?? string.Empty).Trim();
            if (token.Length == 0)
            {
                token = (context.Request.Headers["X-Session-Token"].ToString() ?? string.Empty).Trim();
            }

            if (token.Length == 0)
            {
                logger.LogWarning("Session validation requested with no token provided");
                return Results.Json(new { valid = false, error = "token is required" }, statusCode: 400);
            }

            // Do NOT log the token value (it is a secret — masked or otherwise)
            var session = await repository.ValidateSessionToken(token);
            if (session == null)
            {
                logger.LogWarning("Session validation failed: token invalid or expired");
                return Results.Json(new { valid = false });
            }

            // Log only the surrogate UserId and expiry — never Username or token
            logger.LogInformation(
                "Session validated for user {UserId}, expires {ExpiresAt:o}",
                session.UserId, session.ExpiresAt);

            var expires = session.ExpiresAt.ToString("o", CultureInfo.InvariantCulture);
            return Results.Json(new
            {
                valid = true,
                userId = session.UserId,
                username = session.Username,
                expiresAt = expires
            });
        }
    }
}
