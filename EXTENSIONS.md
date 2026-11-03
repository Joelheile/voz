# Extensions

Extensions are TypeScript modules that change what Voz does with a dictation. The guide to building them is the voz-extension skill, which Voz installs in `~/.voz` for your coding agent.

To build one, open Extensions in the Voz panel and click Build your own. Paste the prompt it copies into Claude Code, Codex or any coding agent. To install the skill without Voz, run `npx skills add Joelheile/voz -g`.

## Instructions for agents

Read [SKILL.md](https://raw.githubusercontent.com/Joelheile/voz/main/skills/voz-extension/SKILL.md) and follow it. The full API is in [api.md](https://raw.githubusercontent.com/Joelheile/voz/main/skills/voz-extension/references/api.md).
