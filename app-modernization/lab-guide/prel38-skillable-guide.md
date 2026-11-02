# Set Up

*About 5 minutes · Everything happens inside the lab VM*

Before the lab starts, you'll sign in twice: once to Azure and once to GitHub. Later parts use these same assigned accounts, but each tool keeps its own sign-in. The browser, VS Code, and the GitHub CLI (`gh`) authenticate separately, so a tool may ask you to authorize it again. When that happens, use the same assigned account. The GitHub CLI starts signed out; Part 2 shows you how to check it and sign in.

Your sign-in details are in the **Resources** tab of these instructions. The VM account, the Azure account, and the lab GitHub account are different accounts; this lab tells you which one each step needs.

> [!Note] Need help? Ask the facilitator.

**Typing URLs and prompts:** Select the address bar or text box **inside the VM** first. Then click a highlighted URL or prompt in these instructions to type it automatically, or copy and paste it.

## Azure

**Goal:** Sign in to the Azure portal with the lab Azure account.

1. In the VM browser, go to +++https://portal.azure.com+++.
2. Sign in with the Azure username from **Resources**.
3. When you're asked for a **Temporary Access Pass (TAP)**, use the TAP from **Resources**. A TAP is a time-limited passcode that stands in for a password in this lab.

**Check:** The Azure portal home page opens. Leave this tab open; you'll use it in Part 1.

## GitHub and Copilot

**Goal:** Sign in to the lab GitHub account and turn on GitHub Copilot in VS Code.

The lab GitHub account uses the **skillable-events** GitHub Enterprise sign-in, which is single sign-on (SSO) with your Azure account.

1. In the VM browser, go to +++https://github.com/enterprises/skillable-events/sso+++ and sign in with the same Azure account.
2. Keep that browser tab open, then open **VS Code**.
3. In VS Code, select **Sign in** for GitHub Copilot, then select **Continue with GitHub**.
4. In the browser, if **Authorize Visual Studio Code** asks which account to use, select **Continue** beside your assigned lab GitHub account. If it asks you to sign in, use the SSO page from step 1 with the same Azure account.
5. On the authorization page, scroll down and select **Authorize Visual-Studio-Code**. If the browser asks to open Visual Studio Code, allow it, then return to VS Code.

**Check:** VS Code shows the lab GitHub account under **Accounts** (the person icon at the bottom left), and Copilot Chat is available. If VS Code asks for a personal account, stop and ask the facilitator rather than using your own.

You're set up. Select **Next** to start Part 1, where you'll plan Caldova's move to Azure with Azure Copilot Migration Agent.

===

# PREL38 Part 1: Modernize applications with Azure Copilot Migration Agent

>**Goal:** Learn how Azure Copilot Migration Agent helps you move from discovered infrastructure to application-aware modernization planning and execution

>**Scenario:** Caldova must modernize its critical applications as it prepares to exit its datacenter. With its VMware renewal approaching and infrastructure costs rising, leadership needs a credible modernization plan that identifies what should move, how it should move, and how execution can be governed. Because applications span multiple servers and services, Caldova needs to plan modernization around applications as a whole, rather than treating each server independently.

>**Environment:** Caldova's environment includes Windows and Linux workloads, .NET and Java applications backed by SQL Server and open-source databases, along with file shares, open-source IT applications, and microservices. These applications form the inventory used for application grouping, modernization planning, and execution.

> [!Note] A pre-created Azure Migrate project named **Caldova** has pre-generated artifacts for you to review, so you don't have to wait for long-running operations. You'll create your own project first and switch to **Caldova** only when a step tells you to.

**Your path through Part 1:** discover and group applications in your own project, start decision insights, then review the finished insights in **Caldova**.

===

# 1. Discover, review, and group applications

>**Step 1: Create a project**

- In the Azure portal, navigate to **Azure Migrate > All projects**
- At the top of the All projects page, click **Create project**
- Create a new Azure Migrate project with the following settings
    - **Subscription:** Keep the default subscription
    - **Resource group:** Azure Migrate
    - **Project name:** Enter a name of your choice
    - **Geography:** Korea

**Check:** Your new project opens on its **Overview** page.

>**Step 2: Discover using Azure Migrate Collector**

- Navigate to Azure Migrate project > Overview, click **Start Discovery**
- Select **Using Azure Migrate Collector** and click **Continue**
- Select **Browse**, choose the collector ZIP file on the lab VM's **D:\** drive, then select **Import**.

While the import runs, review any slides or video your facilitator shares about the other discovery options in Azure Migrate.

>**Step 3: Review Inventory, Best Practices and Group Applications**

- On the **Overview** page, under **Discover**, confirm that **Discovery completed** is displayed.
- Select **All inventory** and review the servers and the workloads found on each one.
- Return to **Overview** and review the **Best practices** recommended for this environment.
- Under **Best practices**, select **Group applications**. AI-powered grouping gathers related servers and workloads into applications, so you can plan by application instead of server by server.
- When grouping is complete, go to **Discover > Applications** and review the groups.

**Check yourself:** Pick one application group. Can you name the servers in it and say why they belong together? That's the application-level view the rest of Part 1 builds on.

===

# 2. Generate and review decision insights

>**Step 1: Generate Decision Insights**

- On the **Overview** page, select **Generate decision insights** to start generating decision insights for your application estate.
- When generation starts, **don't wait for it to finish**. Insights take a while to generate, so you'll review finished ones in the **Caldova** project next.

>**Step 2: Review Decision insights**

- Go to **Azure Migrate > All projects** and select the **Caldova** project, which already has decision insights
- Select **Overview > Decide**
- Review the generated outputs, including:
   - **Estimated Future Cost**
   - **Total economic benefit**
   - **Business case**
   - **Assessments**
   - **Azure Migrate-Briefing** deck

===

# 3. Review application designs and wave plan

>**Step 1: Review Application Design**

- Go to **Plan > Application design** and to view the available application designs.
- Click on **Caldova-Asset-Manager**. 
- Review the **Workload readiness**, **Estimated monthly cost** and **Target architecture topology**.
- Similarly review the **Application designs** for other applications.

>**Step 2: Review Wave Plan**

- Go to **Plan > Wave Plan** to review how applications are organized into migration waves.
- Review the **Waves**, **Wave plan reasoning** and **Risks and recommendations**

> [!Note] Since the environment has fewer than 50 workloads, a single migration wave is recommended. For larger environments, Azure Copilot Migration Agent can recommend multiple waves.

===

# 4. Create Migration waves, Review Execution Plan and Execute

> [!Note] A focused assessment for **Caldova-Asset-Manager** application has been pre-created for the hands-on execution scenario. We will use this assessment to create the migration wave and execution.

>**Step 1: **Create Migration Wave**

- Go to **Plan > Wave Plan** and select the **standlone-assetmanager** from the drop down **Planning based on assessment**
- Generate **Wave Plan**
- Click on **Review and commit waves** and commit the wave. 


>**Step 2: **Review Execution Plan**

- Go to **Execute > Waves** and select the **Wave 1**
- Go to **Wave1 > Execution Plan** and review the plan by selecting **View by application** and **view by step group**
- Configure parameters


>**Step 3: **Execute**

> [!TIP]
> **Congratulations! You have completed Part 1 of the lab.**  
> Thank you for participating!

===

# PREL38 Part 2: Modernize application code with GitHub Copilot

In this part, you'll assess the **Caldova Bank** sample applications, plan a modernization, and check the changed code. Choose one track: **.NET** or **Java**. Each has one **provider** (the app the others call) and two **consumers** (the apps that call it). Modernize the provider first. An architect has prepared shared requirements for this exercise (the **rulebook**); you'll load them before planning.

The `start` folder is your working copy. The `finish` folder contains a prepared result you can use if a live run is slow or unavailable. You can keep moving while an agent works; don't wait for it to finish before starting the next review.

| Stage | Time | What you'll do |
| ----- | ---- | -------------- |
| Assess | 15 minutes | Run one assessment and review the portfolio report |
| Plan | 15 minutes | Create and review plans, then prepare a handoff branch |
| Execute and verify | 30 minutes | Start an agent run and inspect a prepared result |

Use only the commands for your track. Deployment is optional and takes another 20-30 minutes. Don't install tools, create resources, or use a personal account to work around a missing lab setup.

If Part 1 has not finished or is left incomplete, you are still able to proceed to Part 2.

===

## Get ready

*Before step 1 · About 2 minutes*

Switch from the Azure portal to your code tools. You stay on the same VM and use the same accounts you signed in with during **Set Up**.

In Part 1, Azure Copilot Migration Agent showed you *which* Caldova applications to move and where. In Part 2 you work with the code itself. You use GitHub Copilot to assess one application, plan its changes, and check the result.

**Lab route:** Part 1: assess the estate → **Part 2: modernize the code (you are here)** → Azure Copilot and ARM MCP server → SRE Agent.

You'll use **Modernize CLI** (`modernize`), a command-line tool that uses GitHub Copilot to assess and upgrade applications, and **VS Code with GitHub Copilot** to review plans and code. Both are already installed, and you signed in to VS Code during **Set Up**.

### Do this

Modernize CLI uses your GitHub sign-in to reach Copilot. Sign in now using the lab credentials to verify account access and prevent issues with access.

1. In Microsoft Edge inside the VM, select the address bar and open +++https://github.com/enterprises/skillable-events/sso+++. Select **Continue**, then sign in with the **Username** and **Temporary Access Pass** (or **Password**) from **Resources > Azure Portal**. If Microsoft shows a different account, select **Use another account**. Leave the browser open.
2. Open **Windows Terminal** (PowerShell). Select the terminal prompt, then select **Type** on the block below to run it:

    ```powershell
    gh auth login
    ```

    > **Hint:** **Type** enters the text for you wherever your cursor is in the VM, so select the PowerShell prompt first. If the command or its closing `}` remains at the prompt with no output, press **Enter** to run it.

3. Answer each prompt with the arrow keys and **Enter**:

    | Prompt | Select |
    | ------ | ------ |
    | Where do you use GitHub? | **GitHub.com** |
    | What is your preferred protocol for Git operations on this host? | **HTTPS** |
    | Authenticate Git with your GitHub credentials? | **Yes** |
    | How would you like to authenticate GitHub CLI? | **Login with a web browser** |

    If it says you're already logged in and asks whether to re-authenticate, select **No** and go to step 6.
4. The terminal shows a one-time code such as `ABCD-1234`. Write it down or keep the terminal visible, then press **Enter**. The browser opens inside the VM.
5. In the browser, enter the one-time code from the terminal and select **Continue**, then select **Authorize github**. If asked to sign in again, use the same lab account and the single sign-on page from step 1. When the page says your device is connected, close the browser tab and return to the terminal.

    Don't use the **Sign in** form on github.com with a username and password; the lab account only signs in through single sign-on, so that form reports *Incorrect username or password*. The same steps are in **Resources > GitHub sign-in**.
