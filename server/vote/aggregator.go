// Package vote implements the vote aggregator and cycle timer.
// No global mutable state — all state is encapsulated in Aggregator.
package vote

import (
	"context"
	"math/rand"
	"sync"
	"time"

	"github.com/gabryel-lima/livechaos-iv/server/state"
)

// Aggregator counts votes, runs the cycle timer, and publishes results to state.Bus.
type Aggregator struct {
	mu          sync.Mutex
	votes       map[string]int
	voters      map[string]bool
	pool        []string
	cycleDur    time.Duration
	cooldownDur time.Duration
	bus         *state.Bus
}

// NewAggregator creates an Aggregator ready to run.
func NewAggregator(pool []string, cycleDur, cooldownDur time.Duration, bus *state.Bus) *Aggregator {
	return &Aggregator{
		votes:       make(map[string]int),
		voters:      make(map[string]bool),
		pool:        pool,
		cycleDur:    cycleDur,
		cooldownDur: cooldownDur,
		bus:         bus,
	}
}

// CastVote registers one vote per user per cycle.
// effectID must be in the pool; duplicate votes from the same user are silently dropped.
func (a *Aggregator) CastVote(user, effectID string) {
	a.mu.Lock()
	defer a.mu.Unlock()

	if a.voters[user] {
		return
	}
	for _, e := range a.pool {
		if e == effectID {
			a.voters[user] = true
			a.votes[effectID]++
			return
		}
	}
}

// Run starts the voting cycle loop. Blocks until ctx is cancelled.
// Every goroutine panic is recovered and logged.
func (a *Aggregator) Run(ctx context.Context) {
	for {
		// Voting phase — collect votes, tick timer
		if !a.runPhase(ctx, state.PhaseVoting, a.cycleDur, "") {
			return
		}

		winner := a.selectWinner()
		a.reset()

		// Active phase — apply the chosen effect
		if !a.runPhase(ctx, state.PhaseActive, a.cycleDur, winner) {
			return
		}

		// Cooldown phase — brief pause before next round
		if !a.runPhase(ctx, state.PhaseCooldown, a.cooldownDur, "") {
			return
		}
	}
}

// runPhase ticks every 250 ms for dur, publishing State snapshots to the bus.
// Returns true when the phase completes normally; false if ctx was cancelled.
func (a *Aggregator) runPhase(ctx context.Context, phase state.Phase, dur time.Duration, effect string) bool {
	deadline := time.Now().Add(dur)
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return false
		case now := <-ticker.C:
			rem := deadline.Sub(now)
			if rem < 0 {
				rem = 0
			}

			a.mu.Lock()
			votes := make(map[string]int, len(a.votes))
			for k, v := range a.votes {
				votes[k] = v
			}
			a.mu.Unlock()

			a.bus.Publish(state.State{
				TimerMs:    rem.Milliseconds(),
				TimerMaxMs: dur.Milliseconds(),
				Effect:     effect,
				Votes:      votes,
				Phase:      phase,
			})

			if rem == 0 {
				return true
			}
		}
	}
}

// selectWinner returns the effectID with the most votes.
// Ties are broken randomly. If no votes were cast, returns a random pool entry.
func (a *Aggregator) selectWinner() string {
	a.mu.Lock()
	defer a.mu.Unlock()

	if len(a.votes) == 0 {
		if len(a.pool) == 0 {
			return ""
		}
		return a.pool[rand.Intn(len(a.pool))]
	}

	var (
		maxVotes int
		winners  []string
	)
	for id, count := range a.votes {
		if count > maxVotes {
			maxVotes = count
			winners = []string{id}
		} else if count == maxVotes {
			winners = append(winners, id)
		}
	}
	return winners[rand.Intn(len(winners))]
}

func (a *Aggregator) reset() {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.votes = make(map[string]int)
	a.voters = make(map[string]bool)
}
