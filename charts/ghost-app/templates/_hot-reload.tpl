{{/*
Hot reload for PR previews.

Returns a bjw-s values fragment that is deep-merged over the user's values by
templates/common.yaml when hotReload.enabled is true:

  - controllers.<controller>.initContainers.git-sync-init  one-time clone
  - controllers.<controller>.containers.git-sync           polling sidecar
  - controllers.<controller>.containers.<container>        command/args swapped
                                                           for the dev runner
  - configMaps.git-sync-hosts                              pinned known_hosts
  - persistence.workspace / git-sync-ssh / git-sync-hosts  mounted ONLY into the
                                                           containers above
  - defaultPodOptions.securityContext.fsGroup              so git-sync can read
                                                           the mounted SSH key

Nothing else in the pod changes: env, envFrom and other volumes stay exactly
as the app declared them.
*/}}

{{- define "ghost-app.hotReload.checkoutPath" -}}
{{- printf "%s/%s" .Values.hotReload.gitSync.root .Values.hotReload.gitSync.link -}}
{{- end -}}

{{- define "ghost-app.hotReload.sshKey" -}}
{{- default (printf "%s-git-sync-ssh" .Release.Namespace) .Values.hotReload.ssh.key -}}
{{- end -}}

{{- define "ghost-app.preview.gitRepo" -}}
{{- $pv := .Values.preview -}}
{{- coalesce .Values.hotReload.repo $pv.gitRepo (printf "git@github.com:%s/%s.git" $pv.owner .Release.Namespace) -}}
{{- end -}}

{{/*
git-sync env (git-sync reads GITSYNC_* when the flag is not given). Repo and
ref are literals at render time: gitops-sync passes preview.prNumber (the
__GITHUB_PR_NUMBER__ token) when snapshotting, so no pod-metadata reads are
needed.
*/}}
{{- define "ghost-app.hotReload.gitSyncEnv" -}}
{{- $hr := .Values.hotReload -}}
GITSYNC_REPO: {{ include "ghost-app.preview.gitRepo" . | quote }}
{{- if $hr.ref }}
GITSYNC_REF: {{ $hr.ref | quote }}
{{- else if .Values.preview.prNumber }}
GITSYNC_REF: {{ printf "refs/pull/%s/head" (.Values.preview.prNumber | toString) | quote }}
{{- else }}
{{- fail "hotReload needs a git ref: set hotReload.ref or preview.prNumber" -}}
{{- end }}
{{- end -}}

{{- define "ghost-app.hotReload.gitSyncArgs" -}}
{{- $hr := .Values.hotReload -}}
{{- if $hr.repo }}
- --repo={{ $hr.repo }}
{{- end }}
- --ssh-key-file=/etc/git-secret/ssh
- --ssh-known-hosts=true
- --ssh-known-hosts-file=/etc/git-hosts/known_hosts
- --root={{ $hr.gitSync.root }}
- --link={{ $hr.gitSync.link }}
- --depth={{ $hr.gitSync.depth }}
- --submodules=off
{{- range $hr.gitSync.extraArgs }}
- {{ . | quote }}
{{- end }}
{{- end -}}

{{- define "ghost-app.hotReload.defaultArgs" -}}
{{- $hr := .Values.hotReload -}}
{{- $checkout := include "ghost-app.hotReload.checkoutPath" . -}}
- |
  ln -sfn {{ $hr.app.nodeModules }} {{ $hr.workspace }}/node_modules
  exec {{ $hr.app.devCommand }} --legacy-watch --watch {{ $checkout }} --exec 'sh -c "cd {{ $checkout }} && exec {{ $hr.app.run }}"'
{{- end -}}

