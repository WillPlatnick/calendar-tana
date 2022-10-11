#!/usr/bin/env bash
# Thanks to https://josh.fail/2022/dump-calendar-app-events-to-json/ for providing this script
#
# Usage: ical-buddy-json [-w | -d] [-c CALENDAR1[,CALENDAR2...]] [date]
#
# NAME
#   ical-buddy-json -- dumps Apple Calendar data to JSON via iCalBuddy and jq
#
# SYNOPSIS
#   ical-buddy-json [-w | -d] [-c CALENDAR1[,CALENDAR2...]] [date]
#
# DESCRIPTION
#   Dumps Apple Calendar data to JSON via iCalBuddy and jq.
#
# OPTIONS
#   -w, --weekly
#     If set, show events for the entire week that the specified date falls
#     within. This is the default behavior.
#
#   -d, --daily
#     If set, limit output to just the events for the specified date.
#
#   -c [CALENDAR1[,CALENDAR2...]], --calendars [CALENDAR1[,CALENDAR2...]]
#     Comma separated list of calendars to check. If set, this take precedence
#     over any default calendars set in iCalBuddy's config file at
#     `~/.icalBuddyConfig.plist`.
#
#   -g, --group-by-date
#     If set, return a JSON object with dates as keys (i.e.
#     `{"DATE" => [{}, {}], ...}`).
#
#   -r, --raw
#     Show raw iCalBuddy output instead of converting to JSON. Probably only
#     useful for debugging this script.
#
# EXAMPLES
#   ical-buddy-json -w 2021-09-12
#   ical-buddy-json -d 2021-09-12
#
# SEE ALSO
#   ICALBUDDY(1), JQ(1)

# Call this script with DEBUG=1 to add some debugging output
if [[ "$DEBUG" ]]; then
  export PS4='+ [${BASH_SOURCE##*/}:${LINENO}] '
  set -x
fi

set -e

# Character used to separate properies iCalBuddy output
ICBPS="#ICALBUDDY-PROPERTY-SEPARATOR#"

# Character used for new lines in iCalBuddy notes output
ICBNL="#ICALBUDDY-NEW-LINE#"

# Character used for separating dates in iCalBuddy output
ICBSS="#ICALBUDDY-SECTION-SEPARATOR#"

# Echoes given args to STDERR
#
# $@ - args to pass to echo
warn() {
  echo "$@" >&2
}

# Reformats the given date
#
# $1 - source date (default in %Y-%m-%d format)
# $2 - new format to output (not including the +, default %Y-%m-%d)
# $3 - source date format (default is %Y-%m-%d)
reformat_date() {
  local now="$1" new_fmt="${2-%F}" src_fmt="${3-%F}"

  date -j -f "$src_fmt" "$now" "+$new_fmt"
}

# Returns midnight Sunday for the given week
#
# $1 - date in %Y-%m-%d format
start_of_week() {
  local now="$1" offset dow seconds

  dow="$(reformat_date "$now" "%w")"

  seconds="$(reformat_date "$now" "%s")"

  offset="$(days_to_seconds "$dow")"

  date -r "$(( seconds - offset ))" "+%Y-%m-%d 00:00:00 %z"
}

# Returns 11:59:59pm Saturday for the given week
#
# $1 - date in %Y-%m-%d format
end_of_week() {
  local now="$1" offset dow seconds

  dow="$(reformat_date "$now" "%w")"

  seconds="$(reformat_date "$now" "%s")"

  offset="$(days_to_seconds "$(( 6 - dow ))")"

  date -r "$(( seconds + offset ))" "+%Y-%m-%d 23:59:59 %z"
}

# Returns midnight for the given day
#
# $1 - date in %Y-%m-%d format
start_of_day() {
  local now="$1"

  reformat_date "$now" "%Y-%m-%d 00:00:00 %z"
}

# Returns 11:59:59pm for the given day
#
# $1 - date in %Y-%m-%d format
end_of_day() {
  local now="$1"

  reformat_date "$now" "%Y-%m-%d 23:59:59 %z"
}

# Calculates the number of seconds in days
#
# $1 - number of days
days_to_seconds() {
  local days="$1"

  echo "$(( days * 60 * 60 * 24 ))"
}

