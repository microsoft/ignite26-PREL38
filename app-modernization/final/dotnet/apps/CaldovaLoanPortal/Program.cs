using Azure.Monitor.OpenTelemetry.AspNetCore;
using CaldovaLoanPortal;
using CaldovaLoanPortal.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Mvc.Authorization;
using Microsoft.Data.SqlClient;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = WebApplication.CreateBuilder(args);
if (string.IsNullOrEmpty(builder.Configuration["urls"]))
    builder.WebHost.UseUrls("http://0.0.0.0:8080");
builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole();
builder.Services.AddSingleton<Func<SqlConnection>>(() => new SqlConnection(DbConfig.GetConnectionString()));
builder.Services.AddHealthChecks().AddCheck<DatabaseReadiness>("database");
var telemetry = builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource.AddService("CaldovaLoanPortal"))
    .WithTracing(tracing => tracing.AddSqlClientInstrumentation(options => options.RecordException = false));
var exportEnabled = !string.IsNullOrWhiteSpace(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]);
if (exportEnabled)
    telemetry.UseAzureMonitor();

builder.Services.AddAuthentication(CaldovaAuthDefaults.AuthenticationScheme)
    .AddScheme<CaldovaAuthOptions, CaldovaAuthHandler>(CaldovaAuthDefaults.AuthenticationScheme, _ => { });
builder.Services.AddControllersWithViews(options =>
    options.Filters.Add(new AuthorizeFilter(new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build())));
builder.Services.AddHttpClient();
builder.Services.AddHttpClient("CaldovaAuth")
    .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { UseCookies = false, AllowAutoRedirect = false });

var app = builder.Build();
if (!exportEnabled)
    app.Logger.LogWarning("APPLICATIONINSIGHTS_CONNECTION_STRING is not configured; Azure telemetry export is disabled.");
app.UseExceptionHandler(error => error.Run(async context =>
{
    var exception = context.Features.Get<IExceptionHandlerFeature>()?.Error;
    app.Logger.LogError("Loan request failed ({ExceptionType}).", exception?.GetType().Name);
    context.Response.StatusCode = 503;
    await context.Response.WriteAsJsonAsync(new { error = "The loan service could not complete this request." });
}));
app.UseStaticFiles();
app.UseRouting();
app.UseAuthentication();
app.UseAuthorization();
app.MapGet("/health", () => Results.Text("OK")).AllowAnonymous();
app.MapGet("/Health.ashx", () => Results.Text("OK")).AllowAnonymous();
app.MapHealthChecks("/health/ready", new HealthCheckOptions()).AllowAnonymous();
app.MapControllerRoute("legacy-home", "Default.aspx", new { controller = "Home", action = "Index" });
app.MapControllerRoute("legacy-login", "Login.aspx", new { controller = "Account", action = "Login" });
app.MapControllerRoute("legacy-logout", "Logout.aspx", new { controller = "Account", action = "Logout" });
app.MapControllerRoute("default", "{controller=Home}/{action=Index}/{id?}");
app.Run();

public partial class Program;
