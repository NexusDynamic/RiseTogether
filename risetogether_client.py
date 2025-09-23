#!/usr/bin/env python3
"""
RiseTogether Headless Server TUI
Requires: textual, httpx
pip install textual httpx
"""

from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, Vertical, ScrollableContainer
from textual.widgets import Header, Footer, Button, Static, DataTable, Input, Label, Select, Switch
from textual.reactive import reactive
from textual.timer import Timer
import httpx
import asyncio
from datetime import datetime
import json

class RiseTogetherTUI(App):
    """TUI for RiseTogether Headless Server Management"""
    
    CSS = """
    #main {
        layout: grid;
        grid-size: 2 3;
        grid-gutter: 1;
    }
    
    #status_panel {
        column-span: 2;
        height: 10;
        border: solid green;
    }
    
    #players_panel {
        border: solid blue;
        height: 20;
    }
    
    #config_panel {
        border: solid yellow;
        height: 20;
    }
    
    #control_panel {
        column-span: 2;
        height: 10;
        border: solid red;
        layout: horizontal;
    }
    
    .button {
        margin: 1;
        min-width: 20;
    }
    """
    
    BINDINGS = [
        ("q", "quit", "Quit"),
        ("r", "refresh", "Refresh"),
        ("s", "start_game", "Start Game"),
        ("t", "stop_game", "Stop Game"),
        ("n", "next_level", "Next Level"),
        ("x", "reset_game", "Reset Game"),
    ]
    
    def __init__(self, host="localhost", port=8080):
        super().__init__()
        self.base_url = f"http://{host}:{port}"
        self.client = httpx.AsyncClient(timeout=5.0)
        self.status_data = {}
        self.players_data = []
        self.config_data = {}
        
    async def on_mount(self) -> None:
        """Start background refresh timer"""
        self.refresh_timer = self.set_interval(2, self.refresh_data)
        await self.refresh_data()
        
    def compose(self) -> ComposeResult:
        yield Header()
        yield Container(
            Container(
                Static("Game Status", id="status_title"),
                Static("Initializing...", id="status_text"),
                id="status_panel"
            ),
            Container(
                Static("Players", id="players_title"),
                DataTable(id="players_table"),
                id="players_panel"
            ),
            Container(
                Static("Configuration", id="config_title"),
                ScrollableContainer(
                    Static("Loading...", id="config_text"),
                    id="config_scroll"
                ),
                id="config_panel"
            ),
            Container(
                Button("Start Game", id="btn_start", variant="success"),
                Button("Stop Game", id="btn_stop", variant="error"),
                Button("Reset Complete", id="btn_reset", variant="warning"),
                Button("Next Level", id="btn_next", variant="primary"),
                Button("Force Next", id="btn_force", variant="default"),
                id="control_panel"
            ),
            id="main"
        )
        yield Footer()
        
    async def refresh_data(self) -> None:
        """Refresh all data from server"""
        try:
            # Get status
            response = await self.client.get(f"{self.base_url}/status")
            if response.status_code == 200:
                self.status_data = response.json()
                await self.update_status_display()
            
            # Get players
            response = await self.client.get(f"{self.base_url}/players")
            if response.status_code == 200:
                self.players_data = response.json().get("players", [])
                await self.update_players_display()
                
            # Get config
            response = await self.client.get(f"{self.base_url}/config")
            if response.status_code == 200:
                self.config_data = response.json()
                await self.update_config_display()
                
        except Exception as e:
            self.query_one("#status_text", Static).update(f"Connection Error: {e}")
            
    async def update_status_display(self) -> None:
        """Update status panel"""
        status = self.status_data
        status_text = f"""
Coordinator: {status.get('isCoordinator', False)}
Game Active: {status.get('gameActive', False)}
Connected Nodes: {status.get('connectedNodes', 0)}
Level: {status.get('currentLevel', 0) + 1} / Round: {status.get('currentRound', 0) + 1}
Time Remaining: {status.get('timeRemaining', 0):.1f}s
Team 0 Distance: {status.get('teamDistances', {}).get('0', 0):.1f}m
Team 1 Distance: {status.get('teamDistances', {}).get('1', 0):.1f}m
        """
        self.query_one("#status_text", Static).update(status_text.strip())
        
    async def update_players_display(self) -> None:
        """Update players table"""
        table = self.query_one("#players_table", DataTable)
        
        # Initialize table if needed
        if not table.columns:
            table.add_columns("Node ID", "Name", "Team", "Status")
            
        table.clear()
        
        for player in self.players_data:
            node_id = player.get('nodeId', '')[:12] + "..."
            name = player.get('nodeName', 'Unknown')
            team = f"Team {player.get('teamId', '?')}" if player.get('assigned') else "Unassigned"
            status = "Ready" if player.get('ready', False) else "Not Ready"
            
            table.add_row(node_id, name, team, status)
            
    async def update_config_display(self) -> None:
        """Update config panel"""
        config_text = json.dumps(self.config_data, indent=2)
        self.query_one("#config_text", Static).update(config_text)
        
    async def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button presses"""
        button_id = event.button.id
        
        try:
            if button_id == "btn_start":
                response = await self.client.post(f"{self.base_url}/game/start")
                self.notify("Game started" if response.status_code == 200 else "Failed to start")
                
            elif button_id == "btn_stop":
                response = await self.client.post(f"{self.base_url}/game/stop")
                self.notify("Game stopped" if response.status_code == 200 else "Failed to stop")
                
            elif button_id == "btn_reset":
                response = await self.client.post(f"{self.base_url}/game/reset/complete")
                self.notify("Game reset complete" if response.status_code == 200 else "Failed to reset")
                
            elif button_id == "btn_next":
                response = await self.client.post(f"{self.base_url}/level/advance")
                self.notify("Advanced to next level" if response.status_code == 200 else "Failed to advance")
                
            elif button_id == "btn_force":
                response = await self.client.post(f"{self.base_url}/level/force")
                self.notify("Forced next level" if response.status_code == 200 else "Failed to force")
                
            await self.refresh_data()
            
        except Exception as e:
            self.notify(f"Error: {e}", severity="error")
            
    async def action_refresh(self) -> None:
        await self.refresh_data()
        
    async def action_start_game(self) -> None:
        await self.on_button_pressed(Button.Pressed(self.query_one("#btn_start")))
        
    async def action_stop_game(self) -> None:
        await self.on_button_pressed(Button.Pressed(self.query_one("#btn_stop")))
        
    async def action_next_level(self) -> None:
        await self.on_button_pressed(Button.Pressed(self.query_one("#btn_next")))
        
    async def action_reset_game(self) -> None:
        await self.on_button_pressed(Button.Pressed(self.query_one("#btn_reset")))

if __name__ == "__main__":
    import sys
    host = sys.argv[1] if len(sys.argv) > 1 else "localhost"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8080
    
    app = RiseTogetherTUI(host, port)
    app.run()
