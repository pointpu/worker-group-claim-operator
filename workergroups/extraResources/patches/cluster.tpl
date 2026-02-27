{{- define "workergroups.extraResources.patches.cluster" -}}
- fromFieldPath: metadata.labels["crossplane.io/claim-namespace"]
  toFieldPath: spec.forProvider.manifest.metadata.namespace

- type: FromCompositeFieldPath
  fromFieldPath: spec.parameters.clusterName
  toFieldPath: spec.forProvider.manifest.metadata.name

- fromFieldPath: metadata.labels["crossplane.io/claim-name"]
  toFieldPath: metadata.name
  transforms:
    - type: string
      string:
        type: Format
        fmt: "%s-cluster-observed"
{{- end -}}