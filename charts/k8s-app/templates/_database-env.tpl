{{/*
Database connection env.

The apps read their configuration with nconf, whose env provider maps
`a__b__c` to `a.b.c`, so a MySQL connection is always the same handful of
variables over the `app-db-secrets` Secret. Creating that Secret
(secretsInjection.database) therefore also fills it in, into every container
and initContainer of every controller:

  db__client                  mysql2
  db__connection__charset     utf8mb4
  db__connection__database    the release namespace (namespace == app name)
  db__connection__host        secret key host (the VPC hostname)
  db__connection__port        secret key port
  db__connection__user        secret key user
  db__connection__password    secret key password
  db__connection__ssl__ca     secret key ssl_ca (DO managed MySQL needs TLS)

There are no options: an app that wants something else declares that env
itself and wins, which is how a preview points itself at its per-PR
database.
*/}}
{{- define "k8s-app.databaseEnv.values" -}}
{{- $secretRef := dict -}}
{{- range $var, $key := dict "host" "host" "port" "port" "user" "user" "password" "password" "ssl__ca" "ssl_ca" -}}
  {{- $_ := set $secretRef (printf "db__connection__%s" $var)
        (dict "valueFrom" (dict "secretKeyRef" (dict "name" "app-db-secrets" "key" $key))) -}}
{{- end -}}
{{- $env := merge $secretRef (dict
      "db__client" "mysql2"
      "db__connection__charset" "utf8mb4"
      "db__connection__database" .Release.Namespace) -}}
{{- include "k8s-app.env.inject" (dict "ctx" . "env" $env) -}}
{{- end -}}