6. Check the sign-in and the lab folder:

    ```powershell
    gh auth status
    Test-Path C:\lab\caldova\modules\module-01-assess\start
    ```

**Before you continue:** `gh auth status` shows **Logged in to github.com** with your assigned lab account (not a personal account), and `Test-Path` returns `True`.

> **Hint:** If Windows Terminal warns about a multiline paste, check that the preview matches the lab commands, then select **Paste anyway**.

**Choose your track.** Where commands differ, each step has a **.NET** block and a **Java** block. Run only the block for your track.

**When a tool asks:**
- **Which model:** Keep **Auto**. In VS Code, leave **Auto** selected in the model picker. Modernize CLI commands in this lab already include `--model auto`, which selects the same option.
- **Whether to trust a folder:** Trust only the lab folder you opened (under `C:\lab\caldova\modules`), not the whole drive. If VS Code opens in **Restricted Mode**, select **Manage** and trust that folder.

If a check fails:
- **`gh auth status` still says you're not signed in:** Run `gh auth login` again and repeat steps 3-5.
- **The folder check returns `False`, or a tool is missing:** Ask the facilitator. Don't install software or switch to a personal account.

===

## 1. Run the short assessment

*Step 1 of 9 · About 8 minutes*

Run a live assessment on one application, `CaldovaAuthGateway`. It takes about 3 minutes, so start it and move on to step 2 while it works. The prepared report for all six apps is on the next page.

If you're short on time, skip the live assessment and go straight to the prepared report on the next page.

### Do this

1. In PowerShell inside the VM, go to the module and start Modernize CLI:

    ```powershell
    cd C:\lab\caldova\modules\module-01-assess\start
    modernize --model auto
    ```

    Use the arrow keys to move and **Enter** to confirm on every screen below.
2. If you see **Trust this folder?**, select **Yes, always trust this folder** and press **Enter**.
3. On **How would you like to modernize your app?**, keep **Assess** selected and press **Enter**.
4. On **Choose target repositories**, press **↓** twice to select **3. From a config file** (its path ends in `repos.json`), then press **Enter**.

    !IMAGE [Choose target repositories screen with option 3, From a config file, selected and the repos.json path shown](instructions359549/prel38-part2-assess-config-file-20261101.png)
5. On **Add source paths for config file**, the path already ends in `repos.json`. Press **Enter**.
6. On **Choose repositories**, check that it shows `[✓] CaldovaAuthGateway` and **Selected 1/1**, then press **Enter**.

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
10. The **Assessment dashboard** appears with `[Task 1/1] CaldovaAuthGateway` set to **RUNNING**. Leave this window open and go to step 2. You'll come back to it when the run finishes.

**Before you continue:** The dashboard shows `CaldovaAuthGateway` running, and your settings matched the table.

### Screen reference: the assessment settings

!IMAGE [Modernize CLI Assessment Configuration screen showing Full analysis, High, OpenJDK 21, Azure Container Apps (ACA), Linux, Disabled, .NET 10, Azure Container Apps, with Continue selected](instructions359549/prel38-part2-assess-settings-summary-20261101.png)

*This is the screen you should see in step 7. Select **Continue**.*

### If your settings are different

Only do this if the values in step 7 don't match the table, or if you see **Select assessment domains** instead of the summary.

1. If you're on **Assessment Configuration**, press **↓** to select **Reconfigure**, then press **Enter**. If you're already on **Select assessment domains**, continue to step 2.
2. On **Select assessment domains**, check that **Upgrade**, **Cloud Readiness**, and **Security** all have a check mark. Use **↑**/**↓** to move and **Space** to check or clear a box, then press **Enter**.
3. On **Configure assessment**, use **↑**/**↓** to move to a setting that doesn't match and press **Enter** to open it:
    - **Single choice** (Analysis Coverage, Minimum CVE Severity, Target Runtime, .NET Target Compute Services): select the value from the table and press **Enter**.
    - **Check boxes** (Java Target Compute Services, Java Target Operating System): use **Space** so that only the value from the table is checked, then press **Enter**.
4. When every value matches the table, move to **Continue** at the bottom and press **Enter**. Go back to step 8 above.

If the run is slow or fails, skip it and use the prepared report on the next page.


===

## 2. Read the estate and choose a track

*Step 2 of 9 · About 7 minutes*

Choose the .NET or Java group you want to follow. Use the report and source files to see how its apps connect before planning changes.

If you're short on time, use the **.NET** track, the primary path.

**Your track at a glance:**

| Track | Provider (change first) | Consumers (call the provider) | Shared database |
| ----- | ----------------------- | ----------------------------- | --------------- |
| .NET (recommended) | CaldovaAuthGateway | CaldovaLoanPortal, CaldovaRiskEngine | CaldovaBankDB |
| Java | CaldovaLedger | CaldovaPayGateway, CaldovaFraudDetector | CaldovaBankDB |

### Do this

1. In File Explorer inside the VM, select the address bar and open:

    ```plaintext
    C:\lab\caldova\modules\module-01-assess\start\.github\modernize\assessment-prebuilt
    ```

    Open the `reports-...` folder, then double-click `index.html`. If Windows asks how you want to open the file, select **Microsoft Edge**, then **Always**.
2. Review the portfolio, then the repository reports under `repos\<repository>`. Replace `<repository>` with an app's report-folder name. Identify unsupported frameworks, security findings, cloud-readiness issues, and database connection code.
3. Choose one track:

    **.NET:** Provider first: `CaldovaAuthGateway`. Consumers: `CaldovaLoanPortal` and `CaldovaRiskEngine`.

    **Java:** Provider first: `CaldovaLedger`. Consumers: `CaldovaPayGateway` and `CaldovaFraudDetector`.
4. In the gateway's report folder (`repos\CaldovaAuthGateway`), open `facts\data-architecture.md` and `facts\configuration-inventory.md`. Find `System.Data.SqlClient`, SQL-login settings (`DB_USER`/`DB_PASSWORD`), and certificate-validation settings.
5. Identify the service dependency for your track. The loan portal signs in through the gateway; the payment gateway posts to the ledger. The Java applications also call the auth gateway.

**Before you continue:** You can name your provider, its consumers, and the database-authentication changes the plan must cover. All six applications use `CaldovaBankDB`; the exercise targets Azure SQL Database.

Use the fact documents and code rather than guessing from the topology graph. Generated diagrams may omit a real dependency. Assessment counts are examples, not pass/fail thresholds; the **Additional guidance** page explains the reference findings.

**Checkpoint:** One track selected, provider first, and the database connection risks identified.

### When your live assessment finishes

Go back to the Modernize CLI window from step 1. Skip this section if you didn't start a live run.

1. When the run finishes, the CLI prints `SUCCESS: Assessment report has been created.` and the report opens in Microsoft Edge. If Windows asks how you want to open the file, select **Microsoft Edge**, then **Always**.
2. Check that you're looking at your live report: the page title is **Aggregated Assessment Report** and the **Issue summary** shows **1 of 1** scanned applications, with `CaldovaAuthGateway`.

    !IMAGE [Live Aggregated Assessment Report in Microsoft Edge showing Executive insights and an Issue summary of 1 of 1 scanned applications for CaldovaAuthGateway](instructions359549/prel38-part2-live-report-top-20261101.png)

    *Your counts and wording may differ. The report may suggest other Azure services, but the rulebook decides the target (Azure Container Apps).*
3. In the CLI, **How would you like to continue?** appears. Press **↓** to select **2. Return to main menu**, press **Enter**, then press **Esc** to exit Modernize CLI. Don't select **Create modernization plan**; you'll create the plan from a different folder in step 4.

**If the run finishes but no report opens in Edge**, open it yourself:

1. In the CLI output, find the line `SUCCESS: Assessment report has been created.` The line under it, after **See more details in:**, is the full path to `index.html`.
2. In File Explorer, select the address bar and open:

    ```plaintext
    C:\lab\caldova\modules\module-01-assess\start\.github\modernize\assessment
    ```

    Open the newest `reports-...` folder, then double-click `index.html`.

The live report covers one application. Use the prepared six-application report to choose your track.


===

## 3. Load the rulebook and add the PII skill

*Step 3 of 9 · About 3 minutes*

Before creating a plan, load the **rulebook**: the architect's shared policy and approved targets. You'll also copy a **skill** (a folder of instructions Copilot follows for a specific task) that shows the agent how to keep personally identifiable information (PII) out of logs.

If you're short on time, read `rulebook\policies.md` and run action 4 below to copy the skill.

**PII** (personally identifiable information) is data such as names, emails, Social Security numbers, and account numbers. The rulebook says *what* is required ("no PII in logs"). The PII skill shows the agent *how* to do it.

### Do this

