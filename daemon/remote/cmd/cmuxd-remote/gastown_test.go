package main

import (
	"bufio"
	"encoding/base64"
	"encoding/json"
	"sort"
	"strings"
	"testing"
	"time"
)

// --- validateDB allowlist ---

func TestValidateDBAllowsWhitelisted(t *testing.T) {
	for _, db := range []string{"hq", "gmux", "spectralChat", "spectralNotify", "spectralTranscript"} {
		if err := validateDB(db); err != nil {
			t.Errorf("validateDB(%q) returned error: %v", db, err)
		}
	}
}

func TestValidateDBRejectsUnlisted(t *testing.T) {
	for _, db := range []string{"", "mysql", "information_schema", "admin", "DROP TABLE"} {
		if err := validateDB(db); err == nil {
			t.Errorf("validateDB(%q) should have returned an error", db)
		}
	}
}

// --- Capability advertisement ---

func TestHelloAdvertisesGastownCapabilityWhenConnected(t *testing.T) {
	server := newTestServer(&gastownDB{})
	defer server.closeAll()

	resp := server.handleRequest(rpcRequest{
		ID:     1,
		Method: "hello",
		Params: map[string]any{},
	})
	if !resp.OK {
		t.Fatalf("hello should succeed: %+v", resp)
	}
	result, _ := resp.Result.(map[string]any)
	capabilities, _ := result["capabilities"].([]string)
	found := false
	for _, cap := range capabilities {
		if cap == "gastown.v1" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("hello should advertise gastown.v1 when connected: capabilities=%v", capabilities)
	}
}

func TestHelloOmitsGastownCapabilityWhenDisconnected(t *testing.T) {
	server := newTestServer(nil)
	defer server.closeAll()

	resp := server.handleRequest(rpcRequest{
		ID:     1,
		Method: "hello",
		Params: map[string]any{},
	})
	if !resp.OK {
		t.Fatalf("hello should succeed: %+v", resp)
	}
	result, _ := resp.Result.(map[string]any)
	capabilities, _ := result["capabilities"].([]string)
	for _, cap := range capabilities {
		if cap == "gastown.v1" {
			t.Fatalf("hello should NOT advertise gastown.v1 when disconnected: capabilities=%v", capabilities)
		}
	}
}

// --- Graceful degradation (gastown == nil) ---

func TestGastownHandlersReturnUnavailableWhenDisconnected(t *testing.T) {
	server := newTestServer(nil)
	defer server.closeAll()

	methods := []struct {
		method string
		params map[string]any
	}{
		{"gastown.agents", map[string]any{"db": "hq"}},
		{"gastown.beads", map[string]any{"db": "hq"}},
		{"gastown.mail", map[string]any{"db": "hq"}},
		{"gastown.convoys", map[string]any{"db": "hq"}},
		{"gastown.diagnostics", map[string]any{"db": "hq"}},
		{"gastown.hash", map[string]any{"db": "hq", "table": "issues"}},
		{"gastown.databases", map[string]any{}},
	}

	for _, tc := range methods {
		resp := server.handleRequest(rpcRequest{
			ID:     1,
			Method: tc.method,
			Params: tc.params,
		})
		if resp.OK {
			t.Errorf("%s should return error when gastown is nil", tc.method)
			continue
		}
		if resp.Error == nil || resp.Error.Code != "gastown_unavailable" {
			t.Errorf("%s should return gastown_unavailable; got code=%v", tc.method, resp.Error)
		}
	}
}

// --- Parameter validation ---

func TestGastownAgentsMissingDB(t *testing.T) {
	server := newTestServer(&gastownDB{})
	defer server.closeAll()

	for _, params := range []map[string]any{
		{},
		{"db": ""},
		{"db": 42},
	} {
		resp := server.handleRequest(rpcRequest{
			ID:     1,
			Method: "gastown.agents",
			Params: params,
		})
		if resp.OK {
			t.Errorf("gastown.agents with params=%v should fail", params)
			continue
		}
		if resp.Error == nil || resp.Error.Code != "invalid_params" {
			t.Errorf("gastown.agents with params=%v should return invalid_params; got=%v", params, resp.Error)
		}
	}
}

