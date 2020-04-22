# Patched ShinyProxy build

The latest release of [ShinyProxy](https://www.shinyproxy.io) supports [SAML authentication](https://www.shinyproxy.io/configuration/#saml-20). This repository contains a patched version of ShinyProxy which addresses two issues I've come across when using SAML authentication. Moreover, it is patched to support mounting PersistentVolumeClaims and Secrets on Kubernetes.

## Load balancer support

If ShinyProxy is deployed behind a load balancer (or an ingress controller in a Kubernetes cluster) you may come across the following error when trying to authenticate:

```
2019-10-14 09:23:05.704 ERROR 1 --- [  XNIO-2 task-2] o.o.c.b.decoding.BaseSAMLMessageDecoder  : SAML message intended destination endpoint 'https://shinyapp.host.domain.xyz/saml/SSO' did not match the recipient endpoint 'http://shinyapp.host.domain.xyz/saml/SSO'
```

The problem arises when incoming traffic to the load balancer is SSL encrypted but communication between the load balancer and ShinyProxy is unencrypted. Load balancer support can be enabled by [changing the context provider used for SAML authentication](https://docs.spring.io/spring-security-saml/docs/2.0.x/reference/html/configuration-advanced.html#configuration-load-balancing). This has been implemented in the patched version of ShinyProxy in this repository.

In addition to the standard [configuration settings](https://www.shinyproxy.io/configuration/#saml-20) under `proxy.saml`, this version of ShinyProxy provides the following settings:

- `lb-server-name`: Server name of the load balancer. By setting this option, load balancer support is enabled.
- `lb-context-path`: Context path of the load balancer. Optional. Default value `/`.
- `lb-port-in-url`: Include server port in construction of load balancer request URL. Optional. Default value `false`.
- `lb-scheme`: Scheme of the load balancer - either http or https. Optional. Default value `https`.
- `lb-server-port`: Port of the load balancer server. Optional. Default value `443`.

For more details see [here](https://docs.spring.io/spring-security-saml/docs/current/api/org/springframework/security/saml/context/SAMLContextProviderLB.html).

As an example, in the particular use case where I came across the problem, ShinyProxy is running on a Kubernetes cluster and SSL traffic is being terminated at the ingress controller and passed on to ShinyProxy unencrypted.
In this case, where the IDP is Azure AD, the authentication part of the configuration looks like this:

```
proxy:
  authentication: saml
  saml:
    idp-metadata-url: https://login.microsoftonline.com/<tenant-ID>/FederationMetadata/2007-06/FederationMetadata.xml
    app-entity-id: <see App ID URI in your Azure application properties>
    app-base-url: https://shinyapp.host.domain.xyz
    lb-server-name: shinyapp.host.domain.xyz
    roles-attribute: http://schemas.microsoft.com/ws/2008/06/identity/claims/role
```

References:

- [Spring Security SAML documentation on the topic](https://docs.spring.io/spring-security-saml/docs/2.0.x/reference/html/configuration-advanced.html#configuration-load-balancing)
- [Context provider reference](https://docs.spring.io/spring-security-saml/docs/current/api/org/springframework/security/saml/context/SAMLContextProviderLB.html)
- [Stack Overflow post about the problem](https://stackoverflow.com/questions/24805895/recipient-endpoint-doesnt-match-with-saml-response)

## Authentication token expiration

The other issue showed up as follows in the log:

```
2020-02-25 11:11:56.649  INFO 1 --- [  XNIO-2 task-6] o.s.security.saml.log.SAMLDefaultLogger  : AuthNResponse;FAILURE;10.0.0.1;api://xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx;https://sts.windows.net/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/;;;org.opensaml.common.SAMLException: Response doesn't have any valid assertion which would pass subject validation
Caused by: org.springframework.security.authentication.CredentialsExpiredException: Authentication statement is too old to be used with value 2020-02-25T07:37:23.536Z
        at org.springframework.security.saml.websso.WebSSOProfileConsumerImpl.verifyAuthenticationStatement(WebSSOProfileConsumerImpl.java:538)
        at org.springframework.security.saml.websso.WebSSOProfileConsumerImpl.verifyAssertion(WebSSOProfileConsumerImpl.java:306)
        at org.springframework.security.saml.websso.WebSSOProfileConsumerImpl.processAuthenticationResponse(WebSSOProfileConsumerImpl.java:214)
        ... 77 more
```
Note, a large chunk of the stack trace has been excluded for brevity.

The key message in the exception is: "Authentication statement is too old". By default ShinyProxy will deny access if authentication happened more than 7200 seconds ago. If the SAML tokens from your IDP are valid for more than 7200 seconds, then this issue can occur.

The problem is fixed by setting the following configuration setting:

- `proxy.saml.max-auth-age`: Maximum time (in seconds) between users authentication and processing of an authentication statement.

Augmenting the example above, the configuration becomes:

```
proxy:
  authentication: saml
  saml:
    idp-metadata-url: https://login.microsoftonline.com/<tenant-ID>/FederationMetadata/2007-06/FederationMetadata.xml
    app-entity-id: <see App ID URI in your Azure application properties>
    app-base-url: https://shinyapp.host.domain.xyz
    lb-server-name: shinyapp.host.domain.xyz
    roles-attribute: http://schemas.microsoft.com/ws/2008/06/identity/claims/role
    max-auth-age: 86400
```

References:

- [Spring Security SAML documentation on the topic](https://docs.spring.io/autorepo/docs/spring-security-saml/2.0.x/reference/htmlsingle/#time-interval)
- [Stack Overflow post about the problem](https://stackoverflow.com/questions/30528636/idp-initiated-saml-login-error-authentication-statement-is-too-old-to-be-used)
- [Blog post about the issue in the context of Azure AD](https://joostvdg.github.io/blogs/sso-azure-ad/)

## Kubernetes volumes

In ShinyProxy there is already support for making host mounts in Kubernetes using the `container-volumes` parameter (see [here](https://shinyproxy.io/configuration) for details).
The patched version in this repository extends this to also support PersistentVolumeClaims and Secrets. In order to mount these, the mount must be specified as `"type:source:destination"`, where type is either `pvc`, `secret` or `host`. If no type is specified it is assumed to be of type `host`. As an example, if we were to mount both a PersistentVolumeClaim and a Secret, we would specify it as:

```
container-volumes: [ "pvc:my-volume:/mnt/volume", "secret:my-secret:/mnt/secret" ]
```

For more information see [this pull request](https://github.com/openanalytics/containerproxy/pull/29).

## Using ShinyProxy from this repository

A drop-in replacement for the normal ShinyProxy jar is provided [here](https://github.com/johannestang/shinyproxy-lb/releases/download/v2.3.0/shinyproxy-2.3.0.jar). This repository is only used to build the ShinyProxy jar. The actual code is in [my local fork](https://github.com/johannestang/containerproxy) of the [containerproxy repo](https://github.com/openanalytics/containerproxy).
