using Microsoft.AspNetCore.WebUtilities;

namespace CaldovaLoanPortal.Authentication;

public static class GatewayUrls
{
    public static Uri Required(IConfiguration configuration, string name)
    {
        if (!Uri.TryCreate(configuration[name], UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps) ||
            !string.IsNullOrEmpty(uri.UserInfo))
            throw new InvalidOperationException($"{name} must be a configured HTTP(S) URL.");
        return uri;
    }

    public static string Login(IConfiguration configuration, string localPath)
    {
        var origin = Required(configuration, "PUBLIC_BASE_URL");
        if (!localPath.StartsWith('/') || localPath.StartsWith("//", StringComparison.Ordinal) ||
            localPath.Contains('\\') || localPath.Any(char.IsControl))
            localPath = "/";
        return QueryHelpers.AddQueryString(Required(configuration, "AuthGatewayLoginUrl").AbsoluteUri,
            "ReturnUrl", new Uri(origin, localPath).AbsoluteUri);
    }
}
