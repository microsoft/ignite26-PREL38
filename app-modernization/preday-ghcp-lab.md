# PREL38 Part 2: Modernize application code with GitHub Copilot

> **Goal:** Use GitHub Copilot to modernize a legacy codebase from **Caldova Bank**. You'll assess the code, create a modernization plan, execute the framework upgrade and verify the changes.

> **Scenario:** You can choose between upgrading a legacy **.NET** or **Java** solution. Each solution is composed of 3 projects: a **provider** and two **consumers** (apps that call the provider). We'll modernize the provider first. The modernization also has a set of requirements in an external document known as a **rulebook** which will also be adhered to.

> **Environment:** All the work will be done in this VM in the **C:\lab\caldova\modules** folder. There are folders for the assessment, plan, and execute portions of the lab, each with a start and end folder in them. Use the **start** folder as your working copy. The **finish** folder is there as a prepared result you can use if a live run is slow or unavailable.

> [!Note] If the agent is running slow, you can continue on to subsequent chapters in this modernization module without issue.

===

## Get ready

*About 2 minutes*

In Part 1, Azure Copilot Migration Agent showed you *which* Caldova applications to move and where. In Part 2 you work with the code itself. You use GitHub Copilot to assess one application, plan its changes, and check the result.

You'll use **Modernize CLI** (**modernize**), a command-line tool that uses GitHub Copilot to assess and upgrade applications, and **VS Code with GitHub Copilot** to review plans and code. Both are already installed, and you signed in to VS Code during **Set Up**. If you did not, please go back and do so now.

### Sign in to the GitHub CLI

The **Modernize CLI** uses your GitHub sign-in to reach GitHub Copilot. Make sure you have already signed in to GitHub via the browser as outlined in the initial lab setup.

#### GitHub CLI sign-in

For each terminal prompt, use the arrow keys to select the answer, then press **Enter**.

1. Open **Windows Terminal** inside the VM: right-click **Start** and select **Terminal**. At the prompt enter:

    ```powershell
    gh auth login
    ```

    > [!TIP]
    > **Type** enters text wherever your cursor is in the VM, so select the PowerShell prompt first. If the command remains at the prompt with no output, press **Enter** to run it.

    If it says you're already logged in and asks whether to re-authenticate, select **No** and go to step 8 to check the account.
2. At **Where do you use GitHub?**, select **GitHub.com**.
3. At **What is your preferred protocol for Git operations on this host?**, select **HTTPS**.
4. At **Authenticate Git with your GitHub credentials?**, select **Yes**.
5. At **How would you like to authenticate GitHub CLI?**, select **Login with a web browser**.
6. Note the one-time code shown in the terminal, such as **ABCD-1234**, then press **Enter** to open the browser.
7. Enter the code in the browser and select **Continue**, then **Authorize github**. If asked to sign in again, use the same lab account and the SSO address in **Browser sign-in** above. When the page says your device is connected, return to the terminal.
8. Check the account:

    ```powershell
    gh auth status
    ```

    Confirm it says **Logged in to github.com** with your assigned lab account, not a personal account.

#### Check the lab folder

In the same terminal, run:

```powershell
Test-Path C:\lab\caldova\modules\module-01-assess\start
```

> **Before you continue:** **gh auth status** shows **Logged in to github.com** with your assigned lab account (not a personal account), and **Test-Path** returns **True**.

> [!TIP]
> If Windows Terminal warns about a multiline paste, check that the preview matches the lab commands, then select **Paste anyway**.

===

## Step 1. Run the short assessment

*About 8 minutes*

Before upgrading a legacy application, we need to run an assessment on it to see any potential issues we may run in to. 

In this step we'll run a live assessment on one application, **CaldovaAuthGateway** and view a report of the results.

It takes about 3 minutes, so start it and move on to step 2 while it works. We'll be able to view a prepared report for the entire suite of applications in that step.

### Do this

1. Enter the following in PowerShell, we'll switch to the assessment's module directory and start Modernize CLI:

    ```powershell
    cd C:\lab\caldova\modules\module-01-assess\start
    modernize --model auto
    ```

    Use the arrow keys to move and **Enter** to confirm on every screen below.
2. If you see **Trust this folder?**, select **Yes, always trust this folder** and press **Enter**.
3. On **How would you like to modernize your app?**, keep **Assess** selected and press **Enter**.
4. On **Choose target repositories**, press **↓** twice to select **3. From a config file** (its path ends in **repos.json**), then press **Enter**.

    !IMAGE [Choose target repositories screen with option 3, From a config file, selected and the repos.json path shown](instructions359549/prel38-part2-assess-config-file-20261101.png)
