/*
Copyright 2016 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1

import (
	"k8s.io/kubernetes/pkg/api/v1"
	"k8s.io/kubernetes/pkg/runtime"
)

func addDefaultingFuncs(scheme *runtime.Scheme) error {
	v1.RegisterDefaults(scheme)
	return scheme.AddDefaultingFuncs(
		v1.SetDefaults_Secret,
		v1.SetDefaults_ServiceSpec,
		v1.SetDefaults_NamespaceStatus,
		v1.SetDefaults_Pod,
		v1.SetDefaults_Node,
		v1.SetDefaults_ResourceQuota,
		v1.SetDefaults_ResourceQuotaSpec,
		v1.SetDefaults_ResourceQuotaStatus,
	)
}