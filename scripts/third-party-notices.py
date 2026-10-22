import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
checkouts = {path.name.lower(): path for path in (root / ".build/checkouts").iterdir()}
pins = json.loads((root / "Package.resolved").read_text())["pins"]
sections = ["Voz and third-party license notices", (root / "LICENSE").read_text()]

for pin in pins:
    checkout = checkouts[pin["identity"]]
    sections.extend([
        f"{pin['identity']} {pin['state']['version']}\n{pin['location']}",
        (checkout / "LICENSE").read_text(),
    ])

additional = sorted(path for path in (checkouts["fluidaudio"] / "ThirdPartyLicenses").rglob("*") if path.is_file())
additional.extend([
    checkouts["posthog-ios"] / "vendor/libwebp/COPYING",
    checkouts["posthog-ios"] / "vendor/PHPLCrashReporter/LICENSE",
])
for path in additional:
    sections.extend([str(path.relative_to(root / ".build/checkouts")), path.read_text()])

sections.extend([
    "Geist and Geist Pixel fonts", (root / "Resources/Fonts/OFL.txt").read_text(),
    (root / "Resources/ModelNotices.txt").read_text(),
])
Path(sys.argv[1]).write_text("\n\n".join(sections))
