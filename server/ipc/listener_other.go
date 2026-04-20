//go:build !windows

package ipc

import (
	"fmt"
	"net"
)

// listenWindowsPipe is a stub on non-Windows platforms.
// The caller in pipe.go falls back to a Unix socket before reaching this.
func listenWindowsPipe(_ string) (net.Listener, error) {
	return nil, fmt.Errorf("named pipes are only supported on Windows")
}
