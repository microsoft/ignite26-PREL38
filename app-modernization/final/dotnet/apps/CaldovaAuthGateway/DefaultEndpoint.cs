using Microsoft.AspNetCore.Http;

namespace CaldovaAuthGateway
{
    public static class DefaultEndpoint
    {
        public static IResult Handle(HttpContext context)
        {
            var username = context.User.Identity?.Name ?? string.Empty;
            return Results.Text($"Authenticated user: {username}", "text/plain");
        }
    }
}