5. On **Add source paths for config file**, the path already ends in **repos.json**. Press **Enter**.
6. On **Choose repositories**, check that it shows **[✓] CaldovaAuthGateway** and **Selected 1/1**, then press **Enter**.

    If it lists more than one repository, stop and ask the facilitator to check the lab's one-app default; don't start an assessment of all six apps.
7. On **Assessment Configuration**, compare the values with this table:

    | Setting | Value |
    | ------- | ----- |
    | Analysis Coverage | **Full analysis** |
    | Minimum CVE Severity | High |
    | Java Target Runtime | OpenJDK 21 |
    | Java Target Compute Services | Azure Container Apps (ACA) |
    | Java Target Operating System | Linux |
    | Containerization | Disabled |
    | .NET Target Runtime | .NET 10 |
    | .NET Target Compute Services | Azure Container Apps |

    If every value matches, keep **Continue** selected and press **Enter**. If anything is different, or you see **Select assessment domains** instead, follow **If your settings are different** below, then come back to step 8.
8. On **How would you like to assess?**, keep **1. Assess locally** selected and press **Enter**.
9. On **Enter output path**, press **Enter** to accept the default path.
10. The **Assessment dashboard** appears with **[Task 1/1] CaldovaAuthGateway** set to **RUNNING**. Leave this window open and go to step 2. You'll come back to it when the run finishes.

> **Before you continue:** The dashboard shows **CaldovaAuthGateway** running, and your settings matched the table.

### Screen reference: the assessment settings

!IMAGE [Modernize CLI Assessment Configuration screen showing Full analysis, High, OpenJDK 21, Azure Container Apps (ACA), Linux, Disabled, .NET 10, Azure Container Apps, with Continue selected](instructions359549/prel38-part2-assess-settings-summary-20261101.png)

*This is the screen you should see in step 7 above. Select **Continue**.*

===

## Step 2. Review the assessment

*About 7 minutes*

First decide if you'd rather upgrade the .NET or Java solution - work with whatever you feel most comfortable in. Though if you are short on time, .NET is the primary path.

Use the report and source files to see how its apps connect before planning changes.

**Caldova architecture at a glance:**

| Framework | Provider app | Consumer apps | Shared database |
| ----- | ----------------------- | ----------------------------- | --------------- |
| .NET (recommended) | CaldovaAuthGateway | CaldovaLoanPortal, CaldovaRiskEngine | CaldovaBankDB |
| Java | CaldovaLedger | CaldovaPayGateway, CaldovaFraudDetector | CaldovaBankDB |

### Do this

1. In File Explorer inside the VM, select the address bar and open:

    ```plaintext
    C:\lab\caldova\modules\module-01-assess\start\.github\modernize\assessment-prebuilt
    ```

    Open the **reports-...** folder, then double-click **index.html**. If Windows asks how you want to open the file, select **Microsoft Edge**, then **Always**.
2. Review the portfolio, then you can look at specific reports for each repository. They're in the **repos\&lt;repository&gt;** folder structure. View them in Windows Explorer replacing **<repository>** with an app's report-folder name. Notice unsupported frameworks, security findings, cloud-readiness issues, and database connection code indicated on the report.
3. In the gateway's report folder (**repos\CaldovaAuthGateway**), open **facts\data-architecture.md** and **facts\configuration-inventory.md**. Find **System.Data.SqlClient**, SQL-login settings (**DB_USER/DB_PASSWORD**), and certificate-validation settings.
4. Compart that to the service dependency diagram for your the Java or .NET applications. The loan portal signs in through the gateway; the payment gateway posts to the ledger. The Java applications also call the auth gateway.

> **Before you continue:** You should be able to understand how the provider and its consumer applications interact. And the database-authentication changes the plan must cover. All six applications use **CaldovaBankDB**; the exercise targets Azure SQL Database.

As a best practice, you should use fact and code code documents as the source of truth rather than the topology graph. Generated diagrams may omit a real dependency.

> **Checkpoint:** You've decided to upgrade either the .NET or Java solution and understand the assessment report.

### When your live assessment finishes

Go back to the Modernize CLI window from step 1.

1. When the run finishes, the CLI prints **SUCCESS: Assessment report has been created.** and the report opens in Microsoft Edge.
2. Check that you're looking at your live report: the page title is **Aggregated Assessment Report** and the **Issue summary** shows **1 of 1** scanned applications, with **CaldovaAuthGateway**.

    !IMAGE [Live Aggregated Assessment Report in Microsoft Edge showing Executive insights and an Issue summary of 1 of 1 scanned applications for CaldovaAuthGateway](instructions359549/prel38-part2-live-report-top-20261101.png)

    *Your counts and wording may differ. The report may suggest other Azure services, but the rulebook decides the target (Azure Container Apps).*
