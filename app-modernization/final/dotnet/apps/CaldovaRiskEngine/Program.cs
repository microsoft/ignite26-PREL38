using Azure.Monitor.OpenTelemetry.AspNetCore;
using CaldovaRiskEngine;
using CoreWCF;
using CoreWCF.Configuration;
using CoreWCF.Description;
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
builder.Services.AddScoped<CaldovaRiskEngineService>();
builder.Services.AddServiceModelServices().AddServiceModelMetadata();
builder.Services.AddSingleton<IServiceBehavior, SafeFaultBehavior>();
builder.Services.AddSingleton<IServiceBehavior, UseRequestHeadersForMetadataAddressBehavior>();
builder.Services.AddHealthChecks().AddCheck<DatabaseReadiness>("database");

var telemetry = builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource.AddService("CaldovaRiskEngine"))
    .WithTracing(tracing => tracing.AddSqlClientInstrumentation(options =>
    {
        options.RecordException = false;
    }));
var exportEnabled = !string.IsNullOrWhiteSpace(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]);
if (exportEnabled)
    telemetry.UseAzureMonitor();

var app = builder.Build();
if (!exportEnabled)
    app.Logger.LogWarning("APPLICATIONINSIGHTS_CONNECTION_STRING is not configured; Azure telemetry export is disabled.");

app.UseExceptionHandler(error => error.Run(async context =>
{
    var exception = context.Features.Get<IExceptionHandlerFeature>()?.Error;
    app.Logger.LogError("Risk request failed ({ExceptionType}).", exception?.GetType().Name);
    context.Response.StatusCode = exception is FaultException ? 400 : 503;
    await context.Response.WriteAsJsonAsync(new { error = "The risk operation could not be completed." });
}));

app.UseServiceModel(services =>
{
    services.AddService<CaldovaRiskEngineService>();
    services.AddServiceEndpoint<CaldovaRiskEngineService, IRiskEngineService>(
        new BasicHttpBinding(), "/CaldovaRiskEngine.svc");
});
app.Services.GetRequiredService<ServiceMetadataBehavior>().HttpGetEnabled = true;

app.MapGet("/health", () => Results.Text("OK"));
app.MapGet("/Health.ashx", () => Results.Text("OK"));
app.MapHealthChecks("/health/ready", new HealthCheckOptions());
app.MapGet("/", () => Results.Content(
    "<!DOCTYPE html><html><head><title>CaldovaRiskEngine - Caldova Bank</title></head>" +
    "<body><h1>CaldovaRiskEngine Service</h1><p>Service Running</p>" +
    "<p><a href=\"CaldovaRiskEngine.svc?wsdl\">Service contract (WSDL)</a></p></body></html>", "text/html"));
app.MapGet("/Default.aspx", () => Results.Redirect("/"));
app.MapPost("/api/risk/score/{applicationId:int}",
    async (int applicationId, CaldovaRiskEngineService service) => await service.ScoreLoanApplication(applicationId));
app.MapGet("/api/risk/factors/{customerId:int}",
    async (int customerId, CaldovaRiskEngineService service) => await service.GetRiskFactors(customerId));
app.MapPost("/api/risk/model",
    async (RiskModelUpdateRequest model, CaldovaRiskEngineService service) => await service.UpdateRiskModel(model));
app.Run();

public partial class Program;