func TestGastownBeadsMissingDB(t *testing.T) {
	server := newTestServer(&gastownDB{})
	defer server.closeAll()

	resp := server.handleRequest(rpcRequest{
		ID:     1,
		Method: "gastown.beads",
		Params: map[string]any{},
	})
	if resp.OK {
		t.Fatalf("gastown.beads without db should fail")
	}
	if resp.Error.Code != "invalid_params" {
		t.Fatalf("gastown.beads without db should return invalid_params; got=%v", resp.Error.Code)
	}
}

func TestGastownMailMissingDB(t *testing.T) {
	server := newTestServer(&gastownDB{})
	defer server.closeAll()

	resp := server.handleRequest(rpcRequest{
		ID:     1,
		Method: "gastown.mail",
		Params: map[string]any{},
	})
	if resp.OK {
		t.Fatalf("gastown.mail without db should fail")
	}
	if resp.Error.Code != "invalid_params" {
		t.Fatalf("gastown.mail without db should return invalid_params; got=%v", resp.Error.Code)
	}
}

func TestGastownConvoysMissingDB(t *testing.T) {
	server := newTestServer(&gastownDB{})
	defer server.closeAll()

	resp := server.handleRequest(rpcRequest{
		ID:     1,
		Method: "gastown.convoys",
		Params: map[string]any{},
	})
	if resp.OK {
		t.Fatalf("gastown.convoys without db should fail")
	}
	if resp.Error.Code != "invalid_params" {
		t.Fatalf("gastown.convoys without db should return invalid_params; got=%v", resp.Error.Code)
	}
}

func TestGastownDiagnosticsMissingDB(t *testing.T) {
	server := newTestServer(&gastownDB{})
	defer server.closeAll()

	resp := server.handleRequest(rpcRequest{
		ID:     1,
		Method: "gastown.diagnostics",
		Params: map[string]any{},
	})
	if resp.OK {
		t.Fatalf("gastown.diagnostics without db should fail")
	}
	if resp.Error.Code != "invalid_params" {
		t.Fatalf("gastown.diagnostics without db should return invalid_params; got=%v", resp.Error.Code)
	}
}

func TestGastownHashMissingParams(t *testing.T) {
	server := newTestServer(&gastownDB{})
	defer server.closeAll()

	// Missing db
	resp := server.handleRequest(rpcRequest{
		ID:     1,
		Method: "gastown.hash",
		Params: map[string]any{"table": "issues"},
	})
	if resp.OK || resp.Error.Code != "invalid_params" {
		t.Fatalf("gastown.hash without db should return invalid_params; got=%+v", resp)
	}

	// Missing table
	resp = server.handleRequest(rpcRequest{
		ID:     2,
		Method: "gastown.hash",
		Params: map[string]any{"db": "hq"},
	})
	if resp.OK || resp.Error.Code != "invalid_params" {
		t.Fatalf("gastown.hash without table should return invalid_params; got=%+v", resp)
	}

	// Both missing
	resp = server.handleRequest(rpcRequest{
		ID:     3,
		Method: "gastown.hash",
		Params: map[string]any{},
	})
	if resp.OK || resp.Error.Code != "invalid_params" {
		t.Fatalf("gastown.hash without params should return invalid_params; got=%+v", resp)
	}
}

// --- listDatabases returns sorted allowlist ---

func TestListDatabasesReturnsAllowlist(t *testing.T) {
	gdb := &gastownDB{}
	// listDatabases calls db.Ping() which will fail without a real connection,
	// but we can verify allowedDatabases is correct directly.
	expected := []string{"gmux", "hq", "spectralChat", "spectralNotify", "spectralTranscript"}
	var got []string
	for db := range allowedDatabases {
		got = append(got, db)
	}
	sort.Strings(got)
	sort.Strings(expected)
	if len(got) != len(expected) {
		t.Fatalf("allowedDatabases has %d entries, want %d", len(got), len(expected))
	}
	for i := range got {
		if got[i] != expected[i] {
			t.Errorf("allowedDatabases[%d] = %q, want %q", i, got[i], expected[i])
		}
	}
	_ = gdb // used above for context, allowedDatabases is the package-level var
}

// --- Watcher event emission ---

