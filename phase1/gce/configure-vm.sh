#! /bin/bash

set -o errexit
set -o pipefail
set -o nounset

get_metadata() {
  curl \
    -sSL --fail \
    -H "Metadata-Flavor: Google" \
    "metadata/computeMetadata/v1/instance/attributes/${1}"
}

ROLE=$(get_metadata "k8s-role")
PHASE2_PROVIDER=$(get_metadata "k8s-phase2-provider")

# mkdir -p /etc/kubernetes/
# get_metadata "k8s-config" > /etc/kubernetes/k8s_config.json
#
# mkdir -p /srv/kubernetes
# case "${ROLE}" in
#   "master")
#     get_metadata "k8s-ca-public-key" \
#       > /srv/kubernetes/ca.pem
#     get_metadata "k8s-apisever-public-key" \
#       > /srv/kubernetes/apiserver.pem
#     get_metadata "k8s-apisever-private-key" \
#       > /srv/kubernetes/apiserver-key.pem
#     get_metadata "k8s-master-kubeconfig" \
#       > /srv/kubernetes/kubeconfig.json
#     ;;
#   "node")
#     get_metadata "k8s-node-kubeconfig" \
#       > /srv/kubernetes/kubeconfig.json
#     ;;
#   *)
#     echo "'${ROLE}' is not a valid role"
#     exit 1
#     ;;
# esac

cat <<EOF > /etc/apt/sources.list.d/k8s.list
deb [arch=amd64] https://apt.dockerproject.org/repo ubuntu-xenial main
EOF

mkdir -p /etc/systemd/system/docker.service.d/
cat <<EOF > /etc/systemd/system/docker.service.d/clear_mount_propagtion_flags.conf
[Service]
MountFlags=shared
EOF

apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv-keys F76221572C52609D
apt-get update
apt-get install -y docker-engine=1.12.0-0~xenial
systemctl enable docker || true
systemctl start docker || true

if [ "$PHASE2_PROVIDER" == "kubeadm" ]; then

  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
  deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
  apt-get update
  apt-get install -y kubelet kubeadm kubectl kubernetes-cni

  case "${ROLE}" in
    "master")
      kubeadm init --token 123456.123456
      ;;
    "node")
      kubeadm join --token 123456.123456 $(get_metadata "k8s-master-ip")
      ;;
    *)
      echo invalid phase2 provider.
      exit 1
      ;;
  esac
else
  docker run \
    --net=host \
    -v /:/mnt/root \
    -v /run:/run \
    -v /etc/kubernetes:/etc/kubernetes \
    -v /var/lib/ignition:/usr/share/oem \
    gcr.io/mikedanese-k8s/ignite:v3
fi

systemctl enable kubelet
systemctl start kubelet
