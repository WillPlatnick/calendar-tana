#!/bin/bash

echo "%%tana%%"
IFS=$'\n'
json=$(ical-buddy-json.sh -d)
events=$(echo $json | jq -r '.[].title')
for event in $events; do
  startat=$(echo $json | jq -r ".[] | select(.title==\"${event}\") | .start_at")
  endat=$(echo $json | jq -r ".[] | select(.title==\"${event}\") | .end_at")
  if [[ $startat == "null" ]]; then
    startat="All Day Event"
    endat=""
  fi
  echo "- $startat-$endat $event #meeting"  
done

