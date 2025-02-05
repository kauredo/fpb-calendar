# FPB Calendar

This project automates the process of creating and managing team calendars by fetching game schedules from an external source, adding them to Google Calendar, and sharing them with specified team members.

## Features

- **Game Schedule Extraction**: Scrapes game schedules from a provided URL.
- **Google Calendar Integration**: Automatically creates or updates calendars in Google Calendar.
- **Team Sharing**: Shares calendars with a list of team members via email.
- **Duplicate Event Prevention**: Ensures that no duplicate events are added to the calendar.

## Setup

### Prerequisites

1. **Ruby**: Ensure you have Ruby installed on your system.
2. **Google Cloud Service Account**:

   - Create a service account and download the JSON credentials file.
   - Store the credentials file securely (`simecq-calendar-0801232616b8.json`).

3. **Google Calendar API**:
   - Enable the Google Calendar API for your project.
   - Share the calendar with your service account email.

### Installation

1. Clone this repository:

   ```bash
   git clone https://github.com/yourusername/fpb-calendar.git
   cd fpb-calendar
   ```

2. Install dependencies:

   `bundle install`

3. Add your service account credentials:
   Place the simecq-calendar-0801232616b8.json file in the root directory.

4. Create required files:
   `calendars.json`: A JSON file to map calendar URLs to calendar IDs.
   `emails.txt`: A list of team member emails (one email per line).

### Configuration

- `calendars.json`

  A mapping of calendar URLs to Google Calendar IDs. The script will update this file automatically as calendars are created.

- `emails.txt`

  Add one email per line for each team member who should have access to the calendars.

## Usage

### Fetch game schedules and update calendars:

run `ruby games.rb`, this will:

- Extract game data from URLs in calendars.json.
- Create or update calendars in Google Calendar.
- Share calendars with emails listed in emails.txt.
