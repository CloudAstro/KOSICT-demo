{{/*
Template processing helper function
Expects a dictionary as input:
- values: the value(s) to be substituted
- context: the context used for template substitution

Usage: {{ include "tpl-values" (dict "values" <value(s)> "context" $) }}
*/}}
{{- define "tpl-values" }}
  {{- if kindIs "string" .values }}
    {{- tpl .values .context }}
  {{- else }}
    {{- tpl (toYaml .values) .context }}
  {{- end }}
{{- end }}