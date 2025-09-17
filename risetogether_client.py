#!/usr/bin/env python3
import requests
import json
import time

class RiseTogetherClient:
    def __init__(self, host="localhost", port=8080):
        self.base_url = f"http://{host}:{port}"
    
    def get_status(self):
        return requests.get(f"{self.base_url}/status").json()
    
    def get_config(self):
        return requests.get(f"{self.base_url}/config").json()
    
    def update_config(self, config):
        return requests.post(f"{self.base_url}/config", json=config).json()
    
    def get_players(self):
        return requests.get(f"{self.base_url}/players").json()
    
    def assign_team(self, node_id, team_id):
        return requests.post(f"{self.base_url}/teams/assign", 
                            json={"nodeId": node_id, "teamId": team_id}).json()
    
    def start_game(self):
        return requests.post(f"{self.base_url}/game/start").json()
    
    def stop_game(self):
        return requests.post(f"{self.base_url}/game/stop").json()
    
    def reset_game(self):
        return requests.post(f"{self.base_url}/game/reset").json()
    
    def advance_level(self):
        return requests.post(f"{self.base_url}/level/advance").json()
