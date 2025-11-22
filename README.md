# Mobile Application to Remind User to Remember Essentials

## Project Overview
This project is a mobile app that reminds users (primarily the older demographic) to remember to take essentials like keys when they exit the home. The motivation for this project is when I noticed my grandparents commonly forget these essentials when leaving the home, so I thought a simple app like this would significantly make their lives more convenient. This project uses Dart and Flutter SDK.

## App Logic
The logic for the app is simple: the app scans the environment for bluetooth beacons, and if a beacon is detected, a notification goes off. A beacon would be installed near the door so that the phone enters the region of the beacon when the user is about to leave the house.

## TODOs
This project is a work-in-progress. I need to handle the case where the user enters the region of the beacon but from outside the home; a notification must not go off in this case.
