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
	"time"

	fed "k8s.io/kubernetes/federation/apis/federation"
	federation_api "k8s.io/kubernetes/federation/apis/federation/v1beta1"
	federationclientset "k8s.io/kubernetes/federation/client/clientset_generated/federation_release_1_5"
	"k8s.io/kubernetes/federation/pkg/federation-controller/util"
	"k8s.io/kubernetes/federation/pkg/federation-controller/util/deletionhelper"
	"k8s.io/kubernetes/federation/pkg/federation-controller/util/eventsink"
	"k8s.io/kubernetes/pkg/api"
	"k8s.io/kubernetes/pkg/api/errors"
	api_v1 "k8s.io/kubernetes/pkg/api/v1"
	"k8s.io/kubernetes/pkg/client/cache"
	kubeclientset "k8s.io/kubernetes/pkg/client/clientset_generated/release_1_5"
	"k8s.io/kubernetes/pkg/client/record"
	"k8s.io/kubernetes/pkg/controller"
	"k8s.io/kubernetes/pkg/conversion"
	pkg_runtime "k8s.io/kubernetes/pkg/runtime"
	"k8s.io/kubernetes/pkg/util/flowcontrol"
	"k8s.io/kubernetes/pkg/watch"

	"github.com/golang/glog"
	//"k8s.io/client-go/1.5/pkg/api/v1"
)

const (
	FedResourceQuotaPreferencesAnnotation = "federation.kubernetes.io/resource-quota-preferences"
	allClustersKey                        = "ALL_CLUSTERS"
	UserAgentName                         = "Federation-resourcequota-Controller"
)

func parseFederationResourceQuotaPreference(frq *api_v1.ResourceQuota) (*fed.FederatedResourceQuotaPreferences, error) {
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

	deletionHelper *deletionhelper.DeletionHelper

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

	rqc := &ResourceQuotaController{
		federatedApiClient:       client,
		resourceQuotaReviewDelay: time.Second * 10,
		clusterAvailableDelay:    time.Second * 20,
		smallDelay:               time.Second * 3,
		updateTimeout:            time.Second * 30,
		resourceQuotaBackoff:     flowcontrol.NewBackOff(5*time.Second, time.Minute),
		eventRecorder:            recorder,
	}

	// Build delivereres for triggering reconciliations.
	rqc.resourceQuotaDeliverer = util.NewDelayingDeliverer()
	rqc.clusterDeliverer = util.NewDelayingDeliverer()

	// Start informer in federated API servers on resourcequotas that should be federated.
	rqc.resourceQuotaInformerStore, rqc.resourceQuotaInformerController = cache.NewInformer(
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
		util.NewTriggerOnAllChanges(func(obj pkg_runtime.Object) { rqc.deliverResourceQuotaObj(obj, 0, false) }))

	// Federated informer on resourcequotas in members of federation.
	rqc.resourceQuotaFederatedInformer = util.NewFederatedInformer(
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
						rqc.deliverResourceQuotaObj(obj, rqc.resourceQuotaReviewDelay, false)
					},
				))
		},

		&util.ClusterLifecycleHandlerFuncs{
			ClusterAvailable: func(cluster *federation_api.Cluster) {
				// When new cluster becomes available process all the resourcequotas again.
				rqc.clusterDeliverer.DeliverAt(allClustersKey, nil, time.Now().Add(rqc.clusterAvailableDelay))
			},
		},
	)

	// Federated updeater along with Create/Update/Delete operations.
	rqc.federatedUpdater = util.NewFederatedUpdater(rqc.resourceQuotaFederatedInformer,
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
	rqc.deletionHelper = deletionhelper.NewDeletionHelper(
		rqc.hasFinalizerFunc,
		rqc.removeFinalizerFunc,
		rqc.addFinalizerFunc,
		// objNameFunc
		func(obj pkg_runtime.Object) string {
			rq := obj.(*api_v1.ResourceQuota)
			return rq.Name
		},
		rqc.updateTimeout,
		rqc.eventRecorder,
		rqc.resourceQuotaFederatedInformer,
		rqc.federatedUpdater,
	)
	return rqc
}

// Returns true if the given object has the given finalizer in its ObjectMeta.
func (rqc *ResourceQuotaController) hasFinalizerFunc(obj pkg_runtime.Object, finalizer string) bool {
	rq := obj.(*api_v1.ResourceQuota)
	for i := range rq.ObjectMeta.Finalizers {
		if string(rq.ObjectMeta.Finalizers[i]) == finalizer {
			return true
		}
	}
	return false
}

// Removes the finalizer from the given objects ObjectMeta.
// Assumes that the given object is a namespace.
func (rqc *ResourceQuotaController) removeFinalizerFunc(obj pkg_runtime.Object, finalizer string) (pkg_runtime.Object, error) {
	rq := obj.(*api_v1.ResourceQuota)
	newFinalizers := []string{}
	hasFinalizer := false
	for i := range rq.ObjectMeta.Finalizers {
		if string(rq.ObjectMeta.Finalizers[i]) != finalizer {
			newFinalizers = append(newFinalizers, rq.ObjectMeta.Finalizers[i])
		} else {
			hasFinalizer = true
		}
	}
	if !hasFinalizer {
		// Nothing to do.
		return obj, nil
	}
	rq.ObjectMeta.Finalizers = newFinalizers
	rq, err := rqc.federatedApiClient.Core().ResourceQuotas(rq.Namespace).Update(rq)
	if err != nil {
		return nil, fmt.Errorf("failed to remove finalizer %s from resource quota %s: %v", finalizer, rq.Name, err)
	}
	return rq, nil
}

