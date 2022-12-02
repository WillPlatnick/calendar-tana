# calendar-tana

[Video](https://share.cleanshot.com/zoaoYM)

This is a quick PoC to create an Agenda from your macOS calendar using iCalBuddy and bring them into Tana

Special thanks to Joshua Priddle for ical-buddy-json.sh - https://josh.fail/2022/dump-calendar-app-events-to-json/


## Setup

```
brew install jq
brew install ical-buddy
mkdir -p ~/workspace
cd ~/workspace
git clone https://github.com/WillPlatnick/calendar-tana.git
cd calendar-tana 
sudo cp ical-buddy-json.sh /usr/local/bin # Type your macOS login password to copy the file
```

## Limiting Calendars

You can configure icalBuddy to only use specific calendars. Copy the icalBuddyConfig.plist file as shown below.

```
cp ~/workspace/calendar-tana/icalBuddyConfig.plist ~/.icalBuddyConfig.plist
```

Open ~/.icalBuddyConfig.plist in your favorite text editor.

In this file, there are two selected calendars:
Main and DNS

Replace these with the calendar names you want to limit icalBuddy to pull from.


## Tana Setup

I am using the #meeting tag, feel free to adapt to whatever workflow you want
