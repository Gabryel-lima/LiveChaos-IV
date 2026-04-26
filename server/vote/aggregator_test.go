package vote

import (
	"testing"
	"time"

	"github.com/gabryel-lima/livechaos-iv/server/state"
)

func newTestAggregator() *Aggregator {
	return NewAggregator([]string{"EFFECT_A", "EFFECT_B"}, 30*time.Second, 10*time.Second, state.NewBus())
}

func TestCastVote_AllowsOnlyOneVotePerNormalizedUser(t *testing.T) {
	agg := newTestAggregator()

	agg.CastVote("Gabry", "EFFECT_A")
	agg.CastVote(" @gabry ", "EFFECT_B")

	if got := agg.votes["EFFECT_A"]; got != 1 {
		t.Fatalf("expected EFFECT_A to have 1 vote, got %d", got)
	}
	if got := agg.votes["EFFECT_B"]; got != 0 {
		t.Fatalf("expected EFFECT_B to have 0 vote, got %d", got)
	}
	if len(agg.voters) != 1 {
		t.Fatalf("expected one unique voter, got %d", len(agg.voters))
	}
}

func TestCastVote_SpamControlBlocksBurstAttempts(t *testing.T) {
	agg := newTestAggregator()
	user := "spam_user"

	for i := 0; i < spamMaxAttempts+1; i++ {
		agg.CastVote(user, "INVALID_EFFECT")
	}

	agg.CastVote(user, "EFFECT_A")
	if got := agg.votes["EFFECT_A"]; got != 0 {
		t.Fatalf("expected blocked user vote to be dropped, got %d", got)
	}

	if until, ok := agg.spamBlock[user]; !ok || !until.After(time.Now()) {
		t.Fatalf("expected user to be temporarily blocked for spam")
	}

	agg.CastVote("normal_user", "EFFECT_A")
	if got := agg.votes["EFFECT_A"]; got != 1 {
		t.Fatalf("expected normal user vote to count, got %d", got)
	}
}
