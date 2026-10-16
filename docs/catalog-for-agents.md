# Completing Catalogs with AI Agents

## Workflow

A catalog is drafted from existing tags, completed by an AI agent or AI chat, validated, and previewed before it is applied. Output from a model is never applied without validation and a dry run.

```bash
ilibrary export ~/Music/Staging -o catalog.json
ilibrary prompt catalog.json > prompt.md
# Give prompt.md to the AI chat, or let the agent edit catalog.json directly.
ilibrary validate catalog.json ~/Music/Staging
ilibrary apply catalog.json ~/Music/Staging --dry-run
ilibrary apply catalog.json ~/Music/Staging
```

## For Agents That Run Commands

An agent that can run commands should follow the same steps and observe the following rules.

- Edit only the catalog. Never edit, move, or delete music files directly, and never run `apply` without `--dry-run` unless the person has reviewed the dry run and asked for the change.
- Read the authoring rules printed by `ilibrary prompt`. Leave unknown values empty rather than guessing, record evidence for copyright lines and release dates in `notes` and `sources`, and keep the order of discs and tracks.
- Run `ilibrary validate` after each edit and resolve every error. Warnings, such as `(P)` instead of `℗`, should also be resolved.
- Run `ilibrary validate catalog.json PATH` to confirm that every file matches. A file whose title differs from the catalog at its disc and track numbers is matched there only when no other track carries the file's title and more of the album's files have agreeing titles than differing ones; files without a title tag do not count. Otherwise it is reported as unmatched.
- Present the output of `ilibrary apply --dry-run` to the person and explain each change before it is applied.

## For AI Chats

Give the chat the complete output of `ilibrary prompt`. Replace `catalog.json` with the returned document only after checking that it is a single JSON document, then validate it and run a dry run as above.