3. In the CLI, **How would you like to continue?** appears. Press **↓** to select **2. Return to main menu**, press **Enter**, then press **Esc** to exit Modernize CLI. Don't select **Create modernization plan**; you'll create the plan from a different folder in step 4.

**If the run finishes but no report opens in Edge**, open it yourself:

1. In the CLI output, find the line **SUCCESS: Assessment report has been created.** The line under it, after **See more details in:**, is the full path to **index.html**.
2. In File Explorer, select the address bar and open:

    ```plaintext
    C:\lab\caldova\modules\module-01-assess\start\.github\modernize\assessment
    ```

    Open the newest **reports-...** folder, then double-click **index.html**.

===

## Step 3. Load the rulebook and add the PII skill

*About 3 minutes*

Before creating a plan, load the **rulebook**. A rulebook is shared policy and approved targets the upgrade must pass. 

You'll also copy a **skill** (a folder of instructions Copilot follows for a specific task) that shows the agent how to keep personally identifiable information (PII) out of logs.

**PII** (personally identifiable information) is data such as names, emails, Social Security numbers, and account numbers. The rulebook says *what* is required ("no PII in logs"). The PII skill shows the agent *how* to do it.

### Do this

1. In VS Code, use **File > Open Folder** to open **C:\lab\caldova\modules\module-02-plan\start**. Read **rulebook\policies.md** and **rulebook\targets.md**.
2. Notice the training policy requires managed identity, certificate validation, no personal data in logs, supported dependencies, health checks, and Azure Container Apps readiness.
3. Open **.github\modernize\config.json** **in this module folder**. This file tells Modernize CLI where to download the rulebook. Check that **feature_flags.rulebook** is **true** and that **portfolio_url** is exactly:

    ```plaintext
    https://github.com/ayangupt/ignite26-caldova-rulebook
    ```

    That repository contains three files: **charter.md**, **targets.md**, and **policies.md**. The **rulebook** folder you just read is a copy for you; the tool uses the online version.
4. Copy the PII masking skill into all three applications in your track. If an application already has the skill, the command skips it, so it's safe to run again:

    **.NET:**

    ```powershell
    cd C:\lab\caldova\modules\module-02-plan\start
    $repos = 'CaldovaAuthGateway','CaldovaLoanPortal','CaldovaRiskEngine'
    foreach ($r in $repos) {
      $skills = "apps\$r\.github\skills"
      New-Item -ItemType Directory -Force -Path $skills | Out-Null
      if (-not (Test-Path "$skills\pii-masking")) {
        Copy-Item skills\pii-masking $skills -Recurse
      }
      Get-ChildItem "$skills\pii-masking"
    }
    ```

    **Java:**

    ```powershell
    cd C:\lab\caldova\modules\module-02-plan\start
    $repos = 'CaldovaLedger','CaldovaPayGateway','CaldovaFraudDetector'
    foreach ($r in $repos) {
      $skills = "apps\$r\.github\skills"
      New-Item -ItemType Directory -Force -Path $skills | Out-Null
      if (-not (Test-Path "$skills\pii-masking")) {
        Copy-Item skills\pii-masking $skills -Recurse
      }
      Get-ChildItem "$skills\pii-masking"
    }
    ```

> **Before you continue:** Each of the three listings should include **SKILL.md**, which confirms that each repository contains **.github\skills\pii-masking**. When planning starts, look for **Rulebook loaded (3 files)**. The plan should also contain **rulebook-compliance.md** and **.metadata\rulebook-metadata.json**.

### Screen reference: the CLI loaded the rulebook

!IMAGE [Native Modernize CLI output showing Rulebook loaded (3 files)](instructions359549/prel38-part2-cli-rulebook-loaded-20261029.png)

===

## Step 4. Create the provider project's plan

*About 10 minutes*

We'll use Modernize CLI to turn the assessment into a **plan**: a task list for the code changes. We'll verify the plan covers the Azure target, database access, logging, and authentication before any code changes begin.

> [!Note] **Short on time?** Skip the live plan and use the prepared plans on the track branch in **module-02-plan\finish**.

### Do this

1. Stay in **module-02-plan\start**. Run the following based on your track:

    **.NET:**

    ```powershell
    Get-Content goals\dotnet.txt -Raw | Set-Clipboard
    ```

    **Java:**

    ```powershell
    Get-Content goals\java.txt -Raw | Set-Clipboard
    ```
