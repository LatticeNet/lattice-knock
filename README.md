# lattice-knock

A small UDP port-knock client for [Lattice](https://github.com/LatticeNet) SSH Guard, with an installer that also works where GitHub is hard to reach.

SSH Guard can close a node's SSH port behind a knock gate: the port opens for a source address after that address sends the right UDP sequence. The Lattice console reveals the sequence and a command such as:

```sh
knock -u -d 500 203.0.113.9 23853 36932 24556 && ssh -p 58394 root@203.0.113.9
```

That is the argument shape of the packaged `knock` client from knockd. This client takes the same arguments, so the copied command works whichever `knock` your PATH finds, and it adds the checks that make a knock fail loudly instead of quietly opening nothing.

## Install

From GitHub:

```sh
curl -fsSL https://raw.githubusercontent.com/LatticeNet/lattice-knock/v0.1.0-alpha.2/install.sh | sh
```

From your Lattice control plane, for networks that cannot reach GitHub. A Lattice server serves the client it was released with at `/tools/knock/`, and its `install.sh` already names that server and the client's sha256:

```sh
curl -fsSL https://lattice.example.com/tools/knock/install.sh | sh
```

Through a GitHub mirror, with the sha256 from the Lattice console or the release page:

```sh
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/LatticeNet/lattice-knock/v0.1.0-alpha.2/install.sh \
  | sh -s -- --github-mirror https://ghfast.top/ --sha256 <hash>
```

What the checks are worth: the installer compares the download with `SHA256SUMS` from the same place, which catches corruption in transit but not a source that lies. `--sha256` is the check that holds against a mirror or server serving wrong bytes. The installer says so when you install through a mirror, a control plane or wget without it.

The installer puts `knock` in `~/.local/bin` (`--dir` to change, `--name` to install under another name) and refuses to replace an existing `knock` it did not install (`--force` to replace it anyway). `install.sh --help` lists every option; `install.sh --uninstall` removes the client.

Requirements: bash, and curl or wget.

## Use

```sh
knock [-u] [-d MS] [-v] HOST PORT PORT PORT     # the packaged client's form
knock [-d MS] HOST PORT,PORT,PORT               # one comma list
knock HOST                                      # sequence from the config file
```

`HOST` may be an ssh alias: the client asks `ssh -G` for the real hostname, resolves it to IPv4 itself, and knocks that address.

The config file is `~/.config/lattice/knock.conf` (`KNOCK_CONF` to change), one host per line:

```
# host-or-alias  sequence
prod-hk          23853,36932,24556
```

Keep it readable only by you (`chmod 600`): a sequence is a credential.

## What it checks

- Knocks are UDP only and every datagram carries one byte. An unanswered TCP knock is retransmitted by the kernel, so knockd sees the same port twice and never advances; an empty datagram does not open the gate.
- A sequence has exactly three ports, the length Lattice SSH Guard uses (`KNOCK_PORTS` to change). A trailing comma drops a port, and a short sequence would otherwise report success and leave the port shut.
- The gate admits IPv4 sources only, so `-6` is refused and names resolve to IPv4.
- The sequence is never printed, not even with `-v`.
- When the client knows the ssh port, it waits for the ssh server's identification line after the knock and exits 4 if none comes within five seconds (`KNOCK_CHECK_TIMEOUT`). It knows the port when `HOST` is an ssh alias whose entry in `~/.ssh/config` sets the hostname or the port (not behind `ProxyJump` or `ProxyCommand`, where ssh never dials the target from here), or when you pass `-c PORT`. `--no-check` skips it. A knock can arrive and still open nothing for you: a carrier NAT that sends UDP and TCP from different public addresses opens the gate for the knock's address while ssh connects from the other. A TCP connect alone would not catch this, because a proxy client's TUN completes the handshake itself and closes only once its upstream fails, so the client waits for the banner. With the check, `knock prod && ssh prod` stops with a sentence instead of hanging.

## Where a sequence can still end up

- **Shell history.** Ports typed on the command line are saved with the command. The client notes this each time (`KNOCK_QUIET=1` hides the note). The config file keeps them out of history; so does a leading space in bash with `HISTCONTROL=ignorespace` or zsh with `setopt HIST_IGNORE_SPACE`.
- **Process listings and execve audit logs.** The client sends through bash's `/dev/udp` by default, from inside its own process, so no child process carries a port in its arguments. `KNOCK_SENDER=nc` uses nc instead, where each port is visible in `ps` for about a second and in any execve audit log for good.

Knock from the address you will connect from. The gate opens for the source the knock arrived from, so a knock through one proxy and an ssh through another opens a door you are not standing at. `KNOCK_BEFORE` runs a command before any packet leaves, with the host and the resolved address as arguments, and a non-zero exit stops the knock; use it for a local check such as which route those packets will take.

## Develop

```sh
bash tests/run.sh          # needs Python 3 for the packet and installer tests
shellcheck knock install.sh tests/run.sh
```

Releases are tags `vX.Y.Z-alpha.N`. The release workflow checks that the tag matches `KNOCK_VERSION` in `knock` and `KNOCK_RELEASE` in `install.sh`, runs shellcheck and the tests, and publishes `knock`, `install.sh` and `SHA256SUMS` as release assets.

## License

MIT
