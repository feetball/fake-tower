# Dedicated server

A dedicated server runs the lobby and the simulation without being a player: it
has no role, aircraft or microphone, and it relays the radio and voice. Use it
when nobody in the group can host. That covers browser players, who cannot
host, and phones, which usually cannot accept inbound connections.

## Run

```sh
godot --headless --path game res://core/net/server.tscn -- --server
```

The scene argument is optional. Without it, Godot loads the game's main scene
and the server swaps it out at startup. With it, the menu is never loaded.
An export that has the `dedicated_server` feature tag runs as a server without
`--server`.

| Option | Default | |
|---|---|---|
| `--port=<p>` | 27270 | ENet, **UDP**: desktop and mobile clients |
| `--ws-port=<p>` | 27271 (or `--port`+1) | WebSocket, **TCP**: browsers, and anyone behind a proxy. `0` turns it off |
| `--min-players=<n>` | 4 | players needed to start (1–8) |
| `--autostart-at=<n>` | off | start the round by itself once n players are in (never below `--min-players`), and return to the lobby `--lobby-after` seconds after the end |
| `--lobby-after=<sec>` | 15 | see above |

When `--autostart-at` is off, the first player to join is the **lobby leader**.
They see Start Round in the lobby and Back to lobby on the end screen. If the
leader leaves, the next player in join order takes over. The leader can still
start early when `--autostart-at` is set. When everyone has left, the room
resets to an empty lobby.

The server prints one `[server] …` line per lobby change, round start (with
roles) and round end (with the winner). Because the frame rate is capped at
30 fps, the server uses little CPU; the simulation runs at 10 Hz. To keep it
running, use systemd or similar:

```ini
# /etc/systemd/system/fake-tower.service
[Service]
ExecStart=/opt/godot/godot --headless --path /opt/fake-tower/game res://core/net/server.tscn -- --server
Restart=always
User=faketower
```

## Ports and what joins where

| Client | Types in the join box | Reaches |
|---|---|---|
| Desktop / phone app | `server.example.org` or `server.example.org:27270` | UDP 27270 (ENet) |
| Browser, page on `http://` | `server.example.org` | `ws://server.example.org:27271` |
| Browser, page on `https://` | `server.example.org` or `wss://server.example.org` | `wss://…:443`, through the TLS proxy below |
| Anyone | `ws://…` or `wss://…` URL | that URL as written |

Open UDP 27270 and TCP 27271 in the firewall. If TLS is in front, open TCP 443
instead of exposing 27271. Browser pages served over https may only open
`wss://` (TLS) connections, so they need the proxy below.

## TLS reverse proxy (Caddy) for wss://

Caddy obtains a certificate automatically and passes WebSocket upgrades through
with a plain `reverse_proxy`:

```caddy
# /etc/caddy/Caddyfile
tower.example.org {
	reverse_proxy 127.0.0.1:27271
}
```

Web players then join `wss://tower.example.org`, or just type
`tower.example.org` on an https page. To share a host name with other sites,
put the server under a path:

```caddy
example.org {
	handle_path /tower* {
		reverse_proxy 127.0.0.1:27271
	}
	# … other routes
}
```

With this setup, players join `wss://example.org/tower`.

Start the server with `--ws-port=27271` (the default). If the proxy is the only
way in, firewall 27271 from outside. Desktop and phone apps can keep using UDP
27270 directly, or join the same `wss://` URL.

A web build can be pointed at the server from a link:
`https://example.org/play/?join=wss://example.org/tower&name=Ann`.
