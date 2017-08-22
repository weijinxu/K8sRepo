#!/bin/bash
function usage() {
  echo "Usage: "
  echo "       $0 <-m MASTER_IP> <-n NODE_IP> <-f FCP_IP> [-am] [-an] [-af]"
  echo "   or  $0 <-m MASTER_IP> <-n NODE_IP> [-am] [-an] [-aa]"
  echo "   or  $0 <-k SSH_TARGET_IP> [-u USER]"
  echo "   or  $0 <-c SCP_TARGET_IP> [-u USER]"
}

function _counter_inc() { export _COUNTER=$((_COUNTER+1)) ; }

function _echo() { _counter_inc; echo -e ${_B}$(date -u) ${_COUNTER} $@ ${_E}; }

function echo_i() { _B="\033[39m"; _E="\033[0m"; _echo " [INFO]" $@; unset _E; unset _B; }

function echo_t() { _B="\033[32m"; _E="\033[0m"; _echo "[TRACE]" $@; unset _E; unset _B; }

function fatal() { _B="\033[31m"; _E="\033[0m";  _echo "[ERROR]" $@ ; exit 1; }

function init_const() {
  # Internal command counter
  export _COUNTER=0

  # Data and time
  echo_t "export _DATE=$(date -u +%Y%m%d_%H%M%S_%Z) "
  export _DATE=$(date -u +%Y%m%d_%H%M%S_%Z)

  # Local host IP retrieval
  echo_t "export ETH_NAME=$(ifconfig | grep -oE '^eth.' | head -n 1) "
  export ETH_NAME=$(ifconfig | grep -oE "^eth." | head -n 1)
  echo_t "export ETH_IP=$(ifconfig ${ETH_NAME} | grep -oP 'inet addr:\K\S+' ) "
  export ETH_IP=$(ifconfig ${ETH_NAME} | grep -oP 'inet addr:\K\S+' )
  #export ETH_IP=$(ifconfig $ETH_NAME | grep -E 'inet\W' | grep -oE [0-9]+.[0-9]+.[0-9]+.[0-9]+ | head -n 1)

  # HTTP proxy
  #http://10.162.206.127:3128
  #echo_t "export _proxy=http://10.122.49.205:3128 "
  #export _proxy=http://10.122.49.205:3128
  echo_t "export _proxy=http://10.162.206.127:3128 "
  export _proxy=http://10.162.206.127:3128
  echo_t "export no_proxy=localhost,127.0.0,1,${ETH_IP},rnd-mirrors.huawei.com,code.huawei.com "
  export no_proxy=localhost,127.0.0,1,${ETH_IP},rnd-mirrors.huawei.com,code.huawei.com

  # Fundermental settings
  echo_t "export BASE_DIR=/usr1 "
  export BASE_DIR=/usr1
  echo_t "export PAAS_DIR=${BASE_DIR}/paas "
  export PAAS_DIR=${BASE_DIR}/paas
  echo_t "export LOG_DIR=${PAAS_DIR}/log "
  export LOG_DIR=${PAAS_DIR}/log
  echo_t "export OPT_REL=/opt/release "
  export OPT_REL=/opt/release

  # Git repo and branch
  echo_t "export NFC_PROJ=cloudNFC "
  export NFC_PROJ=cloudNFC
  echo_t "export NFC_REL_REPO=release "
  export NFC_REL_REPO=release
  echo_t "export NFC_REL_BRANCH='paas2.1_630' "
  export NFC_REL_BRANCH='paas2.1_630'
  echo_t "export NFC_GIT_URL=git@code.huawei.com:${NFC_PROJ}/${NFC_REL_REPO}.git "
  export NFC_GIT_URL=git@code.huawei.com:${NFC_PROJ}/${NFC_REL_REPO}.git
  echo_t "export SSH_KEY_FILE=${HOME}/.ssh/id_rsa.pub "
  export SSH_KEY_FILE=${HOME}/.ssh/id_rsa.pub
  echo_t "export GIT_BIN=$(which git) "
  export GIT_BIN=$(which git)

  # Binaries for etcd, K8S master/client, AOS, and FCP
  echo_t "export KUBE_APISERVER=${PAAS_DIR}/kube-apiserver "
  export KUBE_APISERVER=${PAAS_DIR}/kube-apiserver
  echo_t "export KUBE_CONTROLLER_MANAGER=${PAAS_DIR}/kube-controller-manager "
  export KUBE_CONTROLLER_MANAGER=${PAAS_DIR}/kube-controller-manager
  echo_t "export KUBE_SCHEDULER=${PAAS_DIR}/kube-scheduler "
  export KUBE_SCHEDULER=${PAAS_DIR}/kube-scheduler
  echo_t "export KUBELET=${PAAS_DIR}/kubelet "
  export KUBELET=${PAAS_DIR}/kubelet
  echo_t "export KUBE_PROXY=${PAAS_DIR}/kube-proxy "
  export KUBE_PROXY=${PAAS_DIR}/kube-proxy
  echo_t "export KUBECTL=${PAAS_DIR}/kubectl "
  export KUBECTL=${PAAS_DIR}/kubectl
  echo_t "export AOS_API_SERVER=${PAAS_DIR}/api-server "
  export AOS_API_SERVER=${PAAS_DIR}/api-server
  echo_t "export AOS_WORKFLOW_ENGINE=${PAAS_DIR}/workflow-engine "
  export AOS_WORKFLOW_ENGINE=${PAAS_DIR}/workflow-engine
  echo_t "export ETCD=${PAAS_DIR}/etcd "
  export ETCD=${PAAS_DIR}/etcd
  echo_t "export FEDERATION_APISERVER=${PAAS_DIR}/federation-apiserver "
  export FEDERATION_APISERVER=${PAAS_DIR}/federation-apiserver
  echo_t "export FEDERATION_CONTROLLER_MANAGER=${PAAS_DIR}/federation-controller-manager "
  export FEDERATION_CONTROLLER_MANAGER=${PAAS_DIR}/federation-controller-manager
  echo_t "export ETCD2_2_5=${PAAS_DIR}/etcd2.2.5 "
  export ETCD2_2_5=${PAAS_DIR}/etcd2.2.5
  echo_t "export ETCD3_1_0=${PAAS_DIR}/etcd3.1.0 "
  export ETCD3_1_0=${PAAS_DIR}/etcd3.1.0
  echo_t "export ETCDCTL=${PAAS_DIR}/etcdctl "
  export ETCDCTL=${PAAS_DIR}/etcdctl
  echo_t "export TOSCA_DSL_PARSER_TAR=${PAAS_DIR}/tosca-dsl-parser.tar "
  export TOSCA_DSL_PARSER_TAR=${PAAS_DIR}/tosca-dsl-parser.tar
  echo_t "export TOSCA_DSL_PARSER_DIR=${PAAS_DIR}/tosca "
  export TOSCA_DSL_PARSER_DIR=${PAAS_DIR}/tosca
  echo_t "export MYSQL_SERVER_TAR=${PAAS_DIR}/mysql-server.tar "
  export MYSQL_SERVER_TAR=${PAAS_DIR}/mysql-server.tar
  echo_t "export MYSQL_SERVER_RPM_TAR=${PAAS_DIR}/mysql-server-rpm.tar "
  export MYSQL_SERVER_RPM_TAR=${PAAS_DIR}/mysql-server-rpm.tar
  echo_t "export DOCKYARD_TAR_GZ=${PAAS_DIR}/dockyard-20160928-SLES12SP1.tar.gz "
  export DOCKYARD_TAR_GZ=${PAAS_DIR}/dockyard-20160928-SLES12SP1.tar.gz

  # k8s master
  echo_t "export K8S_MASTER_IP=${MASTER_IP} "
  export K8S_MASTER_IP=${MASTER_IP}
  echo_t "export K8S_ETCD_PORT=4001 "
  export K8S_ETCD_PORT=4001

  echo_t "export K8S_CLUSTER_IP_RANGE=10.10.10.0/24 "
  export K8S_CLUSTER_IP_RANGE=10.10.10.0/24
  echo_t "export K8S_CLUSTER_DNS=10.10.10.10 "
  export K8S_CLUSTER_DNS=10.10.10.10
  echo_t "export K8S_SECURE_PORT=8443 "
  export K8S_SECURE_PORT=8443
  echo_t "export K8S_INSECURE_PORT=8888 "
  export K8S_INSECURE_PORT=8888

  echo_t "export K8S_ETCD_LOG_FILE=${LOG_DIR}/k8s_etcd_${_DATE}.log "
  export K8S_ETCD_LOG_FILE=${LOG_DIR}/k8s_etcd_${_DATE}.log
  echo_t "export K8S_APISERVER_LOG_FILE=${LOG_DIR}/k8s_apiserver_${_DATE}.log "
  export K8S_APISERVER_LOG_FILE=${LOG_DIR}/k8s_apiserver_${_DATE}.log
  echo_t "export K8S_CONTROLLER_MANAGER_LOG_FILE=${LOG_DIR}/k8s_controller_manager_${_DATE}.log "
  export K8S_CONTROLLER_MANAGER_LOG_FILE=${LOG_DIR}/k8s_controller_manager_${_DATE}.log
  echo_t "export K8S_SCHEDULER_LOG_FILE=${LOG_DIR}/k8s_scheduler_${_DATE}.log "
  export K8S_SCHEDULER_LOG_FILE=${LOG_DIR}/k8s_scheduler_${_DATE}.log
  echo_t "export K8S_KUBELET_LOG_FILE=${LOG_DIR}/k8s_kubelet_${_DATE}.log "
  export K8S_KUBELET_LOG_FILE=${LOG_DIR}/k8s_kubelet_${_DATE}.log
  echo_t "export K8S_KUBE_PROXY_LOG_FILE=${LOG_DIR}/k8s_kube_proxy_${_DATE}.log "
  export K8S_KUBE_PROXY_LOG_FILE=${LOG_DIR}/k8s_kube_proxy_${_DATE}.log

  # fcp
  echo_t "export FCP_ETCD_PORT=3379 "
  export FCP_ETCD_PORT=3379
  echo_t "export FCP_ETCD_PEER_PORT=3380 "
  export FCP_ETCD_PEER_PORT=3380
  echo_t "export FCP_ETCD_DATA_DIR=/tmp/tmp_fed.iPFYsJjlnC "
  export FCP_ETCD_DATA_DIR=/tmp/tmp_fed.iPFYsJjlnC
  echo_t "export FCP_CLUSTER_IP_RANGE=10.0.0.0/24 "
  export FCP_CLUSTER_IP_RANGE=10.0.0.0/24
  echo_t "export FCP_SECURE_PORT=44311 "
  export FCP_SECURE_PORT=44311
  echo_t "export FCP_INSECURE_PORT=8008 "
  export FCP_INSECURE_PORT=8008
  echo_t "export FCP_DNS_CONFIG_FILE=${PAAS_DIR}/conf/dns-config "
  export FCP_DNS_CONFIG_FILE=${PAAS_DIR}/conf/dns-config
  echo_t "export FCP_KUBE_CONFIG=${PAAS_DIR}/conf/kube.config "
  export FCP_KUBE_CONFIG=${PAAS_DIR}/conf/kube.config
  echo_t "export FCP_APISERVER_LOG_FILE=${LOG_DIR}/fed_apiserver_${_DATE}.log "
  export FCP_APISERVER_LOG_FILE=${LOG_DIR}/fed_apiserver_${_DATE}.log
  echo_t "export FCP_CONTROLLER_MANAGER_LOG_FILE=${LOG_DIR}/fed_controller_manager_${_DATE}.log "
  export FCP_CONTROLLER_MANAGER_LOG_FILE=${LOG_DIR}/fed_controller_manager_${_DATE}.log
  echo_t "export FCP_ETCD_LOG_FILE=${LOG_DIR}/fed_etcd_${_DATE}.log "
  export FCP_ETCD_LOG_FILE=${LOG_DIR}/fed_etcd_${_DATE}.log

  # Mysql
  echo_t "export MYSQL_SERVER_IP=${ETH_IP} "
  export MYSQL_SERVER_IP=${ETH_IP}
  echo_t "export MYSQL_SERVER_PORT=3306 "
  export MYSQL_SERVER_PORT=3306
  echo_t "export MYSQL_ROOT_USER=root "
  export MYSQL_ROOT_USER=root
  echo_t "export MYSQL_ROOT_PWD=root "
  export MYSQL_ROOT_PWD=root
  echo_t "export DOCKYARD_DB_NAME=dockyard "
  export DOCKYARD_DB_NAME=dockyard
  echo_t "export AOS_DB_NAME=paas  "
  export AOS_DB_NAME=paas

  # Dockyard
  echo_t "export DOCKYARD_DEPLOY_DIR=/opt/dockyard "
  export DOCKYARD_DEPLOY_DIR=/opt/dockyard
  echo_t "export DOCKYARD_SERVICE_DIR=/var/paas "
  export DOCKYARD_SERVICE_DIR=/var/paas
  echo_t "export DOCKYARD_CRYPTO_LOG=${DOCKYARD_SERVICE_DIR}/paas_crypto_log.log "
  export DOCKYARD_CRYPTO_LOG=${DOCKYARD_SERVICE_DIR}/paas_crypto_log.log
  echo_t "export DOCKYARD_SERVICE_PORT=8081 # Hard coded in install.sh "
  export DOCKYARD_SERVICE_PORT=8081 # Hard coded in install.sh
  echo_t "export DOCKYARD_SERVICE_KEY=NZEISALJXVKFZFWM9BZHEQLG9JAVVHLOQWPGYOOE # Hard coded in install.sh "
  export DOCKYARD_SERVICE_KEY=NZEISALJXVKFZFWM9BZHEQLG9JAVVHLOQWPGYOOE # Hard coded in install.sh
  echo_t "export DOCKYARD_DEPLOY_LOG_FILE=${LOG_DIR}/dock_deploy_${_DATE}.log "
  export DOCKYARD_DEPLOY_LOG_FILE=${LOG_DIR}/dock_deploy_${_DATE}.log

  # AOS
  echo_t "export AOS_MYSQL_USER=${MYSQL_ROOT_USER} "
  export AOS_MYSQL_USER=${MYSQL_ROOT_USER}
  echo_t "export AOS_MYSQL_PWD=${MYSQL_ROOT_PWD} "
  export AOS_MYSQL_PWD=${MYSQL_ROOT_PWD}
  echo_t "export AOS_MYSQL_PORT=${MYSQL_SERVER_PORT} "
  export AOS_MYSQL_PORT=${MYSQL_SERVER_PORT}
  echo_t "export AOS_MYSQL_DB=${AOS_DB_NAME} "
  export AOS_MYSQL_DB=${AOS_DB_NAME}
  echo_t "export SECURITY_CENTER_PORT=8080 "
  export SECURITY_CENTER_PORT=8080
  echo_t "export STORE_EXT_PORT=8081 "
  export STORE_EXT_PORT=8081
  echo_t "export AOS_API_SERVER_LOG_FILE=${LOG_DIR}/aos_api_server_${_DATE}.log "
  export AOS_API_SERVER_LOG_FILE=${LOG_DIR}/aos_api_server_${_DATE}.log
  echo_t "export AOS_WORKFLOW_ENGINE_LOF_FILE=${LOG_DIR}/aos_workflow_engine_${_DATE}.log "
  export AOS_WORKFLOW_ENGINE_LOF_FILE=${LOG_DIR}/aos_workflow_engine_${_DATE}.log
  export TOSCA_SERVER_PORT=11808
  echo_t "export TOSCA_DSL_PARSER_LOG_FILE=${LOG_DIR}/tosca_dsl_parser_${_DATE}.log "
  export TOSCA_DSL_PARSER_LOG_FILE=${LOG_DIR}/tosca_dsl_parser_${_DATE}.log
}

