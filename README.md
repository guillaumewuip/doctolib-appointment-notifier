# doctolib-checker

`doctolib-checker` continuously checks Doctolib appointment availability and sends alerts as **macOS notifications**, **macOS Reminders**, or both.

Before I was using this script https://github.com/Schlaurens/doctolib-checker but it was bit hard to deal with URLs so I wanted to create my own, so I would like to thanks to https://github.com/Schlaurens for the idea.

## 1. Install

Requires Python 3.11+.

```bash
pip install requests
```

## 2. Configure `settings.json`

The script reads all settings from `settings.json`.

```json
{
  "execution": {
    "check_in_n_seconds": 60
  },
  "checking_window": {
    "start": "",
    "end": "",
    "look_for_n_days": 15
  },
  "doctors": [
    "https://www.doctolib.de/hausarztlich-tatige-internist-in/berlin/claudio-lamprecht/booking/availabilities?specialityId=1286&telehealth=false&placeId=practice-639665&insuranceSectorEnabled=true&insuranceSector=public&motiveIds%5B%5D=8102915&pid=practice-639665&insurance_sector=public&source=profile"
  ],
  "notifications": {
    "macos": {
      "reminder_list": "Doctolib"
    }
  }
}
```

### Settings explained

- `execution.check_in_n_seconds`: wait time between checks.
- `checking_window.start`: earliest appointment date you care about (`YYYY-MM-DD`). Empty = today.
- `checking_window.end`: latest appointment date you accept (`YYYY-MM-DD`). Empty = `start + 15 days`.
- `checking_window.look_for_n_days`: Doctolib API range (`limit`) per request.
- `doctors`: list of sources to check. Each item can be:
  - direct `availabilities.json` URL
  - booking URL (`/booking/availabilities?...`) — auto-resolved
  - doctor/search page URL — script tries to extract availability URLs
- `notifications.macos.reminder_list`: name of the Reminders list used for `--reminder` alerts. The list is created if missing. Default: `Reminders`.

## 3. Which Doctolib link should you paste?

Use the link from the page where Doctolib already shows the **available timeslots**.

![Doctolib timeslots page example](ss.png)

1. Open Doctolib and choose the **doctor**.
2. Choose the **examination/visit type**.
3. Continue until the page where you can see the calendar/timeslots.
4. Copy that URL from the browser address bar.
5. Paste it into `settings.json` in the `doctors` list.

Best link type is usually a booking URL like:

`https://www.doctolib.de/hausarztlich-tatige-internist-in/berlin/claudio-lamprecht/booking/availabilities?specialityId=1286&telehealth=false&placeId=practice-639665&insuranceSectorEnabled=true&insuranceSector=public&motiveIds%5B%5D=8102915&pid=practice-639665&insurance_sector=public&source=profile`

If you paste a doctor page or search page instead, the script will still try to resolve it automatically at runtime.

> **Warning**
> If you are logged in to Doctolib, your URL can look different (for example extra patient/session parameters). That is normal and still okay to use.

## 4. Run

Choose at least one notification channel:

```bash
python doctolib_checker.py --notification
python doctolib_checker.py --reminder
python doctolib_checker.py --notification --reminder
```

If you run without `--notification` or `--reminder`, the script exits with an error.

## 5. Test notifications

```bash
python doctolib_checker.py --notification-test
python doctolib_checker.py --reminder-test
```

## 6. Auto-booking agent

Slots are rare and get booked by other people fast. When the checker finds a slot, it now also fires
a background `pi` agent that drives a dedicated Chrome profile over CDP and attempts the booking
while the notification fires.

The agent refuses to run if doctolib.fr is not authenticated in the automation profile
(it stops with `not_authenticated` and never tries to log in). A booking failure never
crashes the checker loop.

### One-time setup

```bash
./booking_agent/setup_profile.sh
```

Log in to doctolib.fr in the Chrome window that opens, then close that window.
The session cookie persists in `~/.doctolib-booking-agent/chrome-profile`.

### Test it

```bash
# Dry run: walks the funnel but stops before the final confirm button.
./booking_agent/run_booking_agent.sh "<your booking URL>" --dry-run

# Real run (books the appointment!):
./booking_agent/run_booking_agent.sh "<your booking URL>"
```

Exit codes: `0` booked/reached confirmation, `1` not authenticated, `2` slot gone, `3` failed.
Logs live in `~/.doctolib-booking-agent/logs/`.

Only one attempt runs at a time; a new attempt is skipped while another is still booking.
Environment overrides: `BOOKING_AGENT_MODEL` (default `zai/glm-5.3-flash`),
`BOOKING_AGENT_TIMEOUT` (default `300` seconds).
