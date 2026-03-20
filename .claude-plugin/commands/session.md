# /fleece:session — Print Session Prompt

Print the autonomous session prompt for this project.

```bash
make session
```

This prints the contents of `AUTONOMOUS-SESSION.md` which is the template
for starting a `--dangerously-skip-permissions` Claude Code session.

Remind the user to:
1. Edit the "Your Task" section with their actual task
2. Run `make up && make smoke` before starting the session
3. Use `claude --dangerously-skip-permissions` to start