function set_http_proxy() {
  echo_t "export http_proxy=${_proxy} "
  export http_proxy=${_proxy}
  echo_t "export https_proxy=${_proxy} "
  export https_proxy=${_proxy}
}

function unset_http_proxy() {
  echo_t "unset http_proxy "
  unset http_proxy
  echo_t "unset https_proxy "
  unset https_proxy
}

function ensure_file_exist() {
  F=$1
  echo_i "Checking if file exist" ${F}
  if [ ! -f ${F} ] ; then
    fatal "File does not exist ${F}"
  fi
  unset F
}

function ensure_file_executable() {
  F=$1
  echo_i "Checking if file is executable" ${F}
  if [ ! -x ${F} ] ; then
    fatal "File does not exist or is not executable ${F}"
  fi
  unset F
}

function ensure_dir_exist() {
  D=$1
  echo_i "Checking if dir exist" ${D}
  if [ ! -d ${D} ] ; then
    echo_i "Create dir ..."
    echo_t 'mkdir -pv' ${D}
    mkdir -pv ${D}
  else
    echo_i "${D} already exists"
  fi
  if [ ! -d ${D} ] ; then
    fatal "Failed to create dir ${D}"
  fi
  unset D
}

function ensure_base_dir() {
  echo_i "Set base dir to " ${BASE_DIR}
  ensure_dir_exist ${BASE_DIR}
}

