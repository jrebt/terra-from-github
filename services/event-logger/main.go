package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/gorilla/websocket"
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

// WebSocket hub for real-time event broadcasting
type WSHub struct {
	mu      sync.RWMutex
	clients map[*websocket.Conn]bool
}

func (h *WSHub) Add(conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.clients[conn] = true
}

func (h *WSHub) Remove(conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.clients, conn)
	conn.Close()
}

func (h *WSHub) Broadcast(data []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for conn := range h.clients {
		if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
			go h.Remove(conn)
		}
	}
}

var (
	nc       *nats.Conn
	js       nats.JetStreamContext
	store    = &EventStore{}
	wsHub    = &WSHub{clients: make(map[*websocket.Conn]bool)}
	upgrader = websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool { return true },
	}
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

	// Existing endpoints
	http.HandleFunc("/publish", handlePublish)
	http.HandleFunc("/events", handleEvents)
	http.HandleFunc("/health", handleHealth)

	// New JetStream management endpoints
	http.HandleFunc("/api/streams", handleStreams)
	http.HandleFunc("/api/streams/create", handleCreateStream)
	http.HandleFunc("/api/streams/delete", handleDeleteStream)
	http.HandleFunc("/api/consumers", handleConsumers)
	http.HandleFunc("/api/consumers/create", handleCreateConsumer)
	http.HandleFunc("/api/consumers/delete", handleDeleteConsumer)
	http.HandleFunc("/api/publish", handleAPIPublish)
	http.HandleFunc("/api/server", handleServerInfo)

	// WebSocket for real-time events
	http.HandleFunc("/ws", handleWebSocket)

	// Serve static frontend
	http.Handle("/", http.FileServer(http.Dir("static")))

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

		// Broadcast to WebSocket clients
		data, _ := json.Marshal(e)
		wsHub.Broadcast(data)
	}, nats.Durable(consumerName), nats.DeliverAll())
	if err != nil {
		log.Printf("Failed to subscribe: %v", err)
		return
	}
	defer sub.Unsubscribe()
	select {}
}

// --- Existing handlers ---

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

// --- Stream management ---

func handleStreams(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var streams []map[string]interface{}
	for name := range js.StreamNames() {
		info, err := js.StreamInfo(name)
		if err != nil {
			continue
		}
		streams = append(streams, map[string]interface{}{
			"name":       info.Config.Name,
			"subjects":   info.Config.Subjects,
			"storage":    info.Config.Storage.String(),
			"retention":  info.Config.Retention.String(),
			"max_age":    info.Config.MaxAge.String(),
			"max_bytes":  info.Config.MaxBytes,
			"max_msgs":   info.Config.MaxMsgs,
			"messages":   info.State.Msgs,
			"bytes":      info.State.Bytes,
			"consumers":  info.State.Consumers,
			"first_seq":  info.State.FirstSeq,
			"last_seq":   info.State.LastSeq,
			"created":    info.Created.Format(time.RFC3339),
		})
	}
	if streams == nil {
		streams = []map[string]interface{}{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(streams)
}

func handleCreateStream(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Name      string   `json:"name"`
		Subjects  []string `json:"subjects"`
		Storage   string   `json:"storage"`
		MaxAge    string   `json:"max_age"`
		MaxBytes  int64    `json:"max_bytes"`
		MaxMsgs   int64    `json:"max_msgs"`
		Retention string   `json:"retention"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
		return
	}
	if req.Name == "" || len(req.Subjects) == 0 {
		http.Error(w, "name and subjects are required", http.StatusBadRequest)
		return
	}

	storage := nats.FileStorage
	if req.Storage == "memory" {
		storage = nats.MemoryStorage
	}

	retention := nats.LimitsPolicy
	switch req.Retention {
	case "interest":
		retention = nats.InterestPolicy
	case "workqueue":
		retention = nats.WorkQueuePolicy
	}

	maxAge := 24 * time.Hour
	if req.MaxAge != "" {
		if parsed, err := time.ParseDuration(req.MaxAge); err == nil {
			maxAge = parsed
		}
	}

	cfg := &nats.StreamConfig{
		Name:      req.Name,
		Subjects:  req.Subjects,
		Storage:   storage,
		Retention: retention,
		MaxAge:    maxAge,
		MaxBytes:  req.MaxBytes,
		MaxMsgs:   req.MaxMsgs,
	}

	info, err := js.AddStream(cfg)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to create stream: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status": "created",
		"stream": info.Config.Name,
	})
}

func handleDeleteStream(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
		return
	}
	if req.Name == "" {
		http.Error(w, "name is required", http.StatusBadRequest)
		return
	}

	if err := js.DeleteStream(req.Name); err != nil {
		http.Error(w, fmt.Sprintf("Failed to delete stream: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status": "deleted",
		"stream": req.Name,
	})
}

// --- Consumer management ---

func handleConsumers(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	stream := r.URL.Query().Get("stream")
	if stream == "" {
		http.Error(w, "stream query parameter is required", http.StatusBadRequest)
		return
	}

	var consumers []map[string]interface{}
	for name := range js.ConsumerNames(stream) {
		info, err := js.ConsumerInfo(stream, name)
		if err != nil {
			continue
		}
		consumers = append(consumers, map[string]interface{}{
			"name":           info.Config.Durable,
			"stream":         info.Stream,
			"filter_subject": info.Config.FilterSubject,
			"ack_policy":     info.Config.AckPolicy.String(),
			"deliver_policy": info.Config.DeliverPolicy.String(),
			"num_pending":    info.NumPending,
			"num_ack_pending": info.NumAckPending,
			"num_redelivered": info.NumRedelivered,
			"delivered_last":  info.Delivered.Stream,
			"ack_floor":      info.AckFloor.Stream,
			"created":        info.Created.Format(time.RFC3339),
		})
	}
	if consumers == nil {
		consumers = []map[string]interface{}{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(consumers)
}

func handleCreateConsumer(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Stream        string `json:"stream"`
		Name          string `json:"name"`
		FilterSubject string `json:"filter_subject"`
		AckPolicy     string `json:"ack_policy"`
		DeliverPolicy string `json:"deliver_policy"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
		return
	}
	if req.Stream == "" || req.Name == "" {
		http.Error(w, "stream and name are required", http.StatusBadRequest)
		return
	}

	ackPolicy := nats.AckExplicitPolicy
	switch req.AckPolicy {
	case "none":
		ackPolicy = nats.AckNonePolicy
	case "all":
		ackPolicy = nats.AckAllPolicy
	}

	deliverPolicy := nats.DeliverAllPolicy
	switch req.DeliverPolicy {
	case "last":
		deliverPolicy = nats.DeliverLastPolicy
	case "new":
		deliverPolicy = nats.DeliverNewPolicy
	}

	cfg := &nats.ConsumerConfig{
		Durable:       req.Name,
		AckPolicy:     ackPolicy,
		DeliverPolicy: deliverPolicy,
		FilterSubject: req.FilterSubject,
	}

	info, err := js.AddConsumer(req.Stream, cfg)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to create consumer: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":   "created",
		"consumer": info.Config.Durable,
		"stream":   info.Stream,
	})
}