1. In VS Code, use **File > Open Folder** to open `C:\lab\caldova\modules\module-02-plan\start`. Read `rulebook\policies.md` and `rulebook\targets.md`.
2. Confirm the training policy requires managed identity, certificate validation, no personal data in logs, supported dependencies, health checks, and Azure Container Apps readiness.
3. Open `.github\modernize\config.json` **in this module folder**. This file tells Modernize CLI where to download the rulebook. Check that `feature_flags.rulebook` is `true` and that `portfolio_url` is exactly:

    ```plaintext
    https://github.com/ayangupt/ignite26-caldova-rulebook
    ```

    That public training repository contains three files: `charter.md`, `targets.md`, and `policies.md`. The `rulebook\` folder you just read is a copy for you; the tool uses the online version. If the configuration is absent or different, ask the facilitator rather than substituting another source.
4. Copy the PII masking skill into all three applications in your track:

    **.NET:**

    ```powershell
    cd C:\lab\caldova\modules\module-02-plan\start
    $repos = 'CaldovaAuthGateway','CaldovaLoanPortal','CaldovaRiskEngine'
    foreach ($r in $repos) {
      New-Item -ItemType Directory -Force -Path "apps\$r\.github\skills" | Out-Null
      Copy-Item skills\pii-masking "apps\$r\.github\skills\" -Recurse
    }
    ```

    **Java:**

    ```powershell
    cd C:\lab\caldova\modules\module-02-plan\start
    $repos = 'CaldovaLedger','CaldovaPayGateway','CaldovaFraudDetector'
    foreach ($r in $repos) {
      New-Item -ItemType Directory -Force -Path "apps\$r\.github\skills" | Out-Null
      Copy-Item skills\pii-masking "apps\$r\.github\skills\" -Recurse
    }
    ```

**Before you continue:** Each repository contains `.github\skills\pii-masking`. When planning starts, look for **`Rulebook loaded (3 files)`**. The plan should also contain `rulebook-compliance.md` and `.metadata\rulebook-metadata.json`.

If `config.json` is missing, ask the facilitator; signing in again will not create that file. If it exists, check the working directory, feature flag, supplied URL, and existing GitHub access. If the rulebook still won't load, skip the live plan and review the prepared plans on the next page. Don't type in your own URL or point it at a local folder.

### Screen reference: the CLI loaded the rulebook

!IMAGE [Native Modernize CLI output showing Rulebook loaded (3 files)](instructions359549/prel38-part2-cli-rulebook-loaded-20261029.png)

*CLI rulebook-loading evidence. This line confirms the three files loaded; it does not mean that execution tasks or application tests passed.*

These requirements are for the training exercise, not a production policy.


===

## 4. Create the provider's plan

*Step 4 of 9 · About 10 minutes*

Use Modernize CLI to turn the assessment into a **plan**: a task list for the changes. Check that it covers the Azure target, database access, logging, and authentication before any code changes begin.

If you're short on time, skip the live plan and use the prepared plans on the track branch in `module-02-plan\finish`.

### Do this

1. Stay in `module-02-plan\start`. Copy the goal for your track:

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

    1. **Trust this folder?** Press **Enter** to keep **1. Yes, this time only**. (This appears because `module-02-plan\start` is a new folder.)
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
3. On **Create modernization plan**, use **↑** and **↓** to move between **Plan name** and **Type your own prompt**. Highlight **Plan name**, hold **Backspace** until `modernization-plan` is cleared (you'll see *Enter a plan name*), and type the plan name for your track:

    | Track | Provider | Plan name |
    | ----- | -------- | --------- |
    | .NET | `CaldovaAuthGateway` | `caldova-dotnet-modernization` |
    | Java | `CaldovaLedger` | `caldova-java-modernization` |

    Press **↓** to return to **Type your own prompt**.
4. Paste the goal you copied in step 1 with **Ctrl+V** (or right-click in the terminal), then press **Enter**. If nothing pastes, run step 1 again in a second PowerShell tab and paste again.

    Within about two minutes you'll see **`SUCCESS: Rulebook loaded (3 files)`**. Planning takes about 10 minutes in total.

    The planner then asks a few clarifying questions. Their wording varies between runs. For each one, highlight the option marked **(Recommended)** and press **Enter**, unless it conflicts with the rulebook. Never choose an option that provisions Azure infrastructure or deploys the app; this step only plans code changes.

    When you see **Summary for confirmation** and **Should I keep this plan exactly as generated?**, press **Enter** to choose **1. Confirm and keep as generated (Recommended)**.
5. Wait for **`SUCCESS: Rulebook compliance report: ...rulebook-compliance.md`**. The CLI then asks **How would you like to continue?**

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

    The `finish` folder starts on `main`, where these plans are not visible. Switch to the track branch before looking under `apps\<repository>\.github\modernize\<plan-name>`. Replace the placeholders with your app and plan names. Review the two consumer plans there; if live planning was unavailable, review the prepared provider plan there too.

### Screen reference: plan name and goal

!IMAGE [Modernize CLI Create modernization plan screen with Plan name caldova-dotnet-modernization and the cursor in Type your own prompt](instructions359549/prel38-part2-plan-name-20261101.png)

*The plan name is set and the cursor is in **Type your own prompt**, ready for you to paste the goal.*

### Screen reference: leave the plan without executing it

!IMAGE [Modernize CLI How would you like to continue menu with 1. Execute modernization plan highlighted by default and 2. Return to main menu below it](instructions359549/prel38-part2-plan-continue-20261101.png)

*This is what you'll see when the plan finishes: **Execute** is highlighted by default. Press **↓** to **2. Return to main menu** before pressing **Enter**.*

**Before you continue:** Under `apps\<repository>\.github\modernize\<plan-name>\`, you can open `plan.md`, `.metadata\tasks.json`, and `rulebook-compliance.md`. For a live plan, confirm `Rulebook loaded (3 files)` appeared and find `pii-masking` on the logging task.

If the menu looks different, use [Planning from PowerShell](#planning-from-powershell). If that doesn't work, review the prepared plan instead. If the PII skill or another requirement is absent, make the goal explicit and revise the plan before execution.

**Keep the integration contract:** The .NET portal must recognize `.CALDOVAAUTH` through the gateway's `/WhoAmI.ashx`. Its prepared goal includes `goals\dotnet-loanportal-extra.txt`. Test sign-in after the build.


===

## 5. Review the plans before execution

*Step 5 of 9 · About 5 minutes*

Check each plan against the requirements below. Add any missing task now, before the agent changes code.

If you're short on time, review only the provider plan.

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
2. Open `plan.md`, `.metadata\tasks.json`, and `rulebook-compliance.md` under each application's `.github\modernize\<plan-name>` folder. Use `module-02-plan\start` for a completed live provider plan and the selected track branch in `module-02-plan\finish` for prepared plans.
3. Match each requirement below to a concrete task. If a prepared plan has no `rulebook-compliance.md` (for example, the supplied LoanPortal plan), compare `plan.md` and `tasks.json` directly with the supplied rulebook.

    | Requirement | Evidence in the plan |
    | ----------- | -------------------- |
    | Supported runtime | .NET 10, or OpenJDK 21 with Spring Boot 3 |
    | Passwordless database access | Managed identity; remove stored SQL credentials |
    | Validated TLS | Explicit `Encrypt=True` and `TrustServerCertificate=False` |
    | No personal data in logs | Structured logging and the `pii-masking` skill |
    | Supported libraries | Replace `System.Data.SqlClient` or Struts as applicable; scan vulnerabilities |
    | Preserved behavior | Public routes, responses, and cross-application authentication |
    | Deployable result | Health endpoint, environment-based settings, compliant Dockerfile |
    | Verification | Build and tests after major changes |
4. If a requirement has no task, add the work to the plan/task files or regenerate with a clearer goal. Review the revision before proceeding.
5. Confirm that the provider is planned before its consumers.

**Before you continue:** The plans you reviewed cover the rules and integration contracts. Task wording and counts can differ; coverage matters more than matching a sample task list.

Ask the facilitator about an unclear rule or contract. Sample provider task shapes are on the **Reference** page.

**Checkpoint:** The plans you reviewed have their missing tasks addressed and have been checked against the rules.

### Screen reference: reviewing the prepared plan

In Explorer, open `apps > CaldovaAuthGateway > .github > modernize > caldova-dotnet-modernization > plan.md`. If the application itself is your workspace root, begin at `.github`. Use **Open Preview** to read the plan, then check its requirements against the rulebook.

!IMAGE [Prepared Caldova gateway plan open in VS Code, with the plan folder and Markdown preview visible](instructions359549/prel38-part2-win-prepared-plan-20261026.png)

*Example of the prepared plan. The agent wrote it, so check its claims against the code and the rulebook.*


===

## 6. Hand the plans to the developer

*Step 6 of 9 · About 2 minutes*

Put the reviewed plans and skill on a Git branch. Leave the assessment reports out; they contain sample passwords.

If you're short on time, skip to step 7. It uses a prepared folder that already contains the plans.

### Do this

Do not copy or stage plans while a planning agent is still writing them. If it has not finished, skip to **Start the prepared execution** rather than creating an incomplete handoff.

1. In PowerShell inside `module-02-plan\start`, create the handoff branch:

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
2. Bring the reviewed prepared plans into the handoff folder. The following preserves an existing complete plan, such as your live provider plan, and copies a prepared plan only when none exists. This copies from the track branch you selected in `module-02-plan\finish` in step 5.

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

**Before you continue:** Your reviewed `modernization/dotnet` or `modernization/java` branch carries the handoff. The rulebook remains in the central repository.

If the branch already exists, inspect it rather than resetting it. If no remote is supplied, keep the local commit and skip the push. The `-f` and assessment exclusion are explained under **Additional guidance**.


===

## 7. Start the prepared execution

*Step 7 of 9 · About 5 minutes*

Start the agent on the plan. While it works, review the prepared result in the next step; don't wait for the run to finish.

If you're short on time, don't start a run; go to the next page.

### Do this

1. Use the prepared execution folder, not the `module-02-plan` folder you used for planning:

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
2. Inspect `git --no-pager log --oneline` and the provider's `.github\modernize\<plan-name>\.metadata\tasks.json`, using your track's plan name. The runtime upgrade and page/servlet conversion are already committed; the first two tasks should say `"status": "success"`. Check `.github\modernize\config.json` in **this execution module and the provider's app folder**. Both should enable `feature_flags.rulebook` and use `https://github.com/ayangupt/ignite26-caldova-rulebook`. The planning module is a different copy.
3. In **VS Code inside the VM**, open Copilot Chat and use the selector labelled **Agent** at the bottom of the composer to choose **modernize**. If **Agent** is hidden, drag the Chat pane's left border to the left until the label appears. Selecting this custom agent is not the same as typing `@modernize`, which may show file/tool suggestions instead. If **modernize** is not listed, use [Execution without VS Code](#execution-without-vs-code) on the Reference page. Do not substitute the generic **Agent**, **Upgrade**, or a deployment agent, and do not start both routes.

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
4. Send the prompt, select **Execute the plan** if offered, and answer pending tool approvals. On the CLI route, confirm **`Rulebook loaded (3 files)`** in the execution output. In VS Code, inspect the agent's tool output for rulebook-loading evidence; selecting the agent alone does not confirm it loaded the rules. If loading cannot be confirmed, stop the run, ask the facilitator, and use the prepared result. Don't start a second route while a run is active.
5. Leave VS Code or the execution terminal open and continue to the next page. **Do not wait for the entire run.**

**Before you continue:** You can see the agent working in VS Code or the terminal. Leave it running and open the prepared result in the next step.

If the execution module's central configuration is missing, don't start a run without the rulebook loaded. Instead, continue to the finished-result review. If prepared tasks are not in the expected state, ask the facilitator. If the agent stops early, inspect task status before repeating the scoped prompt. Check the task statuses and test results, even if the command exits successfully. Do not launch a second execution while the first is active.

### Screen reference: checking the starting task state

Open `.metadata > tasks.json` from the plan folder. The first two tasks in this prepared start state show `"status": "success"`; the remaining tasks haven't run yet.

!IMAGE [Prepared tasks.json in VS Code showing success for the runtime upgrade and Web Forms conversion tasks](instructions359549/prel38-part2-win-task-states-20261026.png)

*Actual Windows view of the supplied start state. *


===

## 8. Review a finished application

*Step 8 of 9 · About 10 minutes*

Find what the agent missed in the prepared result. Compare the code with the rules, not just the build status.

If you're short on time, check one requirement from the table, then move on.

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
3. Find at least two gaps in the primary application's prepared result:

    | Track | Review targets |
    | ----- | -------------- |
    | .NET portal | Inspect the Dockerfile's base image and `USER`; compare the portal's authentication handler/response model with the gateway contract |
    | Java payments | Check the Dockerfile base image and non-root `USER`; look for the old `struts-config.xml` under `src\main\webapp` |
4. Compare each finding with the rulebook and decide what follow-up task would fix it.

**Before you continue:** You can name two gaps you found and the rule each one affects. This sample was created before the rulebook was loaded, and it skips deployment, so expect gaps.

Open the files and plan directly. If they differ from the examples, check them against the rules; don't try to recreate an old defect.

