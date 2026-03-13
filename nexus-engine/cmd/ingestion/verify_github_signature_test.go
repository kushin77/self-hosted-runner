package main

import (
    "encoding/hex"
    "crypto/hmac"
    "crypto/sha256"
    "testing"
)

func TestVerifyGitHubSignature_Valid(t *testing.T) {
    payload := []byte("hello-world")
    secret := "mysecret"
    mac := hmac.New(sha256.New, []byte(secret))
    mac.Write(payload)
    sig := mac.Sum(nil)
    sigHex := hex.EncodeToString(sig)
    header := "sha256=" + sigHex

    if !VerifyGitHubSignature(payload, header, secret) {
        t.Fatalf("expected valid signature to pass")
    }
}

func TestVerifyGitHubSignature_Invalid(t *testing.T) {
    payload := []byte("hello-world")
    secret := "mysecret"
    header := "sha256=deadbeef"

    if VerifyGitHubSignature(payload, header, secret) {
        t.Fatalf("expected invalid signature to fail")
    }
}

func TestVerifyGitHubSignature_BadHeader(t *testing.T) {
    payload := []byte("hello-world")
    secret := "mysecret"

    if VerifyGitHubSignature(payload, "", secret) {
        t.Fatalf("expected missing header to fail")
    }
    if VerifyGitHubSignature(payload, "notsha256=abc", secret) {
        t.Fatalf("expected malformed header to fail")
    }
}