// Adds the given finalizer to the given objects ObjectMeta.
// Assumes that the given object is a namespace.
func (rqc *ResourceQuotaController) addFinalizerFunc(obj pkg_runtime.Object, finalizer string) (pkg_runtime.Object, error) {
	rq := obj.(*api_v1.ResourceQuota)
	rq.ObjectMeta.Finalizers = append(rq.ObjectMeta.Finalizers, finalizer)
	rq, err := rqc.federatedApiClient.Core().ResourceQuotas(rq.Namespace).Update(rq)
	if err != nil {
		return nil, fmt.Errorf("failed to add finalizer %s to resource quota %s: %v", finalizer, rq.Name, err)
	}
	return rq, nil
}

func (rqc *ResourceQuotaController) Run(stopChan <-chan struct{}) {

	go rqc.resourceQuotaInformerController.Run(stopChan)
	rqc.resourceQuotaFederatedInformer.Start()
	go func() {
		<-stopChan
		rqc.resourceQuotaFederatedInformer.Stop()
	}()
	rqc.resourceQuotaDeliverer.StartWithHandler(func(item *util.DelayingDelivererItem) {
		resourcequota := item.Value.(*resourcequotaItem)
		rqc.reconcileResourceQuota(resourcequota.namespace, resourcequota.name)
	})
	rqc.clusterDeliverer.StartWithHandler(func(_ *util.DelayingDelivererItem) {
		rqc.reconcileResourceQuotasOnClusterChange()
	})
	util.StartBackoffGC(rqc.resourceQuotaBackoff, stopChan)
}

func getResourceQuotaKey(namespace, name string) string {
	return fmt.Sprintf("%s/%s", namespace, name)
}

// Internal structure for data in delaying deliverer.
type resourcequotaItem struct {
	namespace string
	name      string
}

func (rqc *ResourceQuotaController) deliverResourceQuotaObj(obj interface{}, delay time.Duration, failed bool) {
	rq := obj.(*api_v1.ResourceQuota)
	rqc.deliverResourceQuota(rq.Namespace, rq.Name, delay, failed)
}

// Adds backoff to delay if this delivery is related to some failure. Resets backoff if there was no failure.
func (rqc *ResourceQuotaController) deliverResourceQuota(namespace string, name string, delay time.Duration, failed bool) {
	key := getResourceQuotaKey(namespace, name)
	if failed {
		rqc.resourceQuotaBackoff.Next(key, time.Now())
		delay = delay + rqc.resourceQuotaBackoff.Get(key)
	} else {
		rqc.resourceQuotaBackoff.Reset(key)
	}
	rqc.resourceQuotaDeliverer.DeliverAfter(key,
		&resourcequotaItem{namespace: namespace, name: name}, delay)
}

// Check whether all data stores are in sync. False is returned if any of the informer/stores is not yet
// synced with the corresponding api server.
func (rqc *ResourceQuotaController) isSynced() bool {
	if !rqc.resourceQuotaFederatedInformer.ClustersSynced() {
		glog.V(2).Infof("Cluster list not synced")
		return false
	}
	clusters, err := rqc.resourceQuotaFederatedInformer.GetReadyClusters()
	if err != nil {
		glog.Errorf("Failed to get ready clusters: %v", err)
		return false
	}
	if !rqc.resourceQuotaFederatedInformer.GetTargetStore().ClustersSynced(clusters) {
		return false
	}
	return true
}

// The function triggers reconciliation of all federated resourcequotas.
func (rqc *ResourceQuotaController) reconcileResourceQuotasOnClusterChange() {
	if !rqc.isSynced() {
		rqc.clusterDeliverer.DeliverAt(allClustersKey, nil, time.Now().Add(rqc.clusterAvailableDelay))
	}
	for _, obj := range rqc.resourceQuotaInformerStore.List() {
		rq := obj.(*api_v1.ResourceQuota)
		rqc.deliverResourceQuota(rq.Namespace, rq.Name, rqc.smallDelay, false)
	}
}

