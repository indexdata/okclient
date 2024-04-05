function __okclient_show_help {
    printf "Usage: . ok.sh; OK [ options ] [ folio api path [query string] ]\n\n"
    printf "Options: \n"
    printf "  -A <account match string>:    find FOLIO account from register (folio-services.json) by match string,\n"
    printf "                                '-A ?' shows list of all registered accounts\n"
    printf "  -u <username>:                login to service with this username (requires either -A or both of -t and -h)\n"
    printf "  -t <tenant>:                  login to service by this tenant     (requires either -A or both of -u and -h)\n"
    printf "  -h <host> :                   login to service at this host       (requires either -A or both of -u and -t)\n"
    printf "  -p <password>                 password for the provided account   (if omitted, the client will prompt)\n"
    printf "  -S <user defined session tag> supports multiple sessions for different services, for example '-S LOCAL' and '-S SNAPSHOT'"
    printf "                                The tag chosen at login must be provided in subsequent queries"
    printf "  -x                            'exit' (remove access token etc from environment)\n"
    printf "  -E <endpoint match string>:   select a FOLIO endpoint by match string, '-E ?' shows them all \n"
    printf "  -e <api path extension>       further path elements to add to the endpoint, for example a record identifying UUID\n"
    printf "  -q <query string>:            a CQL query string, i.e. 'title=\"magazine - q*\"' which will be url encoded as\n"
    printf "                                query=title%%3D%%22magazine+-+q%%2A%%22\n"
    printf "  -X <method>:                  defaults to curl's default"
    printf "  -n:                           no limit; remove the APIs default limit (if any) on the number of records in the response\n"
    printf "  -d <inline body>:             request body on command line\n"
    printf "  -f <file name>:               file containing request body\n"
    printf "  -c <content type>:            defaults to application/json\n"
    printf "  -s                            curl option '-s'"
    printf "  -o <additional curl options>  add curl options like -s, -v, -o, etc\n"
    printf "  -j <jq script>:               a jq command to apply to the Okapi response, ignored with -f or -d\n"
    printf "  -v                            shows current context and logs the curl request \n"
    printf "                                 (does not invoke curl -v, use -o \"-v\" for that).\n"
    printf "  -?                            show this message\n"
    printf "\n  EXAMPLES:\n"
    printf "  Login, GET instances:                             . ./ok.sh -A diku@localhost -p admin instance-storage/instances\n"
    printf "  Login, provide password interactively:            . ./ok.sh -A diku@localhost\n"
    printf "  Get instances:                                    . ./ok.sh instance-storage/instances\n"
    printf "  Get instance titles with jq:                      . ./ok.sh instance-storage/instances -j '.instances[].title'\n"
    printf "  Select from list of APIs with 'loan' in the path: . ./ok.sh -E loan\n"
    printf "  Create new loan type:                             . ./ok.sh -m post -d '{\"name\": \"my loan type\"}' loan-types\n"
    printf "  Get the names of up to 10 loan types:             . ./ok.sh loan-types -j '.loantypes[].name'\n"
    printf "  Get the names of all loan types:                  . ./ok.sh loan-types -u -j '.loantypes[].name'\n"
    printf "  Find instances with titles like \"magazine -q\":    . ./ok.sh instance-storage/instances -q \"title=\"magazine - q*\" \n"
    printf "  If not logged in: select account, api from lists, GET: . ./ok.sh\n"
}

