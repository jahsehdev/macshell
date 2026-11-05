"""Exercise the Calendar bridge (bin/calendar.py) against a temporary database.

Covers: calendars CRUD, event CRUD + window queries with recurrence expansion,
the reminder scheduler (`due`), the natural-language parser (id/en, Asia/Jakarta),
and the ICS export/import roundtrip. Integration assertions check that the shell
runs the bridge through the scheduler and that GNOME Calendar is the launched app.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

CAL_PY = Path(__file__).resolve().parents[1] / "bin/calendar.py"
SHELL = Path(__file__).resolve().parents[1] / "shell.qml"
MACBAR = Path(__file__).resolve().parents[1] / "UpstreamBar/MacBar.qml"

TZ = "Asia/Jakarta"


class CalendarCliTests(unittest.TestCase):
    def setUp(self):
        self.db = Path(tempfile.mkdtemp()) / "calendar.db"
        self.run_cli("new-calendar", "--name", "Work", "--color", "#34C759")

    def run_cli(self, *args, expect_ok=True, now=None):
        env = dict(os.environ, TZ=TZ)
        cmd = [sys.executable, "-B", str(CAL_PY), "--db", str(self.db)] + list(args)
        if now is not None:
            cmd += ["--now", now]
        result = subprocess.run(cmd, capture_output=True, text=True, env=env)
        if expect_ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('"error"', result.stdout)
        return json.loads(result.stdout), result.returncode

    # ── calendars ──
    def test_calendars_and_events_crud(self):
        # the default "Home" calendar always exists
        names = [c["name"] for c in self.run_cli("calendars")[0]["calendars"]]
        self.assertEqual(names, ["Home", "Work"])
        self.run_cli("new-calendar", "--name", "Personal", "--color", "#FF3B30")
        names = [c["name"] for c in self.run_cli("calendars")[0]["calendars"]]
        self.assertEqual(names, ["Home", "Personal", "Work"])

        payload = {"title": "Rapat mingguan", "calendar": "Work",
                   "start": "2026-11-02T10:00:00+07:00", "end": "2026-11-02T11:00:00+07:00",
                   "reminders": [-900, -300]}
        ev = self.run_cli("new", "--json", json.dumps(payload))[0]["event"]
        self.assertEqual(ev["title"], "Rapat mingguan")
        self.assertEqual(ev["reminders"], [-300, -900])  # stored sorted

        loaded = self.run_cli("get", "--id", ev["id"])[0]["event"]
        self.assertEqual(loaded["title"], "Rapat mingguan")
        self.assertEqual(loaded["color"], "#34C759")

        self.run_cli("save", "--json", json.dumps({"id": ev["id"], "title": "Rapat",
                                                   "reminders": [-600]}))
        loaded = self.run_cli("get", "--id", ev["id"])[0]["event"]
        self.assertEqual(loaded["title"], "Rapat")
        self.assertEqual(loaded["reminders"], [-600])

        window = self.run_cli("events", "--from", "2026-11-01", "--to", "2026-11-30")[0]
        self.assertEqual(len(window["events"]), 1)
        self.run_cli("delete", "--id", ev["id"])
        self.assertEqual(self.run_cli("events", "--from", "2026-11-01", "--to", "2026-11-30")[0]["events"], [])
        self.run_cli("get", "--id", ev["id"], expect_ok=False)

    def test_recurrence_expansion(self):
        payload = {"title": "Rapat mingguan", "calendar": "Work",
                   "start": "2026-11-02T10:00:00+07:00", "end": "2026-11-02T11:00:00+07:00",
                   "rrule": "FREQ=WEEKLY;BYDAY=MO;COUNT=4"}
        self.run_cli("new", "--json", json.dumps(payload))
        window = self.run_cli("events", "--from", "2026-11-01", "--to", "2026-11-30")[0]
        self.assertEqual(len(window["events"]), 4)
        starts = [e["start"] for e in window["events"]]
        # the window query reports UTC ISO strings; 10:00 WIB = 03:00 UTC
        self.assertTrue(all(s.endswith("+00:00") for s in starts))
        self.assertEqual(starts[0][:10], "2026-11-02")
        self.assertEqual(starts[3][:10], "2026-11-23")

    def test_all_day_event(self):
        payload = {"title": "Libur", "start": "2026-11-03", "end": "2026-11-03", "allDay": True}
        ev = self.run_cli("new", "--json", json.dumps(payload))[0]["event"]
        self.assertTrue(ev["allDay"])
        window = self.run_cli("events", "--from", "2026-11-01", "--to", "2026-11-30")[0]
        self.assertEqual(len(window["events"]), 1)
        self.assertTrue(window["events"][0]["allDay"])

    # ── reminder scheduler ──
    def test_reminder_scheduler(self):
        payload = {"title": "Rapat mingguan", "calendar": "Work",
                   "start": "2026-11-02T10:00:00+07:00", "end": "2026-11-02T11:00:00+07:00",
                   "reminders": [-900, -300]}
        self.run_cli("new", "--json", json.dumps(payload))
        # 03:00 UTC = 10:00 WIB; 15 minutes before = 02:45 UTC
        self.assertEqual(self.run_cli("due", now="2026-11-02T02:44:00+00:00")[0]["due"], [])
        due = self.run_cli("due", now="2026-11-02T02:45:00+00:00")[0]["due"]
        self.assertEqual(len(due), 1)
        self.assertEqual(due[0]["title"], "Rapat mingguan")
        # the second call marks the fire done, so nothing is due again
        self.assertEqual(self.run_cli("due", now="2026-11-02T02:45:00+00:00")[0]["due"], [])
        # 5 minutes before = 02:55 UTC, the second fire of this event
        due = self.run_cli("due", now="2026-11-02T02:55:00+00:00")[0]["due"]
        self.assertEqual(len(due), 1)
        self.assertEqual(due[0]["title"], "Rapat mingguan")

    def test_no_reminder_offset_stays_incomplete(self):
        payload = {"title": "Tanpa pengingat", "calendar": "Work",
                   "start": "2026-11-02T10:00:00+07:00", "end": "2026-11-02T11:00:00+07:00",
                   "reminders": []}
        self.run_cli("new", "--json", json.dumps(payload))
        self.assertEqual(self.run_cli("due", now="2026-11-02T03:00:00+00:00")[0]["due"], [])

    # ── natural-language parser (id/en, Asia/Jakarta) ──
    def parse(self, text, now="2026-10-31T12:00:00+07:00"):
        return self.run_cli("parse", "--text", text, now=now)[0]["preview"]

    def test_parser_indonesian(self):
        p = self.parse("rapat besok jam 14.00 selama 1 jam")
        self.assertEqual(p["title"], "rapat")
        self.assertEqual(p["start"][:16], "2026-11-01T14:00")
        self.assertEqual(p["end"][:16], "2026-11-01T15:00")
        self.assertFalse(p["allDay"])

        p = self.parse("rapat besok jam 9 malam")
        self.assertEqual(p["title"], "rapat")
        self.assertEqual(p["start"][:16], "2026-11-01T21:00")

        p = self.parse("gym hari ini jam 06.30 selama 45 menit")
        self.assertEqual(p["title"], "gym")
        self.assertEqual(p["start"][:16], "2026-10-31T06:30")
        self.assertEqual(p["end"][:16], "2026-10-31T07:15")

        p = self.parse("rapat tim besok jam 10 sampai jam 12")
        self.assertEqual(p["title"], "rapat tim")
        self.assertEqual(p["start"][:16], "2026-11-01T10:00")
        self.assertEqual(p["end"][:16], "2026-11-01T12:00")

        p = self.parse("libur sepanjang hari 25 desember")
        self.assertEqual(p["title"], "libur")
        self.assertEqual(p["start"][:10], "2026-12-25")
        self.assertTrue(p["allDay"])

        p = self.parse("reminder: bayar listrik tanggal 5/11 pukul 19")
        self.assertEqual(p["title"], "bayar listrik")
        self.assertEqual(p["start"][:16], "2026-11-05T19:00")

        p = self.parse("makan siang jam 1 siang")
        self.assertEqual(p["title"], "makan siang")
        self.assertEqual(p["start"][:16], "2026-10-31T13:00")

    def test_parser_english(self):
        p = self.parse("submit report friday 9am")
        self.assertEqual(p["title"], "submit report")
        self.assertEqual(p["start"][:16], "2026-11-06T09:00")

        p = self.parse("lunch tomorrow at noon")
        self.assertEqual(p["title"], "lunch")
        self.assertEqual(p["start"][:16], "2026-11-01T12:00")

        p = self.parse("meeting 2pm to 3:30pm")
        self.assertEqual(p["title"], "meeting")
        self.assertEqual(p["start"][:16], "2026-10-31T14:00")
        self.assertEqual(p["end"][:16], "2026-10-31T15:30")

        p = self.parse("review quarterly report on december 15")
        self.assertEqual(p["title"], "review quarterly report")
        self.assertEqual(p["start"][:10], "2026-12-15")

    def test_parser_ambiguities_and_defaults(self):
        p = self.parse("obrolan santai")  # no time at all
        self.assertEqual(p["title"], "obrolan santai")
        self.assertEqual(p["start"][:16], "2026-10-31T09:00")
        self.assertTrue(any("no time found" in a for a in p["ambiguities"]))

        p = self.parse("meeting tanpa pengingat")
        self.assertEqual(p["reminders"], [])

        p = self.parse("rapat")
        self.assertEqual(p["title"], "rapat")
        self.assertEqual(p["reminders"], [-900])  # default 15 minutes before

    def test_parser_timezone(self):
        # the same sentence parsed in Jakarta and in London must differ by the offset
        env = dict(os.environ, TZ="Europe/London")
        r = subprocess.run([sys.executable, "-B", str(CAL_PY), "parse", "--text", "meeting tomorrow at 9am",
                            "--now", "2026-10-31T05:00:00+00:00"],
                           capture_output=True, text=True, env=env)
        p = json.loads(r.stdout)["preview"]
        self.assertEqual(p["start"][:16], "2026-11-01T09:00")

    # ── ICS roundtrip ──
    def test_ics_roundtrip(self):
        payloads = [
            {"title": "Rapat mingguan", "calendar": "Work",
             "start": "2026-11-02T10:00:00+07:00", "end": "2026-11-02T11:00:00+07:00",
             "rrule": "FREQ=WEEKLY;BYDAY=MO;COUNT=4"},
            {"title": "Libur", "start": "2026-11-03", "end": "2026-11-03", "allDay": True},
        ]
        for p in payloads:
            self.run_cli("new", "--json", json.dumps(p))
        with tempfile.TemporaryDirectory() as tmp:
            ics = Path(tmp) / "out.ics"
            self.run_cli("export", "--file", str(ics))
            text = ics.read_text()
            self.assertIn("BEGIN:VCALENDAR", text)
            self.assertIn("RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=4", text)
            self.assertIn("DTSTART;VALUE=DATE:20261103", text)
            self.run_cli("import", "--file", str(ics), "--calendar", "Imported")
            window = self.run_cli("events", "--from", "2026-11-01", "--to", "2026-11-30",
                                  "--calendar", "Imported")[0]
            titles = sorted(e["title"] for e in window["events"])
            self.assertEqual(titles.count("Rapat mingguan"), 4)
            self.assertIn("Libur", titles)

    def test_invalid_event_id(self):
        self.run_cli("get", "--id", "not an id", expect_ok=False)

    # ── integration: shell wiring ──
    def test_shell_runs_bridge_scheduler_and_system_calendar(self):
        shell = SHELL.read_text()
        self.assertIn('shellPath("bin/calendar.py")', shell)
        self.assertIn('target: "calendar"', shell)
        self.assertIn("notify-send", shell)
        macbar = MACBAR.read_text()
        self.assertIn('"calendar", "open"', macbar)
        self.assertIn('Quickshell.execDetached(["gnome-calendar"])', shell)


if __name__ == "__main__":
    unittest.main()
