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

package resourcequota

import (

	"encoding/json"

	"fmt"
	"reflect"
	"sort"
	"time"

	fed "k8s.io/kubernetes/federation/apis/federation"
	federation_api "k8s.io/kubernetes/federation/apis/federation/v1beta1"
	federationclientset "k8s.io/kubernetes/federation/client/clientset_generated/federation_release_1_5"
	"k8s.io/kubernetes/federation/pkg/federation-controller/util"
	"k8s.io/kubernetes/federation/pkg/federation-controller/util/eventsink"
	"k8s.io/kubernetes/pkg/api"
	api_v1 "k8s.io/kubernetes/pkg/api/v1"
	"k8s.io/kubernetes/pkg/client/cache"
	kubeclientset "k8s.io/kubernetes/pkg/client/clientset_generated/release_1_5"
	"k8s.io/kubernetes/pkg/client/record"
	"k8s.io/kubernetes/pkg/controller"
	pkg_runtime "k8s.io/kubernetes/pkg/runtime"
	"k8s.io/kubernetes/pkg/util/flowcontrol"
	"k8s.io/kubernetes/pkg/watch"

	"github.com/golang/glog"
	"k8s.io/client-go/1.5/pkg/api/v1"
)

const (
	FedResourceQuotaPreferencesAnnotation = "federation.kubernetes.io/resource-quota-preferences"
	allClustersKey                        = "ALL_CLUSTERS"
	UserAgentName                         = "Federation-resourcequota-Controller"
)

func parseFederationResourceQuotaPreference(frq *v1.ResourceQuota) (*fed.FederatedResourceQuotaPreferences, error) {
	if frq.Annotations == nil {
		return nil, nil
	}
	frqPrefString, found := frq.Annotations[FedResourceQuotaPreferencesAnnotation]
	if !found {
		return nil, nil
	}
	var frqPref fed.FederatedResourceQuotaPreferences
	if err := json.Unmarshal([]byte(frqPrefString), &frqPref); err != nil {
		return nil, err
	}
	return &frqPref, nil
}

type ResourceQuotaController struct {
	// For triggering single resourcequota reconciliation. This is used when there is an
	// add/update/delete operation on a resourcequota in either federated API server or
	// in some member of the federation.
	resourceQuotaDeliverer *util.DelayingDeliverer

	// For triggering all resourcequotas reconciliation. This is used when
	// a new cluster becomes available.
	clusterDeliverer *util.DelayingDeliverer

	// Contains resourcequotas present in members of federation.
	resourceQuotaFederatedInformer util.FederatedInformer
	// For updating members of federation.
	federatedUpdater util.FederatedUpdater
	// Definitions of resourcequotas that should be federated.
	resourceQuotaInformerStore cache.Store
	// Informer controller for resourcequotas that should be federated.
	resourceQuotaInformerController cache.ControllerInterface

	// Client to federated api server.
	federatedApiClient federationclientset.Interface

	// Backoff manager for resourcequotas
	resourceQuotaBackoff *flowcontrol.Backoff

	// For events
	eventRecorder record.EventRecorder

	resourceQuotaReviewDelay time.Duration
	clusterAvailableDelay    time.Duration
	smallDelay               time.Duration
	updateTimeout            time.Duration
}

