{{/*
Resource name. Defaults to the chart name but follows the release name when
installed under a different one, so two releases can coexist.
*/}}
{{- define "kubeplayground.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Labels every object carries. app.kubernetes.io/* are the conventional set —
the same ones `kubectl get -l` and most tooling expect.
*/}}
{{- define "kubeplayground.labels" -}}
app.kubernetes.io/name: {{ include "kubeplayground.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/*
Selector labels: the SUBSET that must never change. A Deployment's
spec.selector is immutable after creation, so anything volatile (version,
chart) must stay out of it or upgrades fail.
*/}}
{{- define "kubeplayground.selectorLabels" -}}
app: {{ include "kubeplayground.name" . }}-api
{{- end -}}
