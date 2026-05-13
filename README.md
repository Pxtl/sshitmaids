# sshitmaids
**SSH** **i**n **t**he **M**iddle **AI** **D**ocker **S**ecurer

## Synopsis

SSH to github (or other ssh-based foundry, theoretically) handled by a proxy
that keeps user's keys secret in the proxy server.

## Usage

The intention is that you can simply check out this repo and use it as-is after
populating a `.env` file and the volumes.  You can copy from `.env.example` for
your `.env` file.

Example docker compose environment:

```yaml
environment:
  - SSHITMAIDS_DEST=${SSHITMAIDS_DEST:-"git@github.com:22"}
  - GENERATE_CLIENT_CONFIG=${SSHITMAIDS_GENERATE_CLIENT_CONFIG:-"false"}
  - CLIENT_DEST=${SSHITMAIDS_CLIENT_DEST:-"git@sshitmaids:22"}
```

- Destination user, server, and port is configured with the .env var
  `SSHITMAIDS_DEST`.  eg.: `git@github.com:22`.
- Public port is configured with the .env var `SSHITMAIDS_PUBLIC_PORT`
- Use `SSHITMAIDS_GENERATE_CLIENT_CONFIG=true`, which generates config files in
  the `ssh-client` volume using the value from `CLIENT_DEST`, so this can be
  included in the clients' ssh config.  If no `CLIENT_DEST` is provided, it
  assumes sshitmaids is reachable at `git@sshitmaids:22`
- Use `SSHITMAIDS_DO_KEYSCAN=true` to do ssh server keyscan to write
  `known_hosts` in the `sshitmaids` volume, but github's ssh server keyscan is
  rate-limited so requesting it regularly is pointless.

## Volumes

There are two read/write volumes needed by sshitmaids, with example docker compose bindings
below:

```yaml
volumes:
  - ./volumes/sshitmaids:/root/sshitmaids
  - ./volumes/ssh-client:/root/ssh-client
```

- SSH keys go in these volumes.
    - `sshitmaids` volume: SSH Keys for the account that you wish to use to
      connect to the target foundry (eg github).
    - `ssh-client` volume: Public SSH keys for your client that sshitmaids will
      add to `./volumes/ssh/sshitmaids/authorized_keys`, ensuring that only the
      authorized client can access the mitm server.
- All SSH keys are assumed to be `id_ed25519` and `id_ed25519.pub`.

## Reconfiguring sshitmaids

- The volumes are not used live.  Data in the volumes are written into the `.ssh` dirs on the server on startup.  If changes are made to the volumes, the changes can be re-loaded into `.ssh` dirs by calling:

`docker exec sshitmaids /reconfigure`.

## Configuring your Client

Because the client doesn't know that it's being forwarded and the server doesn't
know the original intended destination of the client, `.ssh/config` files are
used to arrange the routing. An optional file can be generated for the client to
use, described above, or the client can be instructed to connect directly to the
`sshitmaids` server (`git@sshitmaids:22` inside the same docker net,
`git@localhost:SSHITMAIDS_PUBLIC_PORT` on the host).

## Why Name?

I kept making the typo while working on it when it was called "ssh-mitm" and
decided to roll with it.

## TODO
- Support more simultaneous targets
- Testing with gitlab
- Automated testing
- Read-only volumes

## License

MIT.  See [LICENSE](LICENSE)