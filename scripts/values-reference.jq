# Emits a Markdown table of the options under $prefix (comma-separated list
# of top-level or nested paths) from values.schema.json, skipping $exclude
# subtrees. Raw Kubernetes objects (their descriptions come straight from the
# k8s OpenAPI spec) are listed as one row and not descended into; the schema
# still validates every field inside them.
def k8s: (.description // "") | test("^[A-Z][A-Za-z]+ (holds|describes|represents|is a|is the|defines|specifies|contains) ");
def passthrough: ["env","envFrom","securityContext","resources","affinity","tolerations","topologySpreadConstraints","nodeSelector","lifecycle","dnsConfig","hostAliases","volumeClaimTemplates","sessionAffinityConfig","behavior","sysctls","resizePolicy","readinessGates","metrics","spec","podSecurityContext","manifest","volumeSpec","rules","hosts","tls","parentRefs","endpoints","podMetricsEndpoints","subjects","roleRef","items","ports","imagePullSecrets","schedulingGates","resourceClaims","selector","defaultBackend","dataSource","dataSourceRef","fileAttributeOverrides","binaryData","data","stringData"];
def typ: if (.type|type)=="array" then (.type|join(" / ")) elif .type then .type elif .oneOf then "one of several shapes" elif .anyOf then "" elif .enum then "enum" else "" end;
def row(path): {path: (path|join(".")), type: typ, default: (if has("default") then (.default|tojson) else "" end), enum: (if .enum then (.enum|map(tostring)|join(", ")) else "" end), description: ((.description // "") | gsub("\n"; " ") | gsub("\\|"; "\\|"))};
def walk_(path):
  (if (path|length)>0 then row(path) else empty end),
  (if (path|length)>0 and ((path[-1] as $k | passthrough | index($k)) != null or k8s) then empty
   else
    (if (.properties|type)=="object" then (.properties | to_entries[] | .key as $k | .value | walk_(path + [$k])) else empty end),
    (if (.additionalProperties|type)=="object" then (.additionalProperties | walk_(path + ["<id>"])) else empty end),
    (if (.items|type)=="object" then (.items | walk_(path + ["[]"])) else empty end),
    (if (.oneOf|type)=="array" then (.oneOf[] | walk_(path)) else empty end),
    (if (.anyOf|type)=="array" then (.anyOf[] | walk_(path)) else empty end),
    (if (.allOf|type)=="array" then (.allOf[] | walk_(path)) else empty end)
   end);
($prefix | split(",")) as $prefixes | ($exclude | split(",") | map(select(length>0))) as $excludes |
[walk_([])]
| unique_by(.path)
| map(select(.description != "" or ((.path|endswith(".[]")|not) and (.path|endswith(".<id>")|not))))
| map(select(.path as $p | any($prefixes[]; . as $x | $p == $x or ($p|startswith($x + ".")))))
| map(select(.path as $p | any($excludes[]; . as $x | $p == $x or ($p|startswith($x + "."))) | not))
| sort_by(.path)
| "| Key | Type | Default | Description |", "|---|---|---|---|",
  (.[] | "| `" + .path + "` | " + .type + (if .enum != "" then " (" + .enum + ")" else "" end) + " | " + (if .default != "" then "`" + .default + "`" else "" end) + " | " + .description + " |")
