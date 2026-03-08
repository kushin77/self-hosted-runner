{{ with secret "pki/issue/control-plane-role" "common_name=control-plane.example.local&ttl=72h" }}
{{ .Data.issuing_ca }}
{{ end }}
