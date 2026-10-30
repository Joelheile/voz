import re
import subprocess
import sys
from datetime import date

BETA = "## In beta"
README_START = "<!-- changelog -->"
README_END = "<!-- /changelog -->"
README_ENTRIES = 5


def git(*args, check=True):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=check).stdout.strip()


def new_entries(ref):
    previous = git("describe", "--tags", "--abbrev=0", "--match", "beta-*", ref, check=False)
    log = git("log", "--format=%B", f"{previous}..{ref}" if previous else ref)
    return [line.removeprefix("Changelog: ").strip() for line in log.splitlines() if line.startswith("Changelog: ")]


def split(text):
    parts = re.split(r"^(?=## )", text, flags=re.M)
    return parts[0], [part.rstrip() + "\n" for part in parts[1:]]


def bullets(section):
    return [line[2:] for line in section.splitlines() if line.startswith("- ")]


def section(heading, entries):
    return heading + "\n\n" + "".join(f"- {entry}\n" for entry in entries)


def update(changelog, channel, version, entries):
    intro, sections = split(changelog)
    known = {entry for part in sections for entry in bullets(part)}
    fresh = list(dict.fromkeys(entry for entry in entries if entry not in known))
    beta = next((part for part in sections if part.startswith(BETA + "\n")), None)
    rest = [part for part in sections if part is not beta]
    pending = fresh + (bullets(beta) if beta else [])
    if pending:
        heading = BETA if channel == "beta" else f"## {version} ({date.today():%B %-d, %Y})"
        rest.insert(0, section(heading, pending))
    return intro + "\n".join(rest)


def readme(text, changelog):
    _, sections = split(changelog)
    latest = bullets(sections[0])[:README_ENTRIES] if sections else []
    body = "".join(f"- {entry}\n" for entry in latest)
    block = f"{README_START}\n{body}\n[See everything new](CHANGELOG.md)\n{README_END}"
    return re.sub(re.escape(README_START) + ".*?" + re.escape(README_END), lambda _: block, text, flags=re.S)


def rewrite(path, change):
    with open(path) as file:
        text = file.read()
    result = change(text)
    with open(path, "w") as file:
        file.write(result)
    return result


def main(channel, version, ref="HEAD"):
    changelog = rewrite("CHANGELOG.md", lambda text: update(text, channel, version, new_entries(ref)))
    rewrite("README.md", lambda text: readme(text, changelog))


if __name__ == "__main__":
    main(*sys.argv[1:])
