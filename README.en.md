# 12306-agent-skill

> An Agent Skill for China Railway 12306: seat availability, fares, transfer routes, train stops and station codes. It only needs `curl` and `jq` — no Python, no Node, no MCP server. Works in Claude Code, Codex, and any AI agent that can run a shell.

![license](https://img.shields.io/badge/license-MIT-blue) ![shell](https://img.shields.io/badge/shell-bash-green) ![deps](https://img.shields.io/badge/deps-curl%20%2B%20jq-orange) ![no-mcp](https://img.shields.io/badge/MCP-not%20required-lightgrey)

📘 [中文](README.md)

---

## What it is

An [Agent Skill](https://agentskills.io/): one `SKILL.md` and one bash script. After you install it, just ask your agent (in Chinese or English):

- "Any second-class seats on high-speed trains from Beijing to Shanghai tomorrow morning? Pick the 3 fastest."
- "No direct train from Xining to Xiamen on Oct 2 — what is the fastest transfer?"
- "When does G1033 reach Yichang East this Sunday, and where does it stop?"

The agent reads `SKILL.md`, runs the script against 12306, and writes the answer. **Query only** — to buy tickets, use the 12306 app.

This is a bash + jq rewrite of [Joooook/12306-mcp](https://github.com/Joooook/12306-mcp) and [Joooook/12306-skill](https://github.com/Joooook/12306-skill), keeping all 10 tools. When tested on 2026-09-26, the original Python skill failed at startup: it first opens 12306's transfer search page, which now requires login. This project reads the endpoint from a public page instead, and fixes several date and sorting bugs (see [CHANGELOG](CHANGELOG.md)).

## Quick start

```bash
brew install jq                    # or: sudo apt install jq
git clone https://github.com/henrywen98/12306-agent-skill.git ~/.claude/skills/12306   # Claude Code
git clone https://github.com/henrywen98/12306-agent-skill.git ~/.codex/skills/12306    # Codex
```

Run it by hand:

```bash
S=~/.claude/skills/12306/scripts/12306.sh
$S get-tickets --date 2026-10-01 --from_station 北京 --to_station 上海 --train_filter_flags G --limited_num 10
$S get-interline-tickets --date 2026-10-02 --from_station 西宁 --to_station 厦门 --middle_station 郑州 --sort_flag duration --limited_num 5
$S get-train-route-stations --train_code G1033 --depart_date 2026-09-27
```

Stations accept Chinese city names, station names, or telegraph codes.

## Optional helpers

| Tool | What for |
|---|---|
| [whereami](https://github.com/georgemandis/whereami) | Get your current city from the OS location service, for "trains from where I am". `brew install georgemandis/tap/whereami` |
| [AMap (Gaode) MCP](https://lbs.amap.com/api/mcp-server/summary) | Find the nearest station and plan the route to it |

Without them, the agent simply asks which city you are in.

## Why hub queries matter

12306's automatic transfer suggestions are limited (12 plans for Xining → Xiamen on 2026-10-02). The fastest suggested plan took 27h36m with an 8-hour night wait. Querying again with Zhengzhou as the transfer hub found a 26h11m same-station plan with a sleeper train at night. So `SKILL.md` tells the agent to also query 2–3 hubs along the way and compare.

## Evaluation

Same prompts answered by Claude with and without this skill, graded against live 12306 data (4 prompts: direct tickets, train stops, two long-distance transfers):

| | With skill | Without |
|---|---|---|
| Checks passed | 100% | 90% |
| Mean time | 57 s | 175 s |
| Mean tokens | 55k | 66k |

## Notes

- Data comes from 12306's public web query endpoints, not an official API. It may break when 12306 changes them — please open an issue.
- For personal use only. Do not send high-frequency requests.

## Credits

[Joooook/12306-mcp](https://github.com/Joooook/12306-mcp) (MIT) and [Joooook/12306-skill](https://github.com/Joooook/12306-skill). Field parsing, seat codes, train filters and output formats come from them. See [NOTICE](NOTICE).

## License

[MIT](LICENSE). If it helps you, a ⭐ helps others find it.
