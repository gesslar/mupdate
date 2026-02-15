# Development

## Prerequisites

- [Node.js](https://nodejs.org/)
- [muddy](https://github.com/gesslar/muddy) (`pnpx @gesslar/muddy`)
- [Mudlet](https://www.mudlet.org/) with a profile open

## Local Integration Testing

The test setup lets you run the full Mupdate update flow inside Mudlet against
a local HTTP server, so you can iterate on `Updater.lua` and `Mupdate.lua`
without publishing to GitHub.

### How It Works

1. `test/test.bash` patches `Updater.lua` to point at `localhost:18089` instead
   of GitHub, builds two versions of a test package ("CopierMupdateTest"), and
   starts a local HTTP server.
2. The **old version** (v0.0.1) is what gets installed in Mudlet.
3. The **new version** (v5.0.0) is what the local server serves, along with the
   version file and `Mupdate.lua`.
4. When Mudlet loads the old package, `sysLoadEvent` fires, the Updater
   downloads `Mupdate.lua` from localhost, checks the version, sees 5.0.0 >
   0.0.1, downloads the new `.mpackage`, and performs the update.

### Setup

If you have a Mudlet file watcher pointed at `test/Copier/build/`, the old
package will auto-install whenever a build completes.

### Running a Test

```bash
bash test/test.bash
```

This will:

- Patch `Updater.lua` with localhost URLs
- Build the new version (v5.0.0) and stage it for serving
- Build the old version (v0.0.1) for installation in Mudlet
- Start the HTTP server on port 18089

In Mudlet, trigger a reload (e.g., `lua resetProfile()`). The update flow will
run and the server will shut down automatically after serving the `.mpackage`.

### Resetting

To rebuild the old version (v0.0.1) so the watcher reinstalls it:

```bash
bash test/reset.bash
```

### Iterating

For a continuous test loop, re-run after each cycle:

```bash
while true; do bash test/test.bash; sleep 1; done
```

Edit `Updater.lua` or `Mupdate.lua`, then trigger `resetProfile()` in Mudlet.
The loop rebuilds, serves, and waits for the next round.

### Test Scripts

| Script | Purpose |
| --- | --- |
| `test/test.bash` | Build both versions, stage serve dir, start HTTP server |
| `test/reset.bash` | Rebuild old version (v0.0.1) so watcher reinstalls it |
| `test/serve.js` | Node.js static file server (auto-exits after serving `.mpackage`) |

### Port

The server defaults to port 18089. Override with the `PORT` environment
variable:

```bash
PORT=9999 bash test/test.bash
```
