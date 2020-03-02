# Black Duck On Kubernetes/OpenShift

Welcome to the README for Black Duck on Kubernetes/OpenShift.

Please note that this document applies *only* to Black Duck on Kubernetes/OpenShift.  If you wish to deploy or use Black Duck on any other platform (e.g., Docker Compose or Docker Swarm), please reference the documentation specific to that platform.

# Deploying Black Duck in Kubernetes/OpenShift

Several approaches are possible to enable deployment of Black Duck using Kubernetes/OpenShift:

1. Helm

A Helm chart is provided to that describes a Kubernetes set of resources required to deploy Black Duck.

2. Synopsys Operator

Another approach for installing Black Duck on Kubernetes/OpenShift is to use [Synopsys Operator](https://synopsys.atlassian.net/wiki/spaces/BDLM/pages/34373652/Synopsys+Operator), a cloud-native administration utility that assists in the deployment and management of Synopsys software in Kubernetes and OpenShift clusters.

Please see the "Black Duck Installation Guide" in the [Synopsys Operator documentation](https://synopsys.atlassian.net/wiki/spaces/BDLM/pages/34373652/Synopsys+Operator) for information on using Synopsys Operator to deploy Black Duck in a Kubernetes or OpenShift cluster.

# Technical Resources

For the latest technical information on Black Duck for Kubernetes/OpenShift, see the [wiki](https://github.com/blackducksoftware/hub/wiki) in this repository.
For the latest technical information on Synopsys Operator, see the [Synopsys Operator wiki](https://github.com/blackducksoftware/synopsys-operator/wiki).

# Other Resources

Another Kubernetes/OpenShift solution provided by Synopsys is [OpsSight Connector](https://github.com/blackducksoftware/opssight-connector/wiki), which works with Black Duck to scan containers in your clusters for open-source security vulnerabilities.

Check out the official [OpsSight documentation](https://synopsys.atlassian.net/wiki/spaces/BDLM/pages/34242566/OpsSight) for information about how OpsSight and Black Duck can make your clusters safer.
