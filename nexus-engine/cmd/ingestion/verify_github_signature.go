package main

import (
    "crypto/hmac"
    "crypto/sha256"
    "encoding/hex"
    "strings"
)

// VerifyGitHubSignature validates the X-Hub-Signature-256 header value.
// signatureHeader should be the header value (e.g. "sha256=abcdef...")
// secret is the webhook secret.
func VerifyGitHubSignature(payload []byte, signatureHeader, secret string) bool {
    if signatureHeader == "" || !strings.HasPrefix(signatureHeader, "sha256=") {
        return false
    }
    sig := strings.TrimPrefix(signatureHeader, "sha256=")
    mac := hmac.New(sha256.New, []byte(secret))
    mac.Write(payload)
    expected := mac.Sum(nil)
    decodedSig, err := hex.DecodeString(sig)
    if err != nil {
        return false
    }
    return hmac.Equal(decodedSig, expected)
}