function ensure_k8s_dir() {
  echo_i "Set k8s dir to " ${PAAS_DIR}
  ensure_dir_exist ${PAAS_DIR}
}

function ensure_log_dir() {
  echo_i "Set log dir to " ${LOG_DIR}
  ensure_dir_exist ${LOG_DIR}
}

function pip_upgrade_by_itself() {
  set_http_proxy
  echo_t "pip install --upgrade pip "
  pip install --upgrade pip
  unset_http_proxy
}

function ensure_binary_by_pip() {
  B=$1 # Binary name
  if [[ -z "${B}" ]] ; then fatal "Nothing to install" ; fi
  if [[ ! -z "$(pip list --format=legacy | grep -i ${B})" ]] ; then
    echo_i "${B} already installed"
    return 0
  fi
  set_http_proxy
  echo_i "Install ${B} ..."
  echo_t "pip install ${B} "
  pip install ${B}
  unset_http_proxy
  if [[ -z "$(pip list --format=legacy | grep -i ${B})" ]] ; then
    echo_i "Retry install ${B} without http proxy..."
    echo_t "pip install ${B} "
    pip install ${B}
  fi
  if [[ -z "$(pip list --format=legacy | grep -i ${B})" ]] ; then
    fatal "Failed to install ${B}, with or without http proxy"
  fi
  echo_i "${B} is installed as $(pip list --format=legacy | grep -i ${B})"
  unset B
}

function ensure_binary_by_apt_get() {
  B=$1 # Binary name
  P=$2 # Package name for apt-get
  if [[ -z "${B}" ]] ; then fatal "Nothing to install" ; fi
  if [[ -z "${P}" ]] ; then P=${B} ; fi
  if [[ ! -z "$(which ${B})" ]] ; then
    echo_i "${B} already installed"
    return 0
  fi
  echo_i "Install ${P} ..."
  echo_t "apt-get install ${P} -y --force-yes "
  apt-get install ${P} -y --force-yes
  if [[ -z "$(which ${B})" ]] ; then
    echo_i "Retry install ${P} with http proxy..."
    set_http_proxy
    echo_t "apt-get install ${P} -y --force-yes "
    apt-get install ${P} -y --force-yes
    unset_http_proxy
  fi
  if [[ -z "$(which ${B})" ]] ; then
    fatal "Failed to install ${B}, with or without http proxy"
  fi
  echo_i "${B} is installed as $(which ${B})"
  unset P
  unset B
}

function ensure_git_binary() {
  ensure_binary_by_apt_get git
  export GIT_BIN=$(which git)
}

function ensure_ssh_key_on_localhost() {
  if [ ! -f ${SSH_KEY_FILE} ] ; then
    echo_i "Creating ssh key file ... " ${SSH_KEY_FILE}
    echo_t 'cat /dev/zero | ssh-keygen -q -N ""'
    cat /dev/zero | ssh-keygen -q -N ""
    echo -e ""
  else
    echo_i "File already exist " ${SSH_KEY_FILE}
  fi
  if [ ! -f ${SSH_KEY_FILE} ] ; then
    fatal "Failed to create ssh key file ... " ${SSH_KEY_FILE}
  fi
}

function ensure_ssh_key_on_git_repo() {
  ensure_ssh_key_on_localhost
  echo_i "Please copy the content of " ${SSH_KEY_FILE} " to http://code.huawei.com/profile/keys/ :"
  echo_t "cat ${SSH_KEY_FILE}"
  cat ${SSH_KEY_FILE}
  echo_i "After copying the key file, press ENTER to continue ..."
  read # Wait for ENTER key
}

