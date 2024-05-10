# Retrieves records from an API by an in principle unlimited list of new-line separated identifiers.
# $1 The API to retrieve records from
# $2 The condition to apply for the provided identifiers (i.e. "id==")
# $3 The collection of identifiers to apply the condition to for the provided API. The identifiers will be queried for with ORs between them.
# $4 (optional) The named session to issue the okr(s) for
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

# Takes a collection of new-line delimited tokens ($1), cuts it up in chunks of 50 tokens and passes the chunks to
# the provided function ($2) together with the incrementally spliced-together result ($3). Using the spliced-together result for
# anything is optional for the provided function. The spliced result is assumed to JSON but doesn't have to be.
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

# Stitches together multiple responses from multiple requests to a given API, using RMBs support for requesting batches of
# records in UUID order by offset-limit.
# $1:  The API to request records from
# $2:  The amount of records to retrieve per request
# $3:  The maximum total amount of records to retrieve
# $4:  (optional) The named session to use for the request
function ok_chunked_download() {
  local api=$1
  local chunkSize=$2
  local max=$3
  local session=$4
  if arrayName="$(ok_get_name_of_array "$api" "$session")" ; then
    chunk=$(OK -S "$session" "$api"\?limit="$chunkSize" -q "cql.allRecords=1 sortBy id" -s)
    lastId=$(jq '.[keys[0]] | last | .id' <<< "$chunk")
    recs=$(jq ".$arrayName" <<< "$chunk")
    records=${recs:1:-1}
    for (( i=chunkSize; i<max; i=i+chunkSize )) {
      chunk=$(OK -S "$session" "$api"\?limit="$chunkSize" -q "id>$lastId sortBy id" -s)
      lastId="$(jq '.[keys[0]] | last | .id'  <<< "$chunk")"
      count="$(jq '.[keys[0]] | length' <<< "$chunk")"
      recs="$(jq ".$arrayName" <<< "$chunk")"
      records="$records,${recs:1:-1}"
      (( count < chunkSize ))  && break
    }
    printf "%s\n" "$(jq ".totalRecords=(.$arrayName|length)" <<< "{ \"$arrayName\": [$records] }")"
  fi
}

function ok_get_name_of_array () {
  api=$1
  session=$2
  okr="OK ${api}?limit=0 -s"
  jqc="keys[] as \$k | select(\"\\(.[\$k] | type)\"==\"array\") | \"\\(\$k)\" "
  arrayName="$($okr -j "$jqc")"
  status=$?
  if [[ $status -eq 0 ]]; then
    [[ ! "$(echo -n "$arrayName" | grep -c '^')" -eq 1 ]] && printf "'%s' not an API collection request? \nExpected a single array, found: <%s>\n" "$api" "$arrayName" && return 1
    echo "$arrayName"
  else
    if [[ $status -eq 4 ]]; then
      printf "jq could not parse response \"%s\"\nRequest was [%s]\n" "$($okr)" "$okr"
    else
      printf "Error status \"%s\"" $status
    fi
  fi
  return 0
}
