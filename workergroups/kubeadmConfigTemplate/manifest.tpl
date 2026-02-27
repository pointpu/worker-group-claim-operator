{{- define "workergroups.kubeadmConfigTemplate.manifest" -}}
{{- printf `

{{- define "default.kubeletConfig" }}%s{{- end }}

{{- define "default.kubeadmTemplateSpec" }}%s{{- end }}

{{- $name                        := index .observed.composite.resource.metadata.labels "crossplane.io/claim-name"  }}
{{- $namespace                   := index .observed.composite.resource.metadata.labels "crossplane.io/claim-namespace"  }}
{{- $clusterName                 := index .observed.composite.resource.spec.parameters "clusterName" }}
{{- $ctxExists                   := false }}
{{- $kctExists                   := false }}
{{- $obs                         := (get .observed.resources "cluster-observed" | default (dict)) -}}

{{- $kctNameObject               := printf "%%s-kubeadmconfigtemplate" $name }}
{{- $kctNameObject               := "" }}
{{- $kubeadmConfigTemplateName   := printf "%%s-%%s-kubeadmconfigtemplate" $clusterName $name | lower }}
{{- $machineDeploymentName       := printf "%%s-%%s" $clusterName $name | lower }}

{{- $defaultKubeletConfig        := fromYaml (include "default.kubeletConfig" .) }}
{{- $customKubeletConfig         := .observed.composite.resource.spec.parameters.kubeletConfiguration | default dict }}
{{- $mergedKubeletConfig         := mergeOverwrite $defaultKubeletConfig $customKubeletConfig }}
{{- $mergedKubeletConfigYaml     := toYaml $mergedKubeletConfig }}

{{- $clusterDNS                  := dig "clusterDNS" "" .observed.composite.resource.spec.parameters -}}
{{- $clusterDomain               := dig "clusterDomain" "" .observed.composite.resource.spec.parameters -}}

{{- $k8sVer                      := "" }}
{{- $runcVer                     := "" }}
{{- $containerdVer               := "" }}
{{- $crictlVer                   := "" }}
{{- $pauseVer                    := "" }}
{{- $kctSpec                     := "" }}
{{- $kctHash                     := "" }}

{{- if hasKey .observed.resources "kubeadmconfigtemplateWg" }}
  {{- $kctExists = true }}
{{- end }}

{{- $clusterVarsList := dig "resource" "status" "atProvider" "manifest" "spec" "topology" "variables" (list) $obs -}}
{{- $clusterVars := dict -}}
{{- range $v := $clusterVarsList }}
  {{- $varName  := index $v "name" -}}
  {{- $varValue := index $v "value" -}}
  {{- if and $varName (ne $varName "") }}
    {{- $_ := set $clusterVars $varName $varValue -}}
  {{- end }}
{{- end }}

{{- $k8sVer = dig "resource" "status" "atProvider" "manifest" "spec" "topology" "version" "" $obs -}}

{{- $runcVer       = index $clusterVars "runc_version"       | default "" -}}
{{- $containerdVer = index $clusterVars "containerd_version" | default "" -}}
{{- $crictlVer     = index $clusterVars "crictl_version"     | default "" -}}
{{- $pauseVer      = index $clusterVars "pause_version"      | default "" -}}

{{- $kubeadmVer := $k8sVer -}}
{{- $kubectlVer := $k8sVer -}}
{{- $kubeletVer := $k8sVer -}}

{{- $ctx := dict
  "clusterDNS"                    $clusterDNS
  "clusterDomain"                 $clusterDomain
  "clusterName"                   $clusterName
  "runcVer"                       $runcVer
  "containerdVer"                 $containerdVer
  "crictlVer"                     $crictlVer
  "kubeadmVer"                    $kubeadmVer
  "kubectlVer"                    $kubectlVer
  "kubeletVer"                    $kubeletVer
  "machineDeploymentName"         $machineDeploymentName
  "pauseVer"                      $pauseVer
  "mergedKubeletConfigYaml"       $mergedKubeletConfigYaml
}}

{{- $ctxForHash := dict
  "clusterDNS"                    $clusterDNS
  "clusterDomain"                 $clusterDomain
  "clusterName"                   $clusterName
  "runcVer"                       $runcVer
  "containerdVer"                 $containerdVer
  "crictlVer"                     $crictlVer
  "kubeadmVer"                    $kubeadmVer
  "kubectlVer"                    $kubectlVer
  "kubeletVer"                    $kubeletVer
  "pauseVer"                      $pauseVer
}}

{{- $ctxExists := ne $kubeadmVer "" -}}

{{- if $ctxExists -}}
  {{- $kctSpec                     = include "default.kubeadmTemplateSpec" $ctx -}}
  {{- $kctHash                     = (sha256sum (toJson $ctxForHash) | trunc 8) -}}
  {{- $kubeadmConfigTemplateName   = printf "%%s-%%s-kubeadmconfigtemplate-%%s" $clusterName $name $kctHash | lower }}
  {{- $kctNameObject               = printf "%%s-kubeadmconfigtemplate" $name }}
{{- end -}}

{{- if or $kctExists $ctxExists -}}
---
apiVersion: kubernetes.crossplane.io/v1alpha2
kind: Object
metadata:
  name: {{ $kctNameObject }}
  annotations:
    gotemplating.fn.crossplane.io/composition-resource-name: kubeadmconfigtemplateWg
    gotemplating.fn.crossplane.io/ready: "True"
spec:
  forProvider:
    manifest:
      apiVersion: bootstrap.cluster.x-k8s.io/v1beta2
      kind: KubeadmConfigTemplate
      metadata:
        name: {{ $kubeadmConfigTemplateName }}
        namespace: {{ $namespace }}
        annotations:
          argocd.argoproj.io/compare-options: "IgnoreExtraneous"
      spec:
        template:
          metadata: null
          spec:
            {{ $kctSpec | nindent 12 }}
{{- end }}


` ( include "workergroups.kubeletConfig.customConfig.default" . ) ( include "workergroups.kubeadmConfigTemplate.spec.default" . ) }}
{{- end }}

