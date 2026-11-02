### Find your way around the project

The code for this part of the lab is under `C:\lab\caldova\modules`. Each module has separate `start` and `finish` Git checkouts, so changing one does not automatically change the others. Follow the folder path in each step.

!IMAGE [Caldova workspace: assessment, planning and execution modules each have start and finish checkouts. An assessment checkout contains six apps, Modernize configuration and reports, and rulebook, skills, docs and goals folders.](instructions359549/prel38-caldova-repo-structure.png)

*Main Part 2 folders and selected files are shown. Contents vary by module and branch. Select the graphic to open it at full size.*

- **`start\`:** Your working copy for that module. Use **`finish\`** only when the guide directs you to a prepared checkpoint.
- **`apps\`:** The six Caldova applications. Everyone assesses **CaldovaAuthGateway** first. Later, the .NET track works on **CaldovaAuthGateway** and the Java track on **CaldovaLedger**.
- **`.github\modernize\`:** CLI settings, repository lists and reports. **`repos.json`** selects the one-app live assessment; **`repos-portfolio.json`** lists all six apps. Your run writes to **`assessment\`**; the supplied reports are in **`assessment-prebuilt\`**.
- **`rulebook\` and `skills\`:** The modernization rules and reusable PII-masking guidance. **`docs\` and `goals\`** provide supporting context.

**Start here:** `C:\lab\caldova\modules\module-01-assess\start`. The instructions will move you to the planning and execution checkouts when needed.
