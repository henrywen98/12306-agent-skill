# 12306 数据解析 / 筛选 / 格式化。由 12306.sh 通过 `jq -L` 引入。
# 逻辑对应 Joooook/12306-mcp src/index.ts 与 12306-skill scripts/12306_apis.py。

def TICKET_KEYS: ["secret_Sstr","button_text_info","train_no","station_train_code","start_station_telecode","end_station_telecode","from_station_telecode","to_station_telecode","start_time","arrive_time","lishi","canWebBuy","yp_info","start_train_date","train_seat_feature","location_code","from_station_no","to_station_no","is_support_card","controlled_train_flag","gg_num","gr_num","qt_num","rw_num","rz_num","tz_num","wz_num","yb_num","yw_num","yz_num","ze_num","zy_num","swz_num","srrb_num","yp_ex","seat_types","exchange_train_flag","houbu_train_flag","houbu_seat_limit","yp_info_new","40","41","42","43","44","45","dw_flag","47","stopcheckTime","country_flag","local_arrive_time","local_start_time","52","bed_level_info","seat_discount_info","sale_time","56"];
def STATION_KEYS: ["station_id","station_name","station_code","station_pinyin","station_short","station_index","code","city","r1","r2"];
def MISSING_STATIONS: [{"station_id":"@cdd","station_name":"成  都东","station_code":"WEI","station_pinyin":"chengdudong","station_short":"cdd","station_index":"","code":"1707","city":"成都","r1":"","r2":""}];
def SEAT_TYPES: {"9":{"name":"商务座","short":"swz"},"P":{"name":"特等座","short":"tz"},"M":{"name":"一等座","short":"zy"},"D":{"name":"优选一等座","short":"zy"},"O":{"name":"二等座","short":"ze"},"S":{"name":"二等包座","short":"ze"},"6":{"name":"高级软卧","short":"gr"},"A":{"name":"高级动卧","short":"gr"},"4":{"name":"软卧","short":"rw"},"I":{"name":"一等卧","short":"rw"},"F":{"name":"动卧","short":"rw"},"3":{"name":"硬卧","short":"yw"},"J":{"name":"二等卧","short":"yw"},"2":{"name":"软座","short":"rz"},"1":{"name":"硬座","short":"yz"},"W":{"name":"无座","short":"wz"},"WZ":{"name":"无座","short":"wz"},"H":{"name":"其他","short":"qt"}};

# ---------- 车站 ----------

