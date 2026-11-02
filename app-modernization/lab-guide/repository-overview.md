### Find your way around the project

The code for this part of the lab is under `C:\lab\caldova\modules`. Each module has separate `start` and `finish` Git checkouts, so changing one does not automatically change the others. Follow the folder path in each step.

<div id="caldova-workspace-map" role="group" aria-labelledby="caldova-workspace-map-title" style="max-width:720px;margin:1em 0;padding:1em;border:1px solid #d7dfe7;border-radius:8px;background:#ffffff;color:#202c3b;line-height:1.5;overflow-wrap:anywhere">
<h4 id="caldova-workspace-map-title" style="margin:0 0 0.8em;font-size:1.3em;color:#202c3b">Your Caldova workspace</h4>
<p style="padding:0.7em;background:#eaf3fb;font-family:Consolas,monospace;color:#202c3b"><strong>C:\lab\caldova\modules\</strong></p>
<div style="margin-left:0.6em;padding-left:1em;border-left:1px solid #8e9ba8;font-family:Consolas,monospace">
<p><strong>module-01-assess\</strong><br><span style="padding-left:1em">start\ &nbsp; finish\</span></p>
<p><strong>module-02-plan\</strong><br><span style="padding-left:1em">start\ &nbsp; finish\</span></p>
<p><strong>module-03-execute\</strong><br><span style="padding-left:1em">start\ &nbsp; finish\</span></p>
</div>
<p><strong>start\</strong> = working copy<br><strong>finish\</strong> = prepared checkpoint</p>
<p style="margin-top:1.5em"><strong>Inside an assessment checkout</strong><br><span style="font-family:Consolas,monospace">module-01-assess\start\</span></p>
<div style="margin-left:0.6em;padding-left:1em;border-left:1px solid #8e9ba8">
<p style="font-family:Consolas,monospace"><strong>apps\</strong></p>
<div style="display:flex;flex-wrap:wrap;gap:0.8em 1.5em;padding:0.8em;background:#f3f7fb">
<div style="flex:1 1 200px;min-width:0"><strong style="color:#075ca8">.NET applications</strong><div style="font-family:Consolas,monospace;line-height:1.8">CaldovaAuthGateway<br>CaldovaLoanPortal<br>CaldovaRiskEngine</div></div>
<div style="flex:1 1 200px;min-width:0"><strong style="color:#176444">Java applications</strong><div style="font-family:Consolas,monospace;line-height:1.8">CaldovaLedger<br>CaldovaPayGateway<br>CaldovaFraudDetector</div></div>
</div>
<p style="margin-top:1.5em;font-family:Consolas,monospace"><strong>.github\modernize\</strong></p>
<table style="width:100%;table-layout:fixed;border-collapse:collapse;overflow-wrap:anywhere">
<thead><tr><th style="width:49%;padding:0.4em;text-align:left">Path</th><th style="padding:0.4em;text-align:left">Purpose</th></tr></thead>
<tbody>
<tr><td style="padding:0.4em;font-family:Consolas,monospace">repos.json</td><td style="padding:0.4em">Live assessment: 1 app</td></tr>
<tr><td style="padding:0.4em;font-family:Consolas,monospace">repos-portfolio.json</td><td style="padding:0.4em">Portfolio list: all 6 apps</td></tr>
<tr><td style="padding:0.4em;font-family:Consolas,monospace">assess-config.yaml</td><td style="padding:0.4em">Assessment settings</td></tr>
<tr><td style="padding:0.4em;font-family:Consolas,monospace">config.json</td><td style="padding:0.4em">Rulebook configuration</td></tr>
<tr><td style="padding:0.4em;font-family:Consolas,monospace">assessment\</td><td style="padding:0.4em">Your reports after a run</td></tr>
<tr><td style="padding:0.4em;font-family:Consolas,monospace">assessment-prebuilt\</td><td style="padding:0.4em">Prepared reports</td></tr>
</tbody>
</table>
<p style="margin-top:1.5em"><strong style="font-family:Consolas,monospace">rulebook\</strong><br>Rules + approved targets</p>
<p><strong style="font-family:Consolas,monospace">skills\</strong><br>Reusable PII guidance</p>
<p><strong style="font-family:Consolas,monospace">docs\ &nbsp; goals\</strong><br>Context + goals</p>
</div>
</div>

*Main Part 2 folders and selected files are shown. Contents vary by module and branch.*

- **`start\`:** Your working copy for that module. Use **`finish\`** only when the guide directs you to a prepared checkpoint.
- **`apps\`:** The six Caldova applications. Everyone assesses **CaldovaAuthGateway** first. Later, the .NET track works on **CaldovaAuthGateway** and the Java track on **CaldovaLedger**.
- **`.github\modernize\`:** CLI settings, repository lists and reports. **`repos.json`** selects the one-app live assessment; **`repos-portfolio.json`** lists all six apps. Your run writes to **`assessment\`**; the supplied reports are in **`assessment-prebuilt\`**.
- **`rulebook\` and `skills\`:** The modernization rules and reusable PII-masking guidance. **`docs\` and `goals\`** provide supporting context.

**Start here:** `C:\lab\caldova\modules\module-01-assess\start`. The instructions will move you to the planning and execution checkouts when needed.
