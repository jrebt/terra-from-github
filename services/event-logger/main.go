package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/nats-io/nats.go"
)

const (
	streamName   = "EVENTS"
	consumerName = "event-logger"
	maxEvents    = 100
)

type Event struct {
	Name      string `json:"name"`
	Data      string `json:"data"`
	Subject   string `json:"subject,omitempty"`
	Timestamp string `json:"timestamp,omitempty"`
}

type EventStore struct {
	mu     sync.RWMutex
	events []Event
}

func (s *EventStore) Add(e Event) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.events = append(s.events, e)
	if len(s.events) > maxEvents {
		s.events = s.events[len(s.events)-maxEvents:]
	}
}

func (s *EventStore) All() []Event {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Event, len(s.events))
	copy(out, s.events)
	return out
}

var (
	nc    *nats.Conn
	js    nats.JetStreamContext
	store = &EventStore{}
)

func main() {
	natsURL := os.Getenv("NATS_URL")
	if natsURL == "" {
		natsURL = "nats://nats.nats.svc.cluster.local:4222"
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	var err error
	nc, err = nats.Connect(natsURL,
		nats.MaxReconnects(-1),
		nats.ReconnectWait(2*time.Second),
		nats.DisconnectErrHandler(func(_ *nats.Conn, err error) {
			log.Printf("NATS disconnected: %v", err)
		}),
		nats.ReconnectHandler(func(_ *nats.Conn) {
			log.Println("NATS reconnected")
		}),
	)
	if err != nil {
		log.Fatalf("Failed to connect to NATS: %v", err)
	}
	defer nc.Close()
	log.Printf("Connected to NATS at %s", natsURL)

	js, err = nc.JetStream()
	if err != nil {
		log.Fatalf("Failed to get JetStream context: %v", err)
	}

	_, err = js.AddStream(&nats.StreamConfig{
		Name:      streamName,
		Subjects:  []string{"events.>"},
		Storage:   nats.FileStorage,
		MaxAge:    24 * time.Hour,
		Retention: nats.LimitsPolicy,
	})
	if err != nil {
		log.Fatalf("Failed to create stream: %v", err)
	}
	log.Printf("Stream %s ready", streamName)

	go consumeEvents()

	http.HandleFunc("/publish", handlePublish)
	http.HandleFunc("/events", handleEvents)
	http.HandleFunc("/health", handleHealth)

	log.Printf("HTTP server listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func consumeEvents() {
	sub, err := js.Subscribe("events.>", func(msg *nats.Msg) {
		var e Event
		if err := json.Unmarshal(msg.Data, &e); err != nil {
			log.Printf("Failed to unmarshal event: %v", err)
			msg.Ack()
			return
		}
		e.Subject = msg.Subject
		e.Timestamp = time.Now().UTC().Format(time.RFC3339)
		store.Add(e)
		msg.Ack()
	}, nats.Durable(consumerName), nats.DeliverAll())
	if err != nil {
		log.Printf("Failed to subscribe: %v", err)
		return
	}
	defer sub.Unsubscribe()
	select {}
}

func handlePublish(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var e Event
	if err := json.NewDecoder(r.Body).Decode(&e); err != nil {
		http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
		return
	}
	if e.Name == "" {
		http.Error(w, `"name" is required`, http.StatusBadRequest)
		return
	}

	subject := fmt.Sprintf("events.%s", e.Name)
	data, _ := json.Marshal(e)

	_, err := js.Publish(subject, data)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to publish: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "published",
		"subject": subject,
	})
}

func handleEvents(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(store.All())
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":         "ok",
		"nats_connected": nc.IsConnected(),
	})
}
