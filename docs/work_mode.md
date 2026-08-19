# AuroraFox Work

AuroraFox Work is the persistent long-task workspace layered over the existing AgentCore.

Current V1.1.1.1 foundation:

- persistent projects stored under `user://work`;
- project title and permanent instructions;
- linked source file paths;
- queued/running/completed task state;
- visible task progress;
- task results saved into per-project `artifacts/`;
- execution through the existing AgentCore, MemoryStore, tools, File Intelligence, project index and sandbox paths rather than a second AI core.

Planned next expansion after the UI asset pack is imported:

- richer artifact types (DOCX/XLSX/PPTX/PDF) through dedicated local generators;
- reusable Work templates;
- project-scoped chat history and artifact browser;
- approvals for consequential tool actions;
- scheduled/conditional Work runs;
- API endpoints for starting and tracking Work tasks remotely.