# fallback to pre-RTR login protocol
function __okclient_get_non_expiry_token {
  local respHeadersFile
  local authResponse
  local respHeaders
  local statusHeader
  respHeadersFile="h-$(uuidgen).txt"
  authResponse=$(curl -sS -D "${respHeadersFile}" -X POST -H "Content-type: application/json" -H "Accept: application/json" -H "X-Okapi-Tenant: ${!sessionFOLIOTENANT}"  -d "{ \"username\": \"${!sessionFOLIOUSER}\", \"password\": \"${!sessionPASSWORD}\"}" "${!sessionFOLIOHOST}/authn/login")
  respHeaders=$(<"$respHeadersFile")
  rm "$respHeadersFile"
  statusHeader=$(echo "${respHeaders}" | head -1)
  if [[ ! $statusHeader == *" 201 "* ]]; then
      printf "\n\nAuthentication failed for user [%s] to %s@%s" "${!sessionFOLIOUSER}" "${!sessionFOLIOTENANT}" "${!sessionFOLIOHOST}"
      printf "%s\n" "$respHeaders"
      if [[ $authResponse = "{"*"}" ]]; then
        printf "Response : \"%s\"\n" "$(echo "$authResponse" | jq -r '.errors[]?.message')"
      else
        printf "%s\n" "$authResponse"
      fi
      return || exit 1
  else
    declare -g -x "$session"TOKEN="$(echo "$respHeaders" | grep x-okapi-token | tr -d '\r' | cut -d " " -f2)"
    sessionTOKEN="$session"TOKEN
    # shellcheck disable=SC2116
    declare -g -x "$session"expiration="$(echo "2034-01-01T01:00:00Z")"
  fi
}

function __okclient_get_token {
  local respHeadersFile
  local authResponse
  local respHeaders
  local statusHeader
  [[ -z "$s" ]] && printf "Logging in to %s %s\n\n" "$sessionFOLIOTENANT" "${!sessionFOLIOTENANT}"
  respHeadersFile="h-$(uuidgen).txt"
  authResponse=$(curl -sS -D "${respHeadersFile}" -X POST -H "Content-type: application/json" -H "Accept: application/json" -H "X-Okapi-Tenant: ${!sessionFOLIOTENANT}"  -d "{ \"username\": \"${!sessionFOLIOUSER}\", \"password\": \"${!sessionPASSWORD}\"}" "${!sessionFOLIOHOST}/authn/login-with-expiry")
  respHeaders=$(<"$respHeadersFile")
  rm "$respHeadersFile"
  statusHeader=$(echo "${respHeaders}" | head -1)
  if [[ $statusHeader == *" 404 "* ]]; then
    __okclient_get_non_expiry_token
  elif [[ ! $statusHeader == *" 201 "* ]]; then
    printf "\n\nAuthentication failed for user [%s] to %s@%s" "${!sessionFOLIOUSER}" "${!sessionFOLIOTENANT}" "${!sessionFOLIOHOST}"
    printf "%s\n" "$respHeaders"
    if [[ $authResponse = "{"*"}" ]]; then
      printf "Response : \"%s\"\n" "$(echo "$authResponse" | jq -r '.errors[]?.message')"
    else
      printf "%s\n" "$authResponse"
    fi
    return 1
  else
    declare -g -x "$session"TOKEN="$(echo "$respHeaders" | grep folioAccessToken | tr -d '\r' | cut -d "=" -f2 | cut -d ";" -f1)"
    sessionTOKEN="$session"TOKEN
    ( $viewContext ) && printf "\n\nLogin response headers:\n\n%s\n" "$respHeaders"
    declare -g -x "$session"expiration="$(echo "$authResponse" | jq -r '.accessTokenExpiration')"
    sessionExpiration="$session"expiration
    ( $viewContext ) && echo "Expiration: ${!sessionExpiration}"
  fi
  return 0
}

function __okclient_define_session_env_vars {
  # Prefix FOLIO env var names with session tag (if any)
  # The values must be accessed by indirection, i.e. ${!sessionToken}
  sessionFOLIOHOST="$session"FOLIOHOST
  sessionFOLIOTENANT="$session"FOLIOTENANT
  sessionFOLIOUSER="$session"FOLIOUSER
  sessionTOKEN="$session"TOKEN
  sessionExpiration="$session"expiration
}

function __okclient_show_session_variables {
  __okclient_define_session_env_vars
  printf "Host (%s):     %s\n" "$sessionFOLIOHOST" "${!sessionFOLIOHOST}"
  printf "Tenant (%s): %s\n"  "$sessionFOLIOTENANT" "${!sessionFOLIOTENANT}"
  printf "User (%s):     %s\n" "$sessionFOLIOUSER" "${!sessionFOLIOUSER}"
  printf "Token (%s):        %s\n" "$sessionTOKEN" "${!sessionTOKEN}"
  printf "Token expires: %s\n" "${!sessionExpiration}"
  printf "\n"
}

