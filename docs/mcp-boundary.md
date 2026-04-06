# MCP Server Boundary (TASK-027)

## Overview

Gmux exposes an MCP (Model Context Protocol) server that maps agent tools onto
existing Gmux socket primitives. This gives AI agents a stable, schema-driven
interface to Gmux operations without UI scraping.

## Transport

- **Protocol:** MCP over stdio (JSON-RPC 2.0, newline-delimited)
- **Protocol version:** `2024-11-05`
- **Entry point:** `cmuxd-remote mcp --stdio [--socket <path>]`

The MCP server connects to the Gmux app socket (via `CMUX_SOCKET_PATH` or
`~/.cmux/socket_addr`) and relays tool calls to existing V2 JSON-RPC methods.

## Tool Surface (First Pass)

Every tool maps 1:1 to an existing Gmux socket method. No new business logic
is introduced — the MCP layer is a protocol adapter.

| MCP Tool | Socket Method | Description |
|----------|--------------|-------------|
| `workspace_list` | `workspace.list` | List all workspaces |
| `workspace_current` | `workspace.current` | Get the active workspace |
| `workspace_create` | `workspace.create` | Create a workspace |
| `workspace_close` | `workspace.close` | Close a workspace |
| `workspace_select` | `workspace.select` | Switch to a workspace |
| `surface_list` | `surface.list` | List terminal surfaces |
| `surface_create` | `surface.create` | Create a surface |
| `surface_close` | `surface.close` | Close a surface |
| `surface_focus` | `surface.focus` | Focus a surface |
| `surface_send_text` | `surface.send_text` | Send text to a surface |
| `pane_list` | `pane.list` | List panes |
| `pane_create` | `pane.create` | Create a pane (split) |
| `notification_create` | `notification.create` | Show a notification |
| `system_capabilities` | `system.capabilities` | Query capabilities |

## Architecture

```
MCP Client (AI agent)
    │  stdio (JSON-RPC 2.0)
    ▼
cmuxd-remote mcp --stdio
    │  Unix socket / TCP (Gmux JSON-RPC)
    ▼
Gmux App (socket handler)
```

The MCP server is stateless — each tool call creates a fresh socket connection,
relays the request, and returns the response. No session state is held in the
MCP layer.

## Out of Scope (First Pass)

These are intentionally deferred for future work:

- **MCP Resources** — Workspace state, surface content, or configuration as
  readable resources. The `resources/list` endpoint returns an empty list.
- **MCP Prompts** — Predefined prompt templates. The `prompts/list` endpoint
  returns an empty list.
- **Key sending** (`surface.send_key`) — Complex key mapping and modifier
  handling. Deferred to avoid incomplete keyboard abstractions.
- **Surface splitting** (`surface.split`) — Available via `pane_create` which
  provides the same functionality with clearer semantics for agents.
- **Browser operations** (`browser.*`) — Web surface management. Deferred until
  agent browser interaction patterns are better understood.
- **Streaming/subscriptions** — Event streams and surface output subscriptions.
  Requires MCP sampling or server-sent events support.
- **Profile isolation** — Multi-profile socket routing (TASK-028).
- **Authentication** — The MCP server inherits the socket's auth mode. No
  additional MCP-level auth is added in this pass.
- **Composite tools** — Higher-level operations that compose multiple socket
  calls (e.g., "open workspace and run command"). Each tool stays 1:1 with a
  socket primitive.

## Usage

### Direct invocation

```bash
cmuxd-remote mcp --stdio
```

### With explicit socket path

```bash
cmuxd-remote mcp --stdio --socket /tmp/gmux-debug.sock
```

### As an MCP server in Claude Code

```json
{
  "mcpServers": {
    "gmux": {
      "command": "cmuxd-remote",
      "args": ["mcp", "--stdio"]
    }
  }
}
```

## Design Principles

1. **1:1 mapping** — Each tool maps to exactly one socket method. No hidden
   composition or side effects.
2. **Reuse primitives** — All business logic lives in the Gmux app. The MCP
   layer is a thin protocol adapter.
3. **Explicit boundaries** — What's supported is listed above. Everything else
   is explicitly deferred.
4. **No UI assumptions** — Tools operate on workspace/surface/pane IDs, not
   visual layout concepts.
5. **Gmux-scoped** — All identifiers and paths are gmux-scoped, not cmux.
