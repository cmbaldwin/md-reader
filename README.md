# MD Reader

A small macOS Markdown reader and editor. A single HTML page, `md-reader.html`, runs on a local
Python bridge server, `md-server.py`, which uses only the standard library.

- The server listens only on `127.0.0.1`, picks a random port and requires a random access token
  for each run.
- It reads one `.md` file and saves edits back to that same file. With no file, Save falls back to
  Save As in the browser.

## Use
    python3 md-server.py path/to/file.md

## Make it a Mac app (open .md files from Finder)
    bash "Make MD Reader App.command"

This builds `~/Applications/MD Reader.app`, a small `osacompile` applet that passes the opened file
to the server. It installs nothing else. Python 3 is required (Xcode Command Line Tools).
