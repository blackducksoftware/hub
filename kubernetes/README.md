# Black Duck On Kubernetes/OpenShift

Welcome to the README for Black Duck on Kubernetes/OpenShift.

Please note that this document applies *only* to Black Duck on Kubernetes/OpenShift.  If you wish to deploy or use Black Duck on any other platform (e.g., Docker Swarm), please reference the documentation specific to that platform.

# Deploying Black Duck in Kubernetes/OpenShift

Several approaches are possible to enable deployment of Black Duck using Kubernetes/OpenShift:

1. Synopsysctl (Synopsys Control)

You can use [Synopsysctl] (https://synopsys.atlassian.net/wiki/spaces/BDLM/pages/34373652/Synopsysctl) to deploy Black Duck on Kubernetes/OpenShift. Synopsysctl is a cloud-native administration utility that assists in the deployment and management of Synopsys software in Kubernetes and OpenShift clusters

Please see the "Black Duck Installation Guide" in the [Synopsysctl documentation](https://synopsys.atlassian.net/wiki/spaces/BDLM/pages/34373652/Synopsysctl) for information on using Synopsysctl to deploy Black Duck in a Kubernetes or OpenShift cluster.

NOTE: Synopsys Operator is decommissioned and it is no longer used to manage and deploy Black Duck application from version 2020.4.0 and later.

# Technical Resources

For the latest technical information on Black Duck for Kubernetes/OpenShift, see the [wiki](https://github.com/blackducksoftware/hub/wiki) in this repository.

# Other Resources

Another Kubernetes/OpenShift solution provided by Synopsys is [OpsSight](https://github.com/blackducksoftware/opssight-connector/wiki), which works with Black Duck to scan containers in your clusters for open-source security vulnerabilities.

Check out the official [OpsSight documentation](https://synopsys.atlassian.net/wiki/spaces/BDLM/pages/34242566/OpsSight) for information about how OpsSight and Black Duck can make your clusters safer.

2. Helm

A Helm chart is provided that describes a Kubernetes set of resources required to deploy Black Duck. You can find the charts within the blackduck folder on Kubernetes GitHub page. The Helm charts are also available in the public chart museum which can be pulled from https://sig-repo.synopsys.com/sig-cloudnative. Please use the following command to access the repository:
`helm repo add synopsys https://sig-repo.synopsys.com/sig-cloudnative`  