# shellcheck disable=SC2140
function __okclient_clear_auth_cache {
  declare -g -x "$session"FOLIOHOST=""
  declare -g -x "$session"FOLIOTENANT=""
  declare -g -x "$session"FOLIOUSER=""
  declare -g -x "$session"TOKEN=""
  declare -g -x "$session"PASSWORD=""
  declare -g -x "$session"expiration=""
  declare -g -x "$session"accountTag=""
}

# Fetch accounts list from json register, optionally filtered by match string
function __okclient_get_folio_account {
  local accountsCount

  if ( $viewContext ); then
    printf "Account match string: %s\n" "$accountMatchString"
  fi
  if [[ "$accountMatchString" == "?" ]]; then
    printf "\nChoose a FOLIO service and account to log in to (more services can be added in %s)\n\n" "$folioServicesJson"
    select accountTag in $(jq -r '.folios[].accounts[].tag' "$folioServicesJson")
    do
     break
    done
  else
    accountsCount="$(jq -r --arg tag "$accountMatchString" '.folios[].accounts[].tag|select(contains($tag))' "$folioServicesJson" | wc -l)"
    if [[ "$accountsCount" == "1" ]]; then
      accountTag=$(jq -r --arg tag "$accountMatchString" '.folios[].accounts[].tag|select(contains($tag))' "$folioServicesJson");
      [[ -z "$s" ]] &&  printf "Selected FOLIO account: %s\n" "$accountTag"
    elif [[ "$accountsCount" == "0" ]]; then
      printf "\nChoose a FOLIO service and account to log in to (listing them because none contains the string '%s')\n\n" "$accountMatchString"
      select accountTag in $(jq -r '.folios[].accounts[].tag' "$folioServicesJson")
      do
       break
      done
    else
      printf "\nSelect a FOLIO service to log in to (more services can be added in %s)\n\n" "$folioServicesJson"
      select accountTag in $(jq -r --arg tag "$accountMatchString" '.folios[].accounts[].tag|select(contains($tag))' "$folioServicesJson")
      do
       break
      done
    fi
  fi
  if [[ -z "$accountTag" ]]; then
      printf "\n Account selection cancelled\n"
      return 100
  fi
  return 0
}

# Potentially present list of services to choose from, set account and login credentials
function __okclient_get_set_auth_env_values {
  if ( $gotAccountMatchString ); then
    __okclient_clear_auth_cache
    if ! __okclient_get_folio_account; then
      return 1
    fi
  else
    if [[ -n "$p_foliouser" ]]; then
      if [[ -z "$p_foliotenant" ]] || [[ -z "$p_foliohost" ]]; then
        printf "Login initiated by -u but cannot determine FOLIO account to use without also either -A or both of -t and -h\n"
        return 2
      else
        __okclient_clear_auth_cache
      fi
    fi
    if [[ -n "$p_foliotenant" ]]; then
      if [[ -z "$p_foliouser" ]] || [[ -z "$p_foliohost" ]]; then
        printf "Login initiated by -t but cannot determine FOLIO account to use without also either -A or both of -u and -h\n"
        return 2
      fi
    fi
    if [[ -n "$p_foliohost" ]]; then
      if [[ -z "$p_foliotenant" ]] || [[ -z "$p_foliouser" ]]; then
        printf "Login initiated by -h but cannot determine FOLIO account to use without also either -A or both of -u and -t\n"
        return 2
      fi
    fi
  fi
  # Declare and export global env variables with account and auth info
  # Prefix variable names with the session tag (if any)
  # Being dynamically named, these env vars must be accessed by indirection throughout the script, i.e. ${!sessionTOKEN}
  # Use explicit account and auth arguments where given through options, otherwise fetch the account details from the json register.
  declare -g -x "$session"FOLIOHOST="${p_foliohost:-$(jq -r --arg tag "$accountTag" '.folios[]|select(.accounts[].tag == $tag) | .host' "$folioServicesJson")}"
  sessionFOLIOHOST="$session"FOLIOHOST
  declare -g -x "$session"FOLIOTENANT="${p_foliotenant:-$(jq -r --arg tag "$accountTag" '.folios[].accounts[]|select(.tag == $tag) | .tenant' "$folioServicesJson")}"
  sessionFOLIOTENANT="$session"FOLIOTENANT
  declare -g -x "$session"FOLIOUSER="${p_foliouser:-$(jq -r --arg tag "$accountTag" '.folios[].accounts[]|select(.tag == $tag) | .username' "$folioServicesJson")}"
  sessionFOLIOUSER="$session"FOLIOUSER
  declare -g "$session"PASSWORD="$password"
  sessionPASSWORD="$session"PASSWORD
  return 0
}

