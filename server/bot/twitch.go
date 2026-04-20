// Package bot implements the Twitch IRC client that forwards !vote commands
// to the vote aggregator.
package bot

import (
	"context"
	"log"
	"strings"

	twitch "github.com/gempir/go-twitch-irc/v4"
)

// VoteCaster is satisfied by *vote.Aggregator.
type VoteCaster interface {
	CastVote(user, effectID string)
}

// TwitchBot connects to Twitch IRC and forwards vote messages to the aggregator.
type TwitchBot struct {
	channel string
	oauth   string
	agg     VoteCaster
}

// NewTwitchBot creates a TwitchBot.
// oauth must be a valid "oauth:..." token loaded from the environment.
func NewTwitchBot(channel, oauth string, agg VoteCaster) *TwitchBot {
	return &TwitchBot{channel: channel, oauth: oauth, agg: agg}
}

// Run connects to Twitch IRC and processes "!vote EFFECT_ID" messages until
// ctx is cancelled. Panics are recovered and logged.
func (b *TwitchBot) Run(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[twitch] recovered from panic: %v", r)
		}
	}()

	client := twitch.NewClient(b.channel, b.oauth)

	client.OnPrivateMessage(func(msg twitch.PrivateMessage) {
		text := strings.TrimSpace(msg.Message)
		// Accept "!vote EFFECT_ID" (case-insensitive prefix)
		const prefix = "!vote "
		if len(text) <= len(prefix) {
			return
		}
		lowered := strings.ToLower(text[:len(prefix)])
		if lowered != prefix {
			return
		}
		effectID := strings.TrimSpace(text[len(prefix):])
		if effectID == "" {
			return
		}
		// Effect IDs are SCREAMING_SNAKE_CASE; normalise to upper
		b.agg.CastVote(msg.User.Name, strings.ToUpper(effectID))
	})

	client.Join(b.channel)

	// Disconnect gracefully when context is cancelled.
	go func() {
		<-ctx.Done()
		client.Disconnect()
	}()

	log.Printf("[twitch] connecting to channel %q", b.channel)
	if err := client.Connect(); err != nil && ctx.Err() == nil {
		log.Printf("[twitch] connection error: %v", err)
	}
}