**Hint:** If an earlier Git command leaves you at `:` or `(END)` rather than a PowerShell prompt, press **q** to leave its pager. The commands above disable paging.


===

## 9. Validate the provider

*Step 9 of 9 · About 15 minutes*

Build and test the prepared provider. If your live run has finished, apply the same checks to that result too.

If you're short on time, run only the build and test commands and skip the local run.

### Do this

1. Open the provider in PowerShell inside the VM and build it:

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
    | Runtime and build | SDK-style .NET 10 project, or Spring Boot 3/Java 21; `dotnet build` or `gradle build` succeeds |
    | Database code | Identity-based authentication; no stored password; validated TLS; `DB_HOST`/`DB_NAME` settings |
    | PII | Masking helper used by structured logs; tests assert raw personal data is absent |
    | Security | Inspect the prepared security task's evidence; investigate any remaining High/Critical findings or prohibited libraries |
    | Compatibility | Public routes and response contracts preserved |
    | Container, if Docker is available | Approved Microsoft base image, non-root user, port 8080; image builds |

    A prepared security task may contain a summary in `.metadata\tasks.json` without a separate scan report. A `"success"` status or a summary claiming zero findings is not independent evidence. For the prepared .NET provider, check the current dependency graphs from this folder:

    ```powershell
    dotnet list package --vulnerable --include-transitive
    dotnet list Tests\CaldovaAuthGateway.Tests.csproj package --vulnerable --include-transitive
    ```

    These check NuGet dependencies, not all code/security requirements. If advisory data is unavailable, treat the check as unverified, not as zero findings. For Java, inspect the provided scan evidence or ask the facilitator for the approved scan route; do not install extra tooling.
3. For the prepared .NET gateway, run the supplied test project from the provider folder:

    ```powershell
    dotnet test Tests\CaldovaAuthGateway.Tests.csproj
    ```

    The prepared gateway includes 13 tests; inspect failures rather than treating the count alone as success. For Java, open `build\reports\tests\test\index.html` from the provider folder after `gradle build`. The prepared ledger includes 22 tests. If the tests are absent or fail, inspect the report and ask the facilitator.
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

    **Hint:** `dotnet run` and `gradle bootRun` keep running while the server is available. Gradle can remain at an **EXECUTING** progress indicator; do not wait for it to finish before checking the URL from another window.
5. Leave the server terminal running. In **Edge inside the VM**, open `http://localhost:8080/health`; expect HTTP 200. For .NET, open `http://localhost:8080/Login` and, from a new Windows Terminal tab (select **+**), run `curl.exe http://localhost:8080/WhoAmI.ashx` without adding cookies; expect `{"authenticated":false}`. These local checks do not prove database authentication or Azure telemetry delivery.
6. **Only if the facilitator confirms database readiness and access**, stop the local server with **Ctrl+C**, replace `DB_HOST`/`DB_NAME` with the supplied database values, and restart it before testing sign-in. The facilitator supplies the **application test user**. Your Windows password, Azure login, and Temporary Access Pass are not application credentials. If the database values, test data, or application credentials are unavailable, skip live database sign-in.
7. Return to your live execution. If it finished, repeat these checks on its result. Stop only your preview server with **Ctrl+C** when finished. For Java on Windows, answer **Y** if that terminal asks **Terminate batch job (Y/N)?** Close the dedicated preview terminal afterward so its placeholder settings are not reused. Do not terminate an unknown process if a port is already in use.

**Before you continue:** You have build/test evidence, a compatibility check, and you know which database/container checks ran. Check the database connection separately.

### Screen reference: build, tests, and local routes

Compare your output with these checkpoints, not the elapsed times. These come from running `dotnet build` and `dotnet test Tests\CaldovaAuthGateway.Tests.csproj` against the prepared gateway result.

!IMAGE [Actual Windows build and test output showing 13 tests passed, zero failed, and zero skipped](instructions359549/prel38-part2-win-build-tests-20261026.png)

The route check below shows the requested URLs, HTTP 200 responses, and `{"authenticated":false}` for `/WhoAmI.ashx` without a cookie.

!IMAGE [Actual curl output for localhost health and WhoAmI.ashx, both HTTP 200, with an unauthenticated JSON response](instructions359549/prel38-part2-win-local-routes-20261026.png)

*Example output. The app ran locally with `DB_HOST=localhost` and no database. This proves the build, tests, and local routes work. It doesn't prove Azure SQL access, sign-in, container deployment, or telemetry.*

Defer database checks if the database is unavailable. If Docker or package access fails, mark the container unverified and ask the facilitator. Use **Additional guidance** for the detailed code and security checks.

