# SatelliteY

Personal automation tools and scripts collection.

## Contents

### `/linux-scheduler/`
Linux scheduled service for automated daily tasks:
- `daily_checkin.sh` - Main automation script (WoL + API call)
- `daily-checkin.timer` - systemd timer for daily execution
- `daily-checkin-test.timer` - Test mode timer (1 min delay)

### `/docs/`
- `Windows_AutoLogin_Guide.md` - Windows auto-login configuration
- `Dynamic_Lock_Analysis.md` - Windows Dynamic Lock analysis

### Other
- `minimal_backend.py` - Minimal Flask backend for testing
- `test_lockscreen.py` - Lock screen automation research
- `test_auto_unlock.py` - Auto-unlock testing (Secure Desktop limitations)

## Quick Start

See `/linux-scheduler/README.md` for deployment instructions.

## License

MIT