// NewResourceQuotaController returns a new resourcequota controller
func NewResourceQuotaController(client federationclientset.Interface) *ResourceQuotaController {
	broadcaster := record.NewBroadcaster()
	broadcaster.StartRecordingToSink(eventsink.NewFederatedEventSink(client))
	recorder := broadcaster.NewRecorder(api.EventSource{Component: "federated-resourcequotas-controller"})

	resourcequotacontroller := &ResourceQuotaController{
		federatedApiClient:       client,
		resourceQuotaReviewDelay: time.Second * 10,
		clusterAvailableDelay:    time.Second * 20,
		smallDelay:               time.Second * 3,
		updateTimeout:            time.Second * 30,
		resourceQuotaBackoff:     flowcontrol.NewBackOff(5*time.Second, time.Minute),
		eventRecorder:            recorder,
	}

	// Build delivereres for triggering reconciliations.
	resourcequotacontroller.resourceQuotaDeliverer = util.NewDelayingDeliverer()
	resourcequotacontroller.clusterDeliverer = util.NewDelayingDeliverer()

	// Start informer in federated API servers on resourcequotas that should be federated.
	resourcequotacontroller.resourceQuotaInformerStore, resourcequotacontroller.resourceQuotaInformerController = cache.NewInformer(
		&cache.ListWatch{
			ListFunc: func(options api.ListOptions) (pkg_runtime.Object, error) {
				versionedOptions := util.VersionizeV1ListOptions(options)
				return client.Core().ResourceQuotas(api_v1.NamespaceAll).List(versionedOptions)
			},
			WatchFunc: func(options api.ListOptions) (watch.Interface, error) {
				versionedOptions := util.VersionizeV1ListOptions(options)
				return client.Core().ResourceQuotas(api_v1.NamespaceAll).Watch(versionedOptions)
			},
		},
		&api_v1.ResourceQuota{},
		controller.NoResyncPeriodFunc(),
		util.NewTriggerOnAllChanges(func(obj pkg_runtime.Object) { resourcequotacontroller.deliverResourceQuotaObj(obj, 0, false) }))

	// Federated informer on resourcequotas in members of federation.
	resourcequotacontroller.resourceQuotaFederatedInformer = util.NewFederatedInformer(
		client,
		func(cluster *federation_api.Cluster, targetClient kubeclientset.Interface) (cache.Store, cache.ControllerInterface) {
			return cache.NewInformer(
				&cache.ListWatch{
					ListFunc: func(options api.ListOptions) (pkg_runtime.Object, error) {
						versionedOptions := util.VersionizeV1ListOptions(options)
						return targetClient.Core().ResourceQuotas(api_v1.NamespaceAll).List(versionedOptions)
					},
					WatchFunc: func(options api.ListOptions) (watch.Interface, error) {
						versionedOptions := util.VersionizeV1ListOptions(options)
						return targetClient.Core().ResourceQuotas(api_v1.NamespaceAll).Watch(versionedOptions)
					},
				},
				&api_v1.ResourceQuota{},
				controller.NoResyncPeriodFunc(),
				// Trigger reconciliation whenever something in federated cluster is changed. In most cases it
				// would be just confirmation that some resourcequota opration succeeded.
				util.NewTriggerOnAllChanges(
					func(obj pkg_runtime.Object) {
						resourcequotacontroller.deliverResourceQuotaObj(obj, resourcequotacontroller.resourceQuotaReviewDelay, false)
					},
				))
		},

		&util.ClusterLifecycleHandlerFuncs{
			ClusterAvailable: func(cluster *federation_api.Cluster) {
				// When new cluster becomes available process all the resourcequotas again.
				resourcequotacontroller.clusterDeliverer.DeliverAt(allClustersKey, nil, time.Now().Add(resourcequotacontroller.clusterAvailableDelay))
			},
		},
	)

	// Federated updeater along with Create/Update/Delete operations.
	resourcequotacontroller.federatedUpdater = util.NewFederatedUpdater(resourcequotacontroller.resourceQuotaFederatedInformer,
		func(client kubeclientset.Interface, obj pkg_runtime.Object) error {
			resourcequota := obj.(*api_v1.ResourceQuota)
			_, err := client.Core().ResourceQuotas(resourcequota.Namespace).Create(resourcequota)
			return err
		},
		func(client kubeclientset.Interface, obj pkg_runtime.Object) error {
			resourcequota := obj.(*api_v1.ResourceQuota)
			_, err := client.Core().ResourceQuotas(resourcequota.Namespace).Update(resourcequota)
			return err
		},
		func(client kubeclientset.Interface, obj pkg_runtime.Object) error {
			resourcequota := obj.(*api_v1.ResourceQuota)
			err := client.Core().ResourceQuotas(resourcequota.Namespace).Delete(resourcequota.Name, &api_v1.DeleteOptions{})
			return err
		})
	return resourcequotacontroller
}

