---
description: Take a ticket from intake to a draft PR - plan with you, build and review on its own, then ship on your say-so
argument-hint: "[ticket id | url | pasted text]"
---

Route this ticket using the `patrick-workflows:ticket-workspace` skill's phase table.

1. Arguments: $ARGUMENTS
2. No argument: run `bash "<ticket-workspace skill dir>/scripts/ticket-ws.sh" list` and ask which ticket to continue, or to paste a new one.
3. Turn a URL into its ID first (issue key such as `ABC-123`, or `#<number>` for `.../issues/<number>`). An ID whose workspace exists (`ticket-ws.sh path <id>` is a directory): read its `phase` with `state.sh`, enter its worktree first if `checkout` is a worktree path (see the skill's Worktrees section), then invoke the stage skill the phase table names. For `pr`, invoke `patrick-workflows:ticket-close`. For `closed`, say the ticket is finished.
4. Otherwise it is a new ticket: invoke `patrick-workflows:ticket-plan` with the argument.
