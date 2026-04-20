module github.com/gabryel-lima/livechaos-iv/server

go 1.22

require (
	github.com/BurntSushi/toml v1.3.2
	github.com/Microsoft/go-winio v0.6.2
	github.com/gempir/go-twitch-irc/v4 v4.0.0
	github.com/gorilla/websocket v1.5.1
)

require golang.org/x/sys v0.18.0 // indirect

// YouTube Data API v3 — used by server/bot/youtube.go
// No extra Go module needed: uses only net/http + encoding/json (stdlib).
