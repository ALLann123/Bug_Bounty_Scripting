#!/usr/bin/env python3
"""
dir_scanner.py — Simple hidden-directory/file scanner for testing your OWN
home lab web servers. Only use against systems you own or are authorized
to test.

Usage:
    python3 dir_scanner.py http://192.168.1.10 -w wordlist.txt -t 20
    python3 dir_scanner.py http://192.168.1.10            # uses built-in mini wordlist
"""

import argparse
import sys
import concurrent.futures
import requests
from urllib.parse import urljoin

# Small built-in wordlist used if the user doesn't supply one.
DEFAULT_WORDS = [
    "admin", "login", "backup", "config", ".git", ".env", "uploads",
    "test", "dev", "api", "old", "private", "secret", "data",
    "db", "logs", "tmp", "static", "assets", "scripts", "includes",
    "console", "panel", "dashboard", ".htaccess", "wp-admin", "phpmyadmin",
    "/administrator-panel", 
]


def check_url(session, base_url, word, timeout, status_filter):
    paths_to_try = [word, word + "/"]
    results = []
    for path in paths_to_try:
        url = urljoin(base_url + "/", path)
        try:
            resp = session.get(url, timeout=timeout, allow_redirects=False)
            if status_filter is None or resp.status_code in status_filter:
                results.append((url, resp.status_code, len(resp.content)))
        except requests.RequestException:
            pass
    return results


def load_wordlist(path):
    with open(path, "r", errors="ignore") as f:
        return [line.strip() for line in f if line.strip() and not line.startswith("#")]


def main():
    parser = argparse.ArgumentParser(
        description="Scan a web server for hidden directories/files (authorized testing only)."
    )
    parser.add_argument("target", help="Base URL, e.g. http://192.168.1.10:8080")
    parser.add_argument("-w", "--wordlist", help="Path to wordlist file (one entry per line)")
    parser.add_argument("-t", "--threads", type=int, default=10, help="Number of concurrent threads (default: 10)")
    parser.add_argument("--timeout", type=float, default=5.0, help="Request timeout in seconds (default: 5)")
    parser.add_argument(
        "-s", "--status",
        help="Comma-separated status codes to show (default: 200,204,301,302,307,401,403)",
        default="200,204,301,302,307,401,403",
    )
    parser.add_argument("--all", action="store_true", help="Show all results regardless of status code")
    args = parser.parse_args()

    target = args.target.rstrip("/")
    if not target.startswith("http://") and not target.startswith("https://"):
        print("Error: target must start with http:// or https://")
        sys.exit(1)

    words = load_wordlist(args.wordlist) if args.wordlist else DEFAULT_WORDS
    status_filter = None if args.all else {int(s) for s in args.status.split(",")}

    print(f"[*] Target: {target}")
    print(f"[*] Wordlist size: {len(words)}")
    print(f"[*] Threads: {args.threads}")
    print(f"[*] Showing status codes: {'ALL' if args.all else sorted(status_filter)}")
    print("-" * 60)

    session = requests.Session()
    session.headers.update({"User-Agent": "homelab-dir-scanner/1.0"})

    found = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.threads) as executor:
        futures = {
            executor.submit(check_url, session, target, word, args.timeout, status_filter): word
            for word in words
        }
        for future in concurrent.futures.as_completed(futures):
            for url, status, size in future.result():
                found.append((url, status, size))
                print(f"[{status}] {url}  (size: {size})")

    print("-" * 60)
    print(f"[*] Done. {len(found)} matching path(s) found.")


if __name__ == "__main__":
    main()

"""
[*] Target: https://0a4800ee03c5553b82826ad500ca0059.web-security-academy.net
[*] Wordlist size: 28
[*] Threads: 10
[*] Showing status codes: [200, 204, 301, 302, 307, 401, 403]
------------------------------------------------------------
[200] https://0a4800ee03c5553b82826ad500ca0059.web-security-academy.net/login  (size: 3237)
[200] https://0a4800ee03c5553b82826ad500ca0059.web-security-academy.net/login/  (size: 3237)
[200] https://0a4800ee03c5553b82826ad500ca0059.web-security-academy.net/administrator-panel  (size: 3138)
[200] https://0a4800ee03c5553b82826ad500ca0059.web-security-academy.net/administrator-panel/  (size: 3138)
------------------------------------------------------------
[*] Done. 4 matching path(s) found.
"""