# alalanet skills: directory build

This branch is the build of the **alalanet guard** plugin for Anthropic's plugin directory. It has no
hooks and connects to `https://alalanet.com/mcp/guard`, alalanet's MCP server for install and
MCP-server checks. The full build, with hooks that check every install command automatically and
more skills, is on the [`main` branch](https://github.com/alalanet/skills/tree/main).

| Part | What it does |
|---|---|
| [`install-guard`](skills/install-guard/SKILL.md) skill | Before installing any npm/PyPI package, GitHub repo, skill or MCP server, Claude checks it with alalanet `install_check`: it blocks known malicious packages and holds typosquats of official MCP servers, names that do not exist, install scripts and maintainer changes. |
| alalanet guard MCP server | Seven read-only tools: `install_check`, `check_repo_config` (before opening a repository someone sent you), `check_service` and `connect_check` for remote MCP servers, `verify_tools` (are these the tools the server serves everyone?), `check_artifact` and `get_attestation`. |

Free, no sign-up. Only the install target or the server URL is sent to alalanet, never your code or
files. Privacy policy: <https://alalanet.com/privacy>. Source of the plugin: [plugins/alalanet-guard](plugins/alalanet-guard).

## Verify the skill

Every version of the skill is a release signed by the alalanet server key and appended to a public
transparency log:

```sh
sha256sum skills/install-guard/SKILL.md
curl -s https://alalanet.com/v1/artifacts/<sha256>    # advice: signed_by_alalanet
```

## License

MIT-0.
