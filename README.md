# sshitmaids
**SSH** **i**n **t**he **M**iddle **AI** **D**ocker **S**ecurer

## synopsis

SSH to github (or other ssh-based foundry, theoretically, as long as they can
SSH with the username "git") handled by a proxy that keeps user's keys secret in
the proxy server.

## usage

The intention is that you can simply check out this repo and use it as-is after
populating a `.env` file and the volumes.  You can copy from `.env.example` for
your `.env` file.

- Destination user, server, and port is configured with the .env var
  `SSHITMAIDS_DEST`.  eg.: `git@github.com:22`.
- Public port is configured with the .env var `SSHITMAIDS_PORT`
- Use `SSHITMAIDS_GENERATE_CLIENT_CONFIG=true`, which generates file in
  `./volumes/ssh/client/config` with a Host entry for the sshitmaids host, so
  this can be included in users' ssh config.  Assumes the sshitmaids service is
  in the same docker network and reachable at the hostname:port "sshitmaids:22"
- Use `SSHITMAIDS_DO_KEYSCAN=true` to do ssh server keyscan to write
  `./volumes/ssh/sshitmaids/known_hosts`, but github's ssh server keyscan is
  rate-limited so requesting it regularly is pointless.
- SSH keys go in "volumes".
    - `./volumes/ssh/sshitmaids`: SSH Keys for the account that you wish to use
      to connect to the target foundry (eg github).
    - `./volumes/ssh/client`: Public SSH keys for your client that sshitmaids
      will add to `./volumes/ssh/sshitmaids/authorized_keys`
- All SSH keys are assumed to be `id_ed25519` and `id_ed25519.pub`.

Because the client doesn't know that it's being forwarded and the server doesn't
know the original intended destination of the client, `.ssh/config` files are
used to arrange the routing. An optional file can be generated for the client to
use, described above.

Generation is done at build time, run by the makefile (*not* docker build),
changing the .ENV requires rebuild. TODO.

## why name?

I kept making the typo while working on it when it was called "sshitmaids" and
decided to roll with it.

## license

MIT.  See [LICENSE](LICENSE)