# Prompt user for password unless already supplied (on command line or cached from previous login)
function __okclient_prompt_for_password {
    if [[ -z "$p_password" ]] ; then
      printf "\nEnter password"
      [[ -n "$accountTag" ]] && printf " for %s %s %s %s" "$accountTag" "$p_foliouser" "$p_foliotenant" "$p_foliohost"|| printf " for %s" "${!sessionFOLIOUSER}"
      printf ": "
      read -r -s password
      if [[ -z "$password" ]]; then
        printf "\n Login cancelled\n"
        return 100
      else
        printf "\n"
      fi
      declare -g "$session"PASSWORD="$password"
    else
      declare -g "$session"PASSWORD="$p_password"
    fi
    return 0
}

function __okclient_select_account_and_log_in {
  if ( $gotAccountMatchString || $gotAuthParameters ); then
    # received request to login
    if __okclient_get_set_auth_env_values; then
      if __okclient_prompt_for_password; then
        __okclient_get_token
      fi
    fi
  elif  [[ -z "${!sessionTOKEN}" ]]; then
    # has no existing login
    if [[ -z "$p_endpoint" ]] && $viewContext ; then
      return
    elif [[ -z "$p_endpoint" ]]; then
      printf "\nGot no Okapi token for making requests. Want to select login and API from lists of FOLIO accounts and FOLIO endpoints? "
      [[ -z "$endpointMatchString" ]] && endpointMatchString="?"
    else
      printf "\nGot no Okapi token for making requests. Continue with list of FOLIO accounts to log in to?"
    fi
    read -r -p ' [Y/n]? ' choice
    local choice=${choice:-Y}
    case "$choice" in
      n|N) return 100;;
      *) accountMatchString="?"
         gotAccountMatchString=true
         if __okclient_get_set_auth_env_values ; then
           if __okclient_prompt_for_password ; then
             __okclient_get_token;
           fi
         fi
    esac
  fi
  return 0
}

function __okclient_select_endpoint {
  # Create list of endpoints to choose from, prompt user to choose.
  if [[ -z "$p_endpoint" ]] && ( ! $gotAccountMatchString && ! $gotAuthParameters ) && ( ! $viewContext ) || [[ -n "$endpointMatchString" ]] ; then
    if [[ $endpointMatchString == "?" ]]; then
      OPTS=$(jq -r '.endPoints[]' "$folioServicesJson" );
    else
      OPTS=$(jq -r --arg subStr "$endpointMatchString" '.endPoints[]|(select(contains($subStr)))' "$folioServicesJson" );
    fi
    if [[ -z "$OPTS" ]]; then
      printf "\nDid not yet register a FOLIO API matching '%s'. Here's a list of currently registered FOLIO API paths:\n\n" "$endpointMatchString"
      select endpoint in $(jq -r '.endPoints[]' "$folioServicesJson")
          do
            break
          done
    else
      matchCount=$(echo "$OPTS" | wc -l)
      if [[ "$matchCount" == "1" ]]; then
        endpoint="$OPTS"
        [[ -z "$s" ]] && printf "Selecting unique endpoint match: %s\n" "$endpoint"
      else
        if [[ -z "$endpointMatchString" ]] || [[ "$endpointMatchString" == "?" ]]; then
          printf "\nCurrently registered FOLIO API paths to pick from:\n\n"
        else
          printf "\nCurrently registered FOLIO API paths matching '%s':\n\n" "$endpointMatchString"
        fi
        select endpoint in $OPTS
          do
            break
          done
      fi
    fi
    [[ -z "$s" ]] && printf "\n"
  else
    endpoint="$p_endpoint"
  fi
}

