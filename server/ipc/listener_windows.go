//go:build windows

package ipc

import (
	"net"

	winio "github.com/Microsoft/go-winio"
)

// listenWindowsPipe creates the named pipe using go-winio.
func listenWindowsPipe(name string) (net.Listener, error) {
	return winio.ListenPipe(name, nil)
}
