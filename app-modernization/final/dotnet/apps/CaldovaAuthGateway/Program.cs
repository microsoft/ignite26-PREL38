using Azure.Monitor.OpenTelemetry.AspNetCore;
using CaldovaAuthGateway;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Data.SqlClient;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = WebApplication.CreateBuilder(args);
if (string.IsNullOrEmpty(builder.Configuration["urls"]))
    builder.WebHost.UseUrls("http://0.0.0.0:8080");
builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole();
builder.Services.AddSingleton<Func<SqlConnection>>(() => new SqlConnection(DbConfig.GetConnectionString()));
builder.Services.AddScoped<AuthRepository>();
builder.Services.AddHealthChecks().AddCheck<DatabaseReadiness>("database");
var telemetry = builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource.AddService("CaldovaAuthGateway"))
    .WithTracing(tracing => tracing.AddSqlClientInstrumentation(options => options.RecordException = false));
var exportEnabled = !string.IsNullOrWhiteSpace(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]);
if (exportEnabled)
    telemetry.UseAzureMonitor();

builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(options =>
    {
        options.LoginPath = "/login";
        options.Cookie.Name = ".CALDOVAAUTH";
        options.Cookie.Domain = builder.Configuration["AUTH_COOKIE_DOMAIN"];
        options.Cookie.Path = "/";
        options.Cookie.HttpOnly = true;
        options.Cookie.SameSite = SameSiteMode.Lax;
        options.ExpireTimeSpan = TimeSpan.FromMinutes(30);
        options.SlidingExpiration = false;
        options.Events.OnValidatePrincipal = async context =>
        {
            var token = context.Principal?.FindFirst("sessionToken")?.Value;
            var repository = context.HttpContext.RequestServices.GetRequiredService<AuthRepository>();
            var session = string.IsNullOrWhiteSpace(token) ? null : await repository.ValidateSessionToken(token);
            if (session == null)
            {
                context.RejectPrincipal();
                context.HttpContext.RequestServices.GetRequiredService<ILogger<AuthRepository>>()
                    .LogWarning("Cookie authentication rejected: session is invalid or expired.");
            }
        };
    });
builder.Services.AddAuthorization();

var app = builder.Build();
if (!exportEnabled)
    app.Logger.LogWarning("APPLICATIONINSIGHTS_CONNECTION_STRING is not configured; Azure telemetry export is disabled.");
app.UseExceptionHandler(error => error.Run(async context =>
{
    var exception = context.Features.Get<IExceptionHandlerFeature>()?.Error;
    app.Logger.LogError("Authentication request failed ({ExceptionType}).", exception?.GetType().Name);
    context.Response.StatusCode = 503;
    await context.Response.WriteAsJsonAsync(new { error = "Authentication service is unavailable." });
}));
app.UsePathBase("/auth");
app.UseAuthentication();
app.UseAuthorization();
app.Use(async (context, next) =>
{
    context.Response.Headers.CacheControl = "no-store";
    await next(context);
});

app.MapGet("/health", () => Results.Text("OK")).AllowAnonymous();
app.MapGet("/Health.ashx", () => Results.Text("OK")).AllowAnonymous();
app.MapHealthChecks("/health/ready", new HealthCheckOptions()).AllowAnonymous();
app.MapGet("/api/auth/validate", ApiAuthValidateEndpoint.Handle).AllowAnonymous();
app.MapGet("/ApiAuthValidate.ashx", ApiAuthValidateEndpoint.Handle).AllowAnonymous();
app.MapGet("/WhoAmI.ashx", WhoAmIEndpoint.Handle).AllowAnonymous();
app.MapGet("/login", LoginEndpoint.RenderForm).AllowAnonymous();
app.MapPost("/login", LoginEndpoint.HandleAsync).AllowAnonymous();
app.MapGet("/Login.aspx", LoginEndpoint.RenderForm).AllowAnonymous();
app.MapPost("/Login.aspx", LoginEndpoint.HandleAsync).AllowAnonymous();
app.MapGet("/logout", LogoutEndpoint.HandleAsync).AllowAnonymous();
app.MapGet("/Logout.aspx", LogoutEndpoint.HandleAsync).AllowAnonymous();
app.MapGet("/", DefaultEndpoint.Handle).RequireAuthorization();
app.MapGet("/Default.aspx", DefaultEndpoint.Handle).RequireAuthorization();
app.Run();

public partial class Program;
