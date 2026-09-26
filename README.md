# 12306-agent-skill

> 12306 火车票查询 Agent Skill：直达余票、票价、中转换乘、经停站、车站电报码。只用 `curl` + `jq`，不需要 Python、Node 或 MCP server，装上就能在 Claude Code、Codex 等带 shell 的 AI agent 里用。

![license](https://img.shields.io/badge/license-MIT-blue) ![shell](https://img.shields.io/badge/shell-bash-green) ![deps](https://img.shields.io/badge/deps-curl%20%2B%20jq-orange) ![no-mcp](https://img.shields.io/badge/MCP-not%20required-lightgrey)

📘 [English](README.en.md)

---

## 这是什么

一个 [Agent Skill](https://agentskills.io/)：一个 `SKILL.md` 加一个 bash 脚本。装好后，直接对 agent 说：

- 「明天上午北京去上海的高铁，二等座还有票吗？挑三趟最快的」
- 「10 月 2 号西宁去厦门，没直达的话怎么中转最快」
- 「G1033 这周日几点到宜昌北，中间停哪些站」

agent 会读 `SKILL.md`，自己调用脚本查 12306，再整理成答案。**只查不买**，买票还是去 12306 App。

它是 [Joooook/12306-mcp](https://github.com/Joooook/12306-mcp) 和 [Joooook/12306-skill](https://github.com/Joooook/12306-skill) 的 bash + jq 重写版，10 个工具全部保留。2026-09-26 实测时，原版 Python skill 启动就报错：它要先打开 12306 的中转查询页面，这个页面现在要登录。本项目改为从公开页面读取查询地址，并修了几处日期和排序问题（见[和原版的区别](#和原版的区别)）。

## 适合谁

- ✅ 用 Claude Code、Codex 或其他能跑 shell 的 agent，想让它直接查火车票
- ✅ 不想为一个查票功能装 Python 依赖或常驻 MCP server
- ✅ 常跑长途、需要比较中转方案的人
- ❌ 想让 AI 帮你下单、抢票：本项目不做，也不会做
- ❌ 不用 AI agent、只想在终端里查票：能用，但输出是给 agent 读的，不如直接开 12306 App

## 快速开始

**1. 装 jq**（curl 系统一般自带）

```bash
brew install jq        # macOS
sudo apt install jq    # Debian / Ubuntu
```

**2. 装 skill**：克隆到 agent 读取 skill 的目录，目录名用 `12306`

```bash
# Claude Code：所有项目可用
git clone https://github.com/henrywen98/12306-agent-skill.git ~/.claude/skills/12306

# Claude Code：只给某个项目用
git clone https://github.com/henrywen98/12306-agent-skill.git <项目目录>/.claude/skills/12306

# Codex
git clone https://github.com/henrywen98/12306-agent-skill.git ~/.codex/skills/12306
```

**3. 用**：直接问 agent 火车票的问题。也可以自己在终端里跑：

```bash
S=~/.claude/skills/12306/scripts/12306.sh
$S get-tickets --date 2026-10-01 --from_station 北京 --to_station 上海 --train_filter_flags G --limited_num 10
$S get-interline-tickets --date 2026-10-02 --from_station 西宁 --to_station 厦门 --middle_station 郑州 --sort_flag duration --limited_num 5
$S get-train-route-stations --train_code G1033 --depart_date 2026-09-27
$S list-tools
```

车站可以写城市名（查全城所有车站）、具体站名或电报码，不用先查电报码。

## 推荐的前置依赖（可选）

不装也能用。装了之后，用户说「从我这儿出发」「离我最近的火车站」时，agent 能自己确定位置：

| 依赖 | 用来做什么 | 安装 |
|---|---|---|
| [whereami](https://github.com/georgemandis/whereami) | 用系统定位拿到当前城市，挂代理也准（IP 定位挂代理会定到境外） | `brew install georgemandis/tap/whereami` |
| [高德 MCP](https://lbs.amap.com/api/mcp-server/summary) | 找最近的火车站、规划去车站的路线 | 在高德开放平台申请 key，按官方文档配到 agent 里 |

两个都没有时，agent 会直接问你在哪个城市。

## 示例

**直达余票**（2026-09-26 查询，9 月 28 日北京→上海，7–10 点出发的高铁，按历时排序）：

```
车次|出发站 -> 到达站|出发时间 -> 到达时间|历时
G5 北京南(telecode:VNP) -> 上海(telecode:SHH) 07:59 -> 12:32 历时：04:33
- 商务座: 剩余14张票 2337元
- 一等座: 有票 1069元
- 二等座: 有票 667元
- 无座: 有票 667元
G7 北京南(telecode:VNP) -> 上海虹桥(telecode:AOH) 09:00 -> 13:37 历时：04:37
- 商务座: 剩余13张票 2315元
- 一等座: 剩余20张票 1058元
- 二等座: 有票 661元
- 优选一等座: 剩余20张票 1455元
- 无座: 有票 661元
```

**中转：为什么要补查枢纽站**（2026-09-26 查询，10 月 2 日西宁→厦门，没有直达）

12306 自动推荐的中转方案只有十来个，里面最快的是经太原南，要 27 小时 36 分，还得半夜在太原南等 8 小时。指定郑州作中转站再查一次，就找到了自动推荐里没有的方案（输出节选）：

```
2026-10-02 09:40 -> 2026-10-03 11:51 | 西宁 -> 郑州 -> 厦门北 | 同站换乘 | 2小时25分钟 | 26:11

	G854 西宁(telecode:XNO) -> 郑州(telecode:ZZF) 09:40 -> 16:26 历时：06:46
	- 二等座: 有票 523元
	D226 郑州(telecode:ZZF) -> 厦门北(telecode:XKS) 18:51 -> 11:51 历时：17:00
	- 二等卧: 有票 417元
```

少 1.5 小时，同站换乘，夜里睡动卧。所以 `SKILL.md` 让 agent 查中转时，除了自动推荐，再指定 2～3 个沿途枢纽各查一次，合起来比较。

## 工具

| 工具 | 作用 |
|---|---|
| `get-tickets` | 直达余票和票价。可按车型（G/D/Z/T/K/复兴号/智能动车组）、出发时段筛选，按出发、到达、历时排序 |
| `get-interline-tickets` | 中转方案。可指定中转站，可含无座 |
| `get-train-route-stations` | 某趟车的经停站和到发时刻 |
| `get-stations-code-in-city` | 城市里的所有车站 |
| `get-station-code-of-citys` / `get-station-code-by-names` / `get-station-by-telecode` | 城市名、站名、电报码互查 |
| `get-current-date` | 上海时区的今天，用来算「明天」「周五」 |
| `refresh-cache` / `list-tools` | 刷新车站表缓存 / 列出工具 |

参数细节见 [`SKILL.md`](SKILL.md)。

## 和原版的区别

| | 原版 Python skill | 本项目 |
|---|---|---|
| 依赖 | Python 3.10+ 和 `requests` | bash、curl、jq |
| 2026-09-26 实测 | 启动报错（中转查询页面要登录） | 10 个工具全部可用 |
| 余票接口地址 | 写死的 `leftTicket/query`（已停用） | 每次查询前从公开页面读取当前地址 |
| 途经站跨天发车的日期 | 用始发站日期，会差一天 | 用查询日期；中转第二程按换乘时间推算 |
| 中转排序 | 只在取回的前几个方案里排 | 先取回最多 50 个再排 |
| 查不到车次时 | 拿编号相近的另一趟车顶上 | 报「未查到」，并列出相近车次 |

完整修改记录见 [CHANGELOG](CHANGELOG.md)。

## 测试

用 [skill-creator](https://github.com/anthropics/skills/tree/main/skills/skill-creator) 的方法做了对照测试：同样的问题，分别让「装了本 skill」和「没装任何 skill」的 Claude 回答，按事先写好的检查项打分，并用 12306 实时数据核对答案。共 4 个问题：直达余票、经停站、两条长途中转。

| | 装了本 skill | 没装 |
|---|---|---|
| 检查项通过率 | 100% | 90% |
| 平均耗时 | 57 秒 | 175 秒 |
| 平均 token | 5.5 万 | 6.6 万 |

没装 skill 的 Claude 也能自己找到 12306 接口，但更慢、耗时波动大（最慢一次 404 秒），有两次漏了票价。测试问题见 [`evals/evals.json`](evals/evals.json)。

## 注意

- 数据来自 12306 网站的公开查询接口，不是官方开放 API。12306 改接口时可能失效，遇到了请提 issue。
- 仅供个人查询，请勿高频请求。
- 余票是查询那一刻的，变化很快，以 12306 App 为准。

## 致谢

- [Joooook/12306-mcp](https://github.com/Joooook/12306-mcp)（MIT）和 [Joooook/12306-skill](https://github.com/Joooook/12306-skill)：本项目的字段解析、席别编码、车次筛选规则和输出格式都来自这两个项目。上游许可证见 [NOTICE](NOTICE)。

## License

[MIT](LICENSE)

觉得有用的话，点个 ⭐ 让更多人看到。
