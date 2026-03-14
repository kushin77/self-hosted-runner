package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"golang.org/x/oauth2"
)

// KeycloakClient wraps OIDC operations
type KeycloakClient struct {
	provider     *oidc.Provider
	oauth2Config *oauth2.Config
	verifier     *oidc.IDTokenVerifier
}

// NewKeycloakClient creates a new Keycloak OIDC client
func NewKeycloakClient(keycloakURL, realm, clientID, clientSecret, redirectURL string) (*KeycloakClient, error) {
	ctx := context.Background()

	// Discover OIDC configuration
	provider, err := oidc.NewProvider(ctx, fmt.Sprintf("%s/auth/realms/%s", keycloakURL, realm))
	if err != nil {
		return nil, err
	}

	// Create OAuth2 config
	oauth2Config := &oauth2.Config{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		RedirectURL:  redirectURL,
		Endpoint:     provider.Endpoint(),
		Scopes:       []string{oidc.ScopeOpenID, "profile", "email"},
	}

	// Create ID token verifier
	verifier := provider.Verifier(&oidc.Config{ClientID: clientID})

	return &KeycloakClient{
		provider:     provider,
		oauth2Config: oauth2Config,
		verifier:     verifier,
	}, nil
}

// GetLoginURL generates a login URL
func (kc *KeycloakClient) GetLoginURL(state string) string {
	return kc.oauth2Config.AuthCodeURL(state)
}

// HandleCallback processes OAuth2 callback
func (kc *KeycloakClient) HandleCallback(ctx context.Context, code string) (map[string]interface{}, error) {
	// Exchange authorization code for tokens
	token, err := kc.oauth2Config.Exchange(ctx, code)
	if err != nil {
		return nil, err
	}

	// Get raw ID token
	rawIDToken, ok := token.Extra("id_token").(string)
	if !ok {
		return nil, fmt.Errorf("no id_token in token response")
	}

	// Parse and verify ID token
	idToken, err := kc.verifier.Verify(ctx, rawIDToken)
	if err != nil {
		return nil, err
	}

	// Extract claims
	var claims map[string]interface{}
	if err := idToken.Claims(&claims); err != nil {
		return nil, err
	}

	claims["access_token"] = token.AccessToken
	claims["refresh_token"] = token.RefreshToken
	claims["expires_at"] = token.Expiry

	return claims, nil
}

// ValidateToken validates an access token
func (kc *KeycloakClient) ValidateToken(ctx context.Context, token string) (map[string]interface{}, error) {
	idToken, err := kc.verifier.Verify(ctx, token)
	if err != nil {
		return nil, err
	}

	var claims map[string]interface{}
	if err := idToken.Claims(&claims); err != nil {
		return nil, err
	}

	return claims, nil
}

// Middleware for protecting routes
func (kc *KeycloakClient) AuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, "Missing authorization header", http.StatusUnauthorized)
			return
		}

		// Extract Bearer token
		var token string
		fmt.Sscanf(authHeader, "Bearer %s", &token)

		// Validate token
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		claims, err := kc.ValidateToken(ctx, token)
		if err != nil {
			http.Error(w, "Invalid token", http.StatusUnauthorized)
			return
		}

		// Store claims in request context
		ctx = context.WithValue(r.Context(), "claims", claims)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// Example usage with Gin
package main

import (
	"github.com/gin-gonic/gin"
	"context"
)

func main() {
	keycloak, err := NewKeycloakClient(
		"http://keycloak:8080/auth",
		"master",
		"api-client",
		"client-secret",
		"http://localhost:8080/callback",
	)
	if err != nil {
		log.Fatal(err)
	}

	router := gin.Default()

	// Login endpoint
	router.GET("/login", func(c *gin.Context) {
		state := "random-state" // In production, generate a secure random state
		loginURL := keycloak.GetLoginURL(state)
		c.Redirect(http.StatusFound, loginURL)
	})

	// Callback endpoint
	router.GET("/callback", func(c *gin.Context) {
		code := c.Query("code")
		claims, err := keycloak.HandleCallback(context.Background(), code)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, claims)
	})

	// Protected endpoint
	router.GET("/protected",
		func(c *gin.Context) {
			authHeader := c.GetHeader("Authorization")
			if authHeader == "" {
				c.JSON(http.StatusUnauthorized, gin.H{"error": "Missing auth header"})
				return
			}

			var token string
			fmt.Sscanf(authHeader, "Bearer %s", &token)

			claims, err := keycloak.ValidateToken(context.Background(), token)
			if err != nil {
				c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token"})
				return
			}

			c.JSON(http.StatusOK, gin.H{
				"message": "Access granted",
				"user":    claims,
			})
		},
	)

	router.Run(":8080")
}