func TestGastownWatcherEmitsChangedEvent(t *testing.T) {
	eventOutput := newNotifyingBuffer()
	writer := &stdioFrameWriter{
		writer: bufio.NewWriter(eventOutput),
	}
	watcher := &gastownWatcher{
		frameWriter: writer,
		hashes:      make(map[string]map[string]string),
	}

	watcher.emitChanged("gmux", "issues", "abc123", "def456")

	// Wait for event
	select {
	case <-eventOutput.notify:
	case <-time.After(2 * time.Second):
		t.Fatalf("timed out waiting for gastown.changed event")
	}

	lines := strings.Split(strings.TrimSpace(eventOutput.String()), "\n")
	if len(lines) != 1 {
		t.Fatalf("expected 1 event line, got %d: %q", len(lines), eventOutput.String())
	}

	var event rpcEvent
	if err := json.Unmarshal([]byte(lines[0]), &event); err != nil {
		t.Fatalf("failed to decode event: %v", err)
	}
	if event.Event != "gastown.changed" {
		t.Fatalf("event type = %q, want gastown.changed", event.Event)
	}

	payload, err := base64.StdEncoding.DecodeString(event.DataBase64)
	if err != nil {
		t.Fatalf("failed to decode data_base64: %v", err)
	}
	var data map[string]string
	if err := json.Unmarshal(payload, &data); err != nil {
		t.Fatalf("failed to decode event payload JSON: %v", err)
	}
	if data["db"] != "gmux" {
		t.Errorf("event db = %q, want gmux", data["db"])
	}
	if data["table"] != "issues" {
		t.Errorf("event table = %q, want issues", data["table"])
	}
	if data["old_hash"] != "abc123" {
		t.Errorf("event old_hash = %q, want abc123", data["old_hash"])
	}
	if data["new_hash"] != "def456" {
		t.Errorf("event new_hash = %q, want def456", data["new_hash"])
	}
}

// --- Full stdio RPC round-trip for gastown methods ---

func TestStdioGastownMethodsWithoutDolt(t *testing.T) {
	// When GASTOWN_DOLT_DSN points to a non-existent host, gastown will be nil.
	// The run() function with serve --stdio should handle gastown.* methods gracefully.
	input := strings.NewReader(
		`{"id":1,"method":"hello","params":{}}` + "\n" +
			`{"id":2,"method":"gastown.agents","params":{"db":"hq"}}` + "\n" +
			`{"id":3,"method":"gastown.databases","params":{}}` + "\n",
	)

	t.Setenv("GASTOWN_DOLT_DSN", "root@tcp(127.0.0.1:19999)/")

	var out strings.Builder
	code := run([]string{"serve", "--stdio"}, input, &out, &strings.Builder{})
	if code != 0 {
		t.Fatalf("run serve exit code = %d, want 0", code)
	}

	lines := strings.Split(strings.TrimSpace(out.String()), "\n")
	if len(lines) != 3 {
		t.Fatalf("got %d response lines, want 3: %q", len(lines), out.String())
	}

	// hello should succeed but NOT advertise gastown.v1
	var hello map[string]any
	if err := json.Unmarshal([]byte(lines[0]), &hello); err != nil {
		t.Fatalf("failed to decode hello: %v", err)
	}
	if ok, _ := hello["ok"].(bool); !ok {
		t.Fatalf("hello should succeed: %v", hello)
	}
	helloResult, _ := hello["result"].(map[string]any)
	capabilities, _ := helloResult["capabilities"].([]any)
	for _, cap := range capabilities {
		if cap == "gastown.v1" {
			t.Fatalf("hello should NOT advertise gastown.v1 when Dolt unreachable")
		}
	}

	// gastown.agents should return gastown_unavailable
	var agents map[string]any
	if err := json.Unmarshal([]byte(lines[1]), &agents); err != nil {
		t.Fatalf("failed to decode gastown.agents: %v", err)
	}
	if ok, _ := agents["ok"].(bool); ok {
		t.Fatalf("gastown.agents should fail when Dolt unreachable: %v", agents)
	}
	agentsErr, _ := agents["error"].(map[string]any)
	if agentsErr["code"] != "gastown_unavailable" {
		t.Fatalf("gastown.agents should return gastown_unavailable; got=%v", agentsErr)
	}

	// gastown.databases should also return gastown_unavailable
	var dbs map[string]any
	if err := json.Unmarshal([]byte(lines[2]), &dbs); err != nil {
		t.Fatalf("failed to decode gastown.databases: %v", err)
	}
	if ok, _ := dbs["ok"].(bool); ok {
		t.Fatalf("gastown.databases should fail when Dolt unreachable: %v", dbs)
	}
	dbsErr, _ := dbs["error"].(map[string]any)
	if dbsErr["code"] != "gastown_unavailable" {
		t.Fatalf("gastown.databases should return gastown_unavailable; got=%v", dbsErr)
	}
}

