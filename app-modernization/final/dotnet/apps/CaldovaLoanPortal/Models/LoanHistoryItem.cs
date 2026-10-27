namespace CaldovaLoanPortal.Models;

public class LoanHistoryItem
{
    public int ApplicationID { get; set; }
    public int CustomerID { get; set; }
    public decimal RequestedAmount { get; set; }
    public int TermMonths { get; set; }
    public string Status { get; set; } = "";
    public DateTime ApplicationDate { get; set; }
}
