{{- define "base.usages.default" -}}
base:
  apiVersion: protection.crossplane.io/v1beta1
  kind: ClusterUsage
  spec:
    replayDeletion: true
    of:
      apiVersion: kubernetes.crossplane.io/v1alpha2
      kind: Object
      resourceRef:
        name: ""
    by:
      apiVersion: kubernetes.crossplane.io/v1alpha2
      kind: Object
      resourceRef:
        name: ""
{{- end -}}
