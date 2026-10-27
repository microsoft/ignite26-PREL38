---
name: pii-masking
description: Use when adding or changing logging, telemetry, tracing, audit output, or exception messages in Caldova Bank code. Ensures personally identifiable information (SSN, account numbers, card numbers, names, dates of birth, contact details) is masked or omitted before it is written anywhere.
---

<!-- DRAFT for the PREL38 pre-day lab. Not reviewed by Caldova governance. Delete this comment when approved.
     Placement (unverified): copy to .github/skills/pii-masking/SKILL.md in each repository being modernized.
     The Modernize CLI plan skill states that skills defined in the project's .github/skills/ take priority. -->

# PII masking

Caldova Bank policy ZB-MOD-001, section 6, item 1: PII must not appear in logs, error messages, or telemetry.

## When to apply

Apply this skill to every change that writes text to a log, trace, metric dimension, audit record, console, or exception message. This includes code the modernization adds to satisfy the structured telemetry requirement (GRD-21).

## What counts as PII

| Data | Examples of names in code |
|---|---|
| Social Security number | `ssn`, `socialSecurityNumber`, `taxId` |
| Account and card numbers | `accountNumber`, `acctNo`, `iban`, `routingNumber`, `cardNumber`, `pan` |
| Person details | `firstName`, `lastName`, `fullName`, `dateOfBirth`, `dob` |
| Contact details | `email`, `phone`, `address`, `postalCode` |
| Secrets | `password`, `pwd`, `token`, `apiKey`, `connectionString` |

Also treat any value that matches `\b\d{3}-?\d{2}-?\d{4}\b` (SSN shape) or a 12 to 19 digit run (card or account shape) as PII.

## Rules

1. Prefer a surrogate identifier. Log `CustomerID` or `AccountID`, not the person's details.
2. If the value itself is needed for troubleshooting, mask it with the formats below.
3. Never put raw PII in an exception message, a `ToString()` override, or a structured log property.
4. Secrets are never logged, masked or not.
5. Do not change business behavior. Masking applies to the text that leaves the application, not to the data the application processes.

## Mask formats

| Data | Output |
|---|---|
| SSN | `***-**-1234` |
| Account or card number | `****1234` |
| Email | `j***@example.com` |
| Phone | `***-***-1234` |
| Name, date of birth, address | Omit |

## Procedure

1. Find every logging, tracing, console, and exception-message call site in the files you changed, and in the files you added.
2. Add one `PiiMask` helper per application, in its existing shared namespace or package, with a method per format above. Reuse it if it already exists.
3. Replace each PII argument with the masked value, or with a surrogate identifier.
4. Use structured logging placeholders. Do not build log text by string concatenation.
   - .NET: `_logger.LogInformation("Payment submitted for account {Account}", PiiMask.Account(accountNumber));`
   - Java: `log.info("Payment submitted for account {}", PiiMask.account(accountNumber));`
5. Add a test that logs a known SSN and account number through the changed code path and asserts the captured output contains neither raw value.

## Verification

- Search the changed files for the names in the table above next to any logging call. Zero raw matches.
- The new test passes.
- State in the task summary each call site you masked, and any value you omitted instead.
