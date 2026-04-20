// Package ipc implements the named-pipe server that writes state messages to
// the C# GTA IV mod (pipe client).
//
// On Windows: creates \\.\pipe\LiveChaosIV (or the name from config).
// On Linux/macOS (dev): falls back to a Unix domain socket at /tmp/livechaos.sock.
package ipc

import (
	"context"
	"encoding/json"
	"log"
	"net"
	"os"
	"runtime"

	"github.com/gabryel-lima/livechaos-iv/server/state"
)

// pipeMsg is the newline-delimited JSON format sent over the pipe.
type pipeMsg struct {
	Type       string `json:"type"`
	ID         string `json:"id,omitempty"`
	DurationMs int64  `json:"duration_ms,omitempty"`
	RemMs      int64  `json:"remaining_ms,omitempty"`
}

// PipeServer writes state messages to connected C# mod clients.
type PipeServer struct {
	pipeName string
	bus      *state.Bus
}

// NewPipeServer creates a PipeServer.
func NewPipeServer(pipeName string, bus *state.Bus) *PipeServer {
	return &PipeServer{pipeName: pipeName, bus: bus}
}

// Run starts listening and handles each client in its own goroutine.
// Blocks until ctx is cancelled. Panics are recovered and logged.
func (p *PipeServer) Run(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[ipc] recovered from panic: %v", r)
		}
	}()

	ln, err := p.listen()
	if err != nil {
		log.Printf("[ipc] listen error: %v", err)
		return
	}
	defer ln.Close()

	// Close listener when ctx is cancelled to unblock Accept.
	go func() {
		<-ctx.Done()
		ln.Close()
	}()

	log.Printf("[ipc] listening (platform=%s)", runtime.GOOS)
	for {
		conn, err := ln.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return // context cancelled
			}
			log.Printf("[ipc] accept error: %v", err)
			continue
		}
		go p.handleConn(ctx, conn)
	}
}

func (p *PipeServer) listen() (net.Listener, error) {
	if runtime.GOOS == "windows" {
		return listenWindowsPipe(p.pipeName)
	}
	const sockPath = "/tmp/livechaos.sock"
	_ = os.Remove(sockPath)
	return net.Listen("unix", sockPath)
}

// handleConn subscribes to the bus and forwards typed messages to the client.
func (p *PipeServer) handleConn(ctx context.Context, conn net.Conn) {
	defer conn.Close()
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[ipc] conn panic: %v", r)
		}
	}()

	ch := p.bus.Subscribe()
	defer p.bus.Unsubscribe(ch)

	enc := json.NewEncoder(conn)

	var prev state.State
	for {
		select {
		case <-ctx.Done():
			return
		case s, ok := <-ch:
			if !ok {
				return
			}
			msgs := buildMessages(prev, s)
			for _, m := range msgs {
				if err := enc.Encode(m); err != nil {
					log.Printf("[ipc] write error: %v", err)
					return
				}
			}
			prev = s
		}
	}
}

// buildMessages converts a state transition into one or more typed pipe messages.
func buildMessages(prev, curr state.State) []pipeMsg {
	var out []pipeMsg

	// New effect started → send "effect" command to the mod
	if curr.Phase == state.PhaseActive && prev.Phase != state.PhaseActive && curr.Effect != "" {
		out = append(out, pipeMsg{
			Type:       "effect",
			ID:         curr.Effect,
			DurationMs: curr.TimerMaxMs,
		})
	}

	// Timer update every tick
	out = append(out, pipeMsg{
		Type:  "timer",
		RemMs: curr.TimerMs,
	})

	// Cooldown begins → tell the mod to reset
	if curr.Phase == state.PhaseCooldown && prev.Phase != state.PhaseCooldown {
		out = append(out, pipeMsg{Type: "reset"})
	}

	return out
}
