{{- /* template for rendering registry creds from KV */ -}}
{{- with secret "secret/data/registries/staging" -}}
{
  "username": "{{ .Data.data.username }}",
  "password": "{{ .Data.data.password }}"
}
{{- end -}}