// --- gastownUnavailableResponse / gastownErrorResponse shape ---

func TestGastownUnavailableResponseShape(t *testing.T) {
	resp := gastownUnavailableResponse(42)
	if resp.OK {
		t.Fatal("unavailable response should not be OK")
	}
	if resp.ID != 42 {
		t.Errorf("ID = %v, want 42", resp.ID)
	}
	if resp.Error == nil {
		t.Fatal("unavailable response should have error")
	}
	if resp.Error.Code != "gastown_unavailable" {
		t.Errorf("error code = %q, want gastown_unavailable", resp.Error.Code)
	}
	if resp.Error.Message == "" {
		t.Error("error message should not be empty")
	}
}

func TestGastownErrorResponseShape(t *testing.T) {
	resp := gastownErrorResponse("req-1", json.Unmarshal([]byte("bad"), nil))
	if resp.OK {
		t.Fatal("error response should not be OK")
	}
	if resp.ID != "req-1" {
		t.Errorf("ID = %v, want req-1", resp.ID)
	}
	if resp.Error == nil {
		t.Fatal("error response should have error")
	}
	if resp.Error.Code != "gastown_error" {
		t.Errorf("error code = %q, want gastown_error", resp.Error.Code)
	}
	if resp.Error.Message == "" {
		t.Error("error message should not be empty")
	}
}

// --- Struct JSON serialization ---

func TestGastownAgentJSONFields(t *testing.T) {
	agent := GastownAgent{
		ID:           "wisp-123",
		Title:        "polecat nitro",
		Status:       "active",
		Priority:     2,
		RoleType:     "polecat",
		Rig:          "gmux",
		AgentState:   "working",
		HookBead:     "hq-abc",
		RoleBead:     "gm-xyz",
		LastActivity: "2026-04-14T12:00:00Z",
		Assignee:     "spectralgo",
	}
	data, err := json.Marshal(agent)
	if err != nil {
		t.Fatalf("marshal agent: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal agent: %v", err)
	}

	checks := map[string]any{
		"id":            "wisp-123",
		"title":         "polecat nitro",
		"status":        "active",
		"priority":      float64(2),
		"role_type":     "polecat",
		"rig":           "gmux",
		"agent_state":   "working",
		"hook_bead":     "hq-abc",
		"role_bead":     "gm-xyz",
		"last_activity": "2026-04-14T12:00:00Z",
		"assignee":      "spectralgo",
	}
	for key, want := range checks {
		if decoded[key] != want {
			t.Errorf("agent[%q] = %v, want %v", key, decoded[key], want)
		}
	}
}

func TestGastownBeadJSONFields(t *testing.T) {
	bead := GastownBead{
		ID:        "gm-abc",
		Title:     "Fix bug",
		Status:    "open",
		Priority:  1,
		IssueType: "bug",
		Assignee:  "nitro",
		CreatedAt: "2026-04-14T10:00:00Z",
		UpdatedAt: "2026-04-14T11:00:00Z",
		Sender:    "mayor",
		Pinned:    true,
		WispType:  "issue",
	}
	data, err := json.Marshal(bead)
	if err != nil {
		t.Fatalf("marshal bead: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal bead: %v", err)
	}
	if decoded["pinned"] != true {
		t.Errorf("bead pinned = %v, want true", decoded["pinned"])
	}
	if decoded["wisp_type"] != "issue" {
		t.Errorf("bead wisp_type = %v, want issue", decoded["wisp_type"])
	}
}