# Minutes between the two given times
#
# $1 - start time HH:MM
# $2 - end time HH:MM
minutes_between() {
  local start_at="$1" end_at="$2" start_secs end_secs

  start_secs="$(reformat_date "$start_at:00" "%s" "%T")"
  end_secs="$(reformat_date "$end_at:00" "%s" "%T")"

  echo "$(( (end_secs - start_secs) / 60 ))"
}

# TODO: should we grab earlier events and filter them out? Right now, if a
# multi-day event starts before end_at it is not included in our output when
# it (arguably) should be.
#
# Main wrapper for iCalBuddy.
#
# $1 - datetime to start at (in `%Y-%m-%d %H:%M:%S` format)
# $2 - datetime to end at (in `%Y-%m-%d %H:%M:%S` format)
# $3 - limit events to the specified calendars
fetch_events() {
  local -a opts=()
  local start_at="$1" end_at="$2" calendars="${3-}"

  if [[ "$calendars" ]]; then
    opts+=("--includeCals" "$calendars")
  fi

  opts+=(
    "--separateByDate"
    "--showEmptyDates"
    "--sectionSeparator" "$ICBSS"
    "--noRelativeDates"
    "--dateFormat" "%Y-%m-%d"
    "--timeFormat" "%H:%M"
    "--bullet" ""
    "--propertySeparators" "|$ICBPS|"
    "--includeEventProps" "title,datetime,notes"
    "--propertyOrder" "title,datetime,notes"
    "--noPropNames"
    "--notesNewlineReplacement" "$ICBNL"
    "eventsFrom:$start_at"
    "to:$end_at"
  )

  if ! iCalBuddy "${opts[@]}" 2> /dev/null; then
    warn "Error getting events!"
    return 1
  fi
}

# Parse output from iCalBuddy
#
# $1 - if set, group output by date
parse_events() {
  local group_by_date="${1-}" current_date line

  # Main parse loop...
  while read -r line; do
    local raw_title="" raw_time="" raw_notes="" title="" calendar="" \
      start_at="" end_at="" duration="" notes=""

    # Empty line... skip
    if [[ -z "$line" ]]; then
      continue

    # New date found
    # YYYY-MM-DD:$ICBSS
    elif [[ "${line: -${#ICBSS}}" = "$ICBSS" ]]; then
      current_date="${line%:*}"
      continue

    # No events on $current_date
    elif [[ "$line" = "Nothing." ]]; then
      continue

    # We have a timestamp and notes
    # test2##ICBPS##20:30 - 21:30##ICBPS##notes all day2
    elif [[ "$line" = *"$ICBPS"*"$ICBPS"* ]]; then
      raw_title="${line%%${ICBPS}*}"
      raw_time="${line#*$ICBPS}"
      raw_time="${raw_time%$ICBPS*}"
      raw_notes="${line##*$ICBPS}"

    # We have a timestamp but no notes
    # newnew##ICBPS##18:45 - 19:45
    elif [[ "$line" =~ ${ICBPS}[0-9]{2}:[0-9]{2}\ -\ [0-9]{2}:[0-9]{2}$ ]]; then
      raw_title="${line%%${ICBPS}*}"
      raw_time="${line##*$ICBPS}"
      raw_notes=""

    # All day event with notes
    # newnew##ICBPS##notes!
    elif [[ "$line" = *"$ICBPS"* ]]; then
      raw_title="${line%%${ICBPS}*}"
      raw_time=""
      raw_notes="${line##*$ICBPS}"

    # All day event, no notes
    else
      raw_title="$line"
      raw_time=""
      raw_notes=""
    fi

    # If there isn't at least a title at this point, skip.
    if [[ -z "$raw_title" ]]; then
      continue
    fi

    title="${raw_title% (*}"

    calendar="${raw_title##*(}"
    calendar="${calendar%%)}"

    # HH:MM - HH:MM
    if [[ "$raw_time" =~ ^[012][0-9]:[0-5][0-9]\ -\ [012][0-9]:[0-5][0-9]$ ]]; then
      start_at="${raw_time% - *}"
      end_at="${raw_time#* - }"

      duration="$(minutes_between "$start_at" "$end_at")"

      start_at="$(reformat_date "$start_at:00" "%I:%M%p" "%T" | tr "APM" "apm")"
      end_at="$(reformat_date "$end_at:00" "%I:%M%p" "%T" | tr "APM" "apm")"
    fi

    notes="${raw_notes//$ICBNL/$'\n'}"

    format_row \
      "$title" \
      "$calendar" \
      "$current_date" \
      "$notes" \
      "$start_at" \
      "$end_at" \
      "$duration"
  done | format_collection "$group_by_date"
}

