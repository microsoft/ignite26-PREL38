<a name="start-building"></a>

<p align="center">
<img src="img/banner-ignite-26.png" alt="Microsoft Ignite 2026" width="100%"/>
</p>

# [Microsoft Ignite 2026](https://ignite.microsoft.com)

## PREL38: Operate Caldova with Azure SRE Agent
### Session description

Investigate and recover a simulated production incident in Caldova with Azure SRE Agent. Choose exactly one path: **Preconfigured** (25–30 minutes) to inspect and use a completed configuration, or **Configure** (50 minutes) to investigate the recommended course-recommendations scenario and build its alert → skill → custom agent → response-plan chain.

### 🚀 Getting started

#### In a guided session

If you're following along during a live session:

1. Confirm your instructor has assigned your learner number and deployment token.
2. Choose either the Preconfigured or Configure learner path and complete exactly one scenario.
3. Open the [attendee instructions](instructions/README.md).
4. On the Skillable workstation, start the learner simulator with `pwsh -NoProfile -File scripts/start-simulator.ps1 -LearnerNumber N`, replacing `N` with your assigned learner number.

#### On your own

If you're learning at your own pace:

1. Open the packaged local repository supplied with the lab.
2. Review the [lab architecture](docs/architecture.md) and [lifecycle contract](docs/lifecycle.md).
3. Follow the [attendee instructions](instructions/README.md). GitHub access is not required.

### 🎯 Learning outcomes

By the end of this session, you will be able to:

- Explain how Caldova source context, Azure resources, and telemetry support an SRE Agent investigation.
- Use or configure an Azure SRE Agent custom agent, skill, and response plan for a scoped incident.
- Trigger a Caldova incident simulation, evaluate the evidence and action, and verify service recovery.

### 💻 Technologies used

- Azure SRE Agent
- Azure Monitor
- Azure Container Apps
- Azure Database for PostgreSQL
- Azure Application Gateway
- Azure Virtual Network
- Network Security Groups
- Azure Key Vault
- Azure Virtual Machines
- Application Insights
- Log Analytics
- Bicep
- Skillable
- GitHub

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

- Shamir Aziz — [@meetshamir](https://github.com/meetshamir)

### ⚖️ Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow [Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general). Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.

Any use of third-party trademarks or logos are subject to those third-party's policies.
