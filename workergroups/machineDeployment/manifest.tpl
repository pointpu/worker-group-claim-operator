{{- define "workergroups.machineDeployment.manifest" -}}
{{ printf `

{{- define "default.kubeletConfig" }}%s{{- end }}

{{- define "default.kubeadmTemplateSpec" }}%s{{- end }}

{{- $name                        := index .observed.composite.resource.metadata.labels "crossplane.io/claim-name"  }}
{{- $namespace                   := index .observed.composite.resource.metadata.labels "crossplane.io/claim-namespace"  }}
{{- $clusterName                 := index .observed.composite.resource.spec.parameters "clusterName" }}
{{- $replicas                    := index .observed.composite.resource.spec.parameters "replicas" }}
{{- $cpuCount                    := index .observed.composite.resource.spec.parameters.configuration "cpuCount" }}
{{- $diskSize                    := index .observed.composite.resource.spec.parameters.configuration "diskSize" }}
{{- $memory                      := index .observed.composite.resource.spec.parameters.configuration "memory" }}

{{- $clusterObs                  := (get .observed.resources "cluster-observed" | default (dict)) -}}
{{- $ctxParams                   := printf "cpu=%%v;mem=%%v;disk=%%v" $cpuCount $memory $diskSize -}}
{{- $ctxParamsHash               := (sha256sum $ctxParams | trunc 10) -}}

{{- $kubeadmConfigTemplateName   := printf "%%s-%%s-kubeadmconfigtemplate" $clusterName $name | lower }}
{{- $begetMachineTemplateName    := printf "%%s-%%s-%%s" $clusterName $name $ctxParamsHash | lower }}
{{- $machineDeploymentNameObject := printf "%%s-machinedeployment" $name }}
{{- $machineDeploymentName       := printf "%%s-%%s" $clusterName $name | lower }}
{{- $kctHash                     := "" }}

{{- $defaultKubeletConfig        := fromYaml (include "default.kubeletConfig" .) }}
{{- $customKubeletConfig         := .observed.composite.resource.spec.parameters.kubeletConfiguration | default dict }}
{{- $mergedKubeletConfig         := mergeOverwrite $defaultKubeletConfig $customKubeletConfig }}
{{- $mergedKubeletConfigYaml     := toYaml $mergedKubeletConfig }}

{{- $clusterDNS                  := dig "clusterDNS" "" .observed.composite.resource.spec.parameters -}}
{{- $clusterDomain               := dig "clusterDomain" "" .observed.composite.resource.spec.parameters -}}

{{- $mdExists                    := false }}
{{- $kctExists                   := false }}
{{- $kubeadmVerExists            := false }}
{{- $controlPlaneInitialized     := false }}
{{- $kubeadmDepsOk               := false }}

{{- $clusterVer                  := "" }}
{{- $k8sVer                      := "" }}
{{- $runcVer                     := "" }}
{{- $containerdVer               := "" }}
{{- $crictlVer                   := "" }}
{{- $kubectlVer                  := "" }}
{{- $kubeletVer                  := "" }}
{{- $pauseVer                    := "" }}

{{- with .observed.resources.machineDeployment }}
  {{- $mdExists = true }}
{{- end }}

{{- $clusterVarsList := dig "resource" "status" "atProvider" "manifest" "spec" "topology" "variables" (list) $clusterObs -}}
{{- $clusterVars := dict -}}
{{- range $v := $clusterVarsList }}
  {{- $varName  := index $v "name" -}}
  {{- $varValue := index $v "value" -}}
  {{- if and $varName (ne $varName "") }}
    {{- $_ := set $clusterVars $varName $varValue -}}
  {{- end }}
{{- end }}

{{- $k8sVer        = dig "resource" "status" "atProvider" "manifest" "spec" "topology" "version" "" $clusterObs -}}

{{- $runcVer       = index $clusterVars "runc_version"       | default "" -}}
{{- $containerdVer = index $clusterVars "containerd_version" | default "" -}}
{{- $crictlVer     = index $clusterVars "crictl_version"     | default "" -}}
{{- $pauseVer      = index $clusterVars "pause_version"      | default "" -}}

{{- $kubectlVer    = $k8sVer -}}
{{- $kubeletVer    = $k8sVer -}}
{{- $kubeadmVer    := $k8sVer -}}
{{- $clusterVer    = $k8sVer -}}
{{- $kubeadmVerExists = ne $kubeadmVer "" }}

{{- $ctxForHash := dict
  "clusterDNS"              $clusterDNS
  "clusterDomain"           $clusterDomain
  "clusterName"             $clusterName
  "runcVer"                 $runcVer
  "containerdVer"           $containerdVer
  "crictlVer"               $crictlVer
  "kubeadmVer"              $kubeadmVer
  "kubectlVer"              $kubectlVer
  "kubeletVer"              $kubeletVer
  "pauseVer"                $pauseVer
}}

{{- if $kubeadmVerExists -}}
  {{- $kctHash                   = (sha256sum (toJson $ctxForHash) | trunc 8) -}}
  {{- $kubeadmConfigTemplateName = printf "%%s-%%s-kubeadmconfigtemplate-%%s" $clusterName $name $kctHash | lower -}}
{{- end -}}

{{- $kctExists = and (ne $kctHash "") (not (empty (get .observed.resources "kubeadmconfigtemplateWg"))) -}}

{{- range $cond := (dig "resource" "status" "atProvider" "manifest" "status" "conditions" (list) $clusterObs) -}}
  {{- if and (eq (dig "type" "" $cond) "ControlPlaneAvailable") (eq (dig "status" "" $cond) "True") -}}
    {{- $controlPlaneInitialized = true }}
  {{- end -}}
{{- end -}}

{{- $kubeadmResReadyAnn    := dig "resource" "status" "atProvider" "manifest" "metadata" "annotations" "dependency.kubeadmres.in-cloud.io/ready" "" $clusterObs -}}
{{- $kubeadmResReadyExists := ne $kubeadmResReadyAnn "" -}}
{{- $kubeadmResReady       := eq $kubeadmResReadyAnn "true" -}}
{{- $kubeadmDepsOk          = or (not $kubeadmResReadyExists) $kubeadmResReady -}}

{{ if or
  $mdExists
  (and
    $kctExists
    $kubeadmVerExists
    $controlPlaneInitialized
    $kubeadmDepsOk
  )
}}
---
apiVersion: kubernetes.crossplane.io/v1alpha2
kind: Object
metadata:
  name: {{ $machineDeploymentNameObject }}
  annotations:
    gotemplating.fn.crossplane.io/composition-resource-name: machineDeployment
    gotemplating.fn.crossplane.io/ready: "True"
spec:
  forProvider:
    manifest:
      apiVersion: cluster.x-k8s.io/v1beta2
      kind: MachineDeployment
      metadata:
        name: {{ $machineDeploymentName }}
        namespace: {{ $namespace }}
        labels:
          cluster.x-k8s.io/cluster-name: {{ $clusterName }}
          cluster.x-k8s.io/deployment-name: {{ $machineDeploymentName }}
      spec:
        clusterName: {{ $clusterName }}
        replicas: {{ $replicas }}
        progressDeadlineSeconds: 300
        rollout:
          strategy:
            rollingUpdate: 
              maxUnavailable: 1
        selector:
          matchLabels:
            cluster.x-k8s.io/cluster-name: {{ $clusterName }}
        template:
          metadata:
            labels:
              node-group.beget.com/name: {{ $machineDeploymentName }}
        {{- range $k, $v := dig "spec" "parameters" "labels" nil .observed.composite.resource }}
              {{ $k }}: {{ $v | quote }}
        {{- end }}
          spec:
          {{- $taints := dig "spec" "parameters" "taints" nil .observed.composite.resource }}
          {{- if $taints }}
            taints:
            {{- $taints | toYaml | nindent 12 }}
          {{- end }}
            clusterName: {{ $clusterName }}
            nodeDrainTimeout: 1m
            bootstrap:
              configRef:
                apiGroup: bootstrap.cluster.x-k8s.io
                kind: KubeadmConfigTemplate
                name: {{ $kubeadmConfigTemplateName }}
                namespace: {{ $namespace }}
            infrastructureRef:
              apiGroup: infrastructure.cluster.x-k8s.io
              kind: BegetMachineTemplate
              name: {{ $begetMachineTemplateName }}
              namespace: {{ $namespace }}
            version: {{ $clusterVer }}
{{- end }}

` ( include "workergroups.kubeletConfig.customConfig.default" . ) ( include "workergroups.kubeadmConfigTemplate.spec.default" . ) }}
{{- end -}}