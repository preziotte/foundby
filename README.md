# foundby

Ask your coding agent how people find your site.

```
Set up foundby.dev in this repo and tell me how people are finding this site.
```

foundby is a skill for Claude Code (and any agent that reads `SKILL.md`) plus a few Python
scripts. It keeps a ledger in your repo of every distinct way a person has ever reached
your site: referring hosts, AI assistants, link-preview platforms, in-app browsers, GA
sources, backlinks and web mentions. Each run reports only what is new since the last one.
The agent then looks up each new host, writes a one-line note saying what it actually is,
and records it, so a junk host surfaces once and never again, and a real blog post, forum
thread or YouTube tutorial gets found, read and remembered.

```
FOUNDBY · example.com · new since 2026-10-22 (7d window, 184 rows in ledger)

  NEW  blog      skinnypuppy.eu                              25  via edge
  NEW  video     youtube.com                                  3  via web  youtube.com/watch?v=...
  NEW  forum     news.ycombinator.com                         9  via edge,web
  NEW  directory github:someone/awesome-music-tools           0  via web  github.com/someone/awesome-music-tools
  NEW  unfurler  unfurl:Discord                              14  via edge
  junk (3): 185.220.101.4, seo-tools.xyz, translate.goog
  PAGE forum     reddit.com                                        reddit.com/r/WeAreTheMusicMakers/comments/...
  SURGE search   duckduckgo.com                              41  was ~2.1/day

  sources: edge 2026-10-22..2026-10-29 (168h) · ga 2026-10-22..2026-10-29 · mentions hn:1 github:4 bluesky:2 lobsters:0 youtube:3 · bing API returns no links for this site

  to look up (3): skinnypuppy.eu, news.ycombinator.com, youtube.com
```

No hosted service, no account, no telemetry. State is two files in your repo
(`docs/foundby.md`, which you can read and edit, and the JSON next to it). Credentials
stay on your machine.

## Install

Copy or clone this directory into your project's skills folder:

```
git clone https://github.com/preziotte/foundby .claude/skills/foundby
```

Or install it once for every project: clone anywhere and symlink into `~/.claude/skills/foundby`.

Requirements: Python 3.10+. `pip install cryptography` if you wire Google Analytics.
`gh auth login` for GitHub code search. The aws CLI for CloudFront logs.

## Use

In Claude Code, in your site's repo:

- `/foundby setup` wires a site: writes `foundby.json`, runs `doctor`, and walks you
  through the sources worth adding for your traffic.
- `/foundby` refreshes the ledger and reports what is new. The agent looks up the new
  people-shaped rows and records what they are.
- `/foundby open` opens the ledger viewer in your browser.

Without an agent, the scripts run on their own. The agent's job is the lookup step
(visiting each new host and writing the one-line note); without one, you do that with `set`.

```
# write foundby.json, then check which sources are wired
python3 .claude/skills/foundby/scripts/foundby.py init example.com
python3 .claude/skills/foundby/scripts/foundby.py doctor

# fetch, fold into docs/foundby.md, print what is new (scratch dir holds the raw pulls)
python3 .claude/skills/foundby/scripts/foundby.py run /tmp/foundby

# record what a new host turned out to be
python3 .claude/skills/foundby/scripts/foundby.py set skinnypuppy.eu --kind blog --note "Fan site, links from an inner page"

# open the ledger viewer
python3 .claude/skills/foundby/scripts/foundby.py view
```

## Sources

Four sources, all optional. Each one sees something the others miss. A site with nothing
but a domain gets the mention search.

| Source | Sees | Blind to | Needs |
|---|---|---|---|
| Mention search (HN, GitHub, Bluesky, Lobsters, YouTube descriptions; Reddit with a manual step) | pages that talk about you, clicked or not | X, Instagram, TikTok | nothing; `gh auth login` for GitHub |
| Google Analytics 4 | utm and gclid sources, the AI Assistant channel, in-app browsers; with three custom dimensions, the referring page | anything that does not run JavaScript | a service account on the property |
| CloudFront logs | every request: link previews (private shares in Slack, Discord, iMessage), AI assistants fetching a page | apps that send no Referer (native apps, email clients) | standard logging to S3, aws CLI |
| Bing Webmaster backlinks | the backlinks Bing knows about | most backlinks; often empty | an API key |

`foundby.py doctor` checks what you have wired and says what each missing source would add.
With GA connected it also reads 90 days of channel mix. Setup, cost and blind spots of each
are in [docs/sources.md](docs/sources.md).

## Why this and not a monitoring service

Mention trackers and backlink tools list hosts. They do not fetch each unknown host,
decide that one is a Spanish AI-music tutorial worth a thank-you and another is a parked
domain never to be shown again, and write that into a ledger you own. That classification
is the part that makes the report readable, it is agent work, and it only costs you the
run. The ledger's known-host tables (search engines, AI assistants, directories,
unfurlers) are shared in this repo; the notes are yours.

## Site

[foundby.dev](https://foundby.dev) is `site/public/`, a single static page deployed with
`site/deploy.sh`; infra in `site/main.tf`.

## Related

[agenttraffic](https://agenttraffic.io) reads the same CDN logs and reports what AI agents
did on your site. foundby is about people; agenttraffic is about agents.

MIT.