function scp_k8s_binaries() {
  H=$1 # scp target host IP address
  U=${USER:-root}
  echo_t "ssh ${U}@${H} \"mkdir -pv ${PAAS_DIR}\" "
  ssh ${U}@${H} "mkdir -pv ${PAAS_DIR}"
  echo_t "scp ${BASE_DIR}/setup_one_box.sh ${U}@${H}:${BASE_DIR}/ "
  scp ${BASE_DIR}/setup_one_box.sh ${U}@${H}:${BASE_DIR}/
  echo_t "scp -rp ${PAAS_DIR}/conf ${U}@${H}:${PAAS_DIR}/ "
  scp -rp ${PAAS_DIR}/conf ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${KUBE_APISERVER} ${U}@${H}:${PAAS_DIR}/ "
  scp ${KUBE_APISERVER} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${KUBE_CONTROLLER_MANAGER} ${U}@${H}:${PAAS_DIR}/ "
  scp ${KUBE_CONTROLLER_MANAGER} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${KUBE_SCHEDULER} ${U}@${H}:${PAAS_DIR}/ "
  scp ${KUBE_SCHEDULER} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${KUBELET} ${U}@${H}:${PAAS_DIR}/ "
  scp ${KUBELET} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${KUBE_PROXY} ${U}@${H}:${PAAS_DIR}/ "
  scp ${KUBE_PROXY} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${KUBECTL} ${U}@${H}:${PAAS_DIR}/ "
  scp ${KUBECTL} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${AOS_API_SERVER} ${U}@${H}:${PAAS_DIR}/ "
  scp ${AOS_API_SERVER} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${AOS_WORKFLOW_ENGINE} ${U}@${H}:${PAAS_DIR}/ "
  scp ${AOS_WORKFLOW_ENGINE} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${FEDERATION_APISERVER} ${U}@${H}:${PAAS_DIR}/ "
  scp ${FEDERATION_APISERVER} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${FEDERATION_CONTROLLER_MANAGER} ${U}@${H}:${PAAS_DIR}/ "
  scp ${FEDERATION_CONTROLLER_MANAGER} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${ETCD2_2_5} ${U}@${H}:${PAAS_DIR}/ "
  scp ${ETCD2_2_5} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${ETCD3_1_0} ${U}@${H}:${PAAS_DIR}/ "
  scp ${ETCD3_1_0} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${ETCDCTL} ${U}@${H}:${PAAS_DIR}/ "
  scp ${ETCDCTL} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${TOSCA_DSL_PARSER_TAR} ${U}@${H}:${PAAS_DIR}/ "
  scp ${TOSCA_DSL_PARSER_TAR} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${MYSQL_SERVER_TAR} ${U}@${H}:${PAAS_DIR}/ "
  scp ${MYSQL_SERVER_TAR} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${MYSQL_SERVER_RPM_TAR} ${U}@${H}:${PAAS_DIR}/ "
  scp ${MYSQL_SERVER_RPM_TAR} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp ${DOCKYARD_TAR_GZ} ${U}@${H}:${PAAS_DIR}/ "
  scp ${DOCKYARD_TAR_GZ} ${U}@${H}:${PAAS_DIR}/
  echo_t "scp -rp ${PAAS_DIR}/conf ${U}@${H}:${PAAS_DIR}/ "
  unset H
  unset U
}

function setup_ssh_without_pwd() {
  H=$1 # ssh target host IP address
  U=${USER:-root}
  ensure_ssh_key_on_localhost
  echo_t "cat ${SSH_KEY_FILE} | ssh ${U}@${H} \"cat >> ~${U}/.ssh/authorized_keys\""
  cat ${SSH_KEY_FILE} | ssh ${U}@${H} "mkdir -pv ~${U}/.ssh && cat >> ~${U}/.ssh/authorized_keys"
  unset H
  unset U
}

function ensure_git_nfc_release_branch() {
  cd ${BASE_DIR}
  if [ ! -d "${NFC_REL_REPO}" ] ; then
    ensure_git_binary
    ensure_ssh_key_on_git_repo
    echo_i "Git clone nfc release ..."
    echo_t "${GIT_BIN} clone ${NFC_GIT_URL}"
    ${GIT_BIN} clone ${NFC_GIT_URL}
  else
    echo_i "Git repo already exist"
  fi
  if [ ! -d "${NFC_REL_REPO}" ] ; then
    fatal "Failed to clone nfc release"
  fi
  echo_t "cd ${BASE_DIR}/${NFC_REL_REPO} && ${GIT_BIN} checkout ${NFC_REL_BRANCH}"
  cd ${BASE_DIR}/${NFC_REL_REPO} && ${GIT_BIN} checkout ${NFC_REL_BRANCH} 2>/dev/null
}

function parse_cmd_args() {
  while [[ $# -ge 1 ]]
  do
    key="$1"
    case $key in
      -aa)
      echo_t "export START_K8S_AOS=YES "
      export START_K8S_AOS=YES
      ;;
      -af)
      echo_t "export START_K8S_FCP=YES "
      export START_K8S_FCP=YES
      ;;
      -am)
      echo_t "export START_K8S_MASTER=YES "
      export START_K8S_MASTER=YES
      ;;
      -an)
      echo_t "export START_K8S_NODE=YES "
      export START_K8S_NODE=YES
      ;;
      -c|--scp-binaries)
      echo_t "export SCP_TARGET_IP="$2" "
      export SCP_TARGET_IP="$2"
      shift
      ;;
      -f|--fcp)
      echo_t "export FCP_IP="$2" "
      export FCP_IP="$2"
      shift
      ;;
      -k|--ssh-key)
      echo_t "export SSH_TARGET_IP="$2" "
      export SSH_TARGET_IP="$2"
      shift
      ;;
      -m|--master)
      echo_t "export MASTER_IP="$2" "
      export MASTER_IP="$2"
      shift
      ;;
      -n|--node)
      echo_t "export NODE_IP="$2" "
      export NODE_IP="$2"
      shift
      ;;
      -u|--user)
      echo_t "export USER="$2" "
      export USER="$2"
      shift
      ;;
      *)
      fatal "Unknown option $key"
      ;;
    esac
    shift
  done
}

function ensure_opt_release_dir() {
  if [ ! -d "${OPT_REL}" ] ; then
    echo_t "ln -s ${BASE_DIR}/${NFC_REL_REPO} ${OPT_REL}"
    ln -s ${BASE_DIR}/${NFC_REL_REPO} ${OPT_REL}
  else
    echo_i "${OPT_REL} already exist"
  fi
  if [ ! -d "${OPT_REL}" ] ; then
    fatal "Failed to create ${OPT_REL} dir"
  fi
}

function ensure_k8s_binaries() {
  ensure_file_executable ${KUBE_APISERVER}
  ensure_file_executable ${KUBE_CONTROLLER_MANAGER}
  ensure_file_executable ${KUBE_SCHEDULER}
  ensure_file_executable ${KUBELET}
  ensure_file_executable ${KUBE_PROXY}
  # These files are needed for FCP
  ensure_file_exist ${FCP_KUBE_CONFIG}
  ensure_file_exist ${FCP_DNS_CONFIG_FILE}
}

function is_process_up() {
  P=$1 # Process search key words (for ps command)
  D=$2 # Process description
  PS_RESULT=$(ps -ef | grep "${P}" | grep -v grep | cut -c51- )
  if [ ! -z "${PS_RESULT}" ]; then
    _RESULT=YES # Note: global variable
    echo_i "${D} is up and running as "
    echo_t "${PS_RESULT}"
  else
    _RESULT=NO # Note: global variable
    echo_i "${D} is not running"
  fi
  unset PS_RESULT
  unset D
  unset P
}

function ensure_process_up() {
  P=$1 # Process search key words (for ps command)
  D=$2 # Process description
  PS_RESULT=$(ps -ef | grep "${P}" | grep -v grep | cut -c51- )
  if [ ! -z "${PS_RESULT}" ]; then
    _RESULT=YES # Note: global variable
    echo_i "${D} is up and running as "
    echo_t "${PS_RESULT}"
  else
    _RESULT=NO # Note: global variable
    fatal "${D} is not running"
  fi
  unset PS_RESULT
  unset D
  unset P
}

function start_k8s_etcd() {
  is_process_up "${ETCD2_2_5}" "Etcd for K8S"
  if [ "YES" == "${_RESULT}" ] ; then
    return 0
  fi

  echo_t "${ETCD2_2_5} \ "
  echo_t "  --listen-client-urls=http://0.0.0.0:${K8S_ETCD_PORT} \ "
  echo_t "  --advertise-client-urls=http://${K8S_MASTER_IP}:${K8S_ETCD_PORT} \ "
  echo_t "  >${K8S_ETCD_LOG_FILE} 2>&1 & "
  ${ETCD2_2_5} \
    --listen-client-urls=http://0.0.0.0:${K8S_ETCD_PORT} \
    --advertise-client-urls=http://${K8S_MASTER_IP}:${K8S_ETCD_PORT} \
    >${K8S_ETCD_LOG_FILE} 2>&1 &
  ensure_process_up "${ETCD2_2_5}" "Etcd for K8S"
}

