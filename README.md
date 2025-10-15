# About the Session

A demonstration and discussion of PowerShell modules and scripts used at OCAD University to build, deploy and manage Colleague Self-Service and Web API instances.

A brief background on the pain points which motivated the creation of the tools will be followed by short demonstrations of how the tools are integrated and used in regular operations. An open discussion regarding the specific tools and methods used in tool creation and operations may follow as time allows.

Colleague-specific areas of focus include:

- Building and deploying Colleague Self-Service. 
- Differences in the build process and runtime environments between .NET 4.x and .NET Core (Self-Service 2.x versus 3.x and/or Web API 1.x vs 2.x).
- Running the Colleague API warm-up script both in automation and on an ad-hoc basis while protecting credentials.
- Self-Service and Web API error logging, correlation and tracing.

More general topics include:

- PowerShell remoting, credentials and secrets management for reduction of "click-ops".
- PowerShell script & module authoring and distribution via a local PowerShell repository.
- The MSBuild process, build transforms (SlowCheetah, FatAntelope), build tasks and web deploy packages.
- .NET Interactive and Polyglot Notebooks for troubleshooting and operations.
