{{- define "workergroups.extraResources.patches.machineDeploymentObserver" -}}
- toFieldPath: spec.forProvider.manifest.metadata.namespace
  type: FromCompositeFieldPath
  fromFieldPath: metadata.labels["crossplane.io/claim-namespace"]

- toFieldPath: spec.forProvider.manifest.metadata.name
  combine:
    variables:
      - fromFieldPath: spec.parameters.clusterName
      - fromFieldPath: metadata.labels["crossplane.io/claim-name"]
    strategy: string
    string:
      fmt: "%s-%s"
  type: CombineFromComposite

- toFieldPath: metadata.name
  fromFieldPath: metadata.labels["crossplane.io/claim-name"]
  transforms:
    - type: string
      string:
        type: Format
        fmt: "%s-machinedeployment-observed"
  type: FromCompositeFieldPath

- toFieldPath: status.machineDeploymentStatus.conditions
  fromFieldPath: status.atProvider.manifest.status.conditions
  policy:
    fromFieldPath: Optional
    toFieldPath:   Replace
  type: ToCompositeFieldPath

- toFieldPath: status.machineDeploymentStatus.desiredReplicas
  fromFieldPath: status.atProvider.manifest.status.replicas
  policy:
    fromFieldPath: Optional
    toFieldPath:   Replace
  type: ToCompositeFieldPath

- toFieldPath: status.machineDeploymentStatus.readyReplicas
  fromFieldPath: status.atProvider.manifest.status.readyReplicas
  policy:
    fromFieldPath: Optional
    toFieldPath:   Replace
  type: ToCompositeFieldPath

- toFieldPath: status.machineDeploymentStatus.upToDateReplicas
  fromFieldPath: status.atProvider.manifest.status.upToDateReplicas
  policy:
    fromFieldPath: Optional
    toFieldPath:   Replace
  type: ToCompositeFieldPath
{{- end -}}