{{- define "ghost-app.hotReload.values" -}}
{{- $hr := .Values.hotReload -}}
{{- $controller := $hr.controller -}}
{{- $container := $hr.container -}}
{{- if not (hasKey .Values.controllers $controller) -}}
  {{- fail (printf "hotReload.controller '%s' does not exist under controllers" $controller) -}}
{{- end -}}
{{- if not (hasKey (index .Values.controllers $controller "containers" | default dict) $container) -}}
  {{- fail (printf "hotReload.container '%s' does not exist under controllers.%s.containers" $container $controller) -}}
{{- end -}}
{{- $gitSyncSecurityContext := dict
      "runAsUser" $hr.gitSync.uid
      "runAsGroup" $hr.gitSync.gid
      "runAsNonRoot" true
      "allowPrivilegeEscalation" false
      "capabilities" (dict "drop" (list "ALL")) -}}
{{- $gitSyncMounts := list (dict "path" $hr.workspace) -}}
{{- $sshMounts := list (dict "path" "/etc/git-secret" "readOnly" true) -}}
{{- $hostsMounts := list (dict "path" "/etc/git-hosts" "readOnly" true) -}}
defaultPodOptions:
  securityContext:
    fsGroup: {{ $hr.gitSync.gid }}
controllers:
  {{ $controller }}:
    initContainers:
      git-sync-init:
        image:
          repository: {{ $hr.gitSync.image.repository }}
          tag: {{ $hr.gitSync.image.tag }}
        securityContext: {{ $gitSyncSecurityContext | toJson }}
        resources: {{ $hr.gitSync.resources | toJson }}
        env:
          {{- include "ghost-app.hotReload.gitSyncEnv" . | nindent 10 }}
        args:
          {{- include "ghost-app.hotReload.gitSyncArgs" . | nindent 10 }}
          - --one-time
    containers:
      git-sync:
        image:
          repository: {{ $hr.gitSync.image.repository }}
          tag: {{ $hr.gitSync.image.tag }}
        securityContext: {{ $gitSyncSecurityContext | toJson }}
        resources: {{ $hr.gitSync.resources | toJson }}
        env:
          {{- include "ghost-app.hotReload.gitSyncEnv" . | nindent 10 }}
        args:
          {{- include "ghost-app.hotReload.gitSyncArgs" . | nindent 10 }}
          - --period={{ $hr.gitSync.period }}
          - --max-failures=-1
          # Give the dev runner time to observe the update and stop the old process.
          - --stale-worktree-timeout={{ $hr.gitSync.staleWorktreeTimeout }}
      {{ $container }}:
        # Keep the dev runner in the image directory. Each restart resolves the
        # current checkout afresh so its working directory follows git-sync.
        command: {{ $hr.app.command | toJson }}
        {{- if $hr.app.args }}
        args: {{ $hr.app.args | toJson }}
        {{- else }}
        args:
          {{- include "ghost-app.hotReload.defaultArgs" . | nindent 10 }}
        {{- end }}
configMaps:
  git-sync-hosts:
    data:
      known_hosts: {{ $hr.ssh.knownHosts | quote }}
persistence:
  workspace:
    type: emptyDir
    advancedMounts:
      {{ $controller }}:
        git-sync-init: {{ $gitSyncMounts | toJson }}
        git-sync: {{ $gitSyncMounts | toJson }}
        {{ $container }}: {{ $gitSyncMounts | toJson }}
  git-sync-ssh:
    type: secret
    # Project only the SSH deploy key into the git-sync containers, nothing else.
    name: {{ $hr.ssh.secretName }}
    defaultMode: 0440
    items:
      - key: {{ include "ghost-app.hotReload.sshKey" . }}
        path: ssh
    advancedMounts:
      {{ $controller }}:
        git-sync-init: {{ $sshMounts | toJson }}
        git-sync: {{ $sshMounts | toJson }}
  git-sync-hosts:
    type: configMap
    identifier: git-sync-hosts
    advancedMounts:
      {{ $controller }}:
        git-sync-init: {{ $hostsMounts | toJson }}
        git-sync: {{ $hostsMounts | toJson }}
{{- end -}}