# Format a single event as a JSON object with jq
#
# $1 - event title
# $2 - event calendar name
# $3 - event date (YYYY-MM-DD)
# $4 - event notes
# $5 - event start time (HH:MMam)
# $6 - event end time (HH:MMam)
# $6 - event duration (M)
format_row() {
  local title="$1" \
    calendar="$2" \
    date="$3" \
    notes="$4" \
    start_at="$5" \
    end_at="$6" \
    duration="$7"

  jq --null-input \
    --arg title    "$title" \
    --arg calendar "$calendar" \
    --arg date     "$date" \
    --arg notes    "$notes" \
    --arg start_at "$start_at" \
    --arg end_at   "$end_at" \
    --arg duration "$duration" \
    '
      {
        $title,
        $calendar,
        $date,
        $notes,
        start_at: (if $start_at == "" then null else $start_at end),
        end_at: (if $end_at == "" then null else $end_at end),
        duration: (if $duration == "" then 0 else $duration end) | tonumber,
        urls: $notes | [
          match("https?://[a-zA-Z0-9~#%&_+=,.?/-]+"; "g") | .string
        ] | unique
      }'
}

# Format the collection of events with jq. If group_by_date is set, outputs an
# object with dates as keys (i.e. `{"DATE" => [{}, {}], ...}`), otherwise
# outputs an array of objects (i.e. `[{}, {}...]`)
#
# $1 - if set, group events by date
format_collection() {
  local group_by_date="$1"

  if [[ "$group_by_date" ]]; then
    jq --slurp 'reduce .[] as $e (null; .[$e.date] += [$e])'
  else
    jq --slurp
  fi
}

# Print the help text for this program
#
# $1 - flag used to ask for help ("-h" or "--help")
print_help() {
  sed -ne '/^#/!q;s/^#$/# /;/^# /s/^# //p' < "$0" |
    awk -v f="$1" '
      f == "-h" && ($1 == "Usage:" || u) {
        u=1
        if ($0 == "") {
          exit
        } else {
          print
        }
      }
      f != "-h"
      '
}

main() {
  local start_at end_at calendars target_date mode=weekly raw group_by_date

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -g | --group-by-date) group_by_date=1; shift;;
      -w | --weekly) mode=weekly; shift ;;
      -d | --daily) mode=daily; shift ;;
      -r | --raw) raw=1; shift ;;
      -h | --help) print_help "$1"; return 0 ;;
      -c | --calendars) calendars="$2"; shift 2 ;;
      --) shift; break ;;
      -*) warn "Invalid option '$1'"; return 1 ;;
      *) break ;;
    esac
  done

  if ! type icalBuddy &> /dev/null; then
    warn "icalBuddy missing!"
    return 1
  elif ! type jq &> /dev/null; then
    warn "jq missing!"
    return 1
  fi

  target_date="${1:-$(date "+%Y-%m-%d")}"

  case "$mode" in
    weekly)
      start_at="$(start_of_week "$target_date")"
      end_at="$(end_of_week "$target_date")"
      ;;
    daily)
      start_at="$(start_of_day "$target_date")"
      end_at="$(end_of_day "$target_date")"
      ;;
  esac

  if ! events="$(fetch_events "$start_at" "$end_at" "$calendars")"; then
    return 1
  elif [[ "$raw" ]]; then
    printf "%s" "$events"
  else
    parse_events "$group_by_date" <<< "$events" 2>&1 |
      jq '.' # Make sure we can parase the JSON we've constructed...
  fi
}

main "$@"
