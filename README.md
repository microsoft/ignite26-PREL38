<a name="start-building"></a>

<p align="center">
<img src="img/banner-ignite-26.png" alt="Microsoft Ignite 2026" width="100%"/>
</p>

# [Microsoft Ignite 2026](https://ignite.microsoft.com)

## PREL38: Plan, modernize, deploy, and operate with AI agents

### Session description

Explore how AI agents support application modernization, database migration, and operations. Assess and plan application changes, review a prepared .NET modernization checkpoint, migrate SQL Server databases to Azure SQL Database Hyperscale, and investigate a simulated production incident with Azure SRE Agent.

### 🚀 Getting started

Use the materials for the section your instructor assigns:

| Section | Materials |
|---|---|
| Application modernization | [Guide and prepared .NET final state](app-modernization/README.md) |
| Database modernization | [SQL Server to Azure SQL Database Hyperscale guide](mod3-database-modernization) |
| Operations | [Azure SRE Agent walkthrough](instructions/sre-agent.md) |

#### In a guided session

If you're following along during a live session:

1. Use your assigned Skillable workstation, lab accounts, and resources.
2. Follow the instructor's sequence and the section-specific materials above. The [attendee instructions](instructions/README.md) link to application modernization, database modernization, and SRE Agent. Complete database modernization before moving to SRE Agent.
3. For application modernization, use the starting and review examples supplied in Skillable before comparing them with the prepared final state. This repository does not replace those examples or the live modernization setup.

#### On your own

If you're learning at your own pace:

1. Clone this repository and choose a section from the table above.
2. Start with the [application-modernization guide](app-modernization/README.md) to review the supplied .NET source, container assets, and recorded evidence. Follow the [final-state guide](app-modernization/final/dotnet/README.md) for prerequisites and commands to reproduce its checks.
3. Use the assigned workshop environment for the guided exercises. Live modernization, database migration, and SRE activities require the tools, accounts, and resources described in their respective guides; cloning this repository does not provision them.

### 🎯 Learning outcomes

By the end of this session, you will be able to:

- Assess and plan scoped application modernization, then review changes across connected .NET applications.
- Explain the difference between a prepared final-state checkpoint, a learner's agent output, and verified Azure deployment readiness.
- Assess SQL Server migration readiness and remediate compatibility issues for Azure SQL Database Hyperscale.
- Explain how Caldova source context, Azure resources, and telemetry support an SRE Agent investigation.
- Use or configure an Azure SRE Agent custom agent, skill, and response plan for a scoped incident.
- Trigger a Caldova incident simulation, evaluate the evidence and action, and verify service recovery.

### 💻 Technologies used

#### Modernization and development

- [GitHub Copilot modernization](https://learn.microsoft.com/en-us/azure/developer/github-copilot-app-modernization/)
- [.NET](https://learn.microsoft.com/en-us/dotnet/)
- [ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/)
- [SQL Server](https://learn.microsoft.com/en-us/sql/sql-server/)
- [Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/)
- [Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/identity/)
- [.NET container images](https://learn.microsoft.com/en-us/dotnet/core/docker/introduction)
- [GitHub](https://learn.microsoft.com/en-us/training/paths/github-foundations/)

#### Operations and infrastructure

- [Azure SRE Agent](https://learn.microsoft.com/en-us/azure/sre-agent/overview)
- [Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/)
- [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Azure Database for PostgreSQL](https://learn.microsoft.com/en-us/azure/postgresql/)
- [Azure Application Gateway](https://learn.microsoft.com/en-us/azure/application-gateway/)
- [Azure Virtual Network](https://learn.microsoft.com/en-us/azure/virtual-network/)
- [Network Security Groups](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
- [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/)
- [Azure Virtual Machines](https://learn.microsoft.com/en-us/azure/virtual-machines/)
- [Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
- [Log Analytics](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-overview)
- [Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)

### 📚 Continue your learning

Pick your next step based on your learning style:

| Resource | What you'll get |
|----------|-----------------|
| **[Ignite 2026 Next Steps](https://aka.ms/ignite26-next-steps)** | Additional session repos and materials from Microsoft Ignite 2026 |
| **[Microsoft AI Skills Navigator](https://aka.ms/ignite26-asn)** | Discover AI skills, learning paths, and resources for your next step |
| **[Microsoft Learn](https://aka.ms/ignite26-learn)** | Official documentation and guided learning paths on these topics |
| **[Microsoft Foundry Community](https://aka.ms/MicrosoftFoundryDiscord-Ignite26)** | Connect with other learners and experts in our Discord community |

### 🌟 Microsoft Learn MCP Server

The Microsoft Learn MCP Server gives your AI agent direct access to Microsoft's official documentation — grounded, up-to-date answers about the topics in this session.

**GitHub Copilot CLI** — Install with:

```shell
copilot plugin install microsoftdocs/mcp
```

**VS Code** — One-click install:  
[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install_Microsoft_Learn_MCP-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect/mcp/install?name=microsoft-learn&config=%7B%22type%22%3A%22http%22%2C%22url%22%3A%22https%3A%2F%2Flearn.microsoft.com%2Fapi%2Fmcp%22%7D)

For more information, visit the [Learn MCP Server repo](https://aka.ms/learnmcp).

### 👥 Content owners

<table>
<tr>
    <td align="center">
        <a href="https://github.com/meetshamir">
            <img src="https://github.com/meetshamir.png" width="100" alt="Shamir Aziz"/><br />
            <sub><b>Shamir Aziz</b></sub>
        </a><br />
        <a href="https://github.com/meetshamir">@meetshamir</a>
    </td>
</tr>
</table>

### ⚖️ Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow [Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general). Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.

Any use of third-party trademarks or logos are subject to those third-party's policies.