func (resourcequotacontroller *ResourceQuotaController) Run(stopChan <-chan struct{}) {
	go resourcequotacontroller.resourceQuotaInformerController.Run(stopChan)
	resourcequotacontroller.resourceQuotaFederatedInformer.Start()
	go func() {
		<-stopChan
		resourcequotacontroller.resourceQuotaFederatedInformer.Stop()
	}()
	resourcequotacontroller.resourceQuotaDeliverer.StartWithHandler(func(item *util.DelayingDelivererItem) {
		resourcequota := item.Value.(*resourcequotaItem)
		resourcequotacontroller.reconcileResourceQuota(resourcequota.namespace, resourcequota.name)
	})
	resourcequotacontroller.clusterDeliverer.StartWithHandler(func(_ *util.DelayingDelivererItem) {
		resourcequotacontroller.reconcileResourceQuotasOnClusterChange()
	})
	util.StartBackoffGC(resourcequotacontroller.resourceQuotaBackoff, stopChan)
}

func getResourceQuotaKey(namespace, name string) string {
	return fmt.Sprintf("%s/%s", namespace, name)
}

// Internal structure for data in delaying deliverer.
type resourcequotaItem struct {
	namespace string
	name      string
}

func (resourcequotacontroller *ResourceQuotaController) deliverResourceQuotaObj(obj interface{}, delay time.Duration, failed bool) {
	resourcequota := obj.(*api_v1.ResourceQuota)
	resourcequotacontroller.deliverResourceQuota(resourcequota.Namespace, resourcequota.Name, delay, failed)
}

// Adds backoff to delay if this delivery is related to some failure. Resets backoff if there was no failure.
func (resourcequotacontroller *ResourceQuotaController) deliverResourceQuota(namespace string, name string, delay time.Duration, failed bool) {
	key := getResourceQuotaKey(namespace, name)
	if failed {
		resourcequotacontroller.resourceQuotaBackoff.Next(key, time.Now())
		delay = delay + resourcequotacontroller.resourceQuotaBackoff.Get(key)
	} else {
		resourcequotacontroller.resourceQuotaBackoff.Reset(key)
	}
	resourcequotacontroller.resourceQuotaDeliverer.DeliverAfter(key,
		&resourcequotaItem{namespace: namespace, name: name}, delay)
}

// Check whether all data stores are in sync. False is returned if any of the informer/stores is not yet
// synced with the corresponding api server.
func (resourcequotacontroller *ResourceQuotaController) isSynced() bool {
	if !resourcequotacontroller.resourceQuotaFederatedInformer.ClustersSynced() {
		glog.V(2).Infof("Cluster list not synced")
		return false
	}
	clusters, err := resourcequotacontroller.resourceQuotaFederatedInformer.GetReadyClusters()
	if err != nil {
		glog.Errorf("Failed to get ready clusters: %v", err)
		return false
	}
	if !resourcequotacontroller.resourceQuotaFederatedInformer.GetTargetStore().ClustersSynced(clusters) {
		return false
	}
	return true
}

// The function triggers reconciliation of all federated resourcequotas.
func (resourcequotacontroller *ResourceQuotaController) reconcileResourceQuotasOnClusterChange() {
	if !resourcequotacontroller.isSynced() {
		resourcequotacontroller.clusterDeliverer.DeliverAt(allClustersKey, nil, time.Now().Add(resourcequotacontroller.clusterAvailableDelay))
	}
	for _, obj := range resourcequotacontroller.resourceQuotaInformerStore.List() {
		resourcequota := obj.(*api_v1.ResourceQuota)
		resourcequotacontroller.deliverResourceQuota(resourcequota.Namespace, resourcequota.Name, resourcequotacontroller.smallDelay, false)
	}
}