function start_k8s_api_server {
  is_process_up "${KUBE_APISERVER}" "K8S API server"
  if [ "YES" == "${_RESULT}" ] ; then
    return 0
  fi

  echo_t "${KUBE_APISERVER} \ "
  echo_t "  --insecure-bind-address=${K8S_MASTER_IP} \ "
  echo_t "  --etcd-servers=http://${K8S_MASTER_IP}:${K8S_ETCD_PORT} \ "
  echo_t "  --service-cluster-ip-range=${K8S_CLUSTER_IP_RANGE} \ "
  echo_t "  --insecure-port=${K8S_INSECURE_PORT} \ "
  echo_t "  --secure-port=0  \ "
  echo_t "  --service-node-port-range='53-65535' \ "
  echo_t "  --allow-privileged=true   \ "
  echo_t "  --v=4 >$K8S_APISERVER_LOG_FILE 2>&1 & "
  ${KUBE_APISERVER} \
    --insecure-bind-address=${K8S_MASTER_IP} \
    --etcd-servers=http://${K8S_MASTER_IP}:${K8S_ETCD_PORT} \
    --service-cluster-ip-range=${K8S_CLUSTER_IP_RANGE} \
    --insecure-port=${K8S_INSECURE_PORT} \
    --secure-port=0  \
    --service-node-port-range='53-65535' \
    --allow-privileged=true   \
    --v=4 >$K8S_APISERVER_LOG_FILE 2>&1 &
  ensure_process_up "${KUBE_APISERVER}" "K8S API server"
}

function start_k8s_controller_manager {
  is_process_up "${KUBE_CONTROLLER_MANAGER}" "K8S controller manager"
  if [ "YES" == "${_RESULT}" ] ; then
    return 0
  fi

  echo_t "${KUBE_CONTROLLER_MANAGER} \ "
  echo_t "  --master=${K8S_MASTER_IP}:${K8S_INSECURE_PORT} \ "
  echo_t "  --v=4 >${K8S_CONTROLLER_MANAGER_LOG_FILE} 2>&1 & "
  ${KUBE_CONTROLLER_MANAGER} \
    --master=${K8S_MASTER_IP}:${K8S_INSECURE_PORT} \
    --v=4 >${K8S_CONTROLLER_MANAGER_LOG_FILE} 2>&1 &
  ensure_process_up "${KUBE_CONTROLLER_MANAGER}" "K8S controller manager"
}

function start_k8s_scheduler {
  is_process_up "${KUBE_SCHEDULER}" "K8S scheduler"
  if [ "YES" == "${_RESULT}" ] ; then
    return 0
  fi

  echo_t "${KUBE_SCHEDULER} \ "
  echo_t "  --master=${K8S_MASTER_IP}:${K8S_INSECURE_PORT} \ "
  echo_t "  --address=${K8S_MASTER_IP} \ "
  echo_t "  --v=4 >${K8S_SCHEDULER_LOG_FILE} 2>&1 & "
  ${KUBE_SCHEDULER} \
    --address=${K8S_MASTER_IP} \
    --master=${K8S_MASTER_IP}:${K8S_INSECURE_PORT} \
    --v=4 >${K8S_SCHEDULER_LOG_FILE} 2>&1 &
  ensure_process_up "${KUBE_SCHEDULER}" "K8S scheduler"
}

function start_k8s_master() {
  ensure_k8s_dir
  # ensure_git_nfc_release_branch
  # ensure_opt_release_dir
  ensure_k8s_binaries
  start_k8s_etcd
  start_k8s_api_server
  start_k8s_controller_manager
  start_k8s_scheduler
}

function update_docker_config_and_restart() {
  cat >>/etc/default/docker <<EOF

# Config insecure registry and http proxy
DOCKER_OPTS="\$DOCKER_OPTS --insecure-registry gcr.io --insecure-registry quay.io --mtu=1472 -g /opt/docker"
export http_proxy="http://10.122.49.205:3128/"
export https_proxy="http://10.122.49.205:3128/"
export no_proxy="localhost,127.0.0.1,${ETH_IP},rnd-mirrors.huawei.com,code.huawei.com"
EOF
  echo_t "service docker restart "
  service docker restart
}

function install_docker() {
  DOCKERD="dockerd"
  is_process_up "${DOCKERD}" "Docker daemon"
  if [ "YES" == "${_RESULT}" ] ; then
    return 0
  fi
  PS_RESULT=$(which docker)
  if [ ! -z "${PS_RESULT}" ]; then
    unset PS_RESULT
    echo_i "docker is already installed as $(which docker)"
    return 0
  fi

  set_http_proxy
  echo_t "apt-get update "
  apt-get update
  echo_t "apt-get install -y apt-transport-https ca-certificates "
  apt-get install -y apt-transport-https ca-certificates
  echo_t "apt-key adv --keyserver-options \ "
  echo_t "  --keyserver hkp://p80.pool.sks-keyservers.net:80 \ "
  echo_t "  --recv-keys 58118E89F3A912897C070ADBF76221572C52609D "
  apt-key adv --keyserver-options \
    --keyserver hkp://p80.pool.sks-keyservers.net:80 \
    --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
  # Make sure only following line is in this file (for Ubuntu 14.04 LTS):
  echo_t "echo 'deb https://apt.dockerproject.org/repo ubuntu-trusty main' >/etc/apt/sources.list.d/docker.list "
  echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" >/etc/apt/sources.list.d/docker.list
  echo_t "apt-get update "
  apt-get update
  echo_t "apt-get install -y linux-image-extra-$(uname -r) "
  apt-get install -y linux-image-extra-$(uname -r)
  echo_t "apt-get install -y apparmor "
  apt-get install -y apparmor
  echo_t "apt-get install -y docker-engine --force-yes "
  apt-get install -y docker-engine --force-yes
  unset_http_proxy
  echo_t " service docker restart "
  service docker restart
  ensure_process_up "${DOCKERD}" "Docker daemon"
  update_docker_config_and_restart
  ensure_process_up "${DOCKERD}" "Docker daemon"
}

function start_k8s_kubelet() {
  is_process_up "${KUBELET}" "kubelet"
  if [ "YES" == "${_RESULT}" ] ; then
    return 0
  fi

  echo_t "${KUBELET} \ "
  echo_t "  --api-servers=http://${K8S_MASTER_IP}:${K8S_INSECURE_PORT}  \ "
  echo_t "  --cgroup-root=/                      \ "
  echo_t "  --cluster-dns=${K8S_CLUSTER_DNS}     \ "
  echo_t "  --cluster-domain=cluster.local       \ "
  echo_t "  --hostname-override=${ETH_IP}        \ "
  echo_t "  --allow-privileged=true              \ "
  echo_t "  --v=4 >${K8S_KUBELET_LOG_FILE} 2>&1 & "
  ${KUBELET} \
    --api-servers=http://${K8S_MASTER_IP}:${K8S_INSECURE_PORT}  \
    --cgroup-root=/                      \
    --cluster-dns=${K8S_CLUSTER_DNS}     \
    --cluster-domain=cluster.local       \
    --hostname-override=${ETH_IP}        \
    --allow-privileged=true              \
    --v=4 >${K8S_KUBELET_LOG_FILE} 2>&1 &
  ensure_process_up "${KUBELET}" "kubelet"
}

