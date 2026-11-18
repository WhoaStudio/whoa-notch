# Task context

Détection des serveurs de dev en cours, groupés par projet, dans la page Actions de l'onglet Analytics. Plan proposé, en attente de validation. Rien n'est modifié (le travail Usage/Actions/Servers précédent n'est pas commité).
- Données : `DevServersViewModel` → `DevServersState` → `NotchActionsPageView.apply`. Ajouter `detected: [DetectedServerGroup]`.
- Détection : `lsof -nP -iTCP -sTCP:LISTEN -Fpcn` (≈ instantané ici), cwd par `proc_pidinfo(PROC_PIDVNODEPATHINFO)`, argv par `sysctl KERN_PROCARGS2`. Lecture seule.
- Constaté sur la machine : beaucoup de bruit (ControlCenter, rapportd, figma_agent, claude, Raycast, Dia agent-server) ; postgres Homebrew a pour cwd `/opt/homebrew/var/postgresql@18` → groupe Other / System.

## Agent Tabs (onglet AI) — liste fait ; aperçu du diff fait (GitDiff*, AgentDiffPopoverView), non commité, 2026-11-17
Approuvé : correctifs d'usage, accessibilité, mise en page, mouvement (Reduce Motion), idées 1–3 (liste défilante + ↑/↓, balayage/✕ pour écarter une session close, jeton de frise → ligne du journal).
Fichiers : AgentSessionsView, AgentActivityCardView, AgentSessionStore.dismiss (+ test), plomberie onDismiss jusqu'à NotchPanelController. PromptButton et Core/Animation non modifiés.
