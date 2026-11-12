# alalanet skills

Agent Skills and the `alalanet-guard` Claude Code plugin by [alalanet.com](https://alalanet.com), a free trust layer for AI agents: check before your agent installs, connects or pays.

| Skill | What it does |
|---|---|
| [`install-guard`](skills/install-guard/SKILL.md) | Before installing any npm/PyPI package, GitHub repo, skill or MCP server, check it with alalanet `install_check`: blocks known malicious packages, holds typosquats of official MCP servers, names that do not exist, install scripts and maintainer changes. Free, no sign-up. |
| [`alalanet-check-before-you-pay`](skills/alalanet-check-before-you-pay/SKILL.md) | Before paying an x402 endpoint or connecting to a remote MCP server, check that it is alive, that its price and payment address match its listing, and find working alternatives. Free, no sign-up. |

## Claude Code plugin: check every install automatically

```
/plugin install alalanet-guard --marketplace alalanet/skills
```

(older Claude Code: `/plugin marketplace add alalanet/skills`, then `/plugin install alalanet-guard@alalanet`.)

The plugin adds HTTP hooks that run before the install commands an agent is about to execute
(`npm i`, `npx`, `bunx`, `pnpm`/`yarn`/`bun add`, `pip`/`uv` install, `uvx`, `pipx`, `claude mcp add`,
`codex mcp add`, `skills add`, `clawhub install`, `openclaw skills install`, and IDE extension installs: `code`, `cursor`, `windsurf`, `codium --install-extension`). **block** denies the command, **hold** asks you,
and **allow** stays silent. It also adds the alalanet remote MCP server (`https://alalanet.com/mcp`: the eight
checks before installing, connecting and paying).

Claude Code itself matches the commands: only matching install commands are sent to alalanet, never
your other commands, code or files. alalanet reads only the package names or repository URL in them.
If alalanet does not answer within 20 seconds, the hook does nothing.
Source: [plugins/alalanet-guard](plugins/alalanet-guard).

## Install the skills

```sh
npx skills add alalanet/skills
```

Or copy a skill's folder (`skills/install-guard/` or `skills/alalanet-check-before-you-pay/`) into your
agent's skills folder. Both skills are also served at
<https://alalanet.com/.well-known/agent-skills/index.json> (Agent Skills discovery).

## Verify before you install

Every version of a skill is a release signed by the alalanet server key and appended to a public
transparency log. Check the file you got:

```sh
sha256sum skills/install-guard/SKILL.md    # or skills/alalanet-check-before-you-pay/SKILL.md
curl -s https://alalanet.com/v1/artifacts/<sha256>    # advice: signed_by_alalanet
```

Anything else (`unknown_hash`, a different publisher, `caution_conflicting`) means the file is not ours. The repository always holds the latest signed versions; the live copies are listed in the discovery index above.

## License

MIT-0.
