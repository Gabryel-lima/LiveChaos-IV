// Package bot — YouTube Live Chat polling bot.
// Polls the YouTube Data API v3 for live chat messages and forwards
// "!vote EFFECT_ID" messages to the vote aggregator.
//
// Requires env var YOUTUBE_API_KEY.
// The live video ID is configured in config.toml [youtube] live_video_id.
package bot

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const youtubeAPIBase = "https://www.googleapis.com/youtube/v3"

// YouTubeBot polls YouTube Live Chat and forwards votes to the aggregator.
type YouTubeBot struct {
	apiKey      string
	liveVideoID string
	agg         VoteCaster
}

// NewYouTubeBot creates a YouTubeBot.
// apiKey must be a YouTube Data API v3 key loaded from the environment.
func NewYouTubeBot(apiKey, liveVideoID string, agg VoteCaster) *YouTubeBot {
	return &YouTubeBot{apiKey: apiKey, liveVideoID: liveVideoID, agg: agg}
}

// Run fetches the live chat ID then polls for messages until ctx is cancelled.
// Panics are recovered and logged; network errors are retried with backoff.
func (b *YouTubeBot) Run(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[youtube] recovered from panic: %v", r)
		}
	}()

	chatID, err := b.getLiveChatID(ctx)
	if err != nil {
		log.Printf("[youtube] could not get live chat ID: %v", err)
		return
	}
	log.Printf("[youtube] live chat ID: %s", chatID)

	b.pollLoop(ctx, chatID)
}

// getLiveChatID fetches the activeLiveChatId for the configured video.
func (b *YouTubeBot) getLiveChatID(ctx context.Context) (string, error) {
	params := url.Values{
		"part": {"liveStreamingDetails"},
		"id":   {b.liveVideoID},
		"key":  {b.apiKey},
	}
	endpoint := fmt.Sprintf("%s/videos?%s", youtubeAPIBase, params.Encode())

	var result struct {
		Items []struct {
			LiveStreamingDetails struct {
				ActiveLiveChatId string `json:"activeLiveChatId"`
			} `json:"liveStreamingDetails"`
		} `json:"items"`
	}
	if err := b.get(ctx, endpoint, &result); err != nil {
		return "", err
	}
	if len(result.Items) == 0 || result.Items[0].LiveStreamingDetails.ActiveLiveChatId == "" {
		return "", fmt.Errorf("no active live chat found for video %q", b.liveVideoID)
	}
	return result.Items[0].LiveStreamingDetails.ActiveLiveChatId, nil
}

// pollLoop continuously polls the live chat, calling CastVote for each message.
func (b *YouTubeBot) pollLoop(ctx context.Context, chatID string) {
	pageToken := ""
	backoff := 5 * time.Second

	for {
		if ctx.Err() != nil {
			return
		}

		interval, nextToken, err := b.fetchMessages(ctx, chatID, pageToken)
		if err != nil {
			log.Printf("[youtube] fetch error: %v — retrying in %s", err, backoff)
			select {
			case <-ctx.Done():
				return
			case <-time.After(backoff):
				backoff = min(backoff*2, 60*time.Second)
				continue
			}
		}
		backoff = 5 * time.Second
		pageToken = nextToken

		// Respect the polling interval returned by the API (minimum 1 s).
		if interval < time.Second {
			interval = time.Second
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(interval):
		}
	}
}

// fetchMessages retrieves one page of live chat messages and forwards votes.
// Returns the recommended polling interval and the next page token.
func (b *YouTubeBot) fetchMessages(ctx context.Context, chatID, pageToken string) (time.Duration, string, error) {
	params := url.Values{
		"liveChatId": {chatID},
		"part":       {"snippet,authorDetails"},
		"maxResults": {"200"},
		"key":        {b.apiKey},
	}
	if pageToken != "" {
		params.Set("pageToken", pageToken)
	}
	endpoint := fmt.Sprintf("%s/liveChat/messages?%s", youtubeAPIBase, params.Encode())

	var result struct {
		NextPageToken           string `json:"nextPageToken"`
		PollingIntervalMillis   int64  `json:"pollingIntervalMillis"`
		Items                   []struct {
			AuthorDetails struct {
				DisplayName string `json:"displayName"`
			} `json:"authorDetails"`
			Snippet struct {
				DisplayMessage string `json:"displayMessage"`
			} `json:"snippet"`
		} `json:"items"`
	}
	if err := b.get(ctx, endpoint, &result); err != nil {
		return 0, "", err
	}

	for _, item := range result.Items {
		user := item.AuthorDetails.DisplayName
		text := strings.TrimSpace(item.Snippet.DisplayMessage)

		// Accept "!vote EFFECT_ID"
		const prefix = "!vote "
		if len(text) <= len(prefix) {
			continue
		}
		if strings.ToLower(text[:len(prefix)]) != prefix {
			continue
		}
		effectID := strings.ToUpper(strings.TrimSpace(text[len(prefix):]))
		if effectID != "" {
			b.agg.CastVote(user, effectID)
		}
	}

	interval := time.Duration(result.PollingIntervalMillis) * time.Millisecond
	return interval, result.NextPageToken, nil
}

// get performs a GET request and decodes the JSON response into dst.
func (b *YouTubeBot) get(ctx context.Context, endpoint string, dst any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, body)
	}
	return json.NewDecoder(resp.Body).Decode(dst)
}

func min(a, b time.Duration) time.Duration {
	if a < b {
		return a
	}
	return b
}