func (rqc *ResourceQuotaController) reconcileResourceQuota(namespace string, resourcequotaName string) {

	if !rqc.isSynced() {
		rqc.deliverResourceQuota(namespace, resourcequotaName, rqc.clusterAvailableDelay, false)
		return
	}

	key := getResourceQuotaKey(namespace, resourcequotaName)
	baseResourceQuotaObj, exist, err := rqc.resourceQuotaInformerStore.GetByKey(key)
	if err != nil {
		glog.Errorf("Failed to query main resource quota store for %v: %v", key, err)
		rqc.deliverResourceQuota(namespace, resourcequotaName, 0, true)
		return
	}

	if !exist {
		// Not federated resource quota, ignoring.
		return
	}
	// Create a copy before modifying the resource quota to prevent race condition with
	// other readers of resource quota from store.
	resourceQuotaObj, err := conversion.NewCloner().DeepCopy(baseResourceQuotaObj)
	rq, ok := resourceQuotaObj.(*api_v1.ResourceQuota)
	if err != nil || !ok {
		glog.Errorf("Error in retrieving obj from store: %v, %v", ok, err)
		rqc.deliverResourceQuota(rq.Namespace, rq.Name, rqc.smallDelay, true)
		return
	}
	if rq.DeletionTimestamp != nil {
		if err := rqc.delete(rq); err != nil {
			glog.Errorf("Failed to delete %s: %v", namespace, err)
			rqc.eventRecorder.Eventf(rq, api.EventTypeNormal, "DeleteFailed",
				"Namespace delete failed: %v", err)
			rqc.deliverResourceQuota(rq.Namespace, rq.Name, rqc.smallDelay, true)
		}
		return
	}

	glog.V(3).Infof("Ensuring delete object from underlying clusters finalizer for namespace: %s",
		rq.Name)
	// Add the required finalizers before creating a namespace in
	// underlying clusters.
	// This ensures that the dependent namespaces are deleted in underlying
	// clusters when the federated namespace is deleted.
	updatedResourceQuotaObj, err := rqc.deletionHelper.EnsureFinalizers(rq)
	if err != nil {
		glog.Errorf("Failed to ensure delete object from underlying clusters finalizer in namespace %s: %v",
			rq.Name, err)
		rqc.deliverResourceQuota(rq.Namespace, rq.Name, rqc.smallDelay, true)
		return
	}
	urq := updatedResourceQuotaObj.(*api_v1.ResourceQuota)

	clusters, err := rqc.resourceQuotaFederatedInformer.GetReadyClusters()
	if err != nil {
		glog.Errorf("Failed to get cluster list: %v", err)
		rqc.deliverResourceQuota(namespace, resourcequotaName, rqc.clusterAvailableDelay, true)
		return
	}

	operations := make([]util.FederatedOperation, 0)
	for _, cluster := range clusters {
		clusterResourceQuotaObj, found, err := rqc.resourceQuotaFederatedInformer.GetTargetStore().GetByKey(cluster.Name, key)
		if err != nil {
			glog.Errorf("Failed to get %s from %s: %v", key, cluster.Name, err)
			rqc.deliverResourceQuota(namespace, resourcequotaName, 0, true)
			return
		}

		desiredResourceQuota := &api_v1.ResourceQuota{
			ObjectMeta: util.DeepCopyRelevantObjectMeta(urq.ObjectMeta),
			Spec:       urq.Spec,
			Status:     urq.Status,
		}

		if !found {
			rqc.eventRecorder.Eventf(urq, api.EventTypeNormal, "CreateInCluster",
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

				rqc.eventRecorder.Eventf(urq, api.EventTypeNormal, "UpdateInCluster",
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
	err = rqc.federatedUpdater.UpdateWithOnError(operations, rqc.updateTimeout,
		func(op util.FederatedOperation, operror error) {
			rqc.eventRecorder.Eventf(urq, api.EventTypeNormal, "UpdateInClusterFailed",
				"ResourceQuota update in cluster %s failed: %v", op.ClusterName, operror)
		})

	if err != nil {
		glog.Errorf("Failed to execute updates for %s: %v", key, err)
		rqc.deliverResourceQuota(namespace, resourcequotaName, 0, true)
		return
	}

	// Evertyhing is in order but lets be double sure
	rqc.deliverResourceQuota(namespace, resourcequotaName, rqc.resourceQuotaReviewDelay, false)
}

// delete  deletes the given resource quota or returns error if the deletion was not complete.
func (rqc *ResourceQuotaController) delete(rq *api_v1.ResourceQuota) error {
	var err error
	glog.V(2).Infof("Deleting resource quota %s ...", rq.Name)
	rqc.eventRecorder.Event(rq, api.EventTypeNormal, "DeleteResourceQuota", fmt.Sprintf("Marking for deletion"))
	err = rqc.federatedApiClient.Core().ResourceQuotas(rq.Namespace).Delete(rq.Name, &api_v1.DeleteOptions{})
	if err != nil {
		return fmt.Errorf("failed to delete resource quota: %v", err)
	}

	// Delete the resource quota from all underlying clusters.
	_, err = rqc.deletionHelper.HandleObjectInUnderlyingClusters(rq)
	if err != nil {
		return err
	}

	err = rqc.federatedApiClient.Core().ResourceQuotas(rq.Namespace).Delete(rq.Name, nil)
	if err != nil {
		// Its all good if the error is not found error. That means it is deleted already and we do not have to do anything.
		// This is expected when we are processing an update as a result of resource quota finalizer deletion.
		// The process that deleted the last finalizer is also going to delete the resource quota and we do not have to do anything.
		if !errors.IsNotFound(err) {
			return fmt.Errorf("failed to delete resource quota: %v", err)
		}
	}
	return nil
}