**Core path complete.** [Finish Part 2](#finish-part-2), or continue to optional deployment and reference material.


===

## Optional: Deploy the provider

Verify a managed-identity database connection from Azure Container Apps. Allow 20-30 additional minutes.

### Do this

1. Ask the facilitator for the **separate, approved deployment procedure or plan**. The rulebook keeps cloud deployment out of the core modernization plan; a newly generated plan may contain container files but no deployment task. Confirm that the supplied deployment procedure covers your track and uses the pre-provisioned resource group, registry, Container Apps environment, authorized managed identity, parameter file, and real `DB_HOST`/`DB_NAME` values. A **managed identity** lets the app authenticate to Azure without a stored password. **Skip this activity if the procedure, supplied setup, or authorized Azure sign-in is unavailable.** Do not add a deployment task to the core plan or reuse an inherited or unfamiliar Azure account.
2. Only if the approved procedure supplies `module-05-deploy\start\lab-azure.ps1`, load its values:

    ```powershell
    cd C:\lab\caldova\modules\module-05-deploy\start
    . .\lab-azure.ps1
    az account show
    Get-Item Env:LAB_RESOURCE_GROUP,Env:LAB_REGISTRY,Env:LAB_ENVIRONMENT,Env:LAB_IDENTITY_ID,Env:LAB_IDENTITY_CLIENT_ID
    ```

    The leading `. ` in `. .\lab-azure.ps1` runs the supplied script in your current PowerShell session so its settings remain available. This is called **dot-sourcing**. Check that `az account show` identifies the assigned lab account and subscription before proceeding.
3. Follow the facilitator's deployment procedure. If it uses an agent, use the entry it specifies and include these constraints in the request; do not ask it to execute a deployment task from the core modernization plan:

    ```plaintext
    Follow the separate deployment procedure supplied by the facilitator for my provider.
    Review the procedure and propose the deployment steps before making changes.
    Use the existing resource group <LAB_RESOURCE_GROUP>, registry <LAB_REGISTRY>,
    and Container Apps environment <LAB_ENVIRONMENT>.
    Attach <LAB_IDENTITY_ID>. Set AZURE_CLIENT_ID to <LAB_IDENTITY_CLIENT_ID>,
    DB_HOST to <DB_HOST>, and DB_NAME to <DB_NAME>.
    Use a unique app name ending with my alias.
    Do not create supporting Azure resources, install tools, or use Service Connector.
    The supplied identity already has database access.
    ```
    Replace every `<...>` placeholder with a facilitator-supplied value. Your **alias** is the short learner identifier the facilitator gives you for the app-name suffix, not an email address. **Service Connector** is an Azure feature that configures connections between services; this exercise excludes it because the identity and access are already prepared. Do not invent database names or hosts.
4. Read the generated deployment plan **before approving execution**. It must not create replacement infrastructure, install extensions, or grant database access.
5. Check `/health`, test the database-backed sign-in, and inspect logs for requests without personal data.

**Before you continue:** Confirm the app responds at `/health` and uses the identity provided by the facilitator.

Stop if the plan exceeds the permitted resource scope. Ask the facilitator; do not create missing infrastructure or change permissions.

When finished, delete only the app you created, using its exact name:

```powershell
az containerapp delete --name <your-app> --resource-group <lab-resource-group> --yes
```

Do not delete shared resources or reset the lab.


===

## Additional guidance

Use this page when you need more detail. It is not another required exercise.

### Prepared folders and assessment inputs

Each module's `finish` supplies a prepared result; the next module's `start` provides the corresponding starting point. Execution deliberately uses its prepared start so learners are not dependent on variable planning outcomes.

| Path within a module | Purpose |
| -------------------- | ------- |
| `apps\` | Application repositories |
| `.github\modernize\repos.json` | One-repository live assessment (`CaldovaAuthGateway`); the default in step 1 |
| `.github\modernize\repos-portfolio.json` | Six-repository estate list used to build the prepared portfolio report |
| `.github\modernize\assess-config.yaml` | Assessment settings |
| `.github\modernize\assessment-prebuilt\reports-...\` | Prepared portfolio and repository reports |
| `.github\modernize\config.json` | Rulebook flag and central repository URL |
| `docs\`, `rulebook\`, `skills\`, `goals\` | Training policy, readable rulebook, PII skill, and goals |

### What to notice in the estate

| Repository | Starting point | Relationship |
| ---------- | -------------- | ------------ |
| `CaldovaAuthGateway` | Web Forms/handlers, .NET Framework 4.8, Forms authentication | Sign-in provider for the portal and Java applications |
| `CaldovaLoanPortal` | Web Forms, .NET Framework 4.8 | Uses the gateway and shared authentication cookie |
| `CaldovaRiskEngine` | WCF, .NET Framework 4.8 | Credit-scoring service |
| `CaldovaLedger` | Servlets, Java 17, Gradle | Receives payments from the payment gateway |
| `CaldovaPayGateway` | Struts 1.3.10, Java 8, Gradle | Calls the ledger and auth gateway |
| `CaldovaFraudDetector` | Struts 2.5.30, Java 11, Gradle | Uses the shared database and auth gateway |

The .NET repositories have no NuGet packages in the legacy state, so their security findings are code weaknesses rather than package CVEs. The Java reports also include vulnerable dependencies. Counts change with advisory data and model output.

The prepared report can omit the payments-to-ledger edge, and cross-track calls to the auth gateway may not appear. Inspect `facts\business-workflows.md` and `facts\api-service-contracts.md`. Trust verified code relationships over a generated diagram. The report's suggested App Service/Kubernetes targets are assessment input; this lab's rulebook chooses Container Apps.

### Why the rulebook and skill are separate

`charter.md` defines scope and principles; `targets.md` defines approved technology; `policies.md` defines required behavior and validation gates. The PII skill supplies an implementation approach for the policy's logging requirement. Both must appear in the plan where relevant.

Keep `modernize` in the module working directory so it finds the configuration. If an execution starts from an app folder, check that folder's configuration too. The supplied `portfolio_url` is `https://github.com/ayangupt/ignite26-caldova-rulebook`; learners do not need to publish a repository. Verify the load message during planning and execution. A compliance report is model-generated and must be checked against real tasks and code.

### Why the handoff uses explicit paths and `-f`

Modernize CLI writes an ignore rule into `.github\modernize`, so ordinary staging can skip plans. The handoff command intentionally forces only the named plan folders and the project skills, not the entire `.github\modernize` tree: assessment reports may quote demo credentials from legacy code. Review `git status --short` before committing. Include the whole plan folder because generated file sets vary.

### Deeper provider checks

- **.NET:** Confirm `Microsoft.NET.Sdk.Web`, `net10.0`, and `PackageReference`. Check that legacy `packages.config`/`web.config` and Web Forms handlers were replaced appropriately.
- **Java:** Confirm Spring Boot 3/Java 21 and the `javax` to `jakarta` migration. Check for remaining Struts/servlet dependencies.
- **Database:** .NET should use `Microsoft.Data.SqlClient` with `Authentication=Active Directory Default`; Java should use an Entra identity mode of its JDBC driver. Java may retain `DB_PORT`. Confirm `Encrypt=True;TrustServerCertificate=False`.
- **Compatibility:** The Java consumers inspect the gateway's `/WhoAmI.ashx` response for the session-token contract. Preserve the exact public output and test the unauthenticated and signed-in paths.
- **PII:** Check masking for account, SSN, email, and phone values; names should be omitted. New logs must use the helper. If a generated result has no test for raw-data leakage, add that requirement before treating it as complete.
- **Containers:** Check the rulebook's Microsoft image, non-root user, and port 8080. Docker and package-registry access are prerequisites for a real build, not reasons to claim success without one.

The local Application Insights placeholder on the validation page lets the .NET exporter initialize; it is **not** evidence that telemetry reached Azure. Validate real telemetry only with a facilitator-provided configuration.


===

## Reference

Use these examples to interpret outputs or use a command-line alternative. They are not additional required runs.

### Provider plan shapes

| Theme | .NET gateway | Java ledger |
| ----- | ------------ | ----------- |
| Runtime | SDK-style .NET 10 and package references | OpenJDK 21, Spring Boot 3, Gradle updates |
| Web layer | Replace Web Forms/handlers; preserve routes | Spring MVC controllers; preserve public responses |
| Database | `Microsoft.Data.SqlClient`, identity, environment settings | Identity-based JDBC, remove stored SQL credentials |
| Logging | Structured logging and OpenTelemetry with `pii-masking` | Structured logging and OpenTelemetry with `pii-masking` |
| Security | Scan and address vulnerabilities | Scan and address vulnerabilities |
| Container artifacts | Approved Dockerfile for Container Apps; cloud deployment is separate | Approved Dockerfile for Container Apps; cloud deployment is separate |

Task grouping varies. Check the requirements rather than requiring exactly six tasks. The PII skill belongs on the logging task even when runtime and UI work are combined.

### Assessment from PowerShell

Run from `module-01-assess\start`:

```powershell
cd C:\lab\caldova\modules\module-01-assess\start
modernize assess `
  --source "$PWD\.github\modernize\repos.json" `
  --assess-config "$PWD\.github\modernize\assess-config.yaml" `
  --output-path "$PWD\.github\modernize\assessment" `
  --model auto `
  --no-tty
```

### Planning from PowerShell

Run from `module-02-plan\start`; use the Java goal/provider/plan/language for that track:

```powershell
cd C:\lab\caldova\modules\module-02-plan\start
modernize plan create (Get-Content goals\dotnet.txt -Raw) `
  --source "$PWD\apps\CaldovaAuthGateway" `
  --plan-name caldova-dotnet-modernization `
  --language dotnet `
  --model auto `
  --no-tty
```

### Execution without VS Code

Run from `module-03-execute\start`, where the central rulebook configuration must already be present. Use this route if VS Code does not expose the named modernization agent. Do not start it if another execution is active. The commands include `--model auto`; keep it. The .NET command is:

```powershell
cd C:\lab\caldova\modules\module-03-execute\start
modernize plan execute "Execute all remaining tasks, starting with the first unfinished task. Do not stop after one task. Do not run the deployment task. Do not provision or reconfigure cloud resources, grant access, push, or install tools. Keep public routes and business behavior. Build after each task." `
  --plan-name caldova-dotnet-modernization `
  --source "$PWD\apps\CaldovaAuthGateway" `
  --model auto `
  --no-tty
```

For Java, keep the live run to two unfinished tasks:

```powershell
cd C:\lab\caldova\modules\module-03-execute\start
modernize plan execute "Execute the next two unfinished tasks, one after the other, then stop. Do not run the deployment task. Do not provision or reconfigure cloud resources, grant access, push, or install tools. Keep public routes and business behavior. Build after each task." `
  --plan-name caldova-java-modernization `
  --source "$PWD\apps\CaldovaLedger" `
  --model auto `
  --no-tty
```

### Useful checks

From the provider directory:

```powershell
# .NET source/config check; inspect any matches rather than ignoring them
Select-String -Path *.cs,*.json -Pattern 'DB_PASSWORD','DB_USER','Password=','User Id=','TrustServerCertificate=True'

# Only when Docker is available and registry access is allowed
docker build -t caldova-authgateway .

# In a second terminal while the .NET gateway is running
curl.exe http://localhost:8080/WhoAmI.ashx
```

An empty top-level search is not a complete security scan; inspect nested source and generated configuration too. Without a cookie, the final command should return `{"authenticated":false}`.

For model availability and general command help, use `modernize help models` and the CLI's help. The architect creates the central rulebook ahead of the learner exercise; participants do not need to create or publish it.


===

## Finish Part 2

Leave with evidence and a clear handoff, not merely an agent completion message.

### Quick self-check

Ask yourself these three questions. If you can answer them, you got what this part is meant to teach.

1. **What changed** in the provider, and which rule required each change?
2. **What did you verify yourself** (build, tests, a local route), and what did you only read about?
3. **What's still unverified**, and who would need to check it?

### Check your outcome

Check only outcomes you actually completed. It's fine if some came from prepared results rather than live runs.

- You selected a track using dependencies and database findings.
- You reviewed the plans against the rulebook and included the PII skill.
- You created the handoff branch and started a scoped execution.
- You inspected a prepared result and checked build/test outcomes, rule gaps, and any deferred database or container checks.

If your agent is still running, you can leave it. Follow the facilitator's instructions for stopping it; do not start duplicates or reset the shared lab.

### If something did not work

| Symptom | Next action |
| ------- | ----------- |
| Lab folders, tool, agent, or model missing | Ask the facilitator; do not install or switch to personal access |
| CLI path must be absolute | Use the full path of the prepared configuration file |
| Assessment or execution takes too long | Use the prepared report/result and keep going |
| No `Rulebook loaded (3 files)` message | Check the working folder's config, rulebook flag, and supplied public repository URL; if loading remains unconfirmed, use the prepared evidence |
| Central repository access fails | Verify the supplied URL and `gh auth status`; ask for lab access |
| Plan omits a rule or PII skill | Make the goal explicit and revise the plan before execution |
| Planner asks questions not shown in this guide | Choose the **(Recommended)** option unless it conflicts with the rulebook; never choose provisioning or deployment |
| Pressed Enter on **Execute modernization plan** in step 4 | Press **Ctrl+C** to stop it, then continue with step 5. Execution in step 7 uses a separate prepared folder |
| Git stages no plans | Use the scoped `git add -f` command; keep assessment reports excluded |
| Prepared plans are not visible | Select the track branch in `module-02-plan\finish`; copy the reviewed missing plan folders into `start` before staging |
| Git output stops at `:` or `(END)` | Press **q**; use the non-paged review commands |
| Build passes but sign-in fails | Inspect the gateway/portal authentication contract and confirmed database access |
| Azure SQL or Docker unavailable | Skip that check; it isn't required to finish |

**Handoff:** The next section is **Azure Copilot and ARM MCP server**, followed by **SRE Agent**. Keep using the assigned lab identities. The SRE exercises use a separate, already-deployed Caldova Retail Co. storefront with its own repository and resource instructions. It isn't the code you changed in Part 2; nothing in Part 2 deploys it, and its Azure resources were provisioned before you started.

Select **Next** to continue to Azure Copilot and ARM MCP server.
===

# Azure Copilot and ARM MCP server

In this section, you'll explore how AI agents can help you understand and operate your Azure environment using natural language.

Instead of manually navigating resources or writing queries, you can describe what you want to understand or accomplish and let the agent use Azure tools to gather the information it needs.

You'll start with **Azure Copilot**, an agent that's already connected to Azure, so you can ask about your resources right away. Then you'll connect the same Azure access to GitHub Copilot in VS Code through the **ARM MCP server**. ARM is Azure Resource Manager, Azure's management layer; MCP is Model Context Protocol, a standard way for AI tools to connect to outside services.

> [!Note] Look, don't change. Both tools can make changes to Azure resources. In this lab, ask questions and read results only. Don't approve any action that creates, changes, or deletes a resource.

---

## Create a Space and Explore Your Resources

Azure Copilot **Spaces** let you create a focused working context around a set of Azure resources. For example, you might create a space representing an application, workload, or environment and then ask Copilot to reason specifically about those resources.

### Steps

1. In the Azure portal, open **Azure Copilot** at the top right. Make sure **New Experience** is turned on, then expand it to full screen.

2. Create a new **Space**.

3. Add the Azure resources you want to investigate. If you're not sure where to start, choose the resources in one resource group.
4. Ask questions about the resources in the space, starting with the prompts below.

### Try It

Start with:

> **Analyze the resources in this space and generate a report summarizing what is deployed, how the resources are organized, their current health, and anything I should investigate.**

Then continue the conversation:

> **What are the most important things I should pay attention to?**

> **Are there any configuration or policies I should keep an eye on across these resources?**

> **Turn your findings into a short operational report I could share with my team.**

**Check yourself:** Did Copilot flag anything you wouldn't have found quickly by clicking through the portal? Note one finding; you can compare it with the ARM MCP answers next.

---

# Going Further with the Azure Resource Manager MCP Server

Azure Copilot is one agent experience, but the connection to Azure does not have to stop there.

The **Azure Resource Manager (ARM) MCP Server** provides an agent-friendly interface to Azure that can be connected to other MCP-compatible agent harnesses.

This lets you build more customized Azure agents or bring Azure context and operations into the tools where you already work.

For example, you can connect ARM MCP Server to an agent experience such as **GitHub Copilot in Visual Studio Code**, **Claude**, **Codex** and more to interact with your Azure environment.

## Install the ARM MCP server

**Goal:** Connect GitHub Copilot to the lab's Azure environment.

1. In Microsoft Edge inside the VM, go to +++https://aka.ms/JoinARMMCP+++. The page opens VS Code with an install request for **Azure Resource Manager MCP Server** (type `http`, URL `https://mcp.management.azure.com`).
2. In VS Code, select **Install**.
3. When VS Code asks you to sign in, use the same Azure account you used in **Set Up**.

Seeing the server listed as installed doesn't prove it's connected yet. The first prompt below is the real check.

## Try It

Open GitHub Copilot Chat in VS Code and try these prompts:

> **Using the ARM MCP server, give me an inventory of my Azure resources grouped by subscription and resource type.**

**Check:** Copilot uses the ARM MCP server and returns a read-only inventory of the lab resources assigned to you. If it reports an authorization error or no subscriptions, sign in again with the Azure account from **Set Up**, then ask the facilitator if it still fails.

> **Find all the App Service apps and list the properties of each.**

> **What operations can I perform on these resources?**

Then ask about whatever caught your eye in the Azure Copilot Space. Do the two agents agree?

> [!note] Keep it read-only. If Copilot proposes a change, decline it.

---

## Lab Takeaway

Think of **Azure Copilot as the pre-built agent harness** and **ARM MCP Server as the reusable connection to Azure**.

- **Azure Copilot** gives you a ready-to-use agentic experience for understanding and operating Azure.
- **Azure Copilot Spaces** give the agent a focused collection of resources and instructions to reason over.
- **ARM MCP Server** provides a reusable connection to Azure that can be added to other MCP-compatible agent experiences.
- Together, these experiences demonstrate how you can use AI to **discover, understand, govern, and operate Azure resources using natural language**.

Select **Next** to continue to SRE Agent, the final part.

===

# SRE Agent

## Welcome to Caldova operations

Act as the on-call engineer for Caldova Retail Co., a storefront and operations app running on Azure App Service. Understand the app, investigate a customer-visible search failure, verify recovery, automate recurring work, and build interactive operational views.

Use the assigned `caldova-sreagent-\\<suffix>`. The Web App, resource group, and telemetry resources may also have generated suffixes. Whenever this guide says **Caldova Web App**, use the full actual name in your lab; do not type `\\<suffix>` or assume a fixed example name.

## Your path

| Stage | Exercises | What you'll have at the end |
| ----- | --------- | --------------------------- |
| Give the agent context | 1-4 | Your own repository copy, connected to the assigned agent alongside its Azure scope and logs |
| Investigate and fix | 5-7 | A working product search, verified in the app yourself |
| Automate and budget | 8-10 | A weekly cost review, a live health report, and a clear view of the AAU limit |
| Explore (optional, if time remains) | 11 | A look at report versions, detailed usage, Agent Canvas, skills, custom agents, integrations, and triggers, plus a capability you create if time permits |

**Typing prompts:** Select the text box **inside the VM** first, then click a prompt in these instructions to type it automatically, or copy and paste it. If automatic typing doesn't work, see **Additional guidance > Open Azure SRE Agent**.

**Keep work moving:** Imports, agent replies, task creation, report authoring, and scheduled runs can take several minutes. Answer pending questions or approvals, then continue an independent exercise instead of waiting. Return before a dependent step, such as connecting the imported repository or searching the website. Do not submit duplicate requests.

## 1. Start the GitHub import in the background

**Goal:** Create your own repository copy while you review the agent's context.

Your private copy lets the agent inspect the application's code and propose changes against your lab repository rather than the shared source.

1. Use the **GitHub Enterprise (GHE) lab account** you signed in with in **Set Up > GitHub and Copilot**, not a personal GitHub account. If needed, complete those sign-in steps in the VM browser first.
2. In the VM browser's address bar, enter +++https://github.com/new/import+++ and press **Enter inside the VM**.
3. In **The URL for your source repository\***, enter:

+++https://github.com/puneetg1983/caldova-ignite-authoring.git+++

4. Under **Owner**, select the **same GHE lab account**. Set **Repository Name** to `caldova-ignite-authoring` and visibility to **Private**.
5. Select **Begin import**, leave the status tab open, and continue to exercise 2 **without waiting**.

The destination form below shows where to select your lab account, name your repository copy, and keep it private.

!IMAGE [GitHub import destination fields with the lab account masked and Private selected](instructions359549/reviewed-destination-a53c82bb8f6a.png)

This progress screen means the import is running. Leave it open and use the waiting time to open your assigned SRE Agent.

!IMAGE [GitHub preparing the new repository while the import runs in the background](instructions359549/reviewed-progress-dfbc8bcafce4.png)

## 2. Open Azure SRE Agent

**Goal:** Select the agent assigned to your lab and see how its context is assembled.

The resource list identifies which agent you are opening. Its context wizard connects the Azure scope, telemetry, and code that ground its answers; this is not a new-agent creation exercise.

1. Open a new tab in **Microsoft Edge inside the lab VM**, select its address bar, and enter:

+++https://sre.azure.com+++

2. Press **Enter inside the VM**, then select **Sign in**. If already signed in with the lab Azure account, continue to agent selection.
3. Use the **Azure account** in **Resources > Azure Portal**, not the VM account. At **Temporary Access Pass**, use the **TAP** control in Resources.
4. In the SRE Agent resource list, select your assigned `caldova-sreagent-\\<suffix>` using its full actual name. Reuse this agent throughout the lab; do not create another.

The resource list below identifies the assigned Caldova agent. Open its name rather than starting a new deployment.

!IMAGE [SRE Agent resource list with the assigned Caldova agent; subscription masked](instructions359549/reviewed-agent-list-b627a44cd585.png)

5. On **More context. Better investigations.**, keep **Quickstart** selected and the **context wizard** open. Review resources and connect the imported repository in the next exercises before selecting **Done and go to agent**.

The context wizard groups the Azure resources, logs, and code available to the agent. Keep this screen open for the next two exercises.

!IMAGE [Context wizard after opening the assigned agent, with Quickstart selected, Code, and connected Logs](instructions359549/reviewed-context-wizard-b929c8710b68.png)

## 3. Review Azure resources and telemetry before connecting GitHub

**Goal:** Understand which resource group and log sources the agent uses.

Azure resource scope tells the agent what it may inspect; connected logs provide the evidence for health, traffic, and failure analysis. Reviewing both helps explain the answers you will see later.

After sign-in, you should see the **context wizard**. If not, follow **Additional guidance > Review Azure resources and telemetry** at the end to open it.

Stay on **Quickstart** in the **context wizard**. GitHub is **not connected yet**. You will connect the imported repository later in this section.

1. Under **Azure resources**, click **Show details**. Review the configured **Resource group**. Leave it unchanged.
2. Under **Logs**, click **Show details**. Confirm **Application Insights** and **Log Analytics** both show **Connected**.

The expanded Azure resource card shows the resource-group boundary for this lab; it is not a request to add access.

!IMAGE [Azure resources expanded to show Resource group scope](instructions359549/azure-resource-scope.png)

The Logs card confirms which telemetry sources are connected. These provide the evidence for the investigation and Live Report.

!IMAGE [Logs details with Application Insights and Log Analytics Connected](instructions359549/logs-connected.png)

Continue to **Connect the imported repository**.

## 4. Connect the imported repository

**Goal:** Connect your imported copy so the agent can investigate the application source.

Code context lets the agent relate runtime errors to their implementation and propose a fix instead of relying only on telemetry.

1. Confirm the GitHub import is complete and its source files are visible. Copy the imported repository's URL, not the original source URL.
2. In the **same context wizard**, under **Code**, click **+**. Select **GitHub** and paste your URL into **Repository URL**.
3. Scroll to **Connection method**. Keep **OAuth**, then click **Sign in to GitHub**. Confirm the **lab GitHub account**, review access, and click **Authorize Azure-SRE-Agent**. When **Connected to GitHub** appears, click **Next**.
4. Under **Add repositories**, confirm your imported repository's URL, then click **Save**.
5. Under **Code**, click **Show details** and confirm the imported repository appears.

Your repository URL should look like `https://github.com/User1-12345678_events/caldova-ignite-authoring`. Replace the example username with your actual lab GitHub username; do not use the original `puneetg1983` repository URL.

The repository dialog takes the URL of your imported lab copy, as illustrated below.

!IMAGE [Add repositories dialog with GitHub selected and the Repository URL field](instructions359549/reviewed-repository-connection-8c170c30e987.png)

OAuth connects that repository using your lab GitHub identity. Review the account before authorizing the connection.

!IMAGE [OAuth connection method and Sign in to GitHub](instructions359549/github-oauth.png)

After saving, the Code card should list your imported repository. This confirms the connection without another readiness exercise.

!IMAGE [Code details with one saved repository](instructions359549/repository-saved.png)

## 5. Review the Getting started thread

> [!Note] Spend up to 5 minutes here, then continue to **Inquire and configure Web App**. If the agent is still processing, continue and return later.

**Goal:** Understand what Caldova does and how its Azure resources fit together.

Use this introduction to build an application mental model before making operational decisions. Compare the agent's summary with its architecture and health evidence.

1. In the context wizard, click **Done and go to agent**, then review your **Getting started** thread.
2. Answer any open questions from the agent, then review the application summary, architecture diagram, and health findings.
3. Ask your own question about the app, or start with this one:

++++What is this app about, and what can customers do with it?++++

The example below shows how the onboarding thread combines saved context with questions you can answer to refine the agent's understanding.

!IMAGE [Example onboarding thread showing saved context and follow-up questions](instructions359549/reviewed-thread-overview-30ce58f220a8.png)

*Example from an earlier lab session; your thread title and generated answers may differ.*

## 6. Inquire and configure Web App

**Goal:** Inspect and understand the assigned App Service configuration.

Knowing the hosting settings and the actual website address helps you distinguish configuration choices from application-code failures and gives you the starting point for the search exercise.

1. Select **New chat** to start a separate configuration thread, not the Getting started thread. Enter:

++++List the configuration of the Caldova App Service and provide the full HTTPS link to its website.++++

2. Send the message, review the configuration, and ask questions about any unfamiliar settings.
3. Open the website link in a new **VM browser** tab and confirm the app loads. **Bookmark the page or copy the full URL for the next exercise.** Keep the SRE Agent tab open.

The reply can take time. If it is still running, start the independent scheduled-task or live-report exercise, then return for the website link before debugging.

In the configuration response, look for the assigned web app's full HTTPS website link. Save your own URL rather than copying the example instance below.

!IMAGE [Example App Service configuration response](instructions359549/reviewed-default-hostname-0540d408303f.png)

## 7. Debug the product\-search failure

**Goal:** Investigate the search problem, fix it, and confirm customer-visible recovery.

This exercise connects a real customer symptom with telemetry, code, and a verified running-app fix. A proposed patch is not the outcome: customers must be able to find products again.

1. Open your bookmarked website in the **VM browser**, or select the address bar in a new tab and paste or type the full URL copied during **Inquire and configure Web App**, then press **Enter inside the VM**.
2. Select **Catalog** and confirm browsing works. Under **Search by product name**, enter `jacket` and click **Search**. Observe **500 - Search failed**.

This is the customer-visible failure to investigate: product-name search returns HTTP 500 even though catalog browsing works.

!IMAGE [Product-name search fails with HTTP 500](instructions359549/search-failure.png)

3. Return to the SRE Agent tab, select **New chat**, and enter:

++++Product search fails with HTTP 500, but browsing works. Find out why, fix the running app, and check that searching for jacket returns products.++++

4. Send the message, follow the investigation, and answer the agent's questions.
5. Return to the app tab and repeat the same `jacket` search. Confirm matching products appear and catalog browsing still works.

**Check yourself:** Before moving on, can you say in one sentence what caused the failure and what changed to fix it? If not, ask the agent to summarize the root cause and the change it made.

Investigation and deployment can take time. After answering any pending questions or approvals, continue to the independent scheduled-task or live-report exercise and return to verify recovery. If the issue persists, tell the agent what still fails and ask it to investigate and test further, then repeat the `jacket` search.

## 8. Schedule a weekly cost review

**Goal:** Use chat to automate cost analysis, forecasting, and savings recommendations.

SRE Agent is not just for investigating and fixing incidents. **Scheduled tasks** turn recurring work into automatic flows: NSG-rule and RBAC-access audits, CVE and vulnerability reviews where security inventory is connected, FinOps reviews, anomaly detection, operational reporting, and proposed code changes or pull requests with the appropriate permissions and human review. In this exercise, automate a read-only weekly cost review rather than changing resources.

> [!Note] This lab was just deployed, so little cost history may be available. That reflects the age of the lab, not a limitation of the agent. Forecasts should state their assumptions.

1. In SRE Agent, select **New chat** and enter:

++++Create a weekly scheduled task called "Weekly Caldova cost review" and run it once now. Review current Azure costs, forecast next month, and recommend savings. Produce a self-contained HTML slide deck with charts, tables, and clear visuals for cost drivers, forecasts, and savings. Use available data, label estimates and assumptions, and do not change any resources.++++

2. Send the message and answer **any questions from the agent**. Task creation can take several minutes. **Don't wait for completion**: start the live-report exercise and return to this thread later.
3. **Only after the agent confirms the scheduled task has been created**, select **Automation > Weekly Caldova cost review**. Check its schedule and latest run status. If no run has started or is pending, select **Run task now** once; do not duplicate an agent-triggered run.

Once creation is confirmed, the task details show its schedule, run control, and linked execution thread.

!IMAGE [Run task now and the linked execution thread for Weekly Caldova cost review](instructions359549/reviewed-scheduled-task-run-c2fae5094228.png)

4. **Don't wait for completion.** Scroll to **Create a live traffic and health report** below and continue.
5. After that activity, return to **Automation > Weekly Caldova cost review**. Open its latest execution thread, review the findings, and open the HTML slide deck in the VM browser. Select the HTML download link in the result, then select **Open file** in the VM browser's **Downloads** panel. The run has its own thread, separate from the conversation that created the task.

This HTML deck was produced by the scheduled task's execution, not its creation chat. Its cost breakdown combines a chart, resource table, and explicit pricing assumptions. Treat these amounts as example estimates, not your lab's bill; your data and generated layout will differ.

!IMAGE [Scheduled task's HTML slide deck rendered in the VM browser with a cost chart, resource table, and estimate assumptions](instructions359549/reviewed-scheduled-task-html-0f6ab2cedfbf.png)

## 9. Create a live traffic and health report

**Goal:** Build and use an interactive UI through conversation, using a traffic and health view as this lab's example.

**Live Reports are a UI for AI, not just operational dashboards.** Describe an interactive application in chat, then refine it with the agent. It could be a service-health workspace, a guided approval app, or a **CRM-style application** for exploring customer records, filtering opportunities, and starting supported follow-up workflows. The connected data, tools, and permissions determine what it can actually read or do; creating the UI does not grant access to a CRM or other system.

In this lab, build a read-only traffic and health application: a dependency map becomes the entry point for exploring service telemetry. This is one example of the broader idea, not a limit on what a UI for AI can be. Interactivity depends on the report's available tools and components; do not assume every chart or node is clickable.

1. In the left navigation, select **Live reports > + New report**.
2. When the agent asks what report you want, select **Enter a custom response** and enter:

++++Create a live report called "Caldova Traffic and Health" using 24 hours of connected telemetry. Before the metric cards, draw a dependency graph using Azure service SVG icons inside circular health-colored rings, not text-only rectangles. Include a legend; label unknown health and inferred connections. Where supported, make nodes clickable for service health and metrics/logs; do not invent links. Below, show request counts, failure rate, response times, top requested/failing URLs, and geography where available. Use interactive charts and filters where supported, use a responsive layout, label missing data, and keep it read-only.++++

3. Click the arrow beside your response and answer any further questions. Review the report-saving approval and allow only the expected read-only telemetry tools.
4. Report authoring and saving can take several minutes. **Don't wait for completion.** Return to the scheduled task's creation thread; if it confirms creation, check the task under **Automation**. Finish other pending activities, then return.
5. Return later through **Live reports > Caldova Traffic and Health** once the report is saved. Review the dependency graph first, then the charts and tables.
6. Review the Azure service icons, health rings, and legend. If a graph node offers a drill-down, click it and inspect the service details or related telemetry, then return to the report. Try any available chart filters. If those interactions are unavailable, note that limitation; do not treat a decorative node as a working link. If the layout differs from your request, use **Open authoring thread** to ask for a correction to the existing report, not a duplicate.

    A node's details may open **below the graph**; scroll inside the report to see them. These panels can summarize the report's existing log-query results rather than make a new request. Read health rings as telemetry-based indicators, not a separate Azure Resource Health check.

The map below uses service icons and health rings to make the system easy to scan. Inferred connections and unknown health are labelled rather than presented as verified dependencies.

!IMAGE [Fresh lab report with official Azure service icons, health rings, inferred connections, and a health legend](instructions359549/reviewed-live-report-graph-e6d5eeaf49db.png)

Clicking a service can reveal an interactive details panel below the graph. Here the Web App panel shows request counts, failures, response times, and endpoints from the report's existing telemetry.

!IMAGE [Clicking the Web App icon opens request, failure, response-time, and endpoint details below the graph](instructions359549/reviewed-live-report-service-details-d19a3ff4820c.png)

These examples are from a targeted lab check. Your telemetry, resource names, health, and saved versions will differ. The Web App details summarize observed requests; the Application Insights node describes telemetry collection, not whether the monitored app is healthy.

## 10. Review agent consumption and the AAU budget

**Goal:** Understand how an AAU limit makes agent spending **predictable, controlled, and visible**.

This is a **budgeting exercise, not another Azure resource-cost analysis**. Set an active-flow allowance before giving the agent work, see how much of it has been used, and control how much processing you authorize. You can start small, gain confidence, and increase the allowance as you add useful workflows. A limit bounds active-flow spending; it does not make every task consume the same amount.

1. In the left navigation, select **Build + setup > Monitor > Agent consumption**. Locate **Monthly AAU limit** and the current active-flow usage.

The limit card below separates the fixed always-on flow from the active-flow allowance. This example has 10,000 active-flow AAUs; your allocation may differ. **Change AAU allocation** is the entry point for controlling that allowance, not another resource-cost report.

!IMAGE [Monthly AAU limit showing always-on flow plus 10,000 active-flow AAUs and Change AAU allocation](instructions359549/reviewed-aau-limit-21f2c8d359ee.png)

2. Select **Change AAU allocation**. Inspect the current monthly active-flow allowance and the control for increasing or decreasing it, then select **Cancel** without changing it.

The allocation panel lets you inspect the monthly active-flow allowance. In this example it remains unchanged at 10,000 AAUs; select **Cancel** after inspecting it.

!IMAGE [Change AAU allocation panel with the monthly active-flow allowance and Cancel control](instructions359549/reviewed-aau-allocation-controls-3e3a61f7c836.png)

3. Briefly review **Total active flow consumption**, **Daily active flow consumption**, and the breakdown under **Chats** and **Scheduled tasks**. Compare the used AAUs with the allowance and notice which workflow type accounts for the usage. This is a quick overview, not a thread-by-thread investigation.
4. Scroll to **Consumption by thread**. Scan the visible rows' **Thread type**, **AAUs**, and **Status** to see how individual workflows use the allowance. Comparing these amounts helps you budget agent attention as you add workflows.

The thread list below shows where to find each workflow's AAU consumption. This is a Microsoft documentation example, not this lab's usage; your threads and values will differ, and usage updates can lag.

!IMAGE [Reference example of Consumption by thread showing workflow types, AAUs, and status](instructions359549/reviewed-consumption-threads-reference-77063c8ff9c6.png)

*Reference screenshot: Microsoft, [Monitor agent usage](https://learn.microsoft.com/en-us/azure/sre-agent/monitor-agent-usage), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), reproduced unchanged.*

5. Understand the boundary: when the active-flow limit is reached, chat and actions stop until the allowance is available again. The fixed **always-on** charge is separate and continues while the agent exists.

The active-flow allowance does not cap the Caldova Azure resources or the separate always-on charge. If this lab does not expose Agent consumption, use **Additional guidance > Agent consumption and budget changes**.

## 11. Explore agent capabilities \(optional\)

**Goal:** Use your remaining time to discover how to extend the agent and which capabilities fit your own work.

Time is limited, so start by exploring the available views and examples. **If time permits, try creating and testing a skill or custom agent** with the agent's help. Use the lab's existing permissions and approved connections; exploring does not require additional credentials, resource changes, or test incidents.

### Explore additional resource scopes and log connectors

Reopen the **context wizard** using **Additional guidance > Review Azure resources and telemetry** if needed. Stay on **Quickstart** to explore how an agent can gain broader context for other environments.

1. Click **+** under **Azure resources** to see how you could connect a management group, subscription, or another resource group. Close or cancel without adding anything.
2. Click **+** under **Logs** to explore the available log connectors. Close or cancel without adding anything.

### Explore App Service Health check

**Goal:** Understand endpoint monitoring separately from product-search recovery, without changing settings.

Return to the configuration conversation from exercise 6 and enter:

++++Explain the Caldova App Service Health check setting and how /api/health could be used. Compare it with checking product search. Inspect only; do not change any settings.++++

Review the current setting and the explanation. A working `/api/health` does not prove that product search works. Do not approve a configuration write for this exploration.

### Explore Live Report versions and sharing

1. Open **Live reports > Caldova Traffic and Health**, then open the **version picker** to see the saved versions. Each saved edit creates another version; versions preserve layout and configuration, not historical telemetry. Keep the current version selected for interactive tool calls.
2. Explore the share icon (**Copy link to report**). Recipients must already have access to the agent; sharing the link does not grant access.

### Explore detailed AAU usage and allocation changes

1. Return to **Build + setup > Monitor > Agent consumption**. Use the **Chats** or **Scheduled tasks** cards to filter usage by workflow type, then clear the filter.
2. In **Consumption by thread**, find a completed workflow. Click a thread title to open its conversation and review the agent's steps, tool calls, approvals, and result. For the cost task, use its execution thread, not just the chat that created the schedule.
3. Select **Refresh**, apply a filter, and select **Download** to export the currently filtered threads as CSV.
4. If the facilitator has approved an allocation change, use **Change AAU allocation** to set that approved allowance. An increase takes effect immediately; decreasing it can interrupt current work and takes effect next month. Otherwise leave the allowance unchanged.

### Explore Agent Canvas and Skill Builder

1. Open **Build + setup** (**Builder** in the earlier navigation) and explore **Agent Canvas**, if available. Inspect the existing agent and its capabilities. If a capability is not available in this lab, read its purpose below and continue.
2. Explore **Skills** and **Skill Builder**, if available. You do not need to write skill files manually: **chat with the agent**, describe the procedure you want, refine its draft, and then create and try the skill if time permits.
3. For example, build a reusable skill for troubleshooting **web-service issues**, not just one Caldova search failure. In the skill-building conversation, enter:

++++Help me build a reusable skill for troubleshooting web-service issues. Cover HTTP errors, latency, timeouts, DNS/TLS, application and dependency logs, recent changes, and testing recovery from the user's perspective. Ask about my environment and team procedures, draft the skill, and help me refine it before I create and try it. Do not change application resources.++++

4. Review and refine the proposed guidance with the agent. If time permits, create the skill and ask a relevant troubleshooting question to try it; the agent loads relevant skills when needed. Use the same conversational approach to shape a custom specialist in **Agent Canvas**.
5. Explore the available connector, tool, policy, and hook views. Use the examples below to decide which capability fits a workflow.

| Capability | Why you would use it | Caldova example |
| ---------- | -------------------- | --------------- |
| Skill | Reusable instructions or a runbook that the agent can load when relevant; standardizes a procedure without creating a separate specialist. | A web-service troubleshooting procedure covering errors, latency, dependencies, recent changes, and end-to-end recovery tests. |
| Custom agent | A focused specialist with its own instructions and selected skills/tools, invoked deliberately or routed to by a workflow. | A web-service troubleshooting specialist using the reusable skill, or a FinOps specialist with a narrow remit. |
| Connector | Gives the agent an authenticated connection to a data or service surface. | Azure telemetry, the imported GitHub repository, or an approved incident platform. |
| Tool | A specific operation the agent can perform through its available integrations; inspect its inputs and whether it reads or changes state. | Query request failures, inspect an NSG, or propose a pull request with review. |
| Policy | Constrains agent behavior and approval boundaries so useful automation stays within the intended scope. | Require human review before a deployment or RBAC change. |
| Hook | Runs configured logic at supported lifecycle points to extend or check a workflow. | Add an organization-specific pre-action check or post-action audit record where the platform supports it. |

### Explore incident management and HTTP triggers

1. Open **Incidents**. Incident management requires a connection to an incident-management platform. Explore **Connect an incident platform** or the available integration options to see which providers the agent supports and what connection information they require. Use the lab's existing connections; a new connection needs the appropriate platform credentials and approval.
2. Open **Incidents > Triggers + response plans** and explore how incident sources, filters, response plans, and autonomy settings would route work once an incident platform is connected.
3. Explore the **HTTP trigger** entry or documentation if available. Consider which external application could call a workflow and what authentication and tool access it would need. Treat callback URLs as credentials; use only an approved setup if trying a trigger.

Incident management turns incoming alerts into routed investigation workflows instead of waiting for an operator to start a chat. A response plan chooses which alerts deserve attention, which specialist handles them, and what requires approval. Narrow filters and cooldowns help avoid overlapping work and repeated AAU consumption.

An HTTP trigger lets an external system start a defined agent workflow on demand, such as requesting a deployment-readiness review from a pipeline or a compliance report from an internal portal. Scheduled tasks run by time; incident triggers react to alerts; HTTP triggers react to an explicit application request. Choose the trigger that fits the event and the agent attention you have budgeted.

## Complete

Before you finish, check that you can tick each of these:

- Searching for `jacket` in the app returns products, and catalog browsing still works.
- You've opened the cost review's HTML slide deck from its execution thread.
- You've used the **Caldova Traffic and Health** live report, including any drill-downs it offers.
- You can explain how the AAU limit keeps agent spending predictable, controlled, and visible.

Note anything still running or blocked. Follow the facilitator's cleanup instructions; don't reset the lab or delete shared resources.

## Additional guidance

Use this section if you are stuck or need more help following an instruction, or ask the facilitator. All optional tasks are grouped in **Explore agent capabilities (optional)** above, not here.

### Open Azure SRE Agent

Focus the destination field **inside the VM**. Copy/paste or type the prompt or URL, or click its text in these instructions to type automatically. For automatic typing, keep it focused until typing finishes. Then select **Send** or press **Enter** as instructed. Use **Resources > Azure Portal** for Azure sign-in details, not the VM account.

**Type Text did not work?** Type `https://sre.azure.com` manually in the VM browser's address bar, then press **Enter inside the VM**. Do not change VM settings or permissions.

**Password requested instead of TAP?** Use the Azure password in **Resources > Azure Portal**, not the VM password.

### Review Azure resources and telemetry

If the wizard is closed, go to **Operations hub > Overview > Complete setup**. Ask the facilitator if the option is absent. Review only the existing resource group; do not add broader access.

### Connect the imported repository

Do not add a duplicate connection or use a personal account. If the agent reports that indexing is still running, continue another activity and return later. If it cannot retrieve the imported source, ask the facilitator.

### Review the Getting started thread

Under **Favorites**, select **Team onboarding**. If absent, select **Search Threads**, search `get to know`, and open your lab user's greeting.

### Inquire and configure Web App

Keep Getting started for the app overview. Use **New chat** for configuration. Bookmark or copy the website link returned by the configuration prompt for the next exercise. If it is missing or does not open, use the manual steps below.

### Debug the product-search failure

**Website link missing or not opening?** Find the actual app URL manually:

1. Open a new tab in the **VM browser** and select its address bar. Copy/paste or type the Azure Portal URL below, or click it to type automatically. Then press **Enter inside the VM**:

+++https://portal.azure.com+++

2. In Azure Portal, select **Resource groups** and open the resource group assigned to this lab, shown in **Resources**. In its resource list, open **caldova-webapp-...** with type **App Service**, not the App Service plan.
3. On the web app's **Overview** page, find **Default domain**. Select **Browse** to open the app, or copy the domain and paste or type `https://` followed by that domain into a new VM browser tab, then press **Enter inside the VM**. Bookmark the page or copy its full URL, and keep the SRE Agent tab open.

Example only: `https://caldova-webapp-\\<unique-suffix>.azurewebsites.net`. Your suffix will differ, and Azure may include extra regional hostname components. Use the complete **Default domain** shown for your app, not this example.

**Cannot find the web app?** Confirm Azure Portal is using the lab's Azure account and assigned subscription from **Resources**, then reopen the assigned resource group and clear resource-list filters. Look for **caldova-webapp-...** with type **App Service**. If it is absent or access is denied, ask the facilitator; do not create resources or change permissions. If the app does not open, copy its complete **Default domain** from **Overview** and try the HTTPS address in the VM browser. Do not use the example URL or another learner's hostname.

If search already works, tell the facilitator; do not break the app yourself. Verify recovery by repeating the search in the app.

A source-code pull request is not a deployment. If the running app still fails after a proposed fix, tell the agent the result and ask it to investigate and test further, then repeat the `jacket` search. Returning an empty result set is not recovery for the `jacket` search.

### Schedule a weekly cost review

If the task is not listed yet, return to its creation chat and answer any pending questions or approvals. Continue another activity and check again; do not create a duplicate task.

Wait for the creation thread to confirm that the task exists before looking for it under **Automation**. If creation is still running, continue an independent exercise and return later.

Select **Automation > Weekly Caldova cost review** to check its latest run. Do not start a duplicate run. Open the execution thread to verify the findings and HTML slide deck, rather than relying on the run status alone. If a run fails or the HTML attachment is missing or does not open, record the issue and ask the facilitator; do not install software or grant additional access.

### Create a live traffic and health report

If telemetry is empty, browse the app and try search, then return after another activity. Missing data or unknown dependency health does not mean the app is healthy. Ask the facilitator about connector or query errors; do not add permissions.

While working on another activity, check the report's authoring thread for pending questions or approvals. **Allow once** may be needed to save the report with its expected read-only telemetry tools; saving the report does not change Azure resources. An empty gallery does not necessarily mean generation is still running.

The 24-hour report can still include earlier failures after a fix. Verify recovery with fresh app requests rather than expecting historical failure charts to turn green immediately.

**Generic symbols instead of Azure service icons, or graph too tall?** Open the existing report's **Open authoring thread**, then select its message field **inside the VM**. Copy/paste or type the prompt below, or click it to type automatically:

++++Replace only the Web App and App Insights glyphs with these Azure SVGs inside the existing health rings. Preserve click handlers and queries. Cap graph height at 400px without distortion. Save a new version, not a new report. Web App: https://raw.githubusercontent.com/puneetg1983/caldova-ignite-authoring/b4d549a6e6d38b260cde398873ec44c5d3caf43c/skillable/instructions/images/prel38-revision/azure-app-service.svg App Insights: https://raw.githubusercontent.com/puneetg1983/caldova-ignite-authoring/b4d549a6e6d38b260cde398873ec44c5d3caf43c/skillable/instructions/images/prel38-revision/azure-application-insights.svg++++

Send the message, continue an independent activity, and return for any save approval. These original Microsoft icons are supplied unchanged under the [Azure icon terms](https://learn.microsoft.com/en-us/azure/architecture/icons/#icon-terms). Keep the health rings around the icons; do not alter their shapes.

**Clicked a node but cannot see details?** Scroll within the report, using its right-hand scrollbar if the mouse wheel does not move it. Look below the graph and legend for the service panel. If no panel or supported interaction appears, record that limitation rather than inventing a link.

### Agent consumption and budget changes

In the new navigation, open **Build + setup**, expand **Monitor**, and select **Agent consumption**. Earlier navigation uses **Settings > Agent consumption**. If neither route is available, ask the facilitator and use the labelled screenshots to discuss the limit and usage. Do not restart the agent, switch navigation modes, enable features, or change permissions to reveal the page. Record any unavailable inspection rather than treating missing usage as zero.

Usage can lag behind the conversation. Select the correct month, clear type/day/status filters, and select **Refresh** before concluding that a thread is missing or has used no AAUs. Use thread titles and execution details to identify work; do not assume a report or scheduled task is represented only by its creation chat.

### Reference guides

The consumption and optional exploration follow the product guides below. These links explain the capabilities; creating them is not required in this lab. If a control is unavailable in your lab version, ask the facilitator rather than changing permissions.

- [Agent consumption](https://learn.microsoft.com/en-us/azure/sre-agent/monitor-agent-usage) and [AAU limits and billing](https://learn.microsoft.com/en-us/azure/sre-agent/pricing-billing#set-an-active-flow-spending-limit).
- [Create a skill](https://sre.azure.com/docs/tutorials/automation/create-skill) and [Create a custom agent](https://sre.azure.com/docs/tutorials/automation/create-subagent).
- [Connect Azure Monitor and automate incidents](https://sre.azure.com/docs/get-started/automate-incidents) and [Configure a response plan](https://sre.azure.com/docs/tutorials/agent-config/setup-response-plan).