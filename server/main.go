// LiveChaos-IV Go Server
// Entry point: loads config, wires components, runs until SIGINT/SIGTERM.
package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/BurntSushi/toml"
	"github.com/gabryel-lima/livechaos-iv/server/bot"
	"github.com/gabryel-lima/livechaos-iv/server/ipc"
	"github.com/gabryel-lima/livechaos-iv/server/overlay"
	"github.com/gabryel-lima/livechaos-iv/server/state"
	"github.com/gabryel-lima/livechaos-iv/server/vote"
)

// Config mirrors config.toml.
type Config struct {
	Twitch struct {
		Channel    string `toml:"channel"`
		OAuthToken string `toml:"oauth_token"`
	} `toml:"twitch"`
	YouTube struct {
		Enabled     bool   `toml:"enabled"`
		LiveVideoID string `toml:"live_video_id"`
		APIKey      string `toml:"api_key"`
	} `toml:"youtube"`
	Timer struct {
		VoteDurationS     int `toml:"vote_duration_s"`
		CooldownDurationS int `toml:"cooldown_duration_s"`
	} `toml:"timer"`
	Effects struct {
		Pool []string `toml:"pool"`
	} `toml:"effects"`
	Server struct {
		WSPort   int    `toml:"ws_port"`
		PipeName string `toml:"pipe_name"`
	} `toml:"server"`
}

func loadConfig(path string) (Config, error) {
	var cfg Config
	if _, err := toml.DecodeFile(path, &cfg); err != nil {
		return cfg, err
	}
	return cfg, nil
}

func main() {
	cfgPath := "config.toml"
	if len(os.Args) > 1 {
		cfgPath = os.Args[1]
	}

	cfg, err := loadConfig(cfgPath)
	if err != nil {
		log.Fatalf("[main] config: %v", err)
	}

	// Credentials must come from the environment — never from source files.
	oauth := os.Getenv("TWITCH_OAUTH")
	if oauth == "" {
		log.Fatal("[main] TWITCH_OAUTH environment variable is required")
	}
	cfg.Twitch.OAuthToken = oauth

	// YouTube API key from environment (optional; only required when youtube.enabled = true).
	if ytKey := os.Getenv("YOUTUBE_API_KEY"); ytKey != "" {
		cfg.YouTube.APIKey = ytKey
	}
	if cfg.YouTube.Enabled && cfg.YouTube.APIKey == "" {
		log.Fatal("[main] youtube.enabled is true but YOUTUBE_API_KEY env var is not set")
	}
	if cfg.YouTube.Enabled && cfg.YouTube.LiveVideoID == "" {
		log.Fatal("[main] youtube.enabled is true but youtube.live_video_id is not set in config.toml")
	}

	if cfg.Twitch.Channel == "" {
		log.Fatal("[main] twitch.channel must be set in config.toml")
	}
	if len(cfg.Effects.Pool) == 0 {
		log.Fatal("[main] effects.pool must contain at least one effect ID")
	}

	cycleDur := time.Duration(cfg.Timer.VoteDurationS) * time.Second
	cooldownDur := time.Duration(cfg.Timer.CooldownDurationS) * time.Second

	ctx, cancel := context.WithCancel(context.Background())

	// Graceful shutdown on SIGINT / SIGTERM.
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		sig := <-sigs
		log.Printf("[main] received %s, shutting down", sig)
		cancel()
	}()

	bus := state.NewBus()

	agg := vote.NewAggregator(cfg.Effects.Pool, cycleDur, cooldownDur, bus)

	wsSrv := overlay.NewWSServer(cfg.Server.WSPort, bus)
	go wsSrv.Run(ctx)

	pipeSrv := ipc.NewPipeServer(cfg.Server.PipeName, bus)
	go pipeSrv.Run(ctx)

	twitchBot := bot.NewTwitchBot(cfg.Twitch.Channel, cfg.Twitch.OAuthToken, agg)
	go twitchBot.Run(ctx)

	if cfg.YouTube.Enabled {
		youtubeBot := bot.NewYouTubeBot(cfg.YouTube.APIKey, cfg.YouTube.LiveVideoID, agg)
		go youtubeBot.Run(ctx)
		log.Println("[main] YouTube Live Chat bot started")
	}

	log.Println("[main] LiveChaos-IV server started")
	agg.Run(ctx) // blocks
	log.Println("[main] server stopped")
}
