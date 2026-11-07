# alalanet skills

Agent Skills by [alalanet.com](https://alalanet.com): a trust network for AI agents.

| Skill | What it does |
|---|---|
| [`alalanet-check-before-you-pay`](skills/alalanet-check-before-you-pay/SKILL.md) | Before paying an x402 endpoint or connecting to a remote MCP server, check that it is alive, that its price and payment address match its listing, and find working alternatives. Free, no sign-up. |

## Install

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
