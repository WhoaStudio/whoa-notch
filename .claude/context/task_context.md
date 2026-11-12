# Task context

Release CI fix pushed from isolated worktree /private/tmp/whoa-stash-release-fix.cfdFzt, branch codex/fix-release-cask-pr. Commits 6e5e5d1 (reusable cask PR workflow, recovery dispatch, helper, 4 tests/docs) and 428deb9 (repair v1.0 cask from published DMG SHA256 c4fcade1239bd4df46dbbdb4f04f2626541d18deaceaed98057671d5faea25ee). Twelve local tests, actionlint, ShellCheck and Homebrew audit/style passed; reviewer had no material findings. Unrelated edits/staging in original stable checkout preserved. Stable protection/review unchanged. Version metadata push still requires an authorized release caller; cask changes now use PRs. GitHub connector needs reauthentication; gh CLI remains authenticated.

---

## Agent cards (Claude Code / Claude Desktop answered from the notch)

- Fait : permission avec Always, plan (titre, Auto mode / Manual / Change plan), questions à choix multiple et plusieurs questions avec « Other… », formulaires MCP (`Elicitation`), réponse libre après un tour (opt-in, Préférences ▸ AI ▸ Replies), étiquette Claude Desktop. Code : `Features/Agents/` (`AgentEvent`, `AgentPromptForm`, `AgentPromptCardView`, `AgentHookServer`, `ClaudeHookInstaller`).
- Tests : `AgentPromptTests`, `AgentPromptFormTests`, `AgentPromptCardViewTests` (clics et frappes sur la vraie carte), `AgentHookRoundTripTests` (le vrai script de hook contre un vrai `AgentHookServer` sur un socket temporaire). Cartes rendues en images pour la mise en page.
- Pas vérifié : une vraie session Claude Code avec les hooks réinstallés (les hooks installés avant n'ont pas `Elicitation` : Préférences ▸ AI ▸ Install hooks) ; l'onglet Code de Claude Desktop (exécute-t-il ces hooks et suit-il leurs réponses ?) ; l'app lancée entière.
