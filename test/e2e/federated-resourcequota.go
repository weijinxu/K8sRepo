/*
Copyright 2015 The Kubernetes Authors.

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

package e2e

import (
	"fmt"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	fedclientset "k8s.io/kubernetes/federation/client/clientset_generated/federation_release_1_5"
	"k8s.io/kubernetes/federation/pkg/federation-controller/util"
	"k8s.io/kubernetes/pkg/api/errors"
	"k8s.io/kubernetes/pkg/api/v1"
	kubeclientset "k8s.io/kubernetes/pkg/client/clientset_generated/release_1_5"
	"k8s.io/kubernetes/pkg/util/wait"
	"k8s.io/kubernetes/test/e2e/framework"
)

const (
	FederatedResourceQuotaName    = "federated-resourcequota"
	FederatedResourceQuotaTimeout = 60 * time.Second
	MaxRetries             = 3
)

// Create/delete resourcequota api objects
var _ = framework.KubeDescribe("Federation resourcequotas [Feature:Federation12]", func() {
	var clusters map[string]*cluster // All clusters, keyed by cluster name

	f := framework.NewDefaultFederatedFramework("federated-resourcequota")

	Describe("Secret objects", func() {

		BeforeEach(func() {
			framework.SkipUnlessFederated(f.Client)
			clusters = map[string]*cluster{}
			registerClusters(clusters, UserAgentName, "", f)
		})

		AfterEach(func() {
			framework.SkipUnlessFederated(f.Client)
			unregisterClusters(clusters, f)
		})

		It("should be created and deleted successfully", func() {
			framework.SkipUnlessFederated(f.Client)
			rsqName := f.FederationNamespace.Name
			resourcequota := createSecretOrFail(f.FederationClientset_1_5, rsqName)
			defer func() { // Cleanup
				By(fmt.Sprintf("Deleting resourcequota %q in namespace %q", resourcequota.Name, rsqName))
				err := f.FederationClientset_1_5.Core().Secrets(rsqName).Delete(resourcequota.Name, &v1.DeleteOptions{})
				framework.ExpectNoError(err, "Error deleting resourcequota %q in namespace %q", resourcequota.Name, rsqName)
			}()
			// wait for resourcequota shards being created
			waitForSecretShardsOrFail(rsqName, resourcequota, clusters)
			resourcequota = updateSecretOrFail(f.FederationClientset_1_5, rsqName)
			waitForSecretShardsUpdatedOrFail(rsqName, resourcequota, clusters)
		})
	})
})

func createResourceQuotaOrFail(clientset *fedclientset.Clientset, namespace string) *v1.Secret {
	if clientset == nil || len(namespace) == 0 {
		Fail(fmt.Sprintf("Internal error: invalid parameters passed to createSecretOrFail: clientset: %v, namespace: %v", clientset, namespace))
	}

	resourcequota := &v1.ResourceQuota{
		ObjectMeta: v1.ObjectMeta{
			Name: FederatedResourceQuotaName,
		},
	}
	By(fmt.Sprintf("Creating resourcequota %q in namespace %q", resourcequota.Name, namespace))
	_, err := clientset.Core().ResourceQuotas(namespace).Create(resourcequota)
	framework.ExpectNoError(err, "Failed to create resourcequota %s", resourcequota.Name)
	By(fmt.Sprintf("Successfully created federated resourcequota %q in namespace %q", FederatedResourceQuotaName, namespace))
	return resourcequota
}

func updateResourceQuotaOrFail(clientset *fedclientset.Clientset, namespace string) *v1.Secret {
	if clientset == nil || len(namespace) == 0 {
		Fail(fmt.Sprintf("Internal error: invalid parameters passed to updateSecretOrFail: clientset: %v, namespace: %v", clientset, namespace))
	}

	var newSecret *v1.Secret
	for retryCount := 0; retryCount < MaxRetries; retryCount++ {
		resourcequota, err := clientset.Core().Secrets(namespace).Get(FederatedResourceQuotaName)
		if err != nil {
			framework.Failf("failed to get resourcequota %q: %v", FederatedResourceQuotaName, err)
		}

		// Update one of the data in the resourcequota.
		resourcequota.Data = map[string][]byte{
			"key": []byte("value"),
		}
		newSecret, err = clientset.Core().Secrets(namespace).Update(resourcequota)
		if err == nil {
			return newSecret
		}
		if !errors.IsConflict(err) && !errors.IsServerTimeout(err) {
			framework.Failf("failed to update resourcequota %q: %v", FederatedResourceQuotaName, err)
		}
	}
	framework.Failf("too many retries updating resourcequota %q", FederatedResourceQuotaName)
	return newSecret
}

func waitForResourceQuotaShardsOrFail(namespace string, resourcequota *v1.Secret, clusters map[string]*cluster) {
	framework.Logf("Waiting for resourcequota %q in %d clusters", resourcequota.Name, len(clusters))
	for _, c := range clusters {
		waitForSecretOrFail(c.Clientset, namespace, resourcequota, true, FederatedResourceQuotaTimeout)
	}
}

func waitForResourceQuotaOrFail(clientset *kubeclientset.Clientset, namespace string, resourcequota *v1.Secret, present bool, timeout time.Duration) {
	By(fmt.Sprintf("Fetching a federated resourcequota shard of resourcequota %q in namespace %q from cluster", resourcequota.Name, namespace))
	var clusterSecret *v1.Secret
	err := wait.PollImmediate(framework.Poll, timeout, func() (bool, error) {
		clusterSecret, err := clientset.Core().Secrets(namespace).Get(resourcequota.Name)
		if (!present) && errors.IsNotFound(err) { // We want it gone, and it's gone.
			By(fmt.Sprintf("Success: shard of federated resourcequota %q in namespace %q in cluster is absent", resourcequota.Name, namespace))
			return true, nil // Success
		}
		if present && err == nil { // We want it present, and the Get succeeded, so we're all good.
			By(fmt.Sprintf("Success: shard of federated resourcequota %q in namespace %q in cluster is present", resourcequota.Name, namespace))
			return true, nil // Success
		}
		By(fmt.Sprintf("Secret %q in namespace %q in cluster.  Found: %v, waiting for Found: %v, trying again in %s (err=%v)", resourcequota.Name, namespace, clusterSecret != nil && err == nil, present, framework.Poll, err))
		return false, nil
	})
	framework.ExpectNoError(err, "Failed to verify resourcequota %q in namespace %q in cluster: Present=%v", resourcequota.Name, namespace, present)

	if present && clusterSecret != nil {
		Expect(util.SecretEquivalent(*clusterSecret, *resourcequota))
	}
}

func waitForResourceQuotaShardsUpdatedOrFail(namespace string, resourcequota *v1.Secret, clusters map[string]*cluster) {
	framework.Logf("Waiting for resourcequota %q in %d clusters", resourcequota.Name, len(clusters))
	for _, c := range clusters {
		waitForSecretUpdateOrFail(c.Clientset, namespace, resourcequota, FederatedSecretTimeout)
	}
}

func waitForResourceQuotaUpdateOrFail(clientset *kubeclientset.Clientset, namespace string, resourcequota *v1.Secret, timeout time.Duration) {
	By(fmt.Sprintf("Fetching a federated resourcequota shard of resourcequota %q in namespace %q from cluster", resourcequota.Name, namespace))
	err := wait.PollImmediate(framework.Poll, timeout, func() (bool, error) {
		clusterSecret, err := clientset.Core().Secrets(namespace).Get(resourcequota.Name)
		if err == nil { // We want it present, and the Get succeeded, so we're all good.
			if util.SecretEquivalent(*clusterSecret, *resourcequota) {
				By(fmt.Sprintf("Success: shard of federated resourcequota %q in namespace %q in cluster is updated", resourcequota.Name, namespace))
				return true, nil
			} else {
				By(fmt.Sprintf("Expected equal resourcequotas. expected: %+v\nactual: %+v", *resourcequota, *clusterSecret))
			}
			By(fmt.Sprintf("Secret %q in namespace %q in cluster, waiting for resourcequota being updated, trying again in %s (err=%v)", resourcequota.Name, namespace, framework.Poll, err))
			return false, nil
		}
		By(fmt.Sprintf("Secret %q in namespace %q in cluster, waiting for being updated, trying again in %s (err=%v)", resourcequota.Name, namespace, framework.Poll, err))
		return false, nil
	})
	framework.ExpectNoError(err, "Failed to verify resourcequota %q in namespace %q in cluster", resourcequota.Name, namespace)
}
