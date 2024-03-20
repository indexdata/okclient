function showHelp() {
    printf "Usage: . ./ok.sh [options] [folio api path]\n\n"
    printf "Options: \n"
    printf "  -A <account match string>:  login to service with label matched by provided string, '-A ?' shows list of all registered accounts to choose from \n"
    printf "  -u <username>:              login to service with this username (requires either -A or both of -t and -h)\n"
    printf "  -t <tenant>:                login to service by this tenant (requires either -A or both of -u and -h)\n"
    printf "  -h <host> :                 login to service at this host (requires either -A or both of -u and -t)\n"
    printf "  -p <password>               password for the provided account\n"
    printf "  -E <endpoint match string>: list FOLIO endpoints (API paths) matching the provided string '-E ?' shows them all \n"
    printf "  -e <api path extension>     further path elements to add to the endpoint, for example a record identifying UUID\n"
    printf "  -m <method>:                defaults to curl's default\n"
    printf "  -q <query string>:          cql query string, i.e. 'title=\"magazine - q*\"' which will be url encoded as query=title%%3D%%22magazine+-+q%%2A%%22 \n"
    printf "  -d <inline body>:           request body on command line\n"
    printf "  -f <file name>:             file containing request body\n"
    printf "  -c <content type>:          defaults to application/json\n"
    printf "  -o <curl options>           additional curl options (-s, -v, -o etc)\n"
    printf "  -n:                         no limit; remove the APIs default limit (if any) on the number of records in the response\n"
    printf "  -j <jq script>:             a jq command to apply to the Okapi response, ignored with -f or -d\n"
    printf "  -v                          verbose logging, or, view current context\n"
    printf "  -x                          exit FOLIO (remove access token etc from env)\n"
    printf "  -?                          show this message\n"
    printf "\n\n"
    printf "Examples:\n"
    printf "  Login, GET instances:                             . ./ok.sh -A diku@localhost -p admin instance-storage/instances\n"
    printf "  Login, provide password interactively:            . ./ok.sh -A diku@localhost"
    printf "  Get instances:                                    . ./ok.sh instance-storage/instances\n"
    printf "  Get instance titles with jq:                      . ./ok.sh instance-storage/instances -j '.instances[].title'\n"
    printf "  Select from list of APIs with 'loan' in the path: . ./ok.sh -E loan\n"
    printf "  Create new loan type:                             . ./ok.sh -m post -d '{\"name\": \"my loan type\"}' loan-types\n"
    printf "  Get the names of up to 10 loan types:             . ./ok.sh loan-types -j '.loantypes[].name'\n"
    printf "  Get the names of all loan types:                  . ./ok.sh loan-types -u -j '.loantypes[].name'\n "
    printf "  Get count of users in a patron group:             . ./ok.sh users -q \"patronGroup==60a6c316-6b93-40b8-8bf6-4a5dc5ca4f68\" -j '.totalRecords'\n"
    printf "\n\nFOLIO tenant and Okapi token are set as env vars \$FOLIOTENANT and \$TOKEN.\n\n"
}

if [ "$1" == "-?" ]; then
  showHelp
elif [ "$#" -eq 0 ] ; then
  printf "FOLIO client script  (do  [ ./ok.sh -? ]  to see options and examples)\n"
fi


OPTIND=1
method=""
api=""
apiPathExt=""
query=""
file=""
data=""
curlOptions=""
noRecordLimit=false
jqCommand=""
accountMatchString=""
endpointMatchString=""
exit=false
viewContext=false
p_foliouser=""
p_foliotenant=""
p_foliohost=""
p_password=""
gotAccountMatchString=false
gotAuthParameters=false
EP=""

script_args=()
while [ $OPTIND -le "$#" ]
do
  if getopts "A:u:t:p:h:E:e:d:m:q:f:c:j:o:nvx?" option
  then
    case $option
    in
      c) contentType=$OPTARG;;
      d) data=$OPTARG;;
      E) endpointMatchString=$OPTARG;;
      e) apiPathExt="/${OPTARG#"/"}";;
      f) file=$OPTARG;;
      j) jqCommand=$OPTARG;;
      A) accountMatchString=$OPTARG
         gotAccountMatchString=true;;
      m) method="-X$OPTARG"
         method=${method^^};;
      o) curlOptions=$OPTARG;;
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

api="${script_args[0]}"

