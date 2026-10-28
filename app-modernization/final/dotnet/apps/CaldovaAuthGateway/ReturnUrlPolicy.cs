namespace CaldovaAuthGateway;

public static class ReturnUrlPolicy
{
    public static string Resolve(string? value, IConfiguration configuration)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Any(char.IsControl) || value.Contains('\\'))
            return "/";
        if (value.StartsWith('/') && (value.Length == 1 || value[1] != '/'))
            return value;
        if (!Uri.TryCreate(value, UriKind.Absolute, out var target) ||
            !string.IsNullOrEmpty(target.UserInfo) ||
            (target.Scheme != Uri.UriSchemeHttps && !(target.IsLoopback && target.Scheme == Uri.UriSchemeHttp)))
            return "/";

        var origins = (configuration["AUTH_ALLOWED_RETURN_ORIGINS"] ?? "")
            .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return origins.Any(origin => Uri.TryCreate(origin, UriKind.Absolute, out var allowed) &&
            string.Equals(allowed.GetLeftPart(UriPartial.Authority), target.GetLeftPart(UriPartial.Authority),
                StringComparison.OrdinalIgnoreCase)) ? value : "/";
    }
}
