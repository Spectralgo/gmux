package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
)

// --- MCP JSON-RPC 2.0 types ---

type mcpRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      any             `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type mcpResponse struct {
	JSONRPC string    `json:"jsonrpc"`
	ID      any       `json:"id,omitempty"`
	Result  any       `json:"result,omitempty"`
	Error   *mcpError `json:"error,omitempty"`
}

type mcpError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

// --- MCP tool schema types ---

type mcpToolDef struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	InputSchema any    `json:"inputSchema"`
}

// toolRoute maps an MCP tool to a Gmux socket JSON-RPC method.
type toolRoute struct {
	def    mcpToolDef
	method string                            // Gmux socket method (e.g. "workspace.list")
	mapArgs func(map[string]any) map[string]any // optional arg transform; nil = pass through
}

// gmuxToolRoutes defines the first-pass MCP tool surface.
// Each tool maps 1:1 to an existing Gmux socket primitive.
var gmuxToolRoutes []toolRoute

func init() {
	gmuxToolRoutes = []toolRoute{
		// --- Workspace operations ---
		{
			def: mcpToolDef{
				Name:        "workspace_list",
				Description: "List all workspaces in the Gmux instance.",
				InputSchema: schemaObject(nil, nil),
			},
			method: "workspace.list",
		},
		{
			def: mcpToolDef{
				Name:        "workspace_current",
				Description: "Get the currently active workspace.",
				InputSchema: schemaObject(nil, nil),
			},
			method: "workspace.current",
		},
		{
			def: mcpToolDef{
				Name:        "workspace_create",
				Description: "Create a new workspace. Optionally specify a shell command, working directory, or title.",
				InputSchema: schemaObject(map[string]any{
					"command":           schemaProp("string", "Shell command to execute in the new workspace."),
					"working_directory": schemaProp("string", "Working directory for the workspace shell."),
					"title":             schemaProp("string", "Display title for the workspace tab."),
				}, nil),
			},
			method: "workspace.create",
			mapArgs: func(args map[string]any) map[string]any {
				p := make(map[string]any, len(args))
				if v, ok := args["command"]; ok {
					p["initial_command"] = v
				}
				if v, ok := args["working_directory"]; ok {
					p["working_directory"] = v
				}
				if v, ok := args["title"]; ok {
					p["title"] = v
				}
				return p
			},
		},
		{
			def: mcpToolDef{
				Name:        "workspace_close",
				Description: "Close a workspace by its ID.",
				InputSchema: schemaObject(map[string]any{
					"workspace_id": schemaProp("string", "ID of the workspace to close."),
				}, []string{"workspace_id"}),
			},
			method: "workspace.close",
		},
		{
			def: mcpToolDef{
				Name:        "workspace_select",
				Description: "Switch to a workspace by its ID, making it the active workspace.",
				InputSchema: schemaObject(map[string]any{
					"workspace_id": schemaProp("string", "ID of the workspace to select."),
				}, []string{"workspace_id"}),
			},
			method: "workspace.select",
		},

		// --- Surface operations ---
		{
			def: mcpToolDef{
				Name:        "surface_list",
				Description: "List all terminal surfaces, optionally filtered to a specific workspace.",
				InputSchema: schemaObject(map[string]any{
					"workspace_id": schemaProp("string", "Filter surfaces to this workspace. Omit for all."),
				}, nil),
			},
			method: "surface.list",
		},
		{
			def: mcpToolDef{
				Name:        "surface_create",
				Description: "Create a new terminal surface in a workspace and pane.",
				InputSchema: schemaObject(map[string]any{
					"workspace_id": schemaProp("string", "Target workspace ID."),
					"pane_id":      schemaProp("string", "Target pane ID."),
				}, nil),
			},
			method: "surface.create",
		},
		{
			def: mcpToolDef{
				Name:        "surface_close",
				Description: "Close a terminal surface by its ID.",
				InputSchema: schemaObject(map[string]any{
					"surface_id": schemaProp("string", "ID of the surface to close."),
				}, []string{"surface_id"}),
			},
			method: "surface.close",
		},
		{
			def: mcpToolDef{
				Name:        "surface_focus",
				Description: "Focus a terminal surface within its workspace.",
				InputSchema: schemaObject(map[string]any{
					"surface_id":   schemaProp("string", "ID of the surface to focus."),
					"workspace_id": schemaProp("string", "Workspace containing the surface."),
				}, []string{"surface_id"}),
			},
			method: "surface.focus",
		},
		{
			def: mcpToolDef{
				Name:        "surface_send_text",
				Description: "Send text input to a terminal surface, as if typed by the user.",
				InputSchema: schemaObject(map[string]any{
					"surface_id": schemaProp("string", "Target surface ID."),
					"text":       schemaProp("string", "Text to send to the surface."),
				}, []string{"surface_id", "text"}),
			},
			method: "surface.send_text",
		},

		// --- Pane operations ---
		{
			def: mcpToolDef{
				Name:        "pane_list",
				Description: "List all panes, optionally filtered to a specific workspace.",
				InputSchema: schemaObject(map[string]any{
					"workspace_id": schemaProp("string", "Filter panes to this workspace. Omit for all."),
				}, nil),
			},
			method: "pane.list",
		},
		{
			def: mcpToolDef{
				Name:        "pane_create",
				Description: "Create a new pane (split) in a workspace. Defaults to a right split.",
				InputSchema: schemaObject(map[string]any{
					"workspace_id": schemaProp("string", "Target workspace ID."),
					"direction":    schemaProp("string", "Split direction: left, right, up, or down. Defaults to right."),
				}, nil),
			},
			method: "pane.create",
		},

		// --- Notification ---
		{
			def: mcpToolDef{
				Name:        "notification_create",
				Description: "Show a notification in the Gmux UI.",
				InputSchema: schemaObject(map[string]any{
					"title":        schemaProp("string", "Notification title."),
					"body":         schemaProp("string", "Notification body text."),
					"workspace_id": schemaProp("string", "Associate notification with a workspace."),
				}, []string{"title"}),
			},
			method: "notification.create",
		},

		// --- System ---
		{
			def: mcpToolDef{
				Name:        "system_capabilities",
				Description: "Query the Gmux instance for its supported capabilities and version.",
				InputSchema: schemaObject(nil, nil),
			},
			method: "system.capabilities",
		},
	}
}

// --- Schema helpers ---

func schemaProp(typ, description string) map[string]any {
	return map[string]any{"type": typ, "description": description}
}

func schemaObject(properties map[string]any, required []string) map[string]any {
	s := map[string]any{
		"type": "object",
	}
	if properties != nil {
		s["properties"] = properties
	}
	if len(required) > 0 {
		s["required"] = required
	}
	return s
}

// --- MCP server ---

type mcpServer struct {
	socketPath  string
	refreshAddr func() string
	writer      *bufio.Writer
	toolIndex   map[string]*toolRoute
}

func newMCPServer(socketPath string, refreshAddr func() string, output io.Writer) *mcpServer {
	idx := make(map[string]*toolRoute, len(gmuxToolRoutes))
	for i := range gmuxToolRoutes {
		idx[gmuxToolRoutes[i].def.Name] = &gmuxToolRoutes[i]
	}
	return &mcpServer{
		socketPath:  socketPath,
		refreshAddr: refreshAddr,
		writer:      bufio.NewWriter(output),
		toolIndex:   idx,
	}
}

func runMCPServer(args []string) int {
	socketPath := os.Getenv("CMUX_SOCKET_PATH")
	stdio := false

	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--stdio":
			stdio = true
		case "--socket":
			if i+1 < len(args) {
				socketPath = args[i+1]
				i++
			}
		}
	}

	if !stdio {
		fmt.Fprintln(os.Stderr, "mcp requires --stdio")
		return 2
	}

	var refreshAddr func() string
	if socketPath == "" {
		socketPath = readSocketAddrFile()
		refreshAddr = readSocketAddrFile
	}

	server := newMCPServer(socketPath, refreshAddr, os.Stdout)
	if err := server.serve(os.Stdin); err != nil {
		fmt.Fprintf(os.Stderr, "mcp: %v\n", err)
		return 1
	}
	return 0
}

func (s *mcpServer) serve(input io.Reader) error {
	reader := bufio.NewReaderSize(input, 64*1024)

	for {
		line, err := reader.ReadBytes('\n')
		if err != nil {
			if err == io.EOF {
				return nil
			}
			return err
		}
		line = bytes.TrimSpace(line)
		if len(line) == 0 {
			continue
		}

		var req mcpRequest
		if err := json.Unmarshal(line, &req); err != nil {
			s.sendResponse(mcpResponse{
				JSONRPC: "2.0",
				Error:   &mcpError{Code: -32700, Message: "Parse error"},
			})
			continue
		}

		resp := s.handleRequest(req)
		if resp != nil {
			s.sendResponse(*resp)
		}
	}
}

func (s *mcpServer) handleRequest(req mcpRequest) *mcpResponse {
	switch req.Method {
	case "initialize":
		return s.handleInitialize(req)
	case "notifications/initialized":
		return nil // notification — no response
	case "ping":
		return &mcpResponse{JSONRPC: "2.0", ID: req.ID, Result: map[string]any{}}
	case "tools/list":
		return s.handleToolsList(req)
	case "tools/call":
		return s.handleToolsCall(req)
	case "resources/list":
		return &mcpResponse{JSONRPC: "2.0", ID: req.ID, Result: map[string]any{"resources": []any{}}}
	case "prompts/list":
		return &mcpResponse{JSONRPC: "2.0", ID: req.ID, Result: map[string]any{"prompts": []any{}}}
	default:
		return &mcpResponse{
			JSONRPC: "2.0",
			ID:      req.ID,
			Error:   &mcpError{Code: -32601, Message: fmt.Sprintf("Method not found: %s", req.Method)},
		}
	}
}

func (s *mcpServer) handleInitialize(req mcpRequest) *mcpResponse {
	return &mcpResponse{
		JSONRPC: "2.0",
		ID:      req.ID,
		Result: map[string]any{
			"protocolVersion": "2024-11-05",
			"capabilities": map[string]any{
				"tools": map[string]any{},
			},
			"serverInfo": map[string]any{
				"name":    "gmux-mcp",
				"version": version,
			},
		},
	}
}

func (s *mcpServer) handleToolsList(req mcpRequest) *mcpResponse {
	tools := make([]mcpToolDef, len(gmuxToolRoutes))
	for i := range gmuxToolRoutes {
		tools[i] = gmuxToolRoutes[i].def
	}
	return &mcpResponse{
		JSONRPC: "2.0",
		ID:      req.ID,
		Result:  map[string]any{"tools": tools},
	}
}

func (s *mcpServer) handleToolsCall(req mcpRequest) *mcpResponse {
	var params struct {
		Name      string         `json:"name"`
		Arguments map[string]any `json:"arguments"`
	}
	if req.Params != nil {
		if err := json.Unmarshal(req.Params, &params); err != nil {
			return &mcpResponse{
				JSONRPC: "2.0",
				ID:      req.ID,
				Error:   &mcpError{Code: -32602, Message: "Invalid params"},
			}
		}
	}

	route, ok := s.toolIndex[params.Name]
	if !ok {
		return toolErrorResponse(req.ID, fmt.Sprintf("Unknown tool: %s", params.Name))
	}

	if s.socketPath == "" {
		return toolErrorResponse(req.ID, "Gmux socket not available. Set CMUX_SOCKET_PATH or ensure Gmux is running.")
	}

	// Build socket RPC params
	rpcParams := params.Arguments
	if route.mapArgs != nil {
		rpcParams = route.mapArgs(params.Arguments)
	}
	if rpcParams == nil {
		rpcParams = map[string]any{}
	}

	// Relay to Gmux socket
	result, err := socketRoundTripV2(s.socketPath, route.method, rpcParams, s.refreshAddr)
	if err != nil {
		return toolErrorResponse(req.ID, err.Error())
	}

	return &mcpResponse{
		JSONRPC: "2.0",
		ID:      req.ID,
		Result: map[string]any{
			"content": []map[string]any{
				{"type": "text", "text": result},
			},
		},
	}
}

func toolErrorResponse(id any, message string) *mcpResponse {
	return &mcpResponse{
		JSONRPC: "2.0",
		ID:      id,
		Result: map[string]any{
			"content": []map[string]any{
				{"type": "text", "text": message},
			},
			"isError": true,
		},
	}
}

func (s *mcpServer) sendResponse(resp mcpResponse) {
	data, err := json.Marshal(resp)
	if err != nil {
		return
	}
	s.writer.Write(data)
	s.writer.WriteByte('\n')
	s.writer.Flush()
}