2. In the same PowerShell window, start Modernize CLI:

    ```powershell
    modernize --model auto
    ```

    Use the **arrow keys** to move and **Enter** to select on every screen below. Don't press Enter until the highlighted option matches the one named here.
    1. **Trust this folder?** Press **Enter** to keep **1. Yes, this time only**. (This appears because **module-02-plan\start** is a new folder.)
    2. **How would you like to modernize your app?** Press **↓** once to highlight **Plan**, then press **Enter**.
    3. **Choose target repositories:** Press **↓** once to highlight **2. Manual input**, then press **Enter**. Don't choose **Current folder** or **From a config file**; those plan more than the provider.
    4. **Add repository paths:** At **Path 1:**, type the provider folder for your track, then press **Enter**:

        **.NET provider folder:**

        ```plaintext
        C:\lab\caldova\modules\module-02-plan\start\apps\CaldovaAuthGateway
        ```

        **Java provider folder:**

        ```plaintext
        C:\lab\caldova\modules\module-02-plan\start\apps\CaldovaLedger
        ```
    5. **Choose repositories:** Check that only your provider is ticked (**Selected 1/1**), then press **Enter**.
    6. **How would you like to deliver the plan?** Press **Enter** to keep **1. Keep the plan local**. Don't choose **Submit to Cloud Coding Agent**.
