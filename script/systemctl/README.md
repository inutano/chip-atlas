# Running the app under systemd

`chip-atlas.service` starts the app with Puma (`puma.rb` in the repository
root) as the `ubuntu` user and keeps it running:

- `Restart=always`: the app comes back by itself after a crash.
- `OOMPolicy=continue`: if the kernel OOM killer hits one worker, the Puma
  master stays up and starts a new one. With the default (`stop`) systemd
  stopped the whole app and nothing started it again (outage of 2026-11-25).

```
sudo cp script/systemctl/chip-atlas.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now chip-atlas
```

| Task | Command |
| --- | --- |
| Start / stop | `sudo systemctl start chip-atlas` / `sudo systemctl stop chip-atlas` |
| Restart after a deploy | `sudo systemctl restart chip-atlas` |
| Status | `systemctl status chip-atlas` |
| Logs | `log/puma.stdout.log`, `log/puma.stderr.log`, `journalctl -u chip-atlas` |

Booting takes about two minutes (the app loads the experiment lists and
builds the search index before it opens the socket); nginx answers 502 until
then.

## Moving a host from unicorn to Puma

Hosts set up before the move to Ruby 4.0 run unicorn as root from
`/etc/init.d/chip-atlas`. unicorn 6.1.0 crashes on Ruby 4.0 (segmentation
fault in its kgio extension), so the Ruby upgrade and this change go together.
This procedure has not been run on a real host yet; rehearse it on an instance
launched from the production AMI first.

1. Install the Ruby version in `.ruby-version` with rbenv, then
   `bundle install` in the repository.
2. Stop unicorn: `sudo /etc/init.d/chip-atlas stop`, and wait until
   `pgrep -f "unicorn (master|worker)"` finds nothing.
3. Remove the old init script, so that it cannot start unicorn at boot:
   `sudo update-rc.d chip-atlas remove && sudo rm /etc/init.d/chip-atlas`.
   Also remove `/etc/systemd/system/chip-atlas.service.d/oom.conf` if it
   exists; the unit file now carries that setting.
4. The app used to run as root. Hand its files to `ubuntu`:
   `sudo chown -R ubuntu:ubuntu log tmp database.sqlite*`.
5. Install and start the unit as shown above.

nginx needs no change: Puma listens on the same socket,
`tmp/sockets/unicorn.sock`.