# Check token expiration and issue new login if expired
function __okclient_maybe_refresh_token {
  if [[ "$(TZ=UTC printf '%(%Y-%m-%dT%H:%M:%s)T\n')" > "${!sessionExpiration}" ]]; then
    ($viewContext) && echo "Token expired ${!sessionExpiration}. Renewing login before request."
    __okclient_get_token
  fi
}

function __okclient_compose_run_curl_request {
    local tenantHeader="x-okapi-tenant: ${!sessionFOLIOTENANT}"
    local contentTypeHeader="Content-type: $contentType"

    # extension doesn't start with '/' or '?'?  Insert '/'
    [[ -n "$endpointExtension" ]] && [[ ! "$endpointExtension" =~ ^[\?/]+ ]] && endpointExtension="/$endpointExtension"
    local url="${!sessionFOLIOHOST}"/"$endpoint""$endpointExtension"
    # Set record limit to 1.000.000 ~ "no limit"
    if ( $noRecordLimit ); then
      if [[ $url == *"?"* ]]; then
        url="$url""&limit=1000000"
      else
        url="$url""?limit=1000000"
      fi
    fi

    __okclient_maybe_refresh_token
    local tokenHeader="x-okapi-token: ${!sessionTOKEN}"

    # shellcheck disable=SC2086  # curl will issue error on empty additionalCurlOptions argument, so var cannot be quoted
    if [[ -z "$file" ]] && [[ -z "$data" ]]; then
      ( $viewContext ) &&  echo curl "$method" -H \""$tenantHeader"\" -H \""$tokenHeader"\" -H \""$contentTypeHeader"\" "$url" "$additionalCurlOptions"
      if [[ -n "$query" ]]; then
        [ -n "$jqCommand" ] && curl -s -w "\n" --get --data-urlencode "$query" -H "$tenantHeader" -H "$tokenHeader" -H "$contentTypeHeader" "$url"  $additionalCurlOptions | jq -r "$jqCommand"
        [ -z "$jqCommand" ] && curl $s -w "\n" --get --data-urlencode "$query" -H "$tenantHeader" -H "$tokenHeader" -H "$contentTypeHeader" "$url" $additionalCurlOptions
      else
        [ -n "$jqCommand" ] && curl -s -w "\n" $method -H "$tenantHeader" -H "$tokenHeader" -H "$contentTypeHeader" "$url"  $additionalCurlOptions | jq -r "$jqCommand"
        [ -z "$jqCommand" ] && curl $s -w "\n" $method -H "$tenantHeader" -H "$tokenHeader" -H "$contentTypeHeader" "$url" $additionalCurlOptions
      fi
    else
      ( $viewContext ) && [ -n "$file" ] && echo curl $s "$method" -H \""$tenantHeader"\" -H \""$tokenHeader"\" -H \""$contentTypeHeader"\" --data-binary @"${file}" "$url" "$additionalCurlOptions"
      ( $viewContext ) && [ -n "$data" ] && echo curl $s "$method" -H \""$tenantHeader"\" -H \""$tokenHeader"\" -H \""$contentTypeHeader"\" --data-binary \'"${data}"\' "$url" "$additionalCurlOptions"
      [ -n "$file" ] && curl $s -w "\n" $method -H "$tenantHeader" -H "$tokenHeader" -H "$contentTypeHeader" --data-binary @"${file}" "$url" $additionalCurlOptions
      [ -n "$data" ] && curl $s -w "\n" $method -H "$tenantHeader" -H "$tokenHeader" -H "$contentTypeHeader" --data-binary "${data}" "$url" $additionalCurlOptions
    fi
}