# 输入：station_name_*.js 里 station_names 的原始字符串；输出：{code: station}
def parse_stations:
  split("|") as $v
  | reduce range(0; ($v | length / 10 | floor)) as $i ({};
      ([range(0; 10) as $j | {key: STATION_KEYS[$j], value: ($v[$i * 10 + $j] // "")}] | from_entries) as $s
      | if $s.station_code != "" then .[$s.station_code] = $s else . end)
  | reduce MISSING_STATIONS[] as $m (.; if has($m.station_code) then . else .[$m.station_code] = $m end);

# 输入都是 stations.json（{code: station}）
def city_stations: reduce (to_entries[].value) as $s ({}; .[$s.city] += [{station_code: $s.station_code, station_name: $s.station_name}]);
def city_codes: city_stations | with_entries(.key as $c | .value |= (map(select(.station_name == $c)) | first)) | with_entries(select(.value != null));
def name_stations: reduce (to_entries[].value) as $s ({}; .[$s.station_name] = {station_code: $s.station_code, station_name: $s.station_name});
def strip_zhan: if endswith("站") then .[:-1] else . end;
# 站名或电报码 -> 电报码；找不到返回 null
def station_code($q):
  if ($q | test("^[A-Z]+$")) and has($q) then $q
  else name_stations[$q | strip_zhan].station_code end;

# ---------- 余票解析 ----------

def pad2: tostring | if length < 2 then "0" + . else . end;
def hm_minutes: split(":") | (.[0] | tonumber) * 60 + (.[1] | tonumber);
def add_minutes($date; $time; $mins):   # $date: YYYYMMDD 或 YYYY-MM-DD
  ($date | gsub("-"; "") | strptime("%Y%m%d") | mktime) + ($time | hm_minutes) * 60 + $mins * 60
  | todate | .[0:10];

def extract_prices($yp; $disc; $t):
  ([range(0; ($disc | length / 5 | floor)) as $i | $disc[$i * 5:$i * 5 + 5] | {key: .[0:1], value: (.[1:] | tonumber)}] | from_entries) as $d
  | [range(0; ($yp | length / 10 | floor)) as $i
     | $yp[$i * 10:$i * 10 + 10] as $p
     | (if ($p[6:10] | tonumber) >= 3000 then "W"
        elif SEAT_TYPES[$p[0:1]] == null then "H"
        else $p[0:1] end) as $c
     | SEAT_TYPES[$c] as $s
     | {seat_name: $s.name, short: $s.short, seat_type_code: $c,
        num: ($t[$s.short + "_num"] // ""), price: (($p[1:6] | tonumber) / 10), discount: $d[$c]}];

def extract_dw_flags:
  (. // "") | split("#") as $l
  | [ (if $l[0] == "5" then "智能动车组" else empty end),
      (if $l[1] == "1" then "复兴号" else empty end),
      (if ($l[2] // "") | startswith("Q") then "静音车厢" elif ($l[2] // "") | startswith("R") then "温馨动卧" else empty end),
      (if $l[5] == "D" then "动感号" else empty end),
      (if ($l | length) > 6 and $l[6] != "z" then "支持选铺" else empty end),
      (if ($l | length) > 7 and $l[7] != "z" then "老年优惠" else empty end) ];

# 一条车次（直达余票 / 中转的一段）-> 统一结构。$names: 电报码 -> 站名；$date: 本段在出发站的发车日期。
# 不用 start_train_date：它是列车在始发站的日期，途经站跨天发车时会差一天。
def ticket_info($names; $yp; $date):
  {train_no, start_date: add_minutes($date; .start_time; 0),
     arrive_date: add_minutes($date; .start_time; (.lishi | hm_minutes)),
     start_train_code: .station_train_code, start_time, arrive_time, lishi,
     from_station: ($names[.from_station_telecode] // .from_station_name // ""),
     to_station: ($names[.to_station_telecode] // .to_station_name // ""),
     from_station_telecode, to_station_telecode,
     prices: extract_prices($yp; .seat_discount_info // ""; .),
     dw_flag: (.dw_flag | extract_dw_flags)};

# 输入：leftTicket/queryG 的响应；$qdate：查询日期
def parse_tickets($qdate):
  .data.map as $m
  | [.data.result[] | split("|") as $v
     | [range(0; TICKET_KEYS | length) as $i | {key: TICKET_KEYS[$i], value: ($v[$i] // "")}] | from_entries
     | ticket_info($m; .yp_info_new; $qdate)];

# 输入：中转 middleList 数组
def parse_interlines:
  map(. as $m
    # 第一程用方案的 train_date；下一程日期 = 上一程到达时间 + 换乘等待时间
    | (reduce (.fullList // [])[] as $leg ({d: $m.train_date, out: []};
        .d as $d | ($leg | ticket_info({}; .yp_info; $d)) as $t
        | .out += [$t] | .d = add_minutes($t.arrive_date; $t.arrive_time; ($m.wait_time_minutes // 0))) | .out) as $tl
    | {lishi: ((.all_lishi_minutes / 60 | floor | pad2) + ":" + (.all_lishi_minutes % 60 | pad2)),
       start_time, start_date: .train_date, middle_date, arrive_date, arrive_time,
       from_station_code, from_station_name, middle_station_code, middle_station_name,
       end_station_code, end_station_name,
       start_train_code: ($tl[0].start_train_code // ""),
       first_train_no, second_train_no, train_count,
       ticketList: $tl,
       same_station: (.same_station == "0"), same_train: (.same_train == "Y"),
       wait_time});

# 输入：queryTrainInfo/query 的 .data.data
def parse_route:
  if length == 0 then [] else
    [.[0] | {train_class_name, service_type, end_station_name, station_name, station_train_code,
             arrive_time, start_time, lishi: .running_time, arrive_day_str}]
    + [.[1:][] | {station_name, station_train_code, arrive_time, start_time, lishi: .running_time, arrive_day_str}]
  end;

# ---------- 筛选 / 排序 ----------

def code_of: .start_train_code // "";
def dw_of: if has("ticketList") then (.ticketList[0].dw_flag // []) else (.dw_flag // []) end;
def match_flag($f):
  code_of as $c
  | if   $f == "G" then ($c | startswith("G") or startswith("C"))
    elif $f == "D" then ($c | startswith("D"))
    elif $f == "Z" then ($c | startswith("Z"))
    elif $f == "T" then ($c | startswith("T"))
    elif $f == "K" then ($c | startswith("K"))
    elif $f == "O" then ($c | test("^[GCDZTK]") | not)
    elif $f == "F" then (dw_of | index("复兴号") != null)
    elif $f == "S" then (dw_of | index("智能动车组") != null)
    else false end;

def filter_tickets($flags; $earliest; $latest; $sort; $rev; $limit):
  (if $flags == "" then . else map(select(. as $t | any($flags | split("")[]; . as $f | $t | match_flag($f)))) end)
  | map(select((.start_time | split(":")[0] | tonumber) as $h | $h >= $earliest and $h < $latest))
  | (if   $sort == "startTime"  then sort_by(.start_date, (.start_time | hm_minutes))
     elif $sort == "arriveTime" then sort_by(.arrive_date, (.arrive_time | hm_minutes))
     elif $sort == "duration"   then sort_by(.lishi | hm_minutes)
     else . end)
  | (if $sort != "" and $rev then reverse else . end)
  | (if $limit > 0 then .[:$limit] else . end);

# ---------- 输出格式 ----------

def fmt_price: if . == (. | floor) then floor | tostring else tostring end;
def ticket_status:
  tostring
  | if test("^[0-9]+$") then (tonumber | if . == 0 then "无票" else "剩余\(.)张票" end)
    elif . == "有" or . == "充足" then "有票"
    elif . == "无" or . == "--" or . == "" then "无票"
    elif . == "候补" then "无票需候补"
    elif . == "*" then "未开售"
    else "\(.)票" end;

def format_tickets_text:
  if length == 0 then "没有查询到相关车次信息" else
    "车次|出发站 -> 到达站|出发时间 -> 到达时间|历时\n"
    + (map("\(.start_train_code) \(.from_station)(telecode:\(.from_station_telecode)) -> \(.to_station)(telecode:\(.to_station_telecode)) \(.start_time) -> \(.arrive_time) 历时：\(.lishi)"
           + (.prices | map("\n- \(.seat_name): \(.num | ticket_status) \(.price | fmt_price)元") | join(""))
           + "\n") | join(""))
  end;

def format_tickets_csv:
  if length == 0 then "没有查询到相关车次信息" else
    "车次,出发站,到达站,出发时间,到达时间,历时,票价,特色标签\n"
    + (map("\(.start_train_code),\(.from_station)(telecode:\(.from_station_telecode)),\(.to_station)(telecode:\(.to_station_telecode)),\(.start_time),\(.arrive_time),\(.lishi),["
           + (.prices | map("\(.seat_name): \(.num | ticket_status) \(.price | fmt_price)元,") | join(""))
           + "],\(if (.dw_flag | length) == 0 then "/" else .dw_flag | join("&") end)\n") | join(""))
  end;

def format_interlines_text:
  if length == 0 then "没有查询到相关中转方案" else
    "出发时间 -> 到达时间 | 出发车站 -> 中转车站 -> 到达车站 | 换乘标志 | 换乘等待时间 | 总历时\n\n"
    + (map("\(.start_date) \(.start_time) -> \(.arrive_date) \(.arrive_time) | \(.from_station_name) -> \(.middle_station_name) -> \(.end_station_name) | "
           + (if .same_train then "同车换乘" elif .same_station then "同站换乘" else "换站换乘" end)
           + " | \(.wait_time) | \(.lishi)\n\n"
           + "\t" + (.ticketList | format_tickets_text | gsub("\n"; "\n\t")) + "\n") | join(""))
  end;

def format_route_text:
  if length == 0 then "未查询到相关车次信息。" else
    .[0] as $f
    | "\($f.station_train_code)次列车（\($f.train_class_name) \(if $f.service_type == "0" then "无空调" else "有空调" end)）\n站序|车站|车次|到达时间|出发时间|历时(hh:mm)\n"
      + ([to_entries[] | "\(.key + 1)|\(.value.station_name)|\(.value.station_train_code)|\(.value.arrive_time)|\(.value.start_time)|\(.value.arrive_day_str) \(.value.lishi)\n"] | join(""))
  end;
