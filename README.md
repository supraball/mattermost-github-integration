Mattermost Github Integration
=============================

This is a small server written in D that listens for incoming github wehooks and
forwards them to mattermost.

See the included `config.json` for an example configuration.

A few parts haven't really been tested, PRs are welcome.
So far this is just a quick hack but it can grow into somethign proper.

To compile, assuming you have `dub` and `dmd` installed, just run

`dub build`


