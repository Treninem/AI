"""Owner-authorized removal of seven integrated temporary aliases only."""
import json
import os
import random
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

REPOSITORY = "Treninem/AI"
CANDIDATE = "chat-2026-09-17-unified-finalization"
VERIFIED = {'chat-2026-09-17-work-computer-autonomy-please-stop': '20be9b108c2de2e1d18cadb6cd2c75ba1e0e4d58', 'tmp-ignore': '031aebaad16fc25a39dfc45c58f96fadb658cac2', 'tmp-main-for-voice-sync': '031aebaad16fc25a39dfc45c58f96fadb658cac2', 'tmp-main-for-voice-sync-2': '031aebaad16fc25a39dfc45c58f96fadb658cac2', 'tmp-main-for-voice-sync-final': '031aebaad16fc25a39dfc45c58f96fadb658cac2', 'tmp-never-use': 'c41a9996692d4588592ecf5735e2c72a10ceb9f2'}


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def open_with_retry(request, attempts=5, timeout=30):
    last_error = None
    for attempt in range(attempts):
        try:
            return urllib.request.urlopen(request, timeout=timeout)
        except urllib.error.HTTPError as error:
            if error.code not in (429, 500, 502, 503, 504):
                raise
            retry_after = error.headers.get("Retry-After")
            delay = float(retry_after) if retry_after else 2 ** attempt
        except (urllib.error.URLError, TimeoutError) as error:
            last_error = error
            delay = 2 ** attempt
        if attempt < attempts - 1:
            time.sleep(delay + random.uniform(0, 0.5))
    raise RuntimeError(f"GitHub API request failed after {attempts} attempts") from last_error


def api(path):
    request = urllib.request.Request(
        "https://api.github.com/repos/" + REPOSITORY + path,
        headers={"Authorization": "Bearer " + os.environ["GITHUB_TOKEN"],
                 "Accept": "application/vnd.github+json"},
    )
    try:
        with open_with_retry(request) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise RuntimeError(f"GitHub read failed: HTTP {error.code}") from None


def main():
    if os.environ.get("GITHUB_REPOSITORY") != REPOSITORY:
        raise RuntimeError("Unexpected repository")
    with open(os.environ["GITHUB_EVENT_PATH"], encoding="utf-8") as stream:
        event = json.load(stream)
    head = event.get("pull_request", {}).get("head", {})
    actual = git("rev-parse", "HEAD")
    if (head.get("ref") != CANDIDATE or head.get("repo", {}).get("full_name") != REPOSITORY
            or head.get("sha") != actual or actual != os.environ["AURORA_EXPECTED_HEAD_SHA"]):
        raise RuntimeError("Unexpected candidate/event/checkout")
    open_heads = set()
    page = 1
    while True:
        pulls = api(f"/pulls?state=open&per_page=100&page={page}")
        if pulls is None:
            raise RuntimeError("Cannot read open PRs")
        for pull in pulls:
            if pull["head"]["repo"] and pull["head"]["repo"]["full_name"] == REPOSITORY:
                open_heads.add(pull["head"]["ref"])
        if len(pulls) < 100:
            break
        page += 1
    for branch, expected in VERIFIED.items():
        if branch in {"main", CANDIDATE} or branch in open_heads:
            print("AURORA_BRANCH_PRESERVED open-PR/canonical " + branch)
            continue
        subprocess.run(["git", "merge-base", "--is-ancestor", expected, actual], check=True)
        current = api("/branches/" + urllib.parse.quote(branch, safe=""))
        if current is None:
            print("AURORA_BRANCH_ALREADY_ABSENT " + branch)
            continue
        if current.get("protected") is not False or current["commit"]["sha"] != expected:
            print("AURORA_BRANCH_PRESERVED protected/advanced " + branch)
            continue
        subprocess.run(["git", "push", "--force-with-lease=refs/heads/" + branch + ":" + expected,
                        "origin", ":refs/heads/" + branch], check=True)
        if api("/branches/" + urllib.parse.quote(branch, safe="")) is not None:
            raise RuntimeError("Deletion readback failed: " + branch)
        print("AURORA_BRANCH_DELETED " + branch + " sha=" + expected)


if __name__ == "__main__":
    main()