if [[ -z "$contentType" ]]; then
  contentType="application/json"
fi

# Find working dir, even if the script is symlinked, to have path to the registry json with accounts and APIs.
SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

folioServicesJson="$DIR"/folio-services.json

function clearAuthCache () {
  FOLIOHOST=""
  FOLIOTENANT=""
  FOLIOUSER=""
  TOKEN=""
  PASSWORD=""
  expiration=""
  accountTag=""
}

# Fetch accounts list from json, optionally filtered by match string
function getFolioAccount() {
  if ( $viewContext ); then
    printf "Account match string: %s\n" "$accountMatchString"
  fi
  if [[ "$accountMatchString" == "?" ]]; then
    printf "\nChoose a FOLIO service and account to log in to (more services can be added in %s)\n\n" "$folioServicesJson"
    OPTS=$(jq -r '.folios[].accounts[].tag' "$folioServicesJson");
    select accountTag in $OPTS
    do
     break
    done
  else
    accountsCount="$(jq -r --arg tag "$accountMatchString" '.folios[].accounts[].tag|select(contains($tag))' "$folioServicesJson" | wc -l)"
    if [[ "$accountsCount" == "1" ]]; then
      accountTag=$(jq -r --arg tag "$accountMatchString" '.folios[].accounts[].tag|select(contains($tag))' "$folioServicesJson");
      printf "Selected FOLIO account: %s\n" "$accountTag"
    elif [[ "$accountsCount" == "0" ]]; then
      printf "\nChoose a FOLIO service and account to log in to (listing them because none contains the string '%s')\n\n" "$accountMatchString"
      OPTS=$(jq -r '.folios[].accounts[].tag' "$folioServicesJson");
      select accountTag in $OPTS
      do
       break
      done
    else
      OPTS=$(jq -r --arg tag "$accountMatchString" '.folios[].accounts[].tag|select(contains($tag))' "$folioServicesJson")
      printf "\nSelect a FOLIO service to log in to (more services can be added in %s)\n\n" "$folioServicesJson"
      select accountTag in $OPTS
      do
       break
      done
    fi
  fi
  if [[ -z "$accountTag" ]]; then
      printf "\n Account selection cancelled\n"
      return || exit 1
  fi
}

# Prompt user for password unless already supplied (on command line or cached from previous login)
function passwordPrompt () {
    if [[ -z "$p_password" ]] ; then
      printf "\nEnter password"
      [[ -n "$accountTag" ]] && printf " for %s" "$accountTag" || printf " for %s" "$FOLIOUSER"
      printf ": "
      read -s password
      if [[ -z "$password" ]]; then
        printf "\n Login cancelled\n"
        return || exit 1
      else
        printf "\n"
      fi
      PASSWORD=$password
    else
      PASSWORD=$p_password
    fi
}

# Potentially present list of services to choose from, set account and login credentials
function setAuthEnvVars() {
  if ( $gotAccountMatchString ); then
    clearAuthCache
    getFolioAccount
  else
    if [[ -n "$p_foliouser" ]]; then
      if [[ -z "$p_foliotenant" ]] || [[ -z "$p_foliohost" ]]; then
        printf "Login initiated by -u but cannot determine account without also either -A or both of -t and -h\n"
        return 0
      else
        clearAuthCache
      fi
    fi
    if [[ -n "$p_foliotenant" ]]; then
      if [[ -z "$p_foliouser" ]] || [[ -z "$p_foliohost" ]]; then
        printf "Login initiated by -t but cannot determine account without also either -A or both of -u and -h\n"
        return 0
      fi
    fi
    if [[ -n "$p_foliohost" ]]; then
      if [[ -z "$p_foliotenant" ]] || [[ -z "$p_foliouser" ]]; then
        printf "Login initiated by -h but cannot determine account without also either -A or both of -u and -t\n"
        return 0
      fi
    fi
  fi
  PASSWORD=$password
  if [[ -n "$p_foliohost" ]]; then
    FOLIOHOST=$p_foliohost
  else
    FOLIOHOST="$(jq -r --arg tag "$accountTag" '.folios[]|select(.accounts[].tag == $tag) | .host' "$folioServicesJson")"
  fi
  if [[ -n "$p_foliotenant" ]]; then
    FOLIOTENANT=$p_foliotenant
  else
    FOLIOTENANT="$(jq -r --arg tag "$accountTag" '.folios[].accounts[]|select(.tag == $tag) | .tenant' "$folioServicesJson")"
  fi
  if [[ -n "$p_foliouser" ]]; then
    FOLIOUSER=$p_foliouser
  else
    FOLIOUSER="$(jq -r --arg tag "$accountTag" '.folios[].accounts[]|select(.tag == $tag) | .username' "$folioServicesJson")"
  fi
  return 1
}

