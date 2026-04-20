// Package overlay implements the WebSocket server and HTTP /state endpoint
// consumed by the OBS Lua overlay script.
package overlay

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"sync"

	"github.com/gabryel-lima/livechaos-iv/server/state"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

// WSServer broadcasts State snapshots over WebSocket and serves GET /state.
type WSServer struct {
	port int
	bus  *state.Bus
	mu   sync.Mutex
	conns map[*websocket.Conn]struct{}
}

// NewWSServer creates a WSServer on the given port.
func NewWSServer(port int, bus *state.Bus) *WSServer {
	return &WSServer{
		port:  port,
		bus:   bus,
		conns: make(map[*websocket.Conn]struct{}),
	}
}

// Run starts the HTTP server and the broadcast loop. Blocks until ctx is cancelled.
// Panics are recovered and logged.
func (s *WSServer) Run(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[overlay] recovered from panic: %v", r)
		}
	}()

	mux := http.NewServeMux()
	mux.HandleFunc("/ws", s.handleWS)
	mux.HandleFunc("/state", s.handleState)

	srv := &http.Server{
		Addr:    fmt.Sprintf(":%d", s.port),
		Handler: mux,
	}

	ln, err := net.Listen("tcp", srv.Addr)
	if err != nil {
		log.Printf("[overlay] listen error: %v", err)
		return
	}

	go func() {
		<-ctx.Done()
		srv.Close()
	}()

	// Subscribe to the bus and broadcast to all WS clients.
	ch := s.bus.Subscribe()
	go s.broadcastLoop(ctx, ch)

	log.Printf("[overlay] listening on ws://localhost:%d/ws and http://localhost:%d/state", s.port, s.port)
	if err := srv.Serve(ln); err != nil && ctx.Err() == nil {
		log.Printf("[overlay] server error: %v", err)
	}
	s.bus.Unsubscribe(ch)
}

// handleWS upgrades the connection to WebSocket and sends the current state
// immediately, then waits for the broadcast loop to push updates.
func (s *WSServer) handleWS(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[overlay] upgrade error: %v", err)
		return
	}

	// Send the current state on connect.
	cur := s.bus.Current()
	if data, err := json.Marshal(cur); err == nil {
		conn.WriteMessage(websocket.TextMessage, data)
	}

	s.mu.Lock()
	s.conns[conn] = struct{}{}
	s.mu.Unlock()

	// Read pump: discard incoming frames, detect close.
	for {
		if _, _, err := conn.ReadMessage(); err != nil {
			break
		}
	}

	s.mu.Lock()
	delete(s.conns, conn)
	s.mu.Unlock()
	conn.Close()
}

// handleState serves the current State as JSON for HTTP polling (OBS Lua fallback).
func (s *WSServer) handleState(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	cur := s.bus.Current()
	if err := json.NewEncoder(w).Encode(cur); err != nil {
		log.Printf("[overlay] /state encode error: %v", err)
	}
}

// broadcastLoop forwards every bus tick to all connected WebSocket clients.
func (s *WSServer) broadcastLoop(ctx context.Context, ch chan state.State) {
	for {
		select {
		case <-ctx.Done():
			return
		case snap, ok := <-ch:
			if !ok {
				return
			}
			data, err := json.Marshal(snap)
			if err != nil {
				log.Printf("[overlay] marshal error: %v", err)
				continue
			}
			s.mu.Lock()
			for conn := range s.conns {
				if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
					conn.Close()
					delete(s.conns, conn)
				}
			}
			s.mu.Unlock()
		}
	}
}
