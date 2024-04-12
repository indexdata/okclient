# okclient

Yet another curl based FOLIO client - for inclusion as submodule in select customer projects.

### Purpose

- Provide short hands for Okapi authentication and other API requests, to use in project scripts.
- Provide a client for exploring or updating FOLIO data interactively.

### Usage

    source ok.sh;  OK [options] [a FOLIO API]

Get help text

    OK -?

### Examples

The shortest request is:

    OK

With that we obviously don't tell the client what FOLIO service or FOLIO API we want to access, so the client will
proceed interactively and ask if we want
to continue from existing lists of suggested FOLIO installations and APIs. It will get them
from [folio-services.json](./folio-services.json), that has somewhat arbitrarily compiled lists of FOLIO instances (i.e.
FOLIO snapshot and bug-fests) and most used APIs (i.e. `inventory-storage/instances`). The lists are supposed to be
extended locally, whether or not those changes are then shared by committing them.

If we were already logged in, the client would assume we wanted to continue on that session and just provide the list of
APIs.

The API can be provided directly and thus non-interactively

    OK instance-storage/instances

The same for the login

    OK -u diku_admin -t diku -h https://folio-snapshot-okapi.dev.folio.org -p ****

Queries can be added directly to the path or through the `-q` option. The -q option will invoke cURLs URL encoding.
Given current sample data in FOLIO snapshot, these requests should provide populated responses.

    OK instance-storage/instances?query=title=ABA

    OK instance-storage/instances -q 'title="magazine - q*"'

### Sessions

The script has a rudimentary session concept allowing a script to maintain multiple tokens for different FOLIO instances
at once.

The session is named on the login by `-S`:

    OK -u diku_admin -t diku -h https://folio-snapshot-okapi.dev.folio.org -p admin -S SNAPSHOT
    OK -u diku_admin -t diku -h http://localhost:9130 -p admin -S LOCAL

This can for example be used for comparing or transferring records from one FOLIO installation to another.

For example, using the sessions above, to copy material types from FOLIO snapshot to FOLIO localhost

    for id in $(OK -S SNAPSHOT material-types -n -j 'mtypes[].id'); do  # from snapshot
        record=$(OK -S SNAPSHOT material-types/"$id" -s)                # from shapshot
        OK -S LOCAL -s -X post -d "$record" material-types              # to local host
    done

Explanation for the options and keywords used in this example:

* -S chooses the session for the request
* -n means no limit on records
* -s is simply invoking cURL -s
* -j invokes jq on the response
* -d is cURLs --data-binary

### Light integration of jq

OK applies a lightweight integration of the JSON query tool `jq` with the option `-j` as shown in the previous example. OK will put `-s` on the curl
request to silence other
output than the response, pipe the response to jq, and then apply jq with the -r option.

    OK instance-storage/instances -j '.instances[].title'

One could just pipe the output of OK to jq instead as
in `OK instance-storage/instances -s | jq -r '.instances[].title'`, but output from OK other than the response (for
example an interactive login) would then go to jq as well.

The `-j` option additional provides a couple of shorthands for some jq query instructions.

#### Keyword RECORDS, jq retrieves arrays
`RECORDS` will be translated into an instruction to retrieve array(s) from a JSON object. This can be used to get the records array from a FOLIO API collection response generically, without necessarily knowing the name of the array, that is. 

    OK material-types -j 'RECORDS[].name'

This request will get the material types record array ("mtypes") from the material-types response.
The example is equivalent to  

    OK material-types -j '.mtypes[].name'
    OK material-types -j '.[keys[]] | (select(type=="array"))[].name'

With `RECORDS` it is thus possible to iterate over APIs and generically get their record arrays:

    for api in material-types identifier-types; do
      for id in $(OK -S SNAPSHOT "$api" -n -j 'RECORDS[].id'); do  # from snapshot
        record=$(OK -S SNAPSHOT "$api"/"$id" -s)                   # from shapshot
        OK -S LOCAL -s -X post -d "$record" "$api"                 # to local host
      done
    done

#### Keyword PROPS, jq retrieves names and types of properties 
`PROPS` will be translated into an instruction to retrieve top level property names and type from a JSON object, for example:

    OK instance-storage/instances -j 'RECORDS[0] | PROPS'`

This request will display the names and types of properties in the first instance record of the collection. The example is equivalent to 

    OK instance-storage/instances -j '.instances[0] | keys[] as $k | "\($k), \(.[$k] | type)"'


### Manipulating data

As for manipulating the data being pulled from or pushed to FOLIO, jq might be one of the handy options.

#### Example

Exporting holdings records from a source FOLIO to a target FOLIO, certain "virtual" properties must be pruned or the
POST will fail:

    for id in $(OK -S $SOURCE_FOLIO holdings-storage/holdings -n -j 'RECORDS[].id'); do
      record=$(OK -S $SOURCE_FOLIO -s holdings-storage/holdings/$id" -j 'del(.holdingsItems,.bareHoldingsItems)')
      OK -S $TARGET_FOLIO -d "$record" holdings-storage/holdings
    done

#### Example

Export active users but assign all a new email to prevent spamming when testing features that send emails.

    for id in $(OK -S $SOURCE_FOLIO users -n -q "active=true" -j 'RECORDS[].id'); do
      record=$(OK -S $SOURCE_FOLIO -s "users/$id" -j 'if .personal?.email != null 
                                                      then .personal.email="name@email.com" 
                                                      else . end')
      OK -S $TARGET_FOLIO -d "$record" users
    done

#### Example

Update a loan policy with a due date interval measured in minutes

    OK -X PUT  loan-policy-storage/loan-policies/4cdff544-b410-4301-a2fc-1aa918806860 -d \
      "$(OK loan-policy-storage/loan-policies/4cdff544-b410-4301-a2fc-1aa918806860 \
                                      -j '.loansPolicy.period.intervalId="Minutes"')"
