# alalanet skills

Agent Skills by [alalanet.com](https://alalanet.com): a trust network for AI agents.

| Skill | What it does |
|---|---|
| [`install-guard`](skills/install-guard/SKILL.md) | Before installing any npm/PyPI package, GitHub repo, skill or MCP server, check it with alalanet `install_check`: blocks known malicious packages, holds typosquats of official MCP servers, names that do not exist, install scripts and maintainer changes. Free, no sign-up. |
| [`alalanet-check-before-you-pay`](skills/alalanet-check-before-you-pay/SKILL.md) | Before paying an x402 endpoint or connecting to a remote MCP server, check that it is alive, that its price and payment address match its listing, and find working alternatives. Free, no sign-up. |

## Claude Code plugin: check every install automatically

```
/plugin install alalanet-guard --marketplace alalanet/skills
```

(older Claude Code: `/plugin marketplace add alalanet/skills`, then `/plugin install alalanet-guard@alalanet`.)

The plugin adds a hook that runs before every install command the agent is about to execute
(`npm i`, `npx`, `pnpm`/`yarn`/`bun add`, `pip`/`uv` install, `uvx`, `pipx`, `claude mcp add`,
`skills add`, `clawhub install`): **block** denies the command, **hold** asks you, **allow** stays silent.
It also adds the alalanet remote MCP server. Only the install target (package names or a repo URL) is
sent to alalanet, never code; if alalanet cannot be reached in 8 seconds the hook stays silent.
Source: [plugins/alalanet-guard](plugins/alalanet-guard).

## Install the skills

```sh
npx skills add alalanet/skills
```

Or copy `skills/alalanet-check-before-you-pay/` into your agent's skills folder. The skill is also
served at <https://alalanet.com/.well-known/agent-skills/index.json> (Agent Skills discovery).

## Verify before you install

Every version of the skill is a release signed by the alalanet server key and appended to a public
transparency log. Check the file you got:

```sh
sha256sum skills/alalanet-check-before-you-pay/SKILL.md
curl -s https://alalanet.com/v1/artifacts/<sha256>    # advice: signed_by_alalanet
```

Anything else (`unknown_hash`, a different publisher, `caution_conflicting`) means the file is not ours. The repository always holds the latest signed version; the live copy is <https://alalanet.com/skill.md>.

## License

MIT-0.