# Send the login request to Okapi
function postLogin() {
  local respHeadersFile
  local authResponse
  local respHeaders
  local statusHeader

  respHeadersFile="h-$(uuidgen).txt"
  authResponse=$(curl -sS -D "${respHeadersFile}" -X POST -H "Content-type: application/json" -H "Accept: application/json" -H "X-Okapi-Tenant: $FOLIOTENANT"  -d "{ \"username\": \"$FOLIOUSER\", \"password\": \"$PASSWORD\"}" "$FOLIOHOST/authn/login-with-expiry")
  respHeaders=$(<"$respHeadersFile")
  rm "$respHeadersFile"
  statusHeader=$(echo "${respHeaders}" | head -1)
  if [[ ! $statusHeader == *" 201 "* ]]; then
    printf "\n\nAuthentication failed for user [%s] to %s@%s" "$FOLIOUSER" "$FOLIOTENANT" "$FOLIOHOST"
    printf "%s\n" "$respHeaders"
    if [[ $authResponse = "{"*"}" ]]; then
      printf "Response : \"%s\"\n" "$(echo "$authResponse" | jq -r '.errors[]?.message')"
    else
      printf "%s\n" "$authResponse"
    fi
    return || exit 1
  else
    TOKEN=$(echo "$respHeaders" | grep folioAccessToken | tr -d '\r' | cut -d "=" -f2 | cut -d ";" -f1)
    if ( $viewContext ); then
      printf "\n\nLogin response headers:\n\n%s\n" "$respHeaders"
    fi
    expiration=$(echo "$authResponse" | jq -r '.accessTokenExpiration')
    if ( $viewContext ); then
      echo "Expiration: $expiration"
    fi
  fi
  if [ -n "$TOKEN" ]; then
    export FOLIOHOST
    export FOLIOTENANT
    export FOLIOUSER
    export TOKEN
    export PASSWORD
    export expiration
  fi
}

# Check token expiration and issue new login if expired
function maybeRefreshLogin() {
  if [[ "$(TZ=UTC printf '%(%Y-%m-%dT%H:%M:%s)T\n')" > "$expiration" ]]; then
    if ($viewContext); then
      echo "Token expired $expiration. Renewing login before request."
    fi
    postLogin
  fi
}

# BEGIN processing
if ( $viewContext ); then
  printf "Host (\$FOLIOHOST):     %s\n" "$FOLIOHOST"
  printf "Tenant (\$FOLIOTENANT): %s\n" "$FOLIOTENANT"
  printf "User (\$FOLIOUSER):     %s\n" "$FOLIOUSER"
  printf "Token (\$TOKEN):        %s\n" "$TOKEN"
  printf "Token expires:         %s\n" "$expiration"
  printf "\n"
fi

# Clear login credentials
if ( $exit ); then
  if [[ -z "$TOKEN" ]]; then
   printf "\nI was asked to log out but there was already no access token found. Clearing env vars.\n\n"
  else
   printf "\nLogging out from FOLIO (forgetting access info for %s to %s@%s).\n\n" "$FOLIOUSER" "$FOLIOTENANT" "$FOLIOHOST"
  fi
  clearAuthCache
  return || exit 1
fi

# Potentially prompt for password, set credentials env and send login to Okapi
if ( $gotAccountMatchString || $gotAuthParameters ); then
  setAuthEnvVars
  if [[ $? -eq 1 ]]; then
    passwordPrompt
    postLogin
  fi
elif  [[ -z "$TOKEN" ]]; then
  if [[ -z "$api" ]]; then
    printf "\nGot no Okapi token, and no API was given for requests. Want to select from lists of FOLIO accounts and FOLIO endpoints? "
  else
    printf "\nGot no Okapi token for making requests. Continue with list of FOLIO accounts to log in to?"
  fi
  read -r -p ' [Y/n]? ' choice
  choice=${choice:-Y}
  case "$choice" in
    n|N) return;;
    *) accountMatchString="?"
       if [[ -z "$api" ]]; then
         endpointMatchString="?"
       fi
       gotAccountMatchString=true
       setAuthEnvVars
       passwordPrompt
       postLogin;; # Proceed with new login.
  esac