function gotFolioSession {
  session=${1:+$1"_"}
  __okclient_define_session_env_vars
  if [[ -n "${!sessionTOKEN}" ]] && [[ -n "${!sessionFOLIOTENANT}" ]] && [[ -n "${!sessionFOLIOUSER}" ]] &&  [[ -n "${!sessionFOLIOHOST}" ]] ; then
    return 0
  else
    return 1
  fi
}

# Find working dir, even if the script is symlinked, to have path to the registry json with accounts and APIs.
SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
folioServicesJson="$DIR"/folio-services.json

function OK {
  if [ "$1" == "-?" ]; then
    __okclient_show_help
  elif [ "$#" -eq 0 ] ; then
    printf "FOLIO client script  (do  [ OK -? ]  to see options and examples)\n"
  fi

  OPTIND=1
  accountMatchString=""
  gotAccountMatchString=false
  p_foliouser=""
  p_foliotenant=""
  p_foliohost=""
  p_password=""
  gotAuthParameters=false
  session=""
  endpointMatchString=""
  p_endpoint=""
  endpoint=""
  endpointExtension=""
  query=""
  noRecordLimit=false
  method=""
  contentType=""
  s=""
  file=""
  data=""
  additionalCurlOptions=""
  jqCommand=""
  exit=false
  viewContext=false

  script_args=()
  while [ $OPTIND -le "$#" ]
  do
    if getopts "A:S:u:t:p:h:E:e:d:X:q:f:c:j:o:snvx?" option
    then
      case $option
      in
        c) contentType=$OPTARG;;
        d) data=$OPTARG;;
        E) endpointMatchString=$OPTARG;;
        e) endpointExtension=$OPTARG;;
        f) file=$OPTARG;;
        j) jqCommand=$OPTARG;;
        A) accountMatchString=$OPTARG
           gotAccountMatchString=true;;
        S) session=${OPTARG:+$OPTARG"_"};;
        X) method="-X${OPTARG^^}";;
        s) s="-s";;
        o) additionalCurlOptions=$OPTARG;;
        u) p_foliouser=$OPTARG
           gotAuthParameters=true;;
        p) p_password=$OPTARG;;
        q) query="query=${OPTARG#"query="}";;
        t) p_foliotenant=$OPTARG
           gotAuthParameters=true;;
        h) p_foliohost=$OPTARG
           gotAuthParameters=true;;
        n) noRecordLimit=true;;
        v) viewContext=true;;
        x) exit=true;;
        \?) return;;
      esac
    else
      script_args+=("${!OPTIND}")
      ((OPTIND++))
    fi
  done

  p_endpoint="${script_args[0]}"
  contentType=${contentType:-"application/json"}

  __okclient_define_session_env_vars

  if ( $viewContext ); then
    __okclient_show_session_variables
  fi

  if ( $exit ); then
    # Clear login credentials and stop on -x
    if [[ -z "${!sessionTOKEN}" ]]; then
     printf "\nI was asked to log out but there was already no access token found. Clearing env vars and exiting.\n\n"
    else
     printf "\nLogging out from FOLIO (forgetting access info for %s to %s@%s).\n\n" "${!sessionFOLIOUSER}" "${!sessionFOLIOTENANT}" "${!sessionFOLIOHOST}"
    fi
    __okclient_clear_auth_cache
  else
    if ( $gotAccountMatchString || $gotAuthParameters ) || [[ -z "${!sessionTOKEN}" ]]; then
      __okclient_select_account_and_log_in
      if [[ -n "${!sessionTOKEN}" ]]; then
        __okclient_select_endpoint
      fi
    else
      # Already got a token, determine API
      __okclient_select_endpoint
    fi

    if [[ -n "$endpoint" ]]; then
      # Determined an API, run curl request
      __okclient_compose_run_curl_request
    fi
  fi

}

