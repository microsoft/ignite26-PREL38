using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Rendering;
using Microsoft.Data.SqlClient;
using System.Text;
using CaldovaLoanPortal.Models;

namespace CaldovaLoanPortal.Controllers;

public class HomeController : Controller
{
    private readonly IConfiguration _config;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<HomeController> _logger;
    private readonly Func<SqlConnection> _connections;

    public HomeController(
        IConfiguration config,
        IHttpClientFactory httpClientFactory,
        ILogger<HomeController> logger,
        Func<SqlConnection> connections)
    {
        _config = config;
        _httpClientFactory = httpClientFactory;
        _logger = logger;
        _connections = connections;
    }

    [HttpGet]
    public async Task<IActionResult> Index()
    {
        // Auth redirect is enforced globally by CaldovaAuthGateway middleware (task 004).
        var model = new LoanApplicationViewModel
        {
            CustomerId = "1",
            TermMonths = "60",
            Step = 1,
            LoanProducts = await LoadLoanProducts(),
            LoanHistory = await LoadLoanHistory()
        };

        // Carry over any submission status stored in TempData (e.g. after review action)
        if (TempData["SubmissionStatus"] is string status)
        {
            model.SubmissionStatus = status;
        }

        return View(model);
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Index(LoanApplicationViewModel model, string action = "Next")
    {
        // Validate before advancing (not when going back)
        if (action != "Previous")
        {
            if (model.Step == 1)
            {
                // Step 1 — Personal Info: customer ID and first/last name are required
                if (string.IsNullOrWhiteSpace(model.CustomerId) ||
                    string.IsNullOrWhiteSpace(model.FirstName) ||
                    string.IsNullOrWhiteSpace(model.LastName))
                {
                    model.ErrorMessage = "Customer ID, First Name, and Last Name are required.";
                    model.LoanProducts = await LoadLoanProducts();
                    model.LoanHistory = await LoadLoanHistory();
                    return View(model);
                }
            }
            else if (model.Step == 2)
            {
                // Step 2 — Employment: employer and job title are required
                if (string.IsNullOrWhiteSpace(model.Employer) ||
                    string.IsNullOrWhiteSpace(model.JobTitle))
                {
                    model.ErrorMessage = "Employer and Job Title are required.";
                    model.LoanProducts = await LoadLoanProducts();
                    model.LoanHistory = await LoadLoanHistory();
                    return View(model);
                }
            }
            else if (model.Step == 3)
            {
                // Step 3 — Loan Details: amount and term must be valid numbers
                if (!decimal.TryParse(model.RequestedAmount, out _) ||
                    !int.TryParse(model.TermMonths, out _))
                {
                    model.ErrorMessage = "Enter valid loan amount and term.";
                    model.LoanProducts = await LoadLoanProducts();
                    model.LoanHistory = await LoadLoanHistory();
                    return View(model);
                }
            }
        }

        if (action == "Previous")
        {
            model.Step = Math.Max(1, model.Step - 1);
        }
        else if (action == "Finish" && model.Step == 5)
        {
            if (await SubmitApplicationAsync(model))
            {
                model.Step = 1;
                model.FirstName = "";
                model.LastName = "";
                model.Email = "";
                model.Employer = "";
                model.JobTitle = "";
                model.YearsEmployed = "";
                model.AnnualIncome = "";
                model.LoanProductId = "";
                model.RequestedAmount = "";
                model.TermMonths = "60";
                model.Purpose = "";
                model.ReviewSummary = "";
            }
        }
        else
        {
            model.Step = Math.Min(5, model.Step + 1);
        }

        if (model.Step == 4)
        {
            // Rebuild on Previous as well; the posted hidden summary is not trusted HTML.
            var name = System.Net.WebUtility.HtmlEncode(
                (model.FirstName + " " + model.LastName).Trim());
            var amount = System.Net.WebUtility.HtmlEncode(model.RequestedAmount);
            var term = System.Net.WebUtility.HtmlEncode(model.TermMonths);
            model.ReviewSummary =
                $"<b>Customer:</b> {name}<br/>" +
                $"<b>Amount:</b> {amount}<br/>" +
                $"<b>Term:</b> {term} months";
        }

        model.LoanProducts = await LoadLoanProducts();
        model.LoanHistory = await LoadLoanHistory();
        return View(model);
    }

    /// <summary>
    /// Handles the "Review" row command from the loan history table.
    /// Equivalent to gvLoanHistory_RowCommand in the original Web Forms code.
    /// </summary>
    [HttpPost]
    [ValidateAntiForgeryToken]
    public IActionResult ReviewApplication()
    {
        TempData["SubmissionStatus"] = "Application selected for review.";
        return RedirectToAction(nameof(Index));
    }

    private async Task<IEnumerable<SelectListItem>> LoadLoanProducts()
    {
        var items = new List<SelectListItem>();
        using var conn = _connections();
        using var cmd = new SqlCommand(
            "SELECT LoanProductID, ProductName FROM LoanProducts WHERE IsActive=1 ORDER BY ProductName;", conn);
        await conn.OpenAsync(HttpContext.RequestAborted);
        using var reader = await cmd.ExecuteReaderAsync(HttpContext.RequestAborted);
        while (await reader.ReadAsync(HttpContext.RequestAborted))
        {
            items.Add(new SelectListItem(
                reader["ProductName"]?.ToString() ?? "",
                reader["LoanProductID"]?.ToString() ?? ""));
        }
        return items;
    }

    private async Task<IEnumerable<LoanHistoryItem>> LoadLoanHistory()
    {
        var items = new List<LoanHistoryItem>();
        using var conn = _connections();
        using var cmd = new SqlCommand(
            "SELECT TOP 25 ApplicationID, CustomerID, RequestedAmount, TermMonths, Status, ApplicationDate " +
            "FROM LoanApplications ORDER BY ApplicationDate DESC;", conn);
        await conn.OpenAsync(HttpContext.RequestAborted);
        using var reader = await cmd.ExecuteReaderAsync(HttpContext.RequestAborted);
        while (await reader.ReadAsync(HttpContext.RequestAborted))
        {
            items.Add(new LoanHistoryItem
            {
                ApplicationID = (int)reader["ApplicationID"],
                CustomerID = (int)reader["CustomerID"],
                RequestedAmount = (decimal)reader["RequestedAmount"],
                TermMonths = (int)reader["TermMonths"],
                Status = reader["Status"]?.ToString() ?? "",
                ApplicationDate = (DateTime)reader["ApplicationDate"]
            });
        }
        return items;
    }

    private async Task<bool> SubmitApplicationAsync(LoanApplicationViewModel model)
    {
        if (!int.TryParse(model.CustomerId, out var cid) || cid <= 0 ||
            !int.TryParse(model.LoanProductId, out var pid) || pid <= 0 ||
            !decimal.TryParse(model.RequestedAmount, out var amt) || amt <= 0 ||
            !int.TryParse(model.TermMonths, out var termVal) || termVal <= 0)
        {
            model.ErrorMessage = "Enter a valid customer, product, positive amount and term.";
            _logger.LogWarning("Loan submission rejected: required fields are invalid.");
            return false;
        }

        using (var conn = _connections())
        using (var cmd = new SqlCommand(
            "INSERT INTO LoanApplications " +
            "(CustomerID, LoanProductID, RequestedAmount, TermMonths, Purpose, Status, ApplicationDate, AssignedOfficer, CreatedDate, ModifiedDate) " +
            "VALUES (@c, @p, @a, @t, @u, 'Submitted', GETDATE(), @o, GETDATE(), GETDATE());", conn))
        {
            cmd.Parameters.AddWithValue("@c", cid);
            cmd.Parameters.AddWithValue("@p", pid);
            cmd.Parameters.AddWithValue("@a", amt);
            cmd.Parameters.AddWithValue("@t", termVal);
            cmd.Parameters.AddWithValue("@u", model.Purpose ?? "");
            cmd.Parameters.AddWithValue("@o", User.Identity?.Name ?? "");
            await conn.OpenAsync(HttpContext.RequestAborted);
            await cmd.ExecuteNonQueryAsync(HttpContext.RequestAborted);
        }
        _logger.LogInformation("Loan application saved for customer {CustomerId}.", cid);
        model.SubmissionStatus = "Application saved.";

        var apiUrl = _config["LoanOriginationApiUrl"];
        if (string.IsNullOrWhiteSpace(apiUrl))
        {
            _logger.LogWarning("Application saved, but loan-origination forwarding is not configured.");
            model.SubmissionStatus = "Application saved. External forwarding is not configured; do not resubmit.";
            return true;
        }

        try
        {
            var escape = (string? s) =>
                System.Security.SecurityElement.Escape(s ?? "") ?? "";
            var amtStr = amt.ToString("F2", System.Globalization.CultureInfo.InvariantCulture);
            var payload =
                $"<loanApplication>" +
                $"<customerId>{escape(model.CustomerId)}</customerId>" +
                $"<loanProductId>{escape(model.LoanProductId)}</loanProductId>" +
                $"<requestedAmount>{amtStr}</requestedAmount>" +
                $"<termMonths>{escape(model.TermMonths)}</termMonths>" +
                $"</loanApplication>";

            var client = _httpClientFactory.CreateClient();
            using var content = new StringContent(payload, Encoding.UTF8, "application/xml");
            using var response = await client.PostAsync(apiUrl, content, HttpContext.RequestAborted);
            if (response.IsSuccessStatusCode)
            {
                model.SubmissionStatus = "Application saved and forwarded.";
                _logger.LogInformation("Loan origination forwarding completed.");
            }
            else
            {
                _logger.LogWarning("Loan origination forwarding failed with HTTP {StatusCode}.", (int)response.StatusCode);
                model.SubmissionStatus = "Application saved, but external forwarding failed; do not resubmit.";
            }
        }
        catch (HttpRequestException)
        {
            _logger.LogWarning("Loan origination forwarding could not be completed.");
            model.SubmissionStatus = "Application saved, but external forwarding failed; do not resubmit.";
        }
        catch (OperationCanceledException) when (!HttpContext.RequestAborted.IsCancellationRequested)
        {
            _logger.LogWarning("Loan origination forwarding timed out.");
            model.SubmissionStatus = "Application saved; forwarding could not be confirmed. Do not resubmit.";
        }
        return true;
    }
}
