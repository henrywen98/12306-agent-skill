#!/usr/bin/env bash
# 12306 查询（curl + jq），复刻 Joooook/12306-mcp 与 12306-skill 的全部工具。
# 用法：12306.sh <tool> [--arg value ...]；12306.sh list-tools 查看工具。
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="$DIR/.cache"
mkdir -p "$CACHE"
API=https://kyfw.12306.cn
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
JAR="$(mktemp "${TMPDIR:-/tmp}/12306jar.XXXXXX")"
trap 'rm -f "$JAR"' EXIT

TOOLS=(list-tools refresh-cache get-current-date get-stations-code-in-city get-station-code-of-citys get-station-code-by-names get-station-by-telecode get-tickets get-interline-tickets get-train-route-stations)

die() { echo "$*"; exit 1; }
jqlib() { local f="${@: -1}"; jq -L "$DIR" "${@:1:$#-1}" "include \"12306\"; $f"; }   # 最后一个参数是 jq 程序
fresh() { [ -s "$1" ] && [ -n "$(find "$1" -mmin -1440 2>/dev/null)" ]; }   # 缓存一天
get() { curl -sS --compressed --max-time 20 -A "$UA" -b "$JAR" -c "$JAR" "$@"; }

# ---------- 缓存：车站表 ----------
refresh_stations() {
  local html js
  html="$(get https://www.12306.cn/index/)" || die "Error: get 12306 web page failed."
  js="$(grep -oE '\./script/core/common/station_name[^"]*\.js' <<<"$html" | head -1)"
  [ -n "$js" ] || die "Error: get station name js file failed."
  get "https://www.12306.cn/index/${js#./}" \
    | sed -nE "s/.*station_names *= *'([^']+)'.*/\1/p" \
    | jqlib -R 'parse_stations' > "$CACHE/stations.json.tmp"
  [ -s "$CACHE/stations.json.tmp" ] || die "Error: parse station names failed."
  mv "$CACHE/stations.json.tmp" "$CACHE/stations.json"
}
stations() { fresh "$CACHE/stations.json" || refresh_stations; cat "$CACHE/stations.json"; }

# ---------- 会话：拿 cookie，同时从公开余票页读出余票 / 中转查询路径 ----------
# 原版从 /otn/lcQuery/init 读中转路径，该页现需登录；leftTicket/init 里有同一个 lc_search_url。
init_session() {
  local html
  html="$(get "$API/otn/leftTicket/init")" || die "Error: Get cookie failed. Check your network."
  LEFT_URL="$(sed -nE "s/.*CLeftTicketUrl *= *'([^']+)'.*/\1/p" <<<"$html" | head -1)"
  LC_URL="$(sed -nE "s/.*lc_search_url *= *'([^']+)'.*/\1/p" <<<"$html" | head -1)"
  LEFT_URL="${LEFT_URL:-leftTicket/queryG}"
  LC_URL="${LC_URL:-/lcquery/queryG}"
  printf '%s\n%s\n' "$LEFT_URL" "$LC_URL" > "$CACHE/query_paths"
  grep -q kyfw "$JAR" || die "Error: Get cookie failed. Check your network."
}

check_date() {  # 不早于今天（上海时区）
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "Error: date must be YYYY-MM-DD."
  [[ ! "$1" < "$(TZ=Asia/Shanghai date +%F)" ]] || die "Error: The date cannot be earlier than today."
}
code_of() { [ -z "$1" ] && { echo ""; return; }; stations | jqlib --arg q "$1" -r 'station_code($q) // empty'; }