3. On **Create modernization plan**, use **↑** and **↓** to move between **Plan name** and **Type your own prompt**. Highlight **Plan name**, hold **Backspace** until **modernization-plan** is cleared (you'll see *Enter a plan name*), and type the plan name for your track:

    | Track | Provider | Plan name |
    | ----- | -------- | --------- |
    | .NET | **CaldovaAuthGateway** | **caldova-dotnet-modernization** |
    | Java | **CaldovaLedger** | **caldova-java-modernization** |

    Press **↓** to return to **Type your own prompt**.
4. Paste the goal you copied in step 1 with **Ctrl+V** (or right-click in the terminal), then press **Enter**. If nothing pastes, run step 1 again in a second PowerShell tab and paste again.

    Within about two minutes you'll see **SUCCESS: Rulebook loaded (3 files)**. Planning takes about 10 minutes in total.

    The planner then asks a few clarifying questions. Their wording varies between runs. For each one, highlight the option marked **(Recommended)** and press **Enter**, unless it conflicts with the rulebook. Don't choose an option that provisions Azure infrastructure or deploys the app; this step only plans code changes.

    When you see **Summary for confirmation** and **Should I keep this plan exactly as generated?**, press **Enter** to choose **1. Confirm and keep as generated (Recommended)**.
5. Wait for **SUCCESS: Rulebook compliance report: ...rulebook-compliance.md**. The CLI then asks **How would you like to continue?**

    > [!WARNING]
    > The highlighted default is **1. Execute modernization plan**. Don't press Enter yet. You'll review the plan first and execute it in a later step.

    Press **↓** once to highlight **2. Return to main menu**, then press **Enter**. On the main menu, press **Esc** to return to the PowerShell prompt.
6. While the provider plan is generating (steps 4-5 above), you can review the prepared plans. In Windows Terminal, select **+** to open a new PowerShell tab and run the commands for your track. Switch back to the first tab every minute or so, because the planner pauses until you answer its questions.

    **.NET:**

    ```powershell
    git -C C:\lab\caldova\modules\module-02-plan\finish switch modernization/dotnet
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the prepared .NET plan branch.' }
    code C:\lab\caldova\modules\module-02-plan\finish
    ```

    **Java:**

    ```powershell
    git -C C:\lab\caldova\modules\module-02-plan\finish switch modernization/java
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the prepared Java plan branch.' }
    code C:\lab\caldova\modules\module-02-plan\finish
    ```

    The **finish** folder starts on **main**, where these plans are not visible. Switch to the track branch before looking under **apps\<repository>\.github\modernize\<plan-name>**. Replace the placeholders with your app and plan names. Review the two consumer plans there; if live planning was unavailable, review the prepared provider plan there too.

### Screen reference: plan name and goal

!IMAGE [Modernize CLI Create modernization plan screen with Plan name caldova-dotnet-modernization and the cursor in Type your own prompt](instructions359549/prel38-part2-plan-name-20261101.png)

*The plan name is set and the cursor is in **Type your own prompt**, ready for you to paste the goal.*

### Screen reference: leave the plan without executing it

!IMAGE [Modernize CLI How would you like to continue menu with 1. Execute modernization plan highlighted by default and 2. Return to main menu below it](instructions359549/prel38-part2-plan-continue-20261101.png)

*This is what you'll see when the plan finishes: **Execute** is highlighted by default. Press **↓** to **2. Return to main menu** before pressing **Enter**.*

> **Before you continue:** Under <b>apps\\<repository\>\\.github\modernize\\<plan-name\></b>, you can open **plan.md**, **.metadata\tasks.json**, and **rulebook-compliance.md**. For a live plan, confirm **Rulebook loaded (3 files)** appeared and find **pii-masking** on the logging task.

If the menu looks different, use [Planning from PowerShell](#planning-from-powershell). If that doesn't work, review the prepared plan instead. If the PII skill or another requirement is absent, make the goal explicit and revise the plan before execution.

**Keep the integration contract:** The .NET portal must recognize **.CALDOVAAUTH** through the gateway's **/WhoAmI.ashx**. Its prepared goal includes **goals\dotnet-loanportal-extra.txt**. Test sign-in after the build.


===

## Step 5. Review the plans before execution

*About 5 minutes*

We'll check each plan against the requirements below. This gives us a chance to add any missing tasks or provide clarification before the agent starts changing code.

> [!Note] **Short on time?** Review only the provider plan.

### Do this

1. In PowerShell, select your track's prepared-plan branch, even if you skipped the live plan:

    **.NET:**

    ```powershell
    git -C C:\lab\caldova\modules\module-02-plan\finish switch modernization/dotnet
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the prepared .NET plan branch.' }
    ```

    **Java:**

    ```powershell
    git -C C:\lab\caldova\modules\module-02-plan\finish switch modernization/java
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the prepared Java plan branch.' }
    ```
2. Open **plan.md**, **.metadata\tasks.json**, and **rulebook-compliance.md** under each application's **.github\modernize\&lt;plan-name&gt;** folder. Use **module-02-plan\start** for a completed live provider plan and the selected track branch in **module-02-plan\finish** for prepared plans.
3. Match each requirement below to a concrete task. If a prepared plan has no **rulebook-compliance.md** (for example, the supplied LoanPortal plan), compare **plan.md** and **tasks.json** directly with the supplied rulebook.

    | Requirement | Evidence in the plan |
    | ----------- | -------------------- |
    | Supported runtime | .NET 10, or OpenJDK 21 with Spring Boot 3 |
    | Passwordless database access | Managed identity; remove stored SQL credentials |
    | Validated TLS | Explicit **Encrypt=True** and **TrustServerCertificate=False** |
    | No personal data in logs | Structured logging and the **pii-masking** skill |
    | Supported libraries | Replace **System.Data.SqlClient** or Struts as applicable; scan vulnerabilities |
    | Preserved behavior | Public routes, responses, and cross-application authentication |
    | Deployable result | Health endpoint, environment-based settings, compliant Dockerfile |
    | Verification | Build and tests after major changes |
4. If a requirement has no task, add the work to the plan/task files or regenerate with a clearer goal. Review the revision before proceeding.
5. Confirm that the provider is planned before its consumers.

> **Before you continue:** The plans you reviewed cover the rules and integration contracts. Task wording and counts can differ; coverage matters more than matching a sample task list.

> **Checkpoint:** The plans you reviewed have their missing tasks addressed and have been checked against the rules.

### Screen reference: reviewing the prepared plan

In Explorer, open **apps > CaldovaAuthGateway > .github > modernize > caldova-dotnet-modernization > plan.md**. If the application itself is your workspace root, begin at **.github**. Use **Open Preview** to read the plan, then check its requirements against the rulebook.

!IMAGE [Prepared Caldova gateway plan open in VS Code, with the plan folder and Markdown preview visible](instructions359549/prel38-part2-win-prepared-plan-20261026.png)

*Example of the prepared plan. The agent wrote it, so check its claims against the code and the rulebook.*


===

## Step 6. Prepare for the code upgrade

*About 2 minutes*

We'll put the reviewed plans and skill on a new Git branch. But we'll leave the assessment reports out because they contain sample passwords.

> [!Note] **Short on time?** Skip to step 7. It uses a prepared folder that already contains the plans.

### Do this

> [!WARNING]
> Do not copy or stage plans while a planning agent is still writing them. If it has not finished, skip to **Start the prepared execution** rather than creating an incomplete handoff.

1. In PowerShell inside **module-02-plan\start**, create the handoff branch:

    **.NET:**

    ```powershell
    cd C:\lab\caldova\modules\module-02-plan\start
    git switch -c modernization/dotnet
    ```

    **Java:**

    ```powershell
    cd C:\lab\caldova\modules\module-02-plan\start
    git switch -c modernization/java
    ```

    If Git says the branch already exists, stop and inspect it rather than resetting it. Don't copy or stage files until you know it's the correct handoff branch.
2. Bring the reviewed prepared plans into the handoff folder. The following preserves an existing complete plan, such as your live provider plan, and copies a prepared plan only when none exists. This copies from the track branch you selected in **module-02-plan\finish** in step 5.

    First, set your track's names. Run **one** of these:

    **.NET:**

    ```powershell
    $repos = 'CaldovaAuthGateway','CaldovaLoanPortal','CaldovaRiskEngine'
    $planName = 'caldova-dotnet-modernization'
    ```

    **Java:**

    ```powershell
    $repos = 'CaldovaLedger','CaldovaPayGateway','CaldovaFraudDetector'
    $planName = 'caldova-java-modernization'
    ```

    Then copy the plans (same for both tracks):

    ```powershell
    foreach ($r in $repos) {
      $planPath = "apps\$r\.github\modernize\$planName"
      if (Test-Path $planPath) {
        if (-not (Test-Path "$planPath\plan.md") -or
            -not (Test-Path "$planPath\.metadata\tasks.json")) {
          throw "Existing plan is incomplete: $planPath. Inspect it; do not overwrite it."
        }
        Write-Host "Keeping existing plan for $r"
        continue
      }
      New-Item -ItemType Directory -Force -Path (Split-Path $planPath) | Out-Null
      Copy-Item "..\finish\$planPath" $planPath -Recurse -ErrorAction Stop
      Write-Host "Using prepared plan for $r"
    }
    ```

    If a plan was copied, review it against the rulebook before staging. Copying prepared artifacts does not establish that central loading or a new generation succeeded.
3. Stage only the named plan folders and the skills you copied earlier:

    ```powershell
    foreach ($r in $repos) {
      git add -f "apps/$r/.github/modernize/$planName" "apps/$r/.github/skills/pii-masking"
      if ($LASTEXITCODE -ne 0) { throw "Staging failed for $r; inspect the paths before committing." }
    }
    git status --short
    ```
4. Confirm each repository's plan and skill appear and **no assessment report is staged**. Then commit:

    ```powershell
    git commit -m "Add the skill and approved modernization plans"
    ```
5. If the supplied lab repository has a remote you are authorized to push to, publish the branch:

    **.NET:**

    ```powershell
    git push -u origin modernization/dotnet
    ```

    **Java:**

    ```powershell
    git push -u origin modernization/java
    ```

> **Before you continue:** Your reviewed **modernization/dotnet** or **modernization/java** branch has the appropriate files. The rulebook remains in the central repository.

If the branch already exists, inspect it rather than resetting it. If no remote is supplied, keep the local commit and skip the push. The **-f** and assessment exclusion are explained under **Additional guidance**.


===

## Step 7. Start the upgrade

*About 5 minutes*

Now we'll have the agent start upgrading the code. While it works, we'll review the prepared result in the next step; don't wait for the run to finish.

> [!Note] **Short on time?** Don't start a run; go to the next page.

### Do this

1. Use the prepared execution folder, not the **module-02-plan** folder you used for planning:

    **.NET:**

    ```powershell
    cd C:\lab\caldova\modules\module-03-execute\start
    git switch modernization/dotnet
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the prepared .NET execution branch.' }
    code apps\CaldovaAuthGateway
    ```

    **Java:**

    ```powershell
    cd C:\lab\caldova\modules\module-03-execute\start
    git switch modernization/java
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the prepared Java execution branch.' }
    code apps\CaldovaLedger
    ```
2. Inspect the commit history using this command:

    ```powershell
    git --no-pager log --oneline
    ```

    Then inspect the provider's **.github\modernize\&lt;plan-name&gt;\.metadata\tasks.json**, using your track's plan name. The runtime upgrade and page/servlet conversion are already committed; the first two tasks should say **"status": "success"**. Check **.github\modernize\config.json** in **this execution module and the provider's app folder**. Both should enable **feature_flags.rulebook** and use **https://github.com/ayangupt/ignite26-caldova-rulebook**. The planning module is a different copy.
3. In **VS Code inside the VM**, open Copilot Chat and use the selector labelled **Agent** at the bottom of the composer to choose **modernize**. If **Agent** is hidden, drag the Chat pane's left border to the left until the label appears. Selecting this custom agent is not the same as typing **@modernize**, which may show file/tool suggestions instead.

    **.NET**

    ```plaintext
    Execute the existing plan caldova-dotnet-modernization in this repository.
    Execute all remaining tasks, starting with the first unfinished task.
    Do not stop after one task. Do not run the deployment task.
    Do not provision or reconfigure cloud resources, grant access, push, or install tools.
    Keep public routes and business behavior. Build after each task.
    ```

    **Java**

    ```plaintext
    Execute the existing plan caldova-java-modernization in this repository.
    Execute the next two unfinished tasks, one after the other, then stop.
    Do not run the deployment task.
    Do not provision or reconfigure cloud resources, grant access, push, or install tools.
    Keep public routes and business behavior. Build after each task.
    ```
4. Send the prompt, select **Execute the plan** if offered, and answer pending tool approvals. In VS Code, inspect the agent's tool output for rulebook-loading evidence, you always want to check the agent's work. If loading cannot be confirmed you can stop the run and try again this time being more specific in your prompt.
5. Leave VS Code open and continue to the next page. **Do not wait for the entire run.**

> **Before you continue:** You can see the agent working in VS Code. Leave it running and open the prepared result in the next step.

If the execution module's central configuration is missing, don't start a run without the rulebook loaded. Instead, continue to the finished-result review. If the agent stops early, inspect task status before repeating the scoped prompt. And remember, always check task statuses and test results, even if the command exits successfully.

### Screen reference: checking the starting task state

Open **.metadata > tasks.json** from the plan folder. The first two tasks in this prepared start state show **"status": "success"**; the remaining tasks haven't run yet.

!IMAGE [Prepared tasks.json in VS Code showing success for the runtime upgrade and Web Forms conversion tasks](instructions359549/prel38-part2-win-task-states-20261026.png)

*Actual Windows view of the supplied start state.*


===

## Step 8. Review a finished application

*About 10 minutes*

We'll inspect the upgraded code to see if the agent missed anything. We'll also compare the code with the rules. Just because something builds doesn't always means its correct.

> [!Note] **Short on time?** Check one requirement from the table, then move on.

### Do this

1. In Windows Terminal inside the VM, select **+** to open a new PowerShell tab. Leave the live run open in its own window or tab, then run:

    **.NET:**

    ```powershell
    cd C:\lab\caldova\modules\module-03-execute\finish
    git switch modernization/dotnet
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the prepared .NET result branch.' }
    git --no-pager log --oneline -- apps/CaldovaLoanPortal
    git --no-pager diff --stat main -- apps/CaldovaLoanPortal
    ```

    **Java:**

    ```powershell
    cd C:\lab\caldova\modules\module-03-execute\finish
    git switch modernization/java
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the prepared Java result branch.' }
    git --no-pager log --oneline -- apps/CaldovaPayGateway
    git --no-pager diff --stat main -- apps/CaldovaPayGateway
    ```
2. Find the replacement for the old UI and service code: ASP.NET Core for .NET, or Spring MVC for Java. Inspect database configuration and public routes.
3. Try to find at least two gaps in the primary application's prepared result:

    | Track | Review targets |
    | ----- | -------------- |
    | .NET portal | Inspect the Dockerfile's base image and **USER**; compare the portal's authentication handler/response model with the gateway contract |
    | Java payments | Check the Dockerfile base image and non-root **USER**; look for the old **struts-config.xml** under **src\main\webapp** |
4. Compare each finding with the rulebook and decide what follow-up task would fix it.
5. **Optional, .NET track only (about 4 minutes):** If you have time, compare the gaps you found with the prepared final state, which is kept separate from **finish**. Run this to open it:

    ```powershell
    $final = 'C:\lab\caldova\modules\module-03-execute\final\dotnet'
    if (Test-Path $final) {
      code $final
    } else {
      'The prepared final state is not on this VM. Skip this item.'
    }
    ```

    If VS Code opens the folder:

    - Open the **.csproj** file in each of the three applications and confirm it targets **net10.0**.
    - Compare the portal's Microsoft-based, non-root Dockerfile with the gaps you found.
    - Read **VALIDATION.md** to see which checks ran locally and which have not run (Azure and central-rulebook checks).

    This is a frozen snapshot, so treat it as prepared evidence, not output from your run. Don't rerun its full test suite, rebuild containers, deploy, or copy it over **finish**.

> **Before you continue:** You can name two gaps you found and the rule each one affects. This sample was created before the rulebook was loaded, and it skips deployment, so expect gaps. If you reviewed the final state, you can say which of your gaps it addresses.

Open the files and plan directly. If they differ from the examples, check them against the rules; don't try to recreate an old defect.

> [!TIP]
> If an earlier Git command leaves you at **:** or **(END)** rather than a PowerShell prompt, press **q** to leave its pager. The commands above disable paging.


===

## Step 9. Validate the provider application

*About 15 minutes*

Now you'll build and test the provider application. The instructions below are for the prepared version of it. But if your live run has finished, you can use that one instead.

> [!Note] **Short on time?** Run only the build and test commands and skip the local run.

### Do this

1. Open the provider application in PowerShell inside the VM and build it:

    **.NET:**

    ```powershell
    git -C C:\lab\caldova\modules\module-03-execute\finish switch modernization/dotnet
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the prepared .NET result branch.' }
    cd C:\lab\caldova\modules\module-03-execute\finish\apps\CaldovaAuthGateway
    dotnet build
    ```

    **Java:**

    ```powershell
    git -C C:\lab\caldova\modules\module-03-execute\finish switch modernization/java
    if ($LASTEXITCODE -ne 0) { throw 'Could not select the prepared Java result branch.' }
    cd C:\lab\caldova\modules\module-03-execute\finish\apps\CaldovaLedger
    gradle build
    ```
2. Check each requirement (gate) below. Each one must pass before this app is ready to release:

    | Gate | Expected evidence |
    | ---- | ----------------- |
    | Runtime and build | SDK-style .NET 10 project, or Spring Boot 3/Java 21; **dotnet build** or **gradle build** succeeds |
    | Database code | Identity-based authentication; no stored password; validated TLS; **DB_HOST**/**DB_NAME** settings |
    | PII | Masking helper used by structured logs; tests assert raw personal data is absent |
    | Security | Inspect the prepared security task's evidence; investigate any remaining High/Critical findings or prohibited libraries |
    | Compatibility | Public routes and response contracts preserved |
    | Container, if Docker is available | Approved Microsoft base image, non-root user, port 8080; image builds |

    A prepared security task may contain a summary in **.metadata\tasks.json** without a separate scan report. A **"success"** status or a summary claiming zero findings isn't total proof. Always check the agent's work. For the prepared .NET provider, check the current dependency graphs from this folder:

    ```powershell
    dotnet list package --vulnerable --include-transitive
    dotnet list Tests\CaldovaAuthGateway.Tests.csproj package --vulnerable --include-transitive
    ```

    These check NuGet dependencies, not all code/security requirements. If advisory data is unavailable, treat the check as unverified, not as zero findings. For Java, inspect the provided scan evidence or ask the facilitator for the approved scan route; do not install extra tooling.
3. For the prepared .NET gateway, run the supplied test project from the provider folder:

    ```powershell
    dotnet test Tests\CaldovaAuthGateway.Tests.csproj
    ```

    The prepared gateway includes 13 tests; inspect failures rather than treating the count alone as success. For Java, open **build\reports\tests\test\index.html** from the provider folder after **gradle build**. The prepared ledger includes 22 tests. If the tests are absent or fail, inspect the report and ask the facilitator.
4. Start the provider in a dedicated PowerShell terminal for **local-only route checks**. These process-local database values are placeholders for the routes below, not a database connection test. For **.NET**, use:

    ```powershell
    cd C:\lab\caldova\modules\module-03-execute\finish\apps\CaldovaAuthGateway
    $env:DB_HOST = 'localhost'
    $env:DB_NAME = 'CaldovaBankDB'
    $env:APPLICATIONINSIGHTS_CONNECTION_STRING = 'InstrumentationKey=00000000-0000-0000-000000000000;IngestionEndpoint=http://localhost/'
    dotnet run
    ```

    For **Java**, use:

    ```powershell
    cd C:\lab\caldova\modules\module-03-execute\finish\apps\CaldovaLedger
    $env:DB_HOST = 'localhost'
    $env:DB_NAME = 'CaldovaBankDB'
    gradle bootRun
    ```

    Do not use the .NET-only Application Insights placeholder for Java. Without a real connection string, the application can report that Azure Monitor export is disabled; that's expected here.

    > [!TIP]
    > **dotnet run** and **gradle bootRun** keep running while the server is available. Gradle can remain at an **EXECUTING** progress indicator; do not wait for it to finish before checking the URL from another window.
5. Leave the server terminal running. In **Edge inside the VM**, open this URL; expect HTTP 200:

    ```plaintext
    http://localhost:8080/health
    ```

    For .NET, open this URL and, from a new Windows Terminal tab (select **+**), run the command below without adding cookies:

    ```plaintext
    http://localhost:8080/Login
    ```

    ```powershell
    curl.exe http://localhost:8080/WhoAmI.ashx
    ```

    Expect **{"authenticated":false}**.
6. If your agent completed its code upgrade you can repeat these checks on its result. Stop only your preview server with **Ctrl+C** when finished. For Java on Windows, answer **Y** if that terminal asks **Terminate batch job (Y/N)?** Close the dedicated preview terminal afterward so its placeholder settings are not reused. Do not terminate an unknown process if a port is already in use.

> **Before you continue:** You have build/test evidence, a compatibility check, and you know which database/container checks ran. Check the database connection separately.

### Screen reference: build, tests, and local routes

Compare your output with these checkpoints. These come from running **dotnet build** and **dotnet test Tests\CaldovaAuthGateway.Tests.csproj** against the prepared gateway result.

!IMAGE [Actual Windows build and test output showing 13 tests passed, zero failed, and zero skipped](instructions359549/prel38-part2-win-build-tests-20261026.png)

The route check below shows the requested URLs, HTTP 200 responses, and **{"authenticated":false}** for **/WhoAmI.ashx** without a cookie.

!IMAGE [Actual curl output for localhost health and WhoAmI.ashx, both HTTP 200, with an unauthenticated JSON response](instructions359549/prel38-part2-win-local-routes-20261026.png)