func handleDeleteConsumer(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Stream string `json:"stream"`
		Name   string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
		return
	}
	if req.Stream == "" || req.Name == "" {
		http.Error(w, "stream and name are required", http.StatusBadRequest)
		return
	}

	if err := js.DeleteConsumer(req.Stream, req.Name); err != nil {
		http.Error(w, fmt.Sprintf("Failed to delete consumer: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":   "deleted",
		"consumer": req.Name,
		"stream":   req.Stream,
	})
}

// --- Publish to any subject ---

func handleAPIPublish(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Subject string `json:"subject"`
		Data    string `json:"data"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
		return
	}
	if req.Subject == "" {
		http.Error(w, "subject is required", http.StatusBadRequest)
		return
	}

	ack, err := js.Publish(req.Subject, []byte(req.Data))
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to publish: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":   "published",
		"subject":  req.Subject,
		"stream":   ack.Stream,
		"sequence": ack.Sequence,
	})
}

// --- Server info ---

func handleServerInfo(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	info := map[string]interface{}{
		"connected":  nc.IsConnected(),
		"server_url": nc.ConnectedUrl(),
		"server_id":  nc.ConnectedServerId(),
		"max_payload": nc.MaxPayload(),
	}

	// Count streams and consumers
	streamCount := 0
	consumerCount := 0
	totalMsgs := uint64(0)
	totalBytes := uint64(0)
	for name := range js.StreamNames() {
		streamCount++
		si, err := js.StreamInfo(name)
		if err == nil {
			totalMsgs += si.State.Msgs
			totalBytes += si.State.Bytes
			consumerCount += si.State.Consumers
		}
	}
	info["streams"] = streamCount
	info["consumers"] = consumerCount
	info["total_messages"] = totalMsgs
	info["total_bytes"] = totalBytes

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(info)
}

// --- WebSocket ---

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade failed: %v", err)
		return
	}
	wsHub.Add(conn)
	log.Printf("WebSocket client connected")

	// Keep connection alive, remove on close
	for {
		if _, _, err := conn.ReadMessage(); err != nil {
			wsHub.Remove(conn)
			log.Printf("WebSocket client disconnected")
			break
		}
	}
}
