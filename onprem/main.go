// +build ignore

// Placeholder for On-Prem runner control plane binary (Issue #13)
// The final implementation will be a Go program that registers with GitHub,
// manages local runners via systemd units, and scales using Karpenter-like
// snapshot mechanism. For now this file is a stub with basic command line
// scaffolding.

package main

import (
    "flag"
    "fmt"
    "os"
)

func main() {
    mode := flag.String("mode", "serve", "operation mode: serve|validate|version")
    flag.Parse()

    switch *mode {
    case "serve":
        fmt.Println("[onprem] serve mode - not yet implemented")
    case "validate":
        fmt.Println("[onprem] validation passed")
        os.Exit(0)
    case "version":
        fmt.Println("onprem control plane v0.0.1")
    default:
        fmt.Fprintf(os.Stderr, "unknown mode %s\n", *mode)
        os.Exit(1)
    }
}
