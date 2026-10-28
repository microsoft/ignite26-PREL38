using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using CaldovaLoanPortal.Models;
using CaldovaLoanPortal.Authentication;

namespace CaldovaLoanPortal.Controllers;

public class AccountController : Controller
{
    private readonly IConfiguration _config;
    private readonly ILogger<AccountController> _logger;

    public AccountController(IConfiguration config, ILogger<AccountController> logger)
    {
        _config = config;
        _logger = logger;
    }

    /// <summary>
    /// Shows the login page with a link to CaldovaAuthGateway.
    /// Equivalent to Login.aspx Page_Load in the original Web Forms application.
    /// This action is exempt from the global authorization policy so that
    /// unauthenticated users can reach it.
    /// </summary>
    [AllowAnonymous]
    [HttpGet]
    public IActionResult Login(string? returnUrl = null)
    {
        // Already authenticated — redirect away
        if (User.Identity?.IsAuthenticated == true)
        {
            var destination = !string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl)
                ? returnUrl
                : Url.Action("Index", "Home")!;
            _logger.LogDebug("Already-authenticated user redirected from login page.");
            return Redirect(destination);
        }

        var resolvedReturn = !string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl)
            ? returnUrl
            : Url.Action("Index", "Home") ?? "/";

        var model = new LoginViewModel
        {
            Message = "Authentication is handled by CaldovaAuthGateway.",
            AuthGatewayLoginUrl = GatewayUrls.Login(_config, resolvedReturn)
        };

        _logger.LogInformation("Login page served; redirecting unauthenticated user to CaldovaAuthGateway.");
        return View(model);
    }

    /// <summary>
    /// Signs the user out by clearing the .CALDOVAAUTH cookie and redirecting to
    /// the CaldovaAuthGateway logout URL.
    /// Equivalent to Logout.aspx Page_Load in the original Web Forms application.
    /// Replaces any System.Web FormsAuthentication.SignOut() call.
    /// </summary>
    [HttpGet]
    public IActionResult Logout()
    {
        // The gateway needs the cookie to revoke the database session before clearing it.
        _logger.LogInformation("User logout forwarded to the authentication gateway.");
        return Redirect(GatewayUrls.Required(_config, "AuthGatewayLogoutUrl").AbsoluteUri);
    }
}
