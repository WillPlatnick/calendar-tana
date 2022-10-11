#!/bin/bash

echo "%%tana%%"
IFS=$'\n'
events=$(ical-buddy-json.sh -d | jq -r '.[].title')
for event in $events; do
  startat=$(ical-buddy-json.sh -d | jq -r ".[] | select(.title==\"${event}\") | .start_at")
  endat=$(ical-buddy-json.sh -d | jq -r ".[] | select(.title==\"${event}\") | .end_at")
  if [[ $startat == "null" ]]; then
    startat="All Day Event"
    endat=""
  fi
  echo "- $startat-$endat $event #meeting"  
done

