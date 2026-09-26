---
name: "12306"
description: 查 12306 火车票——直达余票与票价、中转换乘方案、某趟车的经停站和时刻、车站电报码。用户问高铁/动车/火车票、「明天去上海有没有票」「G1033 几点到南京」「成都到广州怎么中转」「北京有哪些火车站」时就用，即使没提 12306。只查不买：下单要去 12306 App。
---

# 12306 查票

入口：`scripts/12306.sh <工具> [--参数 值 ...]`（curl + jq，直连 12306 官方接口，不需要 Python、不需要登录）。

```bash
S=<本 skill 目录>/scripts/12306.sh
$S get-tickets --date 2026-10-01 --from_station 北京 --to_station 上海 --train_filter_flags G --limited_num 10
```

## 查询流程

1. **定日期。** 用户说「明天」「周五」这种相对日期时，先跑 `get-current-date`（上海时区）再推算，别用自己记的日期。12306 只开放今天起约 15 天的车票，更远的日期会报「超出预售期」，照实告诉用户开售时间还没到。
2. **定车站。** `--from_station` / `--to_station` / `--middle_station` 直接收中文名或电报码，不用先查电报码：
   - 城市名（北京、苏州）会查整个城市的所有车站，结果里的出发/到达站可能是北京南、张家港这类同城站。
   - 具体站名（北京南、上海虹桥，带不带「站」字都行）只查这一站。
   - 名字查不到（「北京市」「浦东」）时报 `Station not found`：去掉「市」字重试，或用 `get-stations-code-in-city` 列出这个城市的站让用户选。
3. **按需筛选。** 一对热门城市一天有上百趟车，全量输出几万字。用户的话里有线索就用筛选参数收窄，没有线索也加 `--limited_num 10~20`：
   - 「高铁」→ `--train_filter_flags G`；「动车」→ `D`；「高铁或动车」→ `GD`；「复兴号」→ `F`
   - 「上午」→ `--earliest_start_time 6 --latest_start_time 12`（小时，左闭右开）
   - 「最快的」→ `--sort_flag duration`；「最早到的」→ `--sort_flag arriveTime`
4. **没有直达或都没票时，查中转**（`get-interline-tickets`）。
   - 12306 自动推荐的中转方案数量有限（实测一条线路只给了 12 个），可能漏掉最快的组合。所以先查一次不指定中转站的，再挑 2～3 个沿途大枢纽（郑州、武汉、西安、长沙、南京、成都、重庆这类线路交汇的城市），每个用 `--middle_station` 单独查一次。每次都加 `--sort_flag duration --limited_num 5`：设了排序或筛选时，脚本会先取回最多 50 个方案，再排序截断，所以前 5 个就是这次查询里最快的。几次的结果合在一起比，再推荐。自动推荐已经最快时，就直接用它。实测过的一条长途线路：自动推荐里最快的方案要 27.5 小时；指定一个枢纽站后，查到了快 1.5 小时、同站换乘、夜里有卧铺的方案。
   - 12306 一次中转查询最多给几十个方案，筛完可能不足 `--limited_num` 条。
   - 车型筛选（`G`/`D`/`F`…）只看第一程。用户要「全程高铁」时，拿到结果后自己检查第二程的车次。
   - 中转站写成「长沙-长沙南」这种两个站名的，表示要换站（出站后去另一个车站），回答时要提醒用户。
5. **回答用户。** 挑出符合用户意图的几趟车，列车次、出发站→到达站、发到时间、历时、用户关心的座位的余票和价格。「有票」表示余票充足（12306 不给具体数）；「无票需候补」表示可以在 12306 App 里排候补；「未开售」表示这趟车还没到起售时间。同一车次出现两条、出发站不同（如 G5 北京 07:40 和北京南 07:59），是 12306 原样返回的：这趟车在同城两个站都能上车，按用户方便的站选。

## 用户没说从哪出发时（可选前置：whereami、高德 MCP）

用户说「从我这儿出发」「离我最近的火车站」却没给城市时：

- 装了 [whereami](https://github.com/georgemandis/whereami)：跑 `whereami --json`，取 `address.city` 当出发城市。它走系统定位，挂代理也准；别用 IP 定位，挂代理时会定到境外。
- 配了[高德 MCP](https://lbs.amap.com/api/mcp-server/summary)：要找最近的车站，用 `maps_around_search` 搜「火车站」，location 填 `经度,纬度`；要问怎么去车站，用路径规划工具。whereami 给的是 WGS-84 坐标，高德用 GCJ-02，国内会偏几百米，精确到街道时要跟用户说明。
- 两个都没有：直接问用户在哪个城市。

## 工具

| 工具 | 必填参数 | 可选参数 |
|---|---|---|
| `get-tickets` 直达余票 | `--date` `--from_station` `--to_station` | `--train_filter_flags` `--earliest_start_time`(0) `--latest_start_time`(24) `--sort_flag` `--sort_reverse` `--limited_num`(0=不限) `--format text\|csv\|json` |
| `get-interline-tickets` 中转方案 | 同上 | `--middle_station`（指定中转站，不填则 12306 自动推荐）`--show_wz`（含无座方案）、筛选排序同上，`--limited_num` 默认 10，`--format text\|json` |
| `get-train-route-stations` 经停站 | `--train_code` `--depart_date` | `--format text\|json` |
| `get-stations-code-in-city` | `--city` | |
| `get-station-code-of-citys` | `--citys`（多个用 `\|` 分隔） | |
| `get-station-code-by-names` | `--station_names`（多个用 `\|` 分隔） | |
| `get-station-by-telecode` | `--station_telecode` | |
| `get-current-date` / `refresh-cache` / `list-tools` | | |

- `--train_filter_flags` 可组合：`G` 高铁/城际（G、C 字头）· `D` 动车 · `Z` 直达 · `T` 特快 · `K` 快速 · `O` 其他 · `F` 复兴号 · `S` 智能动车组。
- `--sort_flag`：`startTime` / `arriveTime` / `duration`；`--sort_reverse` 是开关，不带值。
- `--format`：给用户看用默认的 `text`；要自己再算（比如比价、统计有票的车次）时用 `json`，再用 jq 处理。
- `get-train-route-stations` 的 `--depart_date` 是列车**从始发站出发**的日期。车次号必须完全一致；查不到时报错信息里会列出当天相近的车次，让用户确认。

## 缓存与排错

- 车站表缓存在 `scripts/.cache/stations.json`，一天过期后自动重新下载。新开的车站查不到时，跑一次 `refresh-cache`。
- 余票和中转的接口路径（现在是 `leftTicket/queryG`、`/lcquery/queryG`）每次查询时从公开的 `leftTicket/init` 页面现读，12306 改路径也不用改脚本。
- 返回 `Error: ... failed` 又不是预售期问题时，多半是网络或 12306 限流。隔几秒重试一次；再失败就把报错原样告诉用户。
