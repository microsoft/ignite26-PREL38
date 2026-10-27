using System;
using System.Collections.Generic;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
namespace CaldovaAuthGateway
{
    public static class LoginEndpoint
    {
        public static IResult RenderForm(HttpContext context)
        {
            var loggedOut = context.Request.Query["loggedOut"] == "1";
            var message = loggedOut ? "<p>You have been logged out.</p>" : string.Empty;
            var returnUrl = System.Net.WebUtility.HtmlEncode(ReturnUrlPolicy.Resolve(
                context.Request.Query["ReturnUrl"].ToString(),
                context.RequestServices.GetRequiredService<IConfiguration>()));
            var html = $"""
                <!DOCTYPE html>
                <html>
                <head><title>Login – Caldova Bank</title></head>
                <body>
                {message}
                <form method="post" action="{context.Request.PathBase}/login">
                    <input type="hidden" name="ReturnUrl" value="{returnUrl}" />
                    <label>Username: <input type="text" name="username" /></label><br/>
                    <label>Password: <input type="password" name="password" /></label><br/>
                    <button type="submit">Login</button>
                </form>
                </body>
                </html>
                """;
            return Results.Content(html, "text/html");
        }

        public static async Task<IResult> HandleAsync(
            HttpContext context,
            ILoggerFactory loggerFactory,
            AuthRepository repository)
        {
            var logger = loggerFactory.CreateLogger(typeof(LoginEndpoint));
            var form = await context.Request.ReadFormAsync();
            var username = (form["username"].ToString() ?? string.Empty).Trim();
            var password = form["password"].ToString() ?? string.Empty;

            if (username.Length == 0 || password.Length == 0)
            {
                // Do NOT log username or password — they are PII / secrets
                logger.LogWarning("Login attempt rejected: missing credentials");
                return Results.Text("Username and password are required.", statusCode: 400);
            }

            // Use UserId (surrogate) for all log messages — never log Username, Password, PasswordHash, or Salt
            var user = await repository.GetUserByUsername(username);
            if (user == null || !user.IsActive || user.IsLockedOut)
            {
                logger.LogWarning("Login attempt failed: user not found, inactive, or locked out");
                return Results.Text("Invalid username or password.", statusCode: 401);
            }

            var computedHash = ComputeSha1Hex(user.Salt + password);
            if (!string.Equals(computedHash, user.PasswordHash, StringComparison.OrdinalIgnoreCase))
            {
                // Log only the surrogate UserId — not Username, PasswordHash, or Salt
                logger.LogWarning("Login attempt failed: invalid credentials for user {UserId}", user.UserId);
                return Results.Text("Invalid username or password.", statusCode: 401);
            }

            // Session token is a secret — never log its value (masked or raw)
            var sessionToken = Guid.NewGuid().ToString("N").ToUpperInvariant();
            await repository.CreateSessionToken(
                user.UserId,
                sessionToken,
                context.Connection.RemoteIpAddress?.ToString() ?? string.Empty,
                context.Request.Headers["User-Agent"].ToString() ?? string.Empty);
            await repository.UpdateLastLogin(user.UserId);

            var claims = new List<Claim>
            {
                new Claim(ClaimTypes.Name, user.Username),
                new Claim(ClaimTypes.NameIdentifier, user.UserId.ToString()),
                new Claim("sessionToken", sessionToken)
            };
            var identity = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);
            var principal = new ClaimsPrincipal(identity);

            await context.SignInAsync(
                CookieAuthenticationDefaults.AuthenticationScheme,
                principal,
                new AuthenticationProperties
                {
                    IsPersistent = false,
                    ExpiresUtc = DateTimeOffset.UtcNow.AddMinutes(30)
                });

            // Log only the surrogate identifier — never FirstName, LastName, Username, or any credential
            logger.LogInformation("Login successful for user {UserId}", user.UserId);
            return Results.Redirect(ReturnUrlPolicy.Resolve(form["ReturnUrl"].ToString(),
                context.RequestServices.GetRequiredService<IConfiguration>()));
        }

        private static string ComputeSha1Hex(string input)
        {
            using var sha1 = SHA1.Create();
            var bytes = Encoding.UTF8.GetBytes(input);
            var hash = sha1.ComputeHash(bytes);
            var builder = new StringBuilder(hash.Length * 2);
            foreach (var b in hash)
            {
                builder.Append(b.ToString("X2"));
            }

            return builder.ToString();
        }
    }
}
