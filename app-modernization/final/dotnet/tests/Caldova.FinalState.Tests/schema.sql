-- Test fixture only. This is not a migration for the supplied Azure database.
CREATE TABLE Users (
    UserID int PRIMARY KEY,
    Username nvarchar(100) NOT NULL,
    PasswordHash varchar(128) NOT NULL,
    Salt varchar(128) NOT NULL,
    IsActive bit NOT NULL,
    IsLockedOut bit NOT NULL,
    FirstName nvarchar(100),
    LastName nvarchar(100),
    LastLoginDate datetime,
    ModifiedDate datetime
);
CREATE TABLE Roles (RoleID int PRIMARY KEY, RoleName nvarchar(100) NOT NULL);
CREATE TABLE UserRoles (UserID int NOT NULL, RoleID int NOT NULL);
CREATE TABLE SessionTokens (
    UserID int NOT NULL, Token varchar(128) NOT NULL,
    CreatedAt datetime NOT NULL, ExpiresAt datetime NOT NULL,
    SourceSystem nvarchar(30), IsActive bit NOT NULL,
    IPAddress nvarchar(100), UserAgent nvarchar(1000)
);
CREATE TABLE LoanProducts (
    LoanProductID int PRIMARY KEY,
    ProductName nvarchar(100) NOT NULL,
    IsActive bit NOT NULL
);
CREATE TABLE Accounts (
    AccountID int PRIMARY KEY, CustomerID int NOT NULL,
    Balance decimal(18,2) NOT NULL, Status nvarchar(30) NOT NULL
);
CREATE TABLE LoanApplications (
    ApplicationID int IDENTITY PRIMARY KEY, CustomerID int NOT NULL,
    LoanProductID int NOT NULL, LoanAccountID int NULL,
    RequestedAmount decimal(18,2) NOT NULL, TermMonths int NOT NULL,
    Purpose nvarchar(500), Status nvarchar(30) NOT NULL,
    ApplicationDate datetime NOT NULL, AssignedOfficer nvarchar(100),
    CreatedDate datetime, ModifiedDate datetime
);
CREATE TABLE CreditScores (
    CustomerID int NOT NULL, Score int NOT NULL, ReportDate datetime NOT NULL
);
CREATE TABLE RiskFactors (
    FactorCode nvarchar(100) NOT NULL, FactorName nvarchar(100) NOT NULL,
    Weight decimal(18,6), IsActive bit NOT NULL
);
CREATE TABLE RiskAssessments (
    AssessmentID int IDENTITY PRIMARY KEY,
    ApplicationID int NOT NULL, CustomerID int NOT NULL,
    OverallRiskScore decimal(18,2) NOT NULL, RiskLevel nvarchar(10) NOT NULL,
    Recommendation nvarchar(30) NOT NULL, FactorBreakdown nvarchar(1000)
);
INSERT INTO Roles VALUES (1, 'LoanOfficer');
INSERT INTO UserRoles VALUES (1, 1);
INSERT INTO LoanProducts VALUES (1, 'Fixture loan', 1);
INSERT INTO Accounts VALUES (1, 1, 5000, 'Active');
INSERT INTO LoanApplications
    (CustomerID, LoanProductID, LoanAccountID, RequestedAmount, TermMonths, Status, ApplicationDate)
    VALUES (1, 1, 1, 10000, 60, 'Submitted', GETDATE());
INSERT INTO CreditScores VALUES (1, 650, GETDATE());
INSERT INTO RiskFactors VALUES
    ('CREDIT_SCORE', 'Credit', 1, 1), ('EXIST_DEBT', 'Debt', 1, 1),
    ('ASSET_RES', 'Assets', 1, 1), ('ACCT_AGE', 'Accounts', 1, 1);
