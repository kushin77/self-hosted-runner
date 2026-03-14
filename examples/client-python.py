#!/usr/bin/env python3
# SSO Platform Python Client SDK for FastAPI/Django
# Usage: pip install nexus-sso-client

import json
import requests
from typing import Optional, Dict, Any
from datetime import datetime, timedelta
import jwt
from functools import wraps

class KeycloakClient:
    def __init__(self, keycloak_url: str, realm: str, client_id: str, client_secret: str):
        self.keycloak_url = keycloak_url
        self.realm = realm
        self.client_id = client_id
        self.client_secret = client_secret
        self.token = None
        self.token_expiry = None
        
    def get_oidc_config(self) -> Dict[str, Any]:
        """Get OpenID Connect configuration"""
        url = f"{self.keycloak_url}/realms/{self.realm}/.well-known/openid-configuration"
        return requests.get(url).json()
    
    def get_access_token(self) -> str:
        """Get or refresh access token"""
        if self.token and datetime.now() < self.token_expiry:
            return self.token
        
        config = self.get_oidc_config()
        response = requests.post(
            config['token_endpoint'],
            data={
                'grant_type': 'client_credentials',
                'client_id': self.client_id,
                'client_secret': self.client_secret,
            }
        )
        data = response.json()
        self.token = data['access_token']
        self.token_expiry = datetime.now() + timedelta(seconds=data['expires_in'] - 60)
        return self.token
    
    def validate_token(self, token: str) -> Dict[str, Any]:
        """Validate and decode JWT token"""
        try:
            config = self.get_oidc_config()
            jwks_response = requests.get(config['jwks_uri'])
            jwks = jwks_response.json()
            
            decoded = jwt.decode(
                token,
                key=jwks['keys'][0],
                algorithms=['RS256'],
                audience=self.client_id,
            )
            return decoded
        except jwt.InvalidTokenError as e:
            return {'error': str(e)}
    
    def get_user_info(self, token: str) -> Dict[str, Any]:
        """Get user information"""
        config = self.get_oidc_config()
        headers = {'Authorization': f'Bearer {token}'}
        response = requests.get(config['userinfo_endpoint'], headers=headers)
        return response.json()
    
    def logout_user(self, token: str) -> bool:
        """Logout user"""
        config = self.get_oidc_config()
        response = requests.post(
            config['end_session_endpoint'],
            data={'refresh_token': token}
        )
        return response.status_code == 200

# FastAPI Decorator
def require_auth(func):
    @wraps(func)
    def wrapper(request, *args, **kwargs):
        auth_header = request.headers.get('Authorization', '')
        if not auth_header.startswith('Bearer '):
            return {'error': 'Missing or invalid authorization header'}, 401
        
        token = auth_header.split(' ')[1]
        client = KeycloakClient(
            'http://keycloak:8080/auth',
            'master',
            'api-client',
            'client-secret'
        )
        user_info = client.validate_token(token)
        
        if 'error' in user_info:
            return {'error': 'Invalid token'}, 401
        
        request.user = user_info
        return func(request, *args, **kwargs)
    
    return wrapper

# FastAPI Example
from fastapi import FastAPI, Request

app = FastAPI()
client = KeycloakClient(
    'http://keycloak:8080/auth',
    'master',
    'api-client',
    'client-secret'
)

@app.get("/protected")
@require_auth
async def protected_route(request: Request):
    """Protected endpoint - requires valid JWT"""
    return {
        'message': 'Access granted',
        'user': request.user,
        'timestamp': datetime.now().isoformat()
    }

@app.post("/login")
async def login(credentials: Dict[str, str]):
    """User login endpoint"""
    # Validate credentials with Keycloak
    return {'token': 'jwt_token_here'}

@app.post("/logout")
async def logout(request: Request):
    """User logout endpoint"""
    auth_header = request.headers.get('Authorization', '')
    token = auth_header.split(' ')[1] if auth_header else None
    
    if token:
        client.logout_user(token)
    
    return {'message': 'Logout successful'}

@app.get("/user")
@require_auth
async def get_user(request: Request):
    """Get current user info"""
    return client.get_user_info(request.headers['Authorization'].split(' ')[1])