function start_k8s_kube_proxy() {
  is_process_up "${KUBE_PROXY}" "kube-proxy"
  if [ "YES" == "${_RESULT}" ] ; then
    return 0
  fi

  echo_t "${KUBE_PROXY} \ "
  echo_t "  --master=${K8S_MASTER_IP}:${K8S_INSECURE_PORT} \ "
  echo_t "  --hostname-override=${ETH_IP}         \ "
  echo_t "  --v=4 >${K8S_KUBE_PROXY_LOG_FILE} 2>&1 & "
  ${KUBE_PROXY} \
   --master=${K8S_MASTER_IP}:${K8S_INSECURE_PORT} \
   --hostname-override=${ETH_IP}         \
   --v=4 >${K8S_KUBE_PROXY_LOG_FILE} 2>&1 &
  ensure_process_up "${KUBE_PROXY}" "kube-proxy"
}

function start_k8s_node() {
  install_docker
  start_k8s_kubelet
  start_k8s_kube_proxy
}

function start_fcp_etcd() {
  is_process_up "${ETCD3_1_0}" "Etcd for Federation Control Plane"
  if [ "YES" == "${_RESULT}" ] ; then
    return 0
  fi

  echo_t "${ETCD3_1_0} \ "
  echo_t "  --advertise-client-urls http://${FCP_IP}:${FCP_APISERVER_PORT} \ "
  echo_t "  --data-dir ${FCP_ETCD_DATA_DIR} \ "
  echo_t "  --listen-client-urls http://${FCP_IP}:${FCP_ETCD_PORT} \ "
  echo_t "  --initial-advertise-peer-urls http://${FCP_IP}:${FCP_ETCD_PEER_PORT} \ "
  echo_t "  --listen-peer-urls http://${FCP_IP}:${FCP_ETCD_PEER_PORT} \ "
  echo_t "  --initial-cluster \"default=http://${FCP_IP}:${FCP_ETCD_PEER_PORT}\" \ "
  echo_t "  >${FCP_ETCD_LOG_FILE} 2>&1 & "
  ${ETCD3_1_0} \
   --advertise-client-urls http://${FCP_IP}:${FCP_ETCD_PORT} \
   --data-dir ${FCP_ETCD_DATA_DIR} \
   --listen-client-urls http://${FCP_IP}:${FCP_ETCD_PORT} \
   --initial-advertise-peer-urls http://${FCP_IP}:${FCP_ETCD_PEER_PORT} \
   --listen-peer-urls http://${FCP_IP}:${FCP_ETCD_PEER_PORT} \
   --initial-cluster "default=http://${FCP_IP}:${FCP_ETCD_PEER_PORT}" \
   >${FCP_ETCD_LOG_FILE} 2>&1 &
  ensure_process_up "${ETCD3_1_0}" "Etcd for Federation Control Plane"
}

function start_fcp_apiserver() {
  is_process_up "${FEDERATION_APISERVER}" "Federation API server"
  if [ "YES" == "${_RESULT}" ] ; then
    return 0
  fi

  echo_t "${FEDERATION_APISERVER} \ "
  echo_t "  --insecure-bind-address=${FCP_IP} \ "
  echo_t "  --secure-port=${FCP_SECURE_PORT} \ "
  echo_t "  --insecure-port=${FCP_INSECURE_PORT} \ "
  echo_t "  --advertise-address=${FCP_IP} \ "
  echo_t "  --anonymous-auth=false \ "
  echo_t "  --admission-control=NamespaceLifecycle \ "
  echo_t "  --bind-address=${FCP_IP} \ "
  echo_t "  --etcd-servers=http://${FCP_IP}:${FCP_ETCD_PORT} \ "
  echo_t "  --service-cluster-ip-range=${FCP_CLUSTER_IP_RANGE} \ "
  echo_t "  --v=8 >${FCP_APISERVER_LOG_FILE} 2>&1 & "
  ${FEDERATION_APISERVER} \
    --insecure-bind-address=${FCP_IP} \
    --secure-port=${FCP_SECURE_PORT} \
    --insecure-port=${FCP_INSECURE_PORT} \
    --advertise-address=${FCP_IP} \
    --anonymous-auth=false \
    --admission-control=NamespaceLifecycle \
    --bind-address=${FCP_IP} \
    --etcd-servers=http://${FCP_IP}:${FCP_ETCD_PORT} \
    --service-cluster-ip-range=${FCP_CLUSTER_IP_RANGE} \
    --v=8 >${FCP_APISERVER_LOG_FILE} 2>&1 &
  ensure_process_up "${FEDERATION_APISERVER}" "Federation API server"
}

function start_fcp_controller_manager() {
  is_process_up "${FEDERATION_CONTROLLER_MANAGER}" "Federation controller manager"
  if [ "YES" == "${_RESULT}" ] ; then
    return 0
  fi

  echo_t "${FEDERATION_CONTROLLER_MANAGER} \ "
  echo_t "  --master=http://${FCP_IP}:${FCP_INSECURE_PORT} \ "
  echo_t "  --dns-provider-config=${FCP_DNS_CONFIG_FILE} \ "
  echo_t "  --kubeconfig=${FCP_KUBE_CONFIG} \ "
  echo_t "  --v=8  >${FCP_CONTROLLER_MANAGER_LOG_FILE} 2>&1 & "
  ${FEDERATION_CONTROLLER_MANAGER} \
    --master=http://${FCP_IP}:${FCP_INSECURE_PORT} \
    --dns-provider-config=${FCP_DNS_CONFIG_FILE} \
    --kubeconfig=${FCP_KUBE_CONFIG} \
    --v=8  >${FCP_CONTROLLER_MANAGER_LOG_FILE} 2>&1 &
  ensure_process_up "${FEDERATION_CONTROLLER_MANAGER}" "Federation controller manager"
}

function install_mysql_server() {
  if [[ ! -z "$(dpkg-query --show mysql)" ]] ; then
    echo_i "Mysql is already installed"
    return 0
  fi

  echo_t "export MYSQL_TAR_FILE=mysql-server.tar "
  export MYSQL_TAR_FILE=mysql-server.tar
  echo_t "export MYSQL_INSTALL_TAR=${PAAS_DIR}/${MYSQL_TAR_FILE} "
  export MYSQL_INSTALL_TAR=${PAAS_DIR}/${MYSQL_TAR_FILE}
  ensure_file_exist ${MYSQL_INSTALL_TAR}
  echo_t "export MYSQL_INSTALL_DIR=/opt/mysql "
  export MYSQL_INSTALL_DIR=/opt/mysql
  echo_t "export MYSQL_VAR_LIB_DIR=/var/lib/mysql "
  export MYSQL_VAR_LIB_DIR=/var/lib/mysql
  echo_t "export DEBIAN_FRONTEND=noninteractive "
  export DEBIAN_FRONTEND=noninteractive

  echo_t "rm -rf ${MYSQL_VAR_LIB_DIR} "
  rm -rf ${MYSQL_VAR_LIB_DIR}
  echo_t "rm -rf ${MYSQL_INSTALL_DIR} "
  rm -rf ${MYSQL_INSTALL_DIR}
  echo_t "mkdir -p ${MYSQL_INSTALL_DIR} "
  mkdir -p ${MYSQL_INSTALL_DIR}
  echo_t "cp ${MYSQL_INSTALL_TAR} ${MYSQL_INSTALL_DIR}/ "
  cp ${MYSQL_INSTALL_TAR} ${MYSQL_INSTALL_DIR}/
  echo_t "cd ${MYSQL_INSTALL_DIR} "
  cd ${MYSQL_INSTALL_DIR}
  echo_t "tar -xf ${MYSQL_INSTALL_DIR}/${MYSQL_TAR_FILE} "
  tar -xf ${MYSQL_INSTALL_DIR}/${MYSQL_TAR_FILE}
  #ensure_binary_by_apt_get libaio1
  echo_t "dpkg -i *.deb "
  dpkg -i *.deb
}

