package events

import (
	"sync"
)

type Handler func(Event)

type Bus struct {
	mu       sync.RWMutex
	handlers map[EventKind][]Handler
}

func NewBus() *Bus {
	return &Bus{handlers: make(map[EventKind][]Handler)}
}

func (b *Bus) Subscribe(kind EventKind, h Handler) {
	b.mu.Lock()
	b.handlers[kind] = append(b.handlers[kind], h)
	b.mu.Unlock()
}

func (b *Bus) Publish(e Event) {
	b.mu.RLock()
	handlers := make([]Handler, len(b.handlers[e.Kind]))
	copy(handlers, b.handlers[e.Kind])
	b.mu.RUnlock()

	for _, h := range handlers {
		h(e)
	}
}
