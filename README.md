# okclient

Yet another curl based FOLIO client - for inclusion as submodule in select customer projects.

### Purpose

- Provide short hands for Okapi authentication and other API requests, to use in project scripts.
- Provide a client for exploring or updating FOLIO data interactively.

### Usage

    source ok.sh;  OK

### Examples

    OK

Here we don't tell the client what FOLIO service or FOLIO API we want to access with just `OK`, so it will ask if we
want
to continue from existing lists of suggested FOLIO installations and APIs. It will get them
from [folio-services.json](./folio-services.json), that has somewhat arbitrarily compiled lists of FOLIO instances (i.e.
FOLIO snapshot and bug-fests) and most used APIs (i.e. `inventory-storage/instances`). The lists are supposed to be
extended locally, whether the changes are then shared or not by committing them.

If we were already logged in, the client would assume we wanted to continue on that session and just provide the list of
APIs.

The API can be provided directly of course, making it non-interactive

    OK instance-storage/instances

The same for the login

    OK -u diku_admin -t diku -h https://folio-snapshot-okapi.dev.folio.org -p ****

Queries can be added directly to the path or through the `-q` option. The -q option will invoke cURLs URL encoding.
Given the current sample data in snapshot, these requests should provide populated responses.

    OK instance-storage/instances?query=title=ABA

    OK instance-storage/instances -q 'title="magazine - q*"'

### Sessions

The script has a rudimentary session concept allowing a script to maintain multiple tokens for different FOLIO instances
at the same time.

The session is named on the login by `-S`

    OK -u diku_admin -t diku -h https://folio-snapshot-okapi.dev.folio.org -p admin -S SNAPSHOT
    OK -u diku_admin -t diku -h http://localhost:9130 -p admin -S LOCAL

This can be used for comparing or transferring records from one FOLIO installation to another.

For example, to copy material types and identifier types from FOLIO snapshot to FOLIO localhost

    for api in material-types identifier-types; do
      for id in $(OK -S SNAPSHOT "$api" -n -j 'RECORDS[].id'); do  # from snapshot
        record=$(OK -S SNAPSHOT "$api"/"$id" -s)                   # from shapshot
        OK -S LOCAL -s -X post -d "$record" "$api"                 # to local host
      done
    done

* -S chooses the session for the request
* -n means no limit on records
* -s is simply invoking cURL -s
* -j is shorthand for the invocation of jq on the response: ` -s | jq -r `
* -d is cURLs --data-binary
* RECORDS[] is shorthand for a jq instruction to get the records array from a FOLIO API collection response without
  knowing the name of the array

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
