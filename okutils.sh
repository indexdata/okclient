
function ok_join() {
  local api=$1; local condition=$2; local identifiers=$3; local session="$4"
  if arrayName="$(ok_get_name_of_array "$api" "$session")" ; then
    splicedJson="{ \"$arrayName\": [] }"
    lineCount=$(echo -n "$identifiers" | grep -c '^')
    for (( fromLine=1, pageSize=50; fromLine<=lineCount; fromLine=fromLine+pageSize )); do
      page="$(echo "$identifiers" | sed -n "$(( fromLine )),$(( fromLine+pageSize-1 ))p;$(( fromLine+pageSize ))q")"
      identifierQuery="$condition(${page//$'\n'/ OR })"
      records="$(OK -S "$session" "$api" -n -q "$identifierQuery" -j 'RECORDS[]')"
      splicedJson="$(printf "%s" "$splicedJson" "$records" | jq ".$arrayName += [inputs]")"
    done
    splicedJson="$(printf "%s" "$splicedJson" | jq ".$arrayName |= unique_by(.id) | .totalRecords=(.$arrayName|length)")"
    printf "%s\n" "$splicedJson" && return 0
  else
    printf "Error: %s\n" "$arrayName" && return 1
  fi
}

function ok_slice_and_splice() {
  local allTokens="$1"
  local splicingFunction=$2
  local splicedJson=$3
  lineCount=$(echo -n "$allTokens" | grep -c '^')
  for (( fromLine=1, pageSize=50; fromLine<=lineCount; fromLine=fromLine+pageSize )); do
    sliceOfTokens="$(echo "$allTokens" | sed -n "$(( fromLine )),$(( fromLine+pageSize-1 ))p;$(( fromLine+pageSize ))q")"
    splicedJson="$($splicingFunction "$sliceOfTokens" "$splicedJson")";
  done
  printf "%s" "$splicedJson"
}

function ok_get_name_of_array () {
  api=$1
  session=$2
  arrayName="$(OK -S "$session" "$api" -j "keys[] as \$k | select(\"\\(.[\$k] | type)\"==\"array\") | \"\\(\$k)\" ")"
  [[ ! "$(echo -n "$arrayName" | grep -c '^')" -eq 1 ]] && printf "'%s' not an API collection request? \nExpected a single array, found: <%s>\n" "$api" "$arrayName" && return 1
  echo "$arrayName"
  return 0
}