fi

# Create list of endpoints to choose from, prompt user to choose.
if [[ -z "$api" ]] && ( ! $gotAccountMatchString && ! $gotAuthParameters ) && ( ! $viewContext ) || [[ -n "$endpointMatchString" ]] ; then
  if [[ $endpointMatchString == "?" ]]; then
    OPTS=$(jq -r '.endPoints[]' "$folioServicesJson" );
  else
    OPTS=$(jq -r --arg subStr "$endpointMatchString" '.endPoints[]|(select(contains($subStr)))' "$folioServicesJson" );
  fi
  if [[ -z "$OPTS" ]]; then
    printf "\nDid not yet register a FOLIO API matching '%s'. Here's a list of currently registered FOLIO API paths:\n\n" "$endpointMatchString"
    OPTS=$(jq -r '.endPoints[]' "$folioServicesJson" );
    select EP in $OPTS
        do
          break
        done
  else
    matchCount=$(echo "$OPTS" | wc -l)
    if [[ "$matchCount" == "1" ]]; then
      EP="$OPTS"
      printf "Selecting unique endpoint match: %s\n" "$EP"
    else
      if [[ -z "$endpointMatchString" ]]; then
        printf "\nCurrently registered FOLIO API paths to pick from:\n\n"
      else
        printf "\nCurrently registered FOLIO API paths matching '%s':\n\n" "$endpointMatchString"
      fi
      select EP in $OPTS
        do
          break
        done
    fi
  fi
  printf "\n"
else
  EP="$api"
fi

# Build and execute curl request to Okapi.
if [[ -n "$EP" ]]; then
  tenantHeader="x-okapi-tenant: $FOLIOTENANT"
  contentTypeHeader="Content-type: $contentType"

  # Set record limit to 1.000.000 ~ "no limit"
  url="$FOLIOHOST"/"$EP""$apiPathExt"
  if ( $noRecordLimit ); then
    if [[ $url == *"?"* ]]; then
      url="$url""&limit=1000000"
    else
      url="$url""?limit=1000000"
    fi
  fi

  maybeRefreshLogin
  tokenHeader="x-okapi-token: $TOKEN"

  echo "$curlOptions"

  if [[ -z "$file" ]] && [[ -z "$data" ]]; then
    if ( $viewContext ); then
      # shellcheck disable=SC2086
      echo curl $method -H \""$tenantHeader"\" -H \""$tokenHeader"\" -H \""$contentTypeHeader"\" "$url" "$curlOptions"
    fi
    if [[ -n "$jqCommand" ]]; then
      # shellcheck disable=SC2086
      curl -s -w "\n" --get --data-urlencode "$query" -H "$tenantHeader" -H "$tokenHeader" -H "$contentTypeHeader" "$url"  "$curlOptions" | jq -r "$jqCommand"
    else
      # shellcheck disable=SC2086
      curl -w "\n" --get --data-urlencode "$query" -H "$tenantHeader" -H "$tokenHeader" -H "$contentTypeHeader" "$url" $curlOptions
    fi
  else
    if ( $viewContext ); then
      if [[ -n "$file" ]]; then
        # shellcheck disable=SC2086
        echo curl $method -H \""$tenantHeader"\" -H \""$tokenHeader"\" -H \""$contentTypeHeader"\" --data-binary @"${file}" "$url" $curlOptions
      fi
      if [[ -n "$data" ]]; then
        # shellcheck disable=SC2086
        echo curl $method -H \""$tenantHeader"\" -H \""$tokenHeader"\" -H \""$contentTypeHeader"\" --data-binary \'"${data}"\' "$url" $curlOptions
      fi
    fi
    if [[ -n "$file" ]]; then
      # shellcheck disable=SC2086
        curl $method -H "$tenantHeader" -H "$tokenHeader" -H "$contentTypeHeader" --data-binary @"${file}" "$url" $curlOptions
    fi
    if [[ -n "$data" ]]; then
      # shellcheck disable=SC2086
      curl -w "\n" $method -H "$tenantHeader" -H "$tokenHeader" -H "$contentTypeHeader" --data-binary "${data}" "$url" $curlOptions
    fi
  fi
fi
