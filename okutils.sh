
function OKJoin() {
  local api=$1; local condition=$2; local identifiers=$3;
  arrayName="$(OK "$api" -j "keys[] as \$k | select(\"\\(.[\$k] | type)\"==\"array\") | \"\\(\$k)\" ")"
  splicedJson="{ \"$arrayName\": [] }"
  lineCount=$(echo -n "$identifiers" | grep -c '^')
  for (( fromLine=1, pageSize=100; fromLine<=lineCount; fromLine=fromLine+pageSize )); do
    page="$(echo "$identifiers" | sed -n "$(( fromLine )),$(( fromLine+pageSize-1 ))p;$(( fromLine+pageSize ))q")"
    identifierQuery="$condition(${page//$'\n'/ OR })"
    records="$(OK "$api" -n -q "$identifierQuery" -j 'RECORDS[]')"
    splicedJson="$(printf "%s" "$splicedJson" "$records" | jq ".$arrayName += [inputs]")"
  done
  splicedJson="$(printf "%s" "$splicedJson" | jq ".$arrayName |= unique_by(.id) | .totalRecords=(.$arrayName|length)")"
  printf "%s\n" "$splicedJson"
}

function OKSliceAndSplice() {
  local allTokens="$1"
  local splicingFunction=$2
  local json=$3
  lineCount=$(echo -n "$allTokens" | grep -c '^')
  for (( fromLine=1, pageSize=100; fromLine<=lineCount; fromLine=fromLine+pageSize )); do
    sliceOfTokens="$(echo "$allTokens" | sed -n "$(( fromLine )),$(( fromLine+pageSize-1 ))p;$(( fromLine+pageSize ))q")"
    json="$($splicingFunction "$sliceOfTokens" "$json")";
  done
  printf "%s" "$json"
}