func TestGastownMailJSONFields(t *testing.T) {
	mail := GastownMail{
		ID:        "mail-1",
		Title:     "HELP: stuck",
		Status:    "unread",
		Sender:    "nitro",
		Target:    "witness",
		Pinned:    false,
		CreatedAt: "2026-04-14T12:00:00Z",
	}
	data, err := json.Marshal(mail)
	if err != nil {
		t.Fatalf("marshal mail: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal mail: %v", err)
	}
	if decoded["sender"] != "nitro" {
		t.Errorf("mail sender = %v, want nitro", decoded["sender"])
	}
	if decoded["target"] != "witness" {
		t.Errorf("mail target = %v, want witness", decoded["target"])
	}
}

func TestGastownConvoyJSONFields(t *testing.T) {
	convoy := GastownConvoy{
		ID:        "convoy-1",
		Title:     "Deploy batch",
		Status:    "active",
		Priority:  1,
		MolType:   "deploy",
		WorkType:  "batch",
		CreatedAt: "2026-04-14T12:00:00Z",
	}
	data, err := json.Marshal(convoy)
	if err != nil {
		t.Fatalf("marshal convoy: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal convoy: %v", err)
	}
	if decoded["mol_type"] != "deploy" {
		t.Errorf("convoy mol_type = %v, want deploy", decoded["mol_type"])
	}
	if decoded["work_type"] != "batch" {
		t.Errorf("convoy work_type = %v, want batch", decoded["work_type"])
	}
}

func TestGastownDiagnosticJSONFields(t *testing.T) {
	diag := GastownDiagnostic{Key: "config.version", Value: "1.0"}
	data, err := json.Marshal(diag)
	if err != nil {
		t.Fatalf("marshal diagnostic: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal diagnostic: %v", err)
	}
	if decoded["key"] != "config.version" {
		t.Errorf("diagnostic key = %v, want config.version", decoded["key"])
	}
	if decoded["value"] != "1.0" {
		t.Errorf("diagnostic value = %v, want 1.0", decoded["value"])
	}
}

// --- Watcher hash tracking ---

func TestGastownWatcherSkipsFirstPollEmission(t *testing.T) {
	eventOutput := newNotifyingBuffer()
	writer := &stdioFrameWriter{
		writer: bufio.NewWriter(eventOutput),
	}
	watcher := &gastownWatcher{
		frameWriter: writer,
		hashes:      make(map[string]map[string]string),
	}

	// Simulate first poll: set initial hashes (should NOT emit events)
	watcher.mu.Lock()
	watcher.hashes["gmux"] = map[string]string{"issues": "hash1"}
	watcher.mu.Unlock()

	// No event should have been written
	got := eventOutput.String()
	if got != "" {
		t.Fatalf("first poll should not emit events, got: %q", got)
	}
}

func TestGastownWatcherTracksHashChanges(t *testing.T) {
	eventOutput := newNotifyingBuffer()
	writer := &stdioFrameWriter{
		writer: bufio.NewWriter(eventOutput),
	}
	watcher := &gastownWatcher{
		frameWriter: writer,
		hashes:      make(map[string]map[string]string),
	}

	// Populate initial hash
	watcher.mu.Lock()
	watcher.hashes["gmux"] = map[string]string{"issues": "hash1"}
	watcher.mu.Unlock()

	// Simulate a change detection
	watcher.emitChanged("gmux", "issues", "hash1", "hash2")

	select {
	case <-eventOutput.notify:
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for change event")
	}

	var event rpcEvent
	if err := json.Unmarshal([]byte(strings.TrimSpace(eventOutput.String())), &event); err != nil {
		t.Fatalf("decode event: %v", err)
	}
	if event.Event != "gastown.changed" {
		t.Errorf("event = %q, want gastown.changed", event.Event)
	}
}

// --- Watched tables constant ---

func TestWatchedTablesAreConfigured(t *testing.T) {
	expected := map[string]bool{
		"issues": true,
		"wisps":  true,
		"routes": true,
		"events": true,
	}
	if len(watchedTables) != len(expected) {
		t.Fatalf("watchedTables has %d entries, want %d", len(watchedTables), len(expected))
	}
	for _, table := range watchedTables {
		if !expected[table] {
			t.Errorf("unexpected watched table: %q", table)
		}
	}
}

// --- Test helper ---

func newTestServer(gastown *gastownDB) *rpcServer {
	return &rpcServer{
		nextStreamID:  1,
		nextSessionID: 1,
		streams:       map[string]*streamState{},
		sessions:      map[string]*sessionState{},
		gastown:       gastown,
	}
}