func (resourcequotacontroller *ResourceQuotaController) reconcileResourceQuota(namespace string, resourcequotaName string) {

	if !resourcequotacontroller.isSynced() {
		resourcequotacontroller.deliverResourceQuota(namespace, resourcequotaName, resourcequotacontroller.clusterAvailableDelay, false)
		return
	}

	key := getResourceQuotaKey(namespace, resourcequotaName)
	baseResourceQuotaObj, exist, err := resourcequotacontroller.resourceQuotaInformerStore.GetByKey(key)
	if err != nil {
		glog.Errorf("Failed to query main resourcequota store for %v: %v", key, err)
		resourcequotacontroller.deliverResourceQuota(namespace, resourcequotaName, 0, true)
		return
	}

	if !exist {
		// Not federated resourcequota, ignoring.
		return
	}
	baseResourceQuota := baseResourceQuotaObj.(*api_v1.ResourceQuota)

	clusters, err := resourcequotacontroller.resourceQuotaFederatedInformer.GetReadyClusters()
	if err != nil {
		glog.Errorf("Failed to get cluster list: %v", err)
		resourcequotacontroller.deliverResourceQuota(namespace, resourcequotaName, resourcequotacontroller.clusterAvailableDelay, false)
		return
	}

	operations := make([]util.FederatedOperation, 0)
	for _, cluster := range clusters {
		clusterResourceQuotaObj, found, err := resourcequotacontroller.resourceQuotaFederatedInformer.GetTargetStore().GetByKey(cluster.Name, key)
		if err != nil {
			glog.Errorf("Failed to get %s from %s: %v", key, cluster.Name, err)
			resourcequotacontroller.deliverResourceQuota(namespace, resourcequotaName, 0, true)
			return
		}

		desiredResourceQuota := &api_v1.ResourceQuota{
			ObjectMeta: util.CopyObjectMeta(baseResourceQuota.ObjectMeta),
			Spec:       baseResourceQuota.Spec,
			Status:     baseResourceQuota.Status,
		}

		if !found {
			resourcequotacontroller.eventRecorder.Eventf(baseResourceQuota, api.EventTypeNormal, "CreateInCluster",
				"Creating resourcequota in cluster %s", cluster.Name)

			operations = append(operations, util.FederatedOperation{
				Type:        util.OperationTypeAdd,
				Obj:         desiredResourceQuota,
				ClusterName: cluster.Name,
			})
		} else {
			clusterResourceQuota := clusterResourceQuotaObj.(*api_v1.ResourceQuota)

			// Update existing resourcequota, if needed.
			if !util.ObjectMetaEquivalent(desiredResourceQuota.ObjectMeta, clusterResourceQuota.ObjectMeta) ||
				!reflect.DeepEqual(desiredResourceQuota.Spec, clusterResourceQuota.Spec) ||
					!reflect.DeepEqual(desiredResourceQuota.Status, clusterResourceQuota.Status) {

				resourcequotacontroller.eventRecorder.Eventf(baseResourceQuota, api.EventTypeNormal, "UpdateInCluster",
					"Updating resourcequota in cluster %s", cluster.Name)
				operations = append(operations, util.FederatedOperation{
					Type:        util.OperationTypeUpdate,
					Obj:         desiredResourceQuota,
					ClusterName: cluster.Name,
				})
			}
		}
	}

	if len(operations) == 0 {
		// Everything is in order
		return
	}
	err = resourcequotacontroller.federatedUpdater.UpdateWithOnError(operations, resourcequotacontroller.updateTimeout,
		func(op util.FederatedOperation, operror error) {
			resourcequotacontroller.eventRecorder.Eventf(baseResourceQuota, api.EventTypeNormal, "UpdateInClusterFailed",
				"ResourceQuota update in cluster %s failed: %v", op.ClusterName, operror)
		})

	if err != nil {
		glog.Errorf("Failed to execute updates for %s: %v", key, err)
		resourcequotacontroller.deliverResourceQuota(namespace, resourcequotaName, 0, true)
		return
	}

	// Evertyhing is in order but lets be double sure
	resourcequotacontroller.deliverResourceQuota(namespace, resourcequotaName, resourcequotacontroller.resourceQuotaReviewDelay, false)
}