function start_mysql_server() {
  if [ "running" != "$(service mysql status | grep -o running)" ] ; then
    echo_t "service mysql restart "
    service mysql restart
  else
    echo_i "Mysql server is already running"
  fi
}

function init_mysql_db_for_dockyard() {
  if [ "" != "$(mysql -u${MYSQL_ROOT_USER} -p${MYSQL_ROOT_PWD} -BNe 'select @@basedir; ' 2>/dev/null)" ] ; then
    echo_i "Mysql user and password are already configured"
    return 0
  fi
  echo_t "cp /etc/mysql/my.cnf /etc/mysql/my.bak_${_DATE}.cnf "
  cp /etc/mysql/my.cnf /etc/mysql/my.bak_${_DATE}.cnf
  echo_t 'sed -i "s/\(bind-address[\t ]*\)=.*/\1= ${MYSQL_SERVER_IP}/" /etc/mysql/my.cnf '
  sed -i "s/\(bind-address[\t ]*\)=.*/\1= ${MYSQL_SERVER_IP}/" /etc/mysql/my.cnf
  echo_t "mysql -uroot -e \"UPDATE mysql.user SET Password=PASSWORD('\"${MYSQL_ROOT_PWD}\"') WHERE User='root'; FLUSH PRIVILEGES;\" "
  mysql -uroot -e "UPDATE mysql.user SET Password=PASSWORD('"${MYSQL_ROOT_PWD}"') WHERE User='root'; FLUSH PRIVILEGES;"
  echo_t "sleep 3 "
  sleep 3
  echo_t "mysql -uroot -p${MYSQL_ROOT_PWD} -e \"CREATE DATABASE ${DOCKYARD_DB_NAME}; CREATE DATABASE ${AOS_DB_NAME}; GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '\"${MYSQL_ROOT_PWD}\"'; FLUSH PRIVILEGES;\" "
  mysql -uroot -p${MYSQL_ROOT_PWD} -e "CREATE DATABASE ${DOCKYARD_DB_NAME}; CREATE DATABASE ${AOS_DB_NAME}; GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '"${MYSQL_ROOT_PWD}"'; FLUSH PRIVILEGES;"
  echo_t "service mysql restart "
  service mysql restart
  echo_i "MySQL Installation and Configuration is Complete."
}

function install_and_start_mysql() {
  install_mysql_server
  start_mysql_server
}

function install_and_start_dockyard() {
  if [[ ! -z "$(dpkg-query --show libssl-dev 2>/dev/null)" ]] ; then
    echo_i "Lib-SSL development package is already installed"
  else
    if [[ ! -f /lib64/libcrypto.so.1.0.0 ]] ; then
      echo_t "ln -s /lib/x86_64-linux-gnu/libcrypto.so.1.0.0 /lib64/ "
      ln -s /lib/x86_64-linux-gnu/libcrypto.so.1.0.0 /lib64/
    fi
  fi

  is_process_up "sudo ./dockyard web" "dockyard service"
  if [ "YES" == "${_RESULT}" ] ; then
    return 0
  fi

  ensure_dir_exist ${DOCKYARD_DEPLOY_DIR}
  ensure_dir_exist ${DOCKYARD_SERVICE_DIR}
  echo_t "tar -C ${DOCKYARD_DEPLOY_DIR} -xzf ${DOCKYARD_TAR_GZ} "
  tar -C ${DOCKYARD_DEPLOY_DIR} -xzf ${DOCKYARD_TAR_GZ}
  echo_t "chmod -R 777 ${DOCKYARD_SERVICE_DIR} "
  chmod -R 777 ${DOCKYARD_SERVICE_DIR}
  echo_t "touch  ${DOCKYARD_CRYPTO_LOG} "
  touch  ${DOCKYARD_CRYPTO_LOG}
  # The following environment variables are hard coded in install.sh, don't move them around!!!
  echo_t "export DOCKYARDDB_NAME=${DOCKYARD_DB_NAME} "
  export DOCKYARDDB_NAME=${DOCKYARD_DB_NAME}
  echo_t "export DOCKYARDDB_USER=${MYSQL_ROOT_USER} "
  export DOCKYARDDB_USER=${MYSQL_ROOT_USER}
  echo_t "export DOCKYARDDB_PWD=${MYSQL_ROOT_PWD} "
  export DOCKYARDDB_PWD=${MYSQL_ROOT_PWD}
  echo_t "export OM_MYSQL_IP=${ETH_IP} "
  export OM_MYSQL_IP=${ETH_IP}
  echo_t "export OM_MYSQL_PORT=3306 "
  export OM_MYSQL_PORT=3306
  echo_t "cd ${DOCKYARD_DEPLOY_DIR} "
  cd ${DOCKYARD_DEPLOY_DIR}
  echo_t "./install.sh >${DOCKYARD_DEPLOY_LOG_FILE} "
  ./install.sh >${DOCKYARD_DEPLOY_LOG_FILE}
  ensure_process_up "sudo ./dockyard web" "dockyard service"
}