# ---------- 参数 ----------
TOOL="${1:-}"; shift || true
while [ $# -gt 0 ]; do
  k="${1#--}"; k="${k//-/_}"
  case "$k" in
    sort_reverse|show_wz) printf -v "A_$k" %s true; shift ;;
    *) [ $# -ge 2 ] || die "Error: missing value for --$k"; printf -v "A_$k" %s "$2"; shift 2 ;;
  esac
done
arg() { local v="A_$1"; echo "${!v:-${2:-}}"; }
need() { local v="A_$1"; [ -n "${!v:-}" ] || die "Error: --$1 is required."; }

case "$TOOL" in
  list-tools)
    printf '%s\n' "${TOOLS[@]}" | jq -R . | jq -sc '{tools: ., version: "0.1.0"}' ;;

  refresh-cache)
    refresh_stations; init_session
    echo "缓存刷新完成：已重新获取站点数据（$(jq length "$CACHE/stations.json") 站）与查询路径（${LEFT_URL}, ${LC_URL}）。" ;;

  get-current-date)
    TZ=Asia/Shanghai date +%F ;;

  get-stations-code-in-city)
    need city
    stations | jqlib --arg c "$(arg city)" -rc 'city_stations[$c] // "Error: City not found. "' ;;

  get-station-code-of-citys)
    need citys
    stations | jqlib --arg c "$(arg citys)" -rc 'city_codes as $m | reduce ($c | split("|")[]) as $x ({}; .[$x] = ($m[$x] // {error: "未检索到城市。"}))' ;;

  get-station-code-by-names)
    need station_names
    stations | jqlib --arg c "$(arg station_names)" -rc 'name_stations as $m | reduce ($c | split("|")[] | strip_zhan) as $x ({}; .[$x] = ($m[$x] // {error: "未检索到车站。"}))' ;;

  get-station-by-telecode)
    need station_telecode
    stations | jqlib --arg c "$(arg station_telecode)" -rc '.[$c] // "Error: Station not found. "' ;;

  get-tickets)
    need date; need from_station; need to_station
    date="$(arg date)"; check_date "$date"
    from="$(code_of "$(arg from_station)")"; to="$(code_of "$(arg to_station)")"
    [ -n "$from" ] && [ -n "$to" ] || die "Error: Station not found. from_station_result: ${from:-null}, to_station_result: ${to:-null}."
    init_session
    q="leftTicketDTO.train_date=$date&leftTicketDTO.from_station=$from&leftTicketDTO.to_station=$to&purpose_codes=ADULT"
    resp="$(get "$API/otn/$LEFT_URL?$q")"
    # 12306 换路径时会返回 {"c_url": "leftTicket/queryX", "status": false}，跟一次
    c_url="$(jq -r '.c_url // empty' <<<"$resp" 2>/dev/null || true)"
    [ -n "$c_url" ] && resp="$(get "$API/otn/$c_url?$q")"
    jq -e '.data.result' >/dev/null 2>&1 <<<"$resp" || die "Error: Get tickets data failed. 12306 返回为空：日期超出预售期（通常只开放今天起 15 天内）或接口暂时不可用。"
    fmt="$(arg format text | tr A-Z a-z)"
    jqlib -r --arg fmt "$fmt" --arg date "$date" --arg flags "$(arg train_filter_flags)" --arg sort "$(arg sort_flag)" \
      --argjson e "$(arg earliest_start_time 0)" --argjson l "$(arg latest_start_time 24)" \
      --argjson rev "$(arg sort_reverse false)" --argjson n "$(arg limited_num 0)" '
      parse_tickets($date) | filter_tickets($flags; $e; $l; $sort; $rev; $n)
      | if $fmt == "json" then tojson elif $fmt == "csv" then format_tickets_csv else format_tickets_text end' <<<"$resp" ;;

  get-interline-tickets)
    need date; need from_station; need to_station
    date="$(arg date)"; check_date "$date"
    from="$(code_of "$(arg from_station)")"; to="$(code_of "$(arg to_station)")"
    mid_in="$(arg middle_station)"; mid="$(code_of "$mid_in")"
    if [ -z "$from" ] || [ -z "$to" ] || { [ -n "$mid_in" ] && [ -z "$mid" ]; }; then
      die "Error: Station not found. from_station_result: ${from:-null}, to_station_result: ${to:-null}, middle_station_result: ${mid:-null}"
    fi
    init_session
    n="$(arg limited_num 10)"; wz=$([ "$(arg show_wz)" = true ] && echo Y || echo N)
    # 原版只取回 n 条就排序筛选，最快的方案可能在后面几页。设了排序/筛选/时段时多取几页（最多 50 条）
    fetch="$n"
    if [ -n "$(arg sort_flag)$(arg train_filter_flags)" ] || [ "$(arg earliest_start_time 0)" != 0 ] || [ "$(arg latest_start_time 24)" != 24 ]; then
      [ "$fetch" -lt 50 ] && fetch=50
    fi
    idx=0; all='[]'
    while :; do
      resp="$(get "$API$LC_URL?train_date=$date&from_station_telecode=$from&to_station_telecode=$to&middle_station=$mid&result_index=$idx&can_query=Y&isShowWZ=$wz&purpose_codes=00&channel=E")"
      jq -e . >/dev/null 2>&1 <<<"$resp" || die "Error: request interline tickets data failed. "
      if jq -e '.data | type == "string"' >/dev/null <<<"$resp"; then
        [ "$all" = '[]' ] && die "很抱歉，未查到相关的列车余票。($(jq -r '.errorMsg // ""' <<<"$resp"))"
        break
      fi
      all="$(jq -c --argjson a "$all" '$a + (.data.middleList // [])' <<<"$resp")"
      [ "$(jq -r '.data.can_query' <<<"$resp")" = N ] && break
      [ "$(jq length <<<"$all")" -ge "$fetch" ] && break
      idx="$(jq -r '.data.result_index' <<<"$resp")"
    done
    fmt="$(arg format text | tr A-Z a-z)"
    jqlib -r --arg fmt "$fmt" --arg flags "$(arg train_filter_flags)" --arg sort "$(arg sort_flag)" \
      --argjson e "$(arg earliest_start_time 0)" --argjson l "$(arg latest_start_time 24)" \
      --argjson rev "$(arg sort_reverse false)" --argjson n "$n" '
      parse_interlines | filter_tickets($flags; $e; $l; $sort; $rev; $n)
      | if $fmt == "json" then tojson else format_interlines_text end' <<<"$all" ;;

  get-train-route-stations)
    need train_code; need depart_date
    code="$(arg train_code | tr a-z A-Z)"; date="$(arg depart_date)"
    # 搜索接口是前缀匹配（搜 Z1 会返回 Z14、Z158…），只认车次号完全相同的那条
    search="$(curl -sS --max-time 20 -A "$UA" "https://search.12306.cn/search/v1/train/search?keyword=$code&date=${date//-/}" || true)"
    train_no="$(jq -r --arg c "$code" '(.data // [])[] | select(.station_train_code == $c) | .train_no' <<<"$search" 2>/dev/null | head -1 || true)"
    if [ -z "$train_no" ]; then
      near="$(jq -r '[(.data // [])[:5][] | .station_train_code] | join(", ")' <<<"$search" 2>/dev/null || true)"
      die "很抱歉，未查询到对应车次。${near:+（${date} 相近车次：${near}）}"
    fi
    init_session
    resp="$(get "$API/otn/queryTrainInfo/query?leftTicketDTO.train_no=$train_no&leftTicketDTO.train_date=$date&rand_code=")"
    jq -e '.data' >/dev/null 2>&1 <<<"$resp" || die "Error: get train route stations failed. "
    fmt="$(arg format text | tr A-Z a-z)"
    jqlib -r --arg fmt "$fmt" '.data.data // [] | parse_route | if $fmt == "json" then tojson else format_route_text end' <<<"$resp" ;;

  ""|-h|--help|help)
    echo "用法：$0 <tool> [--arg value ...]"; printf '  %s\n' "${TOOLS[@]}" ;;
  *)
    die "Error: Unknown tool: ${TOOL}（可用：${TOOLS[*]}）" ;;
esac
