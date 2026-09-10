{{/*
Shared pieces of the preview database Jobs (templates/preview-db-*.yaml).

Naming: under the current kustomize flow the per-PR nameSuffix and the
pull-request pod label both come from the pull-request ApplicationSet's
transforms (kustomize.nameSuffix / commonLabels); the chart itself stamps
neither. It only reads the label back through a fieldRef.
*/}}

{{- define "ghost-app.previewDatabase.jobName" -}}
{{- printf "%s-%s" .Release.Name .suffix -}}
{{- end -}}

{{- define "ghost-app.previewDatabase.image" -}}
{{- printf "%s:%s" .Values.previewDatabase.image.repository .Values.previewDatabase.image.tag -}}
{{- end -}}

{{/*
Env shared by the create and drop containers: connection details from the
app-db-secrets Secret, APP_NAME from the namespace (app name == namespace)
and PR_NUMBER from the pod label the ApplicationSet stamps.
*/}}
{{- define "ghost-app.previewDatabase.env" -}}
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
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
- name: PR_NUMBER
  valueFrom:
    fieldRef:
      fieldPath: metadata.labels['{{ $pd.pullRequestLabel }}']
{{- end -}}