function start_aos_apiserver() {
  is_process_up "${AOS_API_SERVER}" "AOS api-server"
  if [ "YES" == "${_RESULT}" ] ; then
    return 0
  fi

  echo_t "export DEPLOY_NAMESPACE=om "
  export DEPLOY_NAMESPACE=om
  echo_t "export CFE_SERVER=http://${K8S_OR_FCP_IP}:${K8S_OR_FCP_PORT} "
  export CFE_SERVER=http://${K8S_OR_FCP_IP}:${K8S_OR_FCP_PORT}
  echo_t "export CMDB_SERVER=http://${K8S_OR_FCP_IP}:${K8S_OR_FCP_PORT} "
  export CMDB_SERVER=http://${K8S_OR_FCP_IP}:${K8S_OR_FCP_PORT}
  # TODO: K8S_OR_FCP_SECURE_PORT
  echo_t "export KUBERNETES_SECURE_PORT=${FCP_SECURE_PORT} "
  export KUBERNETES_SECURE_PORT=${FCP_SECURE_PORT}
  echo_t "export KUBERNETES_INSECURE_PORT=${K8S_OR_FCP_PORT} "
  export KUBERNETES_INSECURE_PORT=${K8S_OR_FCP_PORT}
  echo_t "export MYSQL_PWD=${AOS_MYSQL_PWD} "
  export MYSQL_PWD=${AOS_MYSQL_PWD}
  echo_t "export MYSQL_USER=${AOS_MYSQL_USER} "
  export MYSQL_USER=${AOS_MYSQL_USER}
  echo_t "export MYSQL_IP=${MYSQL_SERVER_IP} "
  export MYSQL_IP=${MYSQL_SERVER_IP}
  echo_t "export MYSQL_PORT=${MYSQL_SERVER_PORT} "
  export MYSQL_PORT=${MYSQL_SERVER_PORT}
  echo_t "export MYSQL_DB=${AOS_MYSQL_DB} "
  export MYSQL_DB=${AOS_MYSQL_DB}
  echo_t "${AOS_API_SERVER} \ "
  echo_t "  --loglevel=DEBUG \ "
  echo_t "  --security_enable=false \ "
  echo_t "  --templatemaxsize=671047 \ "
  echo_t "  --storeaddr=http://${DOCKYARD_SERVICE_IP}:${DOCKYARD_SERVICE_PORT} \ "
  echo_t "  --security-center-addr=${SECURITY_CENTER_ADDR}:${SECURITY_CENTER_PORT} \ "
  echo_t "  --store-extaddr=http://${STORE_EXT_ADDR}:${STORE_EXT_PORT} \ "
  echo_t "  --templatemaxsize=671047 >${AOS_API_SERVER_LOG_FILE} 2>&1 & "
  ${AOS_API_SERVER} \
    --loglevel=DEBUG \
    --security_enable=false \
    --templatemaxsize=671047 \
    --storeaddr=http://${DOCKYARD_SERVICE_IP}:${DOCKYARD_SERVICE_PORT} \
    --security-center-addr=${SECURITY_CENTER_ADDR}:${SECURITY_CENTER_PORT} \
    --store-extaddr=http://${STORE_EXT_ADDR}:${STORE_EXT_PORT} \
    --templatemaxsize=671047 >${AOS_API_SERVER_LOG_FILE} 2>&1 &
  ensure_process_up "${AOS_API_SERVER}" "AOS api-server"
}

function start_workflow_engine() {
  is_process_up "${AOS_WORKFLOW_ENGINE}" "AOS workflow engine"
  if [ "YES" == "${_RESULT}" ] ; then
    return 0
  fi

  echo_t "${AOS_WORKFLOW_ENGINE} \ "
  echo_t "  --cfe-servers=http://${K8S_OR_FCP_IP}:${K8S_OR_FCP_PORT} \ "
  echo_t "  --cmdb-servers=http://${K8S_OR_FCP_IP}:${K8S_OR_FCP_PORT} \ "
  echo_t "  --v=6 >${AOS_WORKFLOW_ENGINE_LOF_FILE} 2>&1 & "
  ${AOS_WORKFLOW_ENGINE} \
    --cfe-servers=http://${K8S_OR_FCP_IP}:${K8S_OR_FCP_PORT} \
    --cmdb-servers=http://${K8S_OR_FCP_IP}:${K8S_OR_FCP_PORT} \
    --v=6 >${AOS_WORKFLOW_ENGINE_LOF_FILE} 2>&1 &
  ensure_process_up "${AOS_WORKFLOW_ENGINE}" "AOS workflow engine"
}

function start_tosca_dsl_parser() {
  is_process_up "dsl_server.dslparser.wsgi" "TOSCA dsl parser"
  if [ "YES" == "${_RESULT}" ] ; then
    return 0
  fi

  ensure_binary_by_apt_get gunicorn
  ensure_binary_by_apt_get pip python-pip
  pip_upgrade_by_itself
  ensure_binary_by_pip django
  ensure_binary_by_pip django-ratelimit
  ensure_binary_by_pip pyyaml
  ensure_binary_by_pip retrying
  ensure_binary_by_pip networkx
  ensure_dir_exist /var/log/dsl-parser
  ensure_dir_exist ${TOSCA_DSL_PARSER_DIR}
  echo_t "tar -C ${TOSCA_DSL_PARSER_DIR} -xf ${TOSCA_DSL_PARSER_TAR} "
  tar -C ${TOSCA_DSL_PARSER_DIR} -xf ${TOSCA_DSL_PARSER_TAR}
  echo_t "cd ${TOSCA_DSL_PARSER_DIR} "
  cd ${TOSCA_DSL_PARSER_DIR}
  echo_t "gunicorn dsl_server.dslparser.wsgi:application \ "
  echo_t "  --error-logfile=${TOSCA_DSL_PARSER_LOG_FILE} \ "
  echo_t "  --log-file=${TOSCA_DSL_PARSER_LOG_FILE} \ "
  echo_t "  --bind=0.0.0.0:${TOSCA_SERVER_PORT} -t 200 >${TOSCA_DSL_PARSER_LOG_FILE} 2>&1 & "
  gunicorn dsl_server.dslparser.wsgi:application \
    --error-logfile=${TOSCA_DSL_PARSER_LOG_FILE} \
    --log-file=${TOSCA_DSL_PARSER_LOG_FILE} \
    --bind=0.0.0.0:${TOSCA_SERVER_PORT} -t 200 >${TOSCA_DSL_PARSER_LOG_FILE} 2>&1 &
  ensure_process_up "dsl_server.dslparser.wsgi" "TOSCA dsl parser"
}

function start_aos() {
  export K8S_OR_FCP_IP=${1}
  export K8S_OR_FCP_PORT=${2}
  echo_t "export DOCKYARD_SERVICE_IP=${K8S_OR_FCP_IP} "
  export DOCKYARD_SERVICE_IP=${K8S_OR_FCP_IP}
  echo_t "export SECURITY_CENTER_ADDR=${K8S_OR_FCP_IP} "
  export SECURITY_CENTER_ADDR=${K8S_OR_FCP_IP}
  echo_t "export STORE_EXT_ADDR=${K8S_OR_FCP_IP} "
  export STORE_EXT_ADDR=${K8S_OR_FCP_IP}
  install_and_start_mysql
  init_mysql_db_for_dockyard
  install_and_start_dockyard
  start_aos_apiserver
  start_workflow_engine
  start_tosca_dsl_parser
}

function start_fcp() {
  start_fcp_etcd
  start_fcp_apiserver
  start_fcp_controller_manager
}

function test_main() {
  parse_cmd_args $@
  init_const
  ensure_base_dir
  ensure_log_dir
  # ensure_ssh_key_on_git_repo
  exit 0
}

function main() {
  parse_cmd_args $@
  if [[ -z "${MASTER_IP}" && -z "${NODE_IP}" && -z "${FCP_IP}" && -z "${SSH_TARGET_IP}" && -z "${SCP_TARGET_IP}" ]] ; then
    usage
    exit 1
  fi

  init_const
  ensure_base_dir
  ensure_log_dir
  if [[ ! -z "${SSH_TARGET_IP}" ]] ; then
    setup_ssh_without_pwd ${SSH_TARGET_IP}
    exit 0
  fi
  if [[ ! -z "${SCP_TARGET_IP}" ]] ; then
    scp_k8s_binaries ${SCP_TARGET_IP}
    exit 0
  fi

  if [ "YES" == "${START_K8S_MASTER}" ] ; then
    start_k8s_master
  fi
  if [ "YES" == "${START_K8S_NODE}" ] ; then
    start_k8s_node
  fi
  if [ "YES" == "${START_K8S_AOS}" ] ; then
    start_aos ${K8S_MASTER_IP} ${K8S_INSECURE_PORT}
  elif [ "YES" == "${START_K8S_FCP}" ] ; then
    start_fcp
    start_aos ${FCP_IP} ${FCP_INSECURE_PORT}
  fi
}

main $@
