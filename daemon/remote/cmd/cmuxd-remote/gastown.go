package main

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

// --- Structs ---

// GastownAgent represents an agent (wisp with role/state info) from the wisps table.
type GastownAgent struct {
	ID           string `json:"id"`
	Title        string `json:"title"`
	Status       string `json:"status"`
	Priority     int    `json:"priority"`
	RoleType     string `json:"role_type"`
	Rig          string `json:"rig"`
	AgentState   string `json:"agent_state"`
	HookBead     string `json:"hook_bead"`
	RoleBead     string `json:"role_bead"`
	LastActivity string `json:"last_activity"`
	Assignee     string `json:"assignee"`
}

// GastownBead represents an issue from the issues table.
type GastownBead struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Status    string `json:"status"`
	Priority  int    `json:"priority"`
	IssueType string `json:"issue_type"`
	Assignee  string `json:"assignee"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
	Sender    string `json:"sender"`
	Pinned    bool   `json:"pinned"`
	WispType  string `json:"wisp_type"`
}

// GastownMail represents a mail wisp from the wisps table.
type GastownMail struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Status    string `json:"status"`
	Sender    string `json:"sender"`
	Target    string `json:"target"`
	Pinned    bool   `json:"pinned"`
	CreatedAt string `json:"created_at"`
}

// GastownConvoy represents a convoy wisp from the wisps table.
type GastownConvoy struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Status    string `json:"status"`
	Priority  int    `json:"priority"`
	MolType   string `json:"mol_type"`
	WorkType  string `json:"work_type"`
	CreatedAt string `json:"created_at"`
}

// GastownDiagnostic represents a key-value entry from config/metadata tables.
type GastownDiagnostic struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

// --- Connection Pool ---

var allowedDatabases = map[string]bool{
	"hq":                  true,
	"gmux":                true,
	"spectralChat":        true,
	"spectralNotify":      true,
	"spectralTranscript":  true,
}

type gastownDB struct {
	db *sql.DB
}

func newGastownDB(dsn string) (*gastownDB, error) {
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("gastown: open db: %w", err)
	}
	db.SetMaxOpenConns(5)
	db.SetMaxIdleConns(2)
	db.SetConnMaxLifetime(5 * time.Minute)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, fmt.Errorf("gastown: ping: %w", err)
	}

	return &gastownDB{db: db}, nil
}

func (g *gastownDB) Close() error {
	return g.db.Close()
}

func validateDB(name string) error {
	if !allowedDatabases[name] {
		return fmt.Errorf("database %q not in allowlist", name)
	}
	return nil
}

// --- Query Functions ---

func (g *gastownDB) queryAgents(dbName string) ([]GastownAgent, error) {
	if err := validateDB(dbName); err != nil {
		return nil, err
	}
	query := fmt.Sprintf("USE `%s`", dbName)
	if _, err := g.db.Exec(query); err != nil {
		return nil, fmt.Errorf("gastown: use db %s: %w", dbName, err)
	}

	rows, err := g.db.Query("SELECT id, title, status, priority, role_type, rig, agent_state, hook_bead, role_bead, last_activity, assignee FROM wisps WHERE role_type != '' OR agent_state != ''")
	if err != nil {
		return nil, fmt.Errorf("gastown: query agents: %w", err)
	}
	defer rows.Close()

	var agents []GastownAgent
	for rows.Next() {
		var a GastownAgent
		var priority sql.NullInt64
		var roleType, rig, agentState, hookBead, roleBead, lastActivity, assignee sql.NullString
		if err := rows.Scan(&a.ID, &a.Title, &a.Status, &priority, &roleType, &rig, &agentState, &hookBead, &roleBead, &lastActivity, &assignee); err != nil {
			return nil, fmt.Errorf("gastown: scan agent: %w", err)
		}
		a.Priority = int(priority.Int64)
		a.RoleType = roleType.String
		a.Rig = rig.String
		a.AgentState = agentState.String
		a.HookBead = hookBead.String
		a.RoleBead = roleBead.String
		a.LastActivity = lastActivity.String
		a.Assignee = assignee.String
		agents = append(agents, a)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("gastown: rows agents: %w", err)
	}
	return agents, nil
}

func (g *gastownDB) queryBeads(dbName string, limit int) ([]GastownBead, error) {
	if err := validateDB(dbName); err != nil {
		return nil, err
	}
	if limit <= 0 {
		limit = 50
	}
	query := fmt.Sprintf("USE `%s`", dbName)
	if _, err := g.db.Exec(query); err != nil {
		return nil, fmt.Errorf("gastown: use db %s: %w", dbName, err)
	}

	rows, err := g.db.Query("SELECT id, title, status, priority, issue_type, assignee, created_at, updated_at, sender, pinned, wisp_type FROM issues ORDER BY updated_at DESC LIMIT ?", limit)
	if err != nil {
		return nil, fmt.Errorf("gastown: query beads: %w", err)
	}
	defer rows.Close()

	var beads []GastownBead
	for rows.Next() {
		var b GastownBead
		var priority sql.NullInt64
		var issueType, assignee, sender, wispType sql.NullString
		var createdAt, updatedAt sql.NullString
		var pinned sql.NullBool
		if err := rows.Scan(&b.ID, &b.Title, &b.Status, &priority, &issueType, &assignee, &createdAt, &updatedAt, &sender, &pinned, &wispType); err != nil {
			return nil, fmt.Errorf("gastown: scan bead: %w", err)
		}
		b.Priority = int(priority.Int64)
		b.IssueType = issueType.String
		b.Assignee = assignee.String
		b.CreatedAt = createdAt.String
		b.UpdatedAt = updatedAt.String
		b.Sender = sender.String
		b.Pinned = pinned.Bool
		b.WispType = wispType.String
		beads = append(beads, b)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("gastown: rows beads: %w", err)
	}
	return beads, nil
}

func (g *gastownDB) queryMail(dbName string) ([]GastownMail, error) {
	if err := validateDB(dbName); err != nil {
		return nil, err
	}
	query := fmt.Sprintf("USE `%s`", dbName)
	if _, err := g.db.Exec(query); err != nil {
		return nil, fmt.Errorf("gastown: use db %s: %w", dbName, err)
	}

	rows, err := g.db.Query("SELECT id, title, status, sender, assignee, pinned, created_at FROM wisps WHERE wisp_type = 'mail' ORDER BY created_at DESC")
	if err != nil {
		return nil, fmt.Errorf("gastown: query mail: %w", err)
	}
	defer rows.Close()

	var mails []GastownMail
	for rows.Next() {
		var m GastownMail
		var sender, target sql.NullString
		var pinned sql.NullBool
		var createdAt sql.NullString
		if err := rows.Scan(&m.ID, &m.Title, &m.Status, &sender, &target, &pinned, &createdAt); err != nil {
			return nil, fmt.Errorf("gastown: scan mail: %w", err)
		}
		m.Sender = sender.String
		m.Target = target.String
		m.Pinned = pinned.Bool
		m.CreatedAt = createdAt.String
		mails = append(mails, m)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("gastown: rows mail: %w", err)
	}
	return mails, nil
}

func (g *gastownDB) queryConvoys(dbName string) ([]GastownConvoy, error) {
	if err := validateDB(dbName); err != nil {
		return nil, err
	}
	query := fmt.Sprintf("USE `%s`", dbName)
	if _, err := g.db.Exec(query); err != nil {
		return nil, fmt.Errorf("gastown: use db %s: %w", dbName, err)
	}

	rows, err := g.db.Query("SELECT id, title, status, priority, mol_type, work_type, created_at FROM wisps WHERE wisp_type = 'convoy'")
	if err != nil {
		return nil, fmt.Errorf("gastown: query convoys: %w", err)
	}
	defer rows.Close()

	var convoys []GastownConvoy
	for rows.Next() {
		var c GastownConvoy
		var priority sql.NullInt64
		var molType, workType sql.NullString
		var createdAt sql.NullString
		if err := rows.Scan(&c.ID, &c.Title, &c.Status, &priority, &molType, &workType, &createdAt); err != nil {
			return nil, fmt.Errorf("gastown: scan convoy: %w", err)
		}
		c.Priority = int(priority.Int64)
		c.MolType = molType.String
		c.WorkType = workType.String
		c.CreatedAt = createdAt.String
		convoys = append(convoys, c)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("gastown: rows convoys: %w", err)
	}
	return convoys, nil
}

func (g *gastownDB) queryDiagnostics(dbName string) ([]GastownDiagnostic, error) {
	if err := validateDB(dbName); err != nil {
		return nil, err
	}
	query := fmt.Sprintf("USE `%s`", dbName)
	if _, err := g.db.Exec(query); err != nil {
		return nil, fmt.Errorf("gastown: use db %s: %w", dbName, err)
	}

	var diagnostics []GastownDiagnostic

	// Query config table
	configRows, err := g.db.Query("SELECT `key`, `value` FROM config")
	if err != nil {
		return nil, fmt.Errorf("gastown: query config: %w", err)
	}
	defer configRows.Close()
	for configRows.Next() {
		var d GastownDiagnostic
		var val sql.NullString
		if err := configRows.Scan(&d.Key, &val); err != nil {
			return nil, fmt.Errorf("gastown: scan config: %w", err)
		}
		d.Key = "config." + d.Key
		d.Value = val.String
		diagnostics = append(diagnostics, d)
	}
	if err := configRows.Err(); err != nil {
		return nil, fmt.Errorf("gastown: rows config: %w", err)
	}

	// Query metadata table
	metaRows, err := g.db.Query("SELECT `key`, `value` FROM metadata")
	if err != nil {
		return nil, fmt.Errorf("gastown: query metadata: %w", err)
	}
	defer metaRows.Close()
	for metaRows.Next() {
		var d GastownDiagnostic
		var val sql.NullString
		if err := metaRows.Scan(&d.Key, &val); err != nil {
			return nil, fmt.Errorf("gastown: scan metadata: %w", err)
		}
		d.Key = "metadata." + d.Key
		d.Value = val.String
		diagnostics = append(diagnostics, d)
	}
	if err := metaRows.Err(); err != nil {
		return nil, fmt.Errorf("gastown: rows metadata: %w", err)
	}

	return diagnostics, nil
}

func (g *gastownDB) hashOfTable(dbName, table string) (string, error) {
	if err := validateDB(dbName); err != nil {
		return "", err
	}
	useQuery := fmt.Sprintf("USE `%s`", dbName)
	if _, err := g.db.Exec(useQuery); err != nil {
		return "", fmt.Errorf("gastown: use db %s: %w", dbName, err)
	}

	var hash string
	if err := g.db.QueryRow("SELECT DOLT_HASHOF_TABLE(?)", table).Scan(&hash); err != nil {
		return "", fmt.Errorf("gastown: hash of %s.%s: %w", dbName, table, err)
	}
	return hash, nil
}

func (g *gastownDB) listDatabases() ([]string, error) {
	var dbs []string
	for db := range allowedDatabases {
		dbs = append(dbs, db)
	}
	// Verify connectivity by pinging
	if err := g.db.Ping(); err != nil {
		return nil, fmt.Errorf("gastown: list databases ping: %w", err)
	}
	return dbs, nil
}

// --- Change Detection Watcher ---

var watchedTables = []string{"issues", "wisps", "routes", "events"}

type gastownWatcher struct {
	gastown     *gastownDB
	frameWriter *stdioFrameWriter

	mu     sync.Mutex
	hashes map[string]map[string]string // db -> table -> hash
}

func newGastownWatcher(gastown *gastownDB, frameWriter *stdioFrameWriter) *gastownWatcher {
	return &gastownWatcher{
		gastown:     gastown,
		frameWriter: frameWriter,
		hashes:      make(map[string]map[string]string),
	}
}

func (w *gastownWatcher) run(ctx context.Context) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	// Initial hash population
	w.pollAll()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			w.pollAll()
		}
	}
}

func (w *gastownWatcher) pollAll() {
	for dbName := range allowedDatabases {
		for _, table := range watchedTables {
			hash, err := w.gastown.hashOfTable(dbName, table)
			if err != nil {
				continue
			}

			w.mu.Lock()
			if w.hashes[dbName] == nil {
				w.hashes[dbName] = make(map[string]string)
			}
			oldHash := w.hashes[dbName][table]
			changed := oldHash != "" && oldHash != hash
			w.hashes[dbName][table] = hash
			w.mu.Unlock()

			if changed {
				w.emitChanged(dbName, table, oldHash, hash)
			}
		}
	}
}

func (w *gastownWatcher) emitChanged(dbName, table, oldHash, newHash string) {
	payload, err := json.Marshal(map[string]string{
		"db":       dbName,
		"table":    table,
		"old_hash": oldHash,
		"new_hash": newHash,
	})
	if err != nil {
		return
	}
	_ = w.frameWriter.writeEvent(rpcEvent{
		Event:      "gastown.changed",
		DataBase64: base64.StdEncoding.EncodeToString(payload),
	})
}

// --- RPC Handlers ---

func (s *rpcServer) handleGastownAgents(req rpcRequest) rpcResponse {
	if s.gastown == nil {
		return gastownUnavailableResponse(req.ID)
	}
	dbName, ok := getStringParam(req.Params, "db")
	if !ok || dbName == "" {
		return rpcResponse{
			ID: req.ID, OK: false,
			Error: &rpcError{Code: "invalid_params", Message: "gastown.agents requires db"},
		}
	}
	agents, err := s.gastown.queryAgents(dbName)
	if err != nil {
		return gastownErrorResponse(req.ID, err)
	}
	return rpcResponse{ID: req.ID, OK: true, Result: map[string]any{"agents": agents}}
}

func (s *rpcServer) handleGastownBeads(req rpcRequest) rpcResponse {
	if s.gastown == nil {
		return gastownUnavailableResponse(req.ID)
	}
	dbName, ok := getStringParam(req.Params, "db")
	if !ok || dbName == "" {
		return rpcResponse{
			ID: req.ID, OK: false,
			Error: &rpcError{Code: "invalid_params", Message: "gastown.beads requires db"},
		}
	}
	limit := 50
	if l, ok := getIntParam(req.Params, "limit"); ok && l > 0 {
		limit = l
	}
	beads, err := s.gastown.queryBeads(dbName, limit)
	if err != nil {
		return gastownErrorResponse(req.ID, err)
	}
	return rpcResponse{ID: req.ID, OK: true, Result: map[string]any{"beads": beads}}
}

func (s *rpcServer) handleGastownMail(req rpcRequest) rpcResponse {
	if s.gastown == nil {
		return gastownUnavailableResponse(req.ID)
	}
	dbName, ok := getStringParam(req.Params, "db")
	if !ok || dbName == "" {
		return rpcResponse{
			ID: req.ID, OK: false,
			Error: &rpcError{Code: "invalid_params", Message: "gastown.mail requires db"},
		}
	}
	mail, err := s.gastown.queryMail(dbName)
	if err != nil {
		return gastownErrorResponse(req.ID, err)
	}
	return rpcResponse{ID: req.ID, OK: true, Result: map[string]any{"mail": mail}}
}

func (s *rpcServer) handleGastownConvoys(req rpcRequest) rpcResponse {
	if s.gastown == nil {
		return gastownUnavailableResponse(req.ID)
	}
	dbName, ok := getStringParam(req.Params, "db")
	if !ok || dbName == "" {
		return rpcResponse{
			ID: req.ID, OK: false,
			Error: &rpcError{Code: "invalid_params", Message: "gastown.convoys requires db"},
		}
	}
	convoys, err := s.gastown.queryConvoys(dbName)
	if err != nil {
		return gastownErrorResponse(req.ID, err)
	}
	return rpcResponse{ID: req.ID, OK: true, Result: map[string]any{"convoys": convoys}}
}

func (s *rpcServer) handleGastownDiagnostics(req rpcRequest) rpcResponse {
	if s.gastown == nil {
		return gastownUnavailableResponse(req.ID)
	}
	dbName, ok := getStringParam(req.Params, "db")
	if !ok || dbName == "" {
		return rpcResponse{
			ID: req.ID, OK: false,
			Error: &rpcError{Code: "invalid_params", Message: "gastown.diagnostics requires db"},
		}
	}
	diagnostics, err := s.gastown.queryDiagnostics(dbName)
	if err != nil {
		return gastownErrorResponse(req.ID, err)
	}
	return rpcResponse{ID: req.ID, OK: true, Result: map[string]any{"diagnostics": diagnostics}}
}

func (s *rpcServer) handleGastownHash(req rpcRequest) rpcResponse {
	if s.gastown == nil {
		return gastownUnavailableResponse(req.ID)
	}
	dbName, ok := getStringParam(req.Params, "db")
	if !ok || dbName == "" {
		return rpcResponse{
			ID: req.ID, OK: false,
			Error: &rpcError{Code: "invalid_params", Message: "gastown.hash requires db"},
		}
	}
	table, ok := getStringParam(req.Params, "table")
	if !ok || table == "" {
		return rpcResponse{
			ID: req.ID, OK: false,
			Error: &rpcError{Code: "invalid_params", Message: "gastown.hash requires table"},
		}
	}
	hash, err := s.gastown.hashOfTable(dbName, table)
	if err != nil {
		return gastownErrorResponse(req.ID, err)
	}
	return rpcResponse{ID: req.ID, OK: true, Result: map[string]any{"hash": hash}}
}

func (s *rpcServer) handleGastownDatabases(req rpcRequest) rpcResponse {
	if s.gastown == nil {
		return gastownUnavailableResponse(req.ID)
	}
	dbs, err := s.gastown.listDatabases()
	if err != nil {
		return gastownErrorResponse(req.ID, err)
	}
	return rpcResponse{ID: req.ID, OK: true, Result: map[string]any{"databases": dbs}}
}

func gastownUnavailableResponse(id any) rpcResponse {
	return rpcResponse{
		ID: id, OK: false,
		Error: &rpcError{Code: "gastown_unavailable", Message: "gastown Dolt connection not available"},
	}
}

func gastownErrorResponse(id any, err error) rpcResponse {
	return rpcResponse{
		ID: id, OK: false,
		Error: &rpcError{Code: "gastown_error", Message: err.Error()},
	}
}

// initGastown creates the gastown DB connection. Returns nil (no error) if Dolt is unreachable.
func initGastown(dsn string) *gastownDB {
	if dsn == "" {
		dsn = "root@tcp(127.0.0.1:3307)/"
	}
	gastown, err := newGastownDB(dsn)
	if err != nil {
		log.Printf("gastown: Dolt connection failed (non-fatal): %v", err)
		return nil
	}
	log.Printf("gastown: connected to Dolt at %s", strings.SplitN(dsn, "@", 2)[len(strings.SplitN(dsn, "@", 2))-1])
	return gastown
}
