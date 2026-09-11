{{/*
Shared pieces of the preview database Jobs (templates/preview-db-*.yaml).

Naming: the per-PR identity is the helm release name (<app>-<pr>); the
pull-request pod label is stamped by the chart's controller defaults from
preview.prNumber.
*/}}

{{- define "k8s-app.previewDatabase.jobName" -}}
{{- printf "%s-%s" .Release.Name .suffix -}}
{{- end -}}

{{- define "k8s-app.previewDatabase.image" -}}
{{- printf "%s:%s" .Values.previewDatabase.image.repository .Values.previewDatabase.image.tag -}}
{{- end -}}

{{/*
Env shared by the create and drop containers: connection details from the
app-db-secrets Secret, APP_NAME from the namespace (app name == namespace)
and GITHUB_PR_NUMBER from preview.prNumber (a render-time literal).
*/}}
{{- define "k8s-app.previewDatabase.env" -}}
{{- $pd := .Values.previewDatabase -}}
- name: DB_USER
  valueFrom:
    secretKeyRef:
      name: {{ $pd.secretName }}
      key: {{ $pd.keys.user }}
- name: DB_PASS
  valueFrom:
    secretKeyRef:
      name: {{ $pd.secretName }}
      key: {{ $pd.keys.password }}
- name: DB_HOST
  valueFrom:
    secretKeyRef:
      name: {{ $pd.secretName }}
      key: {{ $pd.keys.host }}
- name: DB_PORT
  valueFrom:
    secretKeyRef:
      name: {{ $pd.secretName }}
      key: {{ $pd.keys.port }}
- name: APP_NAME
  value: {{ .Release.Namespace | quote }}
- name: GITHUB_PR_NUMBER
  value: {{ required "previewDatabase needs preview.prNumber (set by gitops-sync)" .Values.preview.prNumber | toString | quote }}
{{- end -}}
