// Package state defines the shared State snapshot and the Bus broadcaster.
// No global mutable state — callers own the Bus instance.
package state

import "sync"

// Phase represents the current voting cycle phase.
type Phase string

const (
	PhaseVoting   Phase = "voting"
	PhaseActive   Phase = "active"
	PhaseCooldown Phase = "cooldown"
)

// State is the full snapshot broadcast to all clients every 250 ms.
type State struct {
	TimerMs    int64          `json:"timer_ms"`
	TimerMaxMs int64          `json:"timer_max_ms"`
	Effect     string         `json:"effect"`
	Votes      map[string]int `json:"votes"`
	Phase      Phase          `json:"phase"`
}

// Bus is a fan-out broadcaster for State snapshots.
type Bus struct {
	mu      sync.RWMutex
	subs    []chan State
	current State
}

// NewBus creates a new Bus.
func NewBus() *Bus {
	return &Bus{}
}

// Subscribe returns a buffered channel that receives every published State.
func (b *Bus) Subscribe() chan State {
	ch := make(chan State, 16)
	b.mu.Lock()
	b.subs = append(b.subs, ch)
	b.mu.Unlock()
	return ch
}

// Unsubscribe removes ch from the bus and closes it.
func (b *Bus) Unsubscribe(ch chan State) {
	b.mu.Lock()
	defer b.mu.Unlock()
	for i, s := range b.subs {
		if s == ch {
			b.subs = append(b.subs[:i], b.subs[i+1:]...)
			close(ch)
			return
		}
	}
}

// Publish broadcasts s to all subscribers (non-blocking, slow consumers are dropped)
// and caches it as the current state.
func (b *Bus) Publish(s State) {
	b.mu.Lock()
	b.current = s
	subs := make([]chan State, len(b.subs))
	copy(subs, b.subs)
	b.mu.Unlock()

	for _, ch := range subs {
		select {
		case ch <- s:
		default:
			// Slow consumer — drop to avoid blocking the aggregator.
		}
	}
}

// Current returns the last published State.
func (b *Bus) Current() State {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.current
}
