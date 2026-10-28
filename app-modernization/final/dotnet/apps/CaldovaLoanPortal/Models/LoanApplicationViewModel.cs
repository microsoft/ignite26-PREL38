using Microsoft.AspNetCore.Mvc.Rendering;

namespace CaldovaLoanPortal.Models;

public class LoanApplicationViewModel
{
    /// <summary>Current wizard step (1–5).</summary>
    public int Step { get; set; } = 1;

    // Step 1 — Personal Info
    public string CustomerId { get; set; } = "1";
    public string FirstName { get; set; } = "";
    public string LastName { get; set; } = "";
    public string Email { get; set; } = "";

    // Step 2 — Employment
    public string Employer { get; set; } = "";
    public string JobTitle { get; set; } = "";
    public string YearsEmployed { get; set; } = "";
    public string AnnualIncome { get; set; } = "";

    // Step 3 — Loan Details
    public string LoanProductId { get; set; } = "";
    public string RequestedAmount { get; set; } = "";
    public string TermMonths { get; set; } = "60";
    public string Purpose { get; set; } = "";

    // Step 4 — Review (computed, HTML)
    public string ReviewSummary { get; set; } = "";

    // Status / error messages
    public string SubmissionStatus { get; set; } = "";
    public string ErrorMessage { get; set; } = "";

    // View collections (not bound from POST — repopulated by controller)
    public IEnumerable<SelectListItem> LoanProducts { get; set; } = [];
    public IEnumerable<LoanHistoryItem> LoanHistory { get; set; } = [];
}
