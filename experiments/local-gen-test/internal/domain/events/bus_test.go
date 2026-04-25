package events

import (
	"sync"
	"testing"
	"time"
)

func TestBus(t *testing.T) {
	t.Helper()

	t.Run("subscriber receives published event", func(t *testing.T) {
		t.Helper()
		bus := NewBus()
		var received Event
		bus.Subscribe(KindSessionCreated, func(e Event) {
			received = e
		})

		bus.Publish(Event{
			ID:         "e1",
			Kind:       KindSessionCreated,
			SessionID:  "s1",
			OccurredAt: time.Now(),
		})

		if received.Kind != KindSessionCreated {
			t.Errorf("expected KindSessionCreated, got %s", received.Kind)
		}
	})

	t.Run("subscriber only receives subscribed kind", func(t *testing.T) {
		t.Helper()
		bus := NewBus()
		var called bool
		bus.Subscribe(KindSessionCreated, func(e Event) {
			called = true
		})

		bus.Publish(Event{
			ID:         "e2",
			Kind:       KindAgentForked,
			SessionID:  "s1",
			OccurredAt: time.Now(),
		})

		if called {
			t.Error("handler should not be called for unsubscribed kind")
		}
	})

	t.Run("multiple subscribers all receive event", func(t *testing.T) {
		t.Helper()
		bus := NewBus()
		var count int
		mu := sync.Mutex{}
		handler := func(e Event) {
			mu.Lock()
			count++
			mu.Unlock()
		}
		bus.Subscribe(KindSessionCreated, handler)
		bus.Subscribe(KindSessionCreated, handler)

		bus.Publish(Event{
			ID:         "e3",
			Kind:       KindSessionCreated,
			SessionID:  "s1",
			OccurredAt: time.Now(),
		})

		if count != 2 {
			t.Errorf("expected 2 calls, got %d", count)
		}
	})

	t.Run("concurrent publish is safe", func(t *testing.T) {
		t.Helper()
		bus := NewBus()
		var count int
		mu := sync.Mutex{}
		var wg sync.WaitGroup

		bus.Subscribe(KindSessionCreated, func(e Event) {
			mu.Lock()
			count++
			mu.Unlock()
		})

		for i := 0; i < 100; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				bus.Publish(Event{
					ID:         "e",
					Kind:       KindSessionCreated,
					SessionID:  "s1",
					OccurredAt: time.Now(),
				})
			}()
		}
		wg.Wait()

		if count != 100 {
			t.Errorf("expected 100 calls, got %d", count)
		}
	})
